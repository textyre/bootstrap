# pam_hardening role — refactor design

**Date:** 2026-02-21
**Status:** Approved

## Context

The `pam_hardening` role is part of the workstation bootstrap playbook (Phase 1: System Foundation). It runs on Arch Linux, Ubuntu, Fedora, and Void Linux. The role declares support for EL in `meta/main.yml` but the actual user stack does not include RHEL/CentOS.

Current state: the role only writes `/etc/security/faillock.conf` and deploys a Debian pam-auth-update profile. On Arch, Void, and Fedora the PAM stack is never modified — faillock.conf is written but never activated.

### Research sources

Comparison performed via supergrep (Sourcegraph) against:
- [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening) (5223★)
- [konstruktoid/ansible-role-hardening](https://github.com/konstruktoid/ansible-role-hardening) (614★)
- [Kicksecure/security-misc](https://github.com/Kicksecure/security-misc) (576★)
- [easzlab/kubeasz](https://github.com/easzlab/kubeasz) (11317★)
- [ansible/product-demos](https://github.com/ansible/product-demos) (280★)
- ansible-lockdown/RHEL9-STIG, MVladislav/ansible-cis-ubuntu-2404

## Bugs found in current implementation

| Bug | File | Fix |
|-----|------|-----|
| `changed_when: true` — handler always reports changed | `handlers/main.yml:6` | `changed_when: false` |
| `pam-auth-update --enable` — forces enable ignoring existing state | `tasks/faillock.yml:35` | Change to `--package` |
| `even_deny_root` missing — root exempt from lockout despite `root_unlock_time` set | `templates/faillock.conf.j2` | Add `even_deny_root` directive |
| EL/Arch/Fedora: faillock.conf written but PAM stack never modified | all platforms | Add platform-specific tasks |

## Design decisions

### Approach: Platform-split tasks (chosen over minimal fix and feature-flags)

Single Responsibility Principle applied: each platform file handles exactly one mechanism.

### Scope

- **In scope:** faillock (brute-force protection), all PAM stack activation per platform
- **Out of scope:** pwquality (password complexity) — separate role, SRP
- **Out of scope:** limits.conf — separate role
- **Removed:** EL (RHEL/CentOS) — not in actual stack; replace with Fedora

### Platforms

| Platform | os_family | PAM stack method |
|----------|-----------|-----------------|
| Arch Linux | `Archlinux` | `lineinfile` in `/etc/pam.d/system-auth` |
| Void Linux | `Void` | `lineinfile` in `/etc/pam.d/system-auth` (same as Arch) |
| Ubuntu / Debian | `Debian` | `pam-auth-update --package` with two profiles |
| Fedora | `RedHat` | `authselect enable-feature with-faillock` |

## File structure

```
ansible/roles/pam_hardening/
├── defaults/main.yml          # extended variables
├── tasks/
│   ├── main.yml               # include_tasks: faillock.yml (when: pam_faillock_enabled)
│   ├── faillock.yml           # template faillock.conf + platform dispatcher
│   ├── faillock_debian.yml    # pam-auth-update --package (Ubuntu/Debian)
│   ├── faillock_redhat.yml    # authselect enable-feature with-faillock (Fedora)
│   └── faillock_arch.yml      # lineinfile /etc/pam.d/system-auth (Arch, Void)
├── templates/
│   └── faillock.conf.j2       # extended template
├── handlers/main.yml          # 2 handlers: Debian + RedHat (Arch: no handler needed)
└── meta/main.yml              # remove EL, add Fedora + Void
```

## Variables

### Existing (unchanged values)

```yaml
pam_faillock_enabled: true
pam_faillock_deny: 3
pam_faillock_fail_interval: 900
pam_faillock_unlock_time: 900
pam_faillock_root_unlock_time: 900
pam_faillock_audit: true
pam_faillock_silent: false
```

### New variables

```yaml
pam_faillock_even_deny_root: true    # root also subject to lockout (CIS standard)
                                     # confirmed: dev-sec, Kicksecure, vmware/photon all enable this
pam_faillock_local_users_only: false # skip LDAP/SSO accounts; set true if LDAP in use
pam_faillock_nodelay: false          # eliminate delay after failed auth (pam >= 1.5.1)
pam_faillock_x11_skip: false        # skip faillock for X11 sessions (screensaver protection)
                                     # when true: uses pam_exec.so wrapper à la Kicksecure
```

**Note on deny=3 + x11_skip:** deny=3 is aggressive for GUI workstations (3 screensaver mistypos = 15min lockout). The `pam_faillock_x11_skip` variable is the intended mitigation. Users with lightdm/screensaver should consider enabling it.

## faillock.conf.j2 changes

Add to template:

```jinja2
{% if pam_faillock_even_deny_root %}
even_deny_root
{% endif %}
{% if pam_faillock_local_users_only %}
local_users_only
{% endif %}
{% if pam_faillock_nodelay %}
nodelay
{% endif %}
```

## Platform tasks

### faillock_debian.yml — two split profiles (dev-sec/canonical pattern)

Deploy two separate pam-auth-update profiles instead of one:
- `/usr/share/pam-configs/faillock` — preauth + account
- `/usr/share/pam-configs/faillock-authfail` — authfail (Auth-Final)

This ensures correct hook positioning in the PAM stack relative to other modules.

Handler: `pam-auth-update --package` (not `--enable`).
Source: easzlab/kubeasz (11317★), debops (1373★).

### faillock_redhat.yml — authselect (Fedora)

```yaml
- name: Enable faillock via authselect
  ansible.builtin.command: authselect enable-feature with-faillock
  register: _authselect_result
  changed_when: "'already' not in _authselect_result.stdout"
  notify: Apply authselect (RedHat)
```

Handler runs `authselect apply-changes`.
Pattern from: ansible/product-demos (280★, official Ansible repo), ansible-lockdown/RHEL9-STIG.

### faillock_arch.yml — lineinfile (Arch, Void)

Three `lineinfile` tasks targeting `/etc/pam.d/system-auth`:
1. `auth required pam_faillock.so preauth` — before `pam_unix.so` line
2. `auth required pam_faillock.so authfail` — after `pam_unix.so` line
3. `account required pam_faillock.so` — in account section

No parameters inline — all config from `faillock.conf`.
Pattern confirmed by: ataraxialinux, getsolus/packages distro files.

**X11 skip variant** (`pam_faillock_x11_skip: true`): replaces `pam_faillock.so preauth` with `pam_exec.so seteuid quiet /usr/libexec/pam_faillock_not_if_x` wrapper. Requires deploying the helper script.
Pattern from: Kicksecure/security-misc.

## Handlers

```yaml
- name: Update PAM (Debian)
  ansible.builtin.command: pam-auth-update --package
  changed_when: false
  when: ansible_facts['os_family'] == 'Debian'

- name: Apply authselect (RedHat)
  ansible.builtin.command: authselect apply-changes
  changed_when: false
  when: ansible_facts['os_family'] == 'RedHat'
```

Arch/Void: no handler needed — `lineinfile` changes take effect immediately.

## meta/main.yml changes

Remove: `EL`
Add: `Fedora`, `VoidLinux`

## Molecule

Current molecule tests (Debian container) remain. Test only verifies:
- `faillock.conf` exists and contains `deny =`, `unlock_time =`

Extend verify to also check `even_deny_root` presence.
Arch/Fedora molecule scenarios: out of scope for this refactor.

## Out of scope / future roles

- **pwquality_hardening** — separate role for password complexity (`/etc/security/pwquality.conf`)
- **resource_limits** — separate role for `/etc/security/limits.conf`
