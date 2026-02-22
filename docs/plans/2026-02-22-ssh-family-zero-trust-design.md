# Design: SSH Family — Zero-Trust Architecture

**Date:** 2026-02-22
**Status:** Draft
**Scope:** 5 roles (users, ssh_keys, ssh, teleport, fail2ban) forming a zero-trust SSH access platform

---

## Context

The current SSH role provides solid sshd hardening (CIS L1, dev-sec.io, 14 controls, 39 tests) but lacks:
- Certificate-based authentication (SSH CA)
- Bastion / jump host support
- Session recording and audit
- Convenient user lifecycle management (no state: absent)
- Post-deployment user management without Ansible re-run
- 3 of 5 required distros (missing Fedora, Void, Gentoo)
- Init-system agnosticism (systemd-only)
- Reporting integration (no common role dual logging)

The existing `user` role (redesign approved 2026-02-22) manages users + authorized_keys + sudo.
This design **splits ssh_keys out of user** and adds teleport + fail2ban for zero-trust.

### Community Research

| Project | Stars | Key insight |
|---------|-------|-------------|
| dev-sec/ansible-collection-hardening | 5226 | Gold standard for sshd_config params; has CA support (TrustedUserCAKeys, principals) |
| debops/ansible-sshd | 25 | System-wide authorized_keys at `/etc/ssh/authorized_keys/%u`; LDAP lookup; ferm firewall integration |
| icpcsysops/ansible/ssh_ca | 10 | Real-world SSH CA: sign host keys, TrustedUserCAKeys, authorized_principals |
| rolandu/ssh_users | 0 | Clean pattern: users array with per-user ed25519 generation and key export |

### Tool Decision

**Teleport** selected over HashiCorp Boundary for:
- Built-in SSH CA (no separate Vault needed)
- Session recording with command-level audit (Boundary only logs lifecycle)
- SSO/MFA out of the box (OIDC/SAML)
- Standalone deployment (no HashiCorp ecosystem dependency)
- Replaces both ssh_ca and ssh_bastion roles

---

## Goals

1. Zero-trust SSH: short-lived certificates via Teleport, no long-lived static keys in production
2. Convenient user lifecycle: `state: present/absent` in one YAML → applies to all machines
3. Separation of concerns: 5 roles, each with single responsibility
4. Full compliance with role-requirements.md (5 distros, 5 inits, reporting)
5. Fallback access via authorized_keys when Teleport is unavailable
6. Post-deployment user management via Teleport SSO (no Ansible re-run needed)

---

## Architecture

### Role Family

```
Playbook (strict order)
│
├── 1. users       — user accounts, groups, sudo, umask, password aging
├── 2. ssh_keys    — authorized_keys, key generation (depends on: users)
├── 3. ssh         — sshd hardening, crypto, host keys (depends on: ssh_keys for bootstrap)
├── 4. teleport    — CA, bastion, SSO, session recording (depends on: ssh)
└── 5. fail2ban    — brute-force protection (depends on: ssh)
```

### Shared Data Source

All roles read from a single `accounts` structure in `group_vars/all/accounts.yml`:

```yaml
accounts:
  - name: alice
    state: present              # present | absent
    shell: /bin/zsh
    groups: [wheel, developers]
    sudo: true
    ssh_keys:
      - "ssh-ed25519 AAAA... alice@laptop"
      - "ssh-ed25519 AAAA... alice@phone"
    password_hash: "{{ vault_alice_password }}"
    update_password: on_create
    password_max_age: 365
    password_min_age: 1
    umask: "027"

  - name: bob
    state: absent               # removed everywhere on next run
    groups: [wheel]

  - name: deploy
    state: present
    system: true                # system account (no home, nologin)
    ssh_keys:
      - "ssh-ed25519 AAAA... ci/cd-deploy-key"
    sudo: false
```

### Responsibility Matrix

| Concern | users | ssh_keys | ssh | teleport | fail2ban |
|---------|-------|----------|-----|----------|----------|
| Create/delete user accounts | **owns** | — | — | — | — |
| Group membership | **owns** | — | — | — | — |
| Sudo policy & hardening | **owns** | — | — | — | — |
| Password aging (CIS 5.5.x) | **owns** | — | — | — | — |
| Umask (CIS 5.4.x) | **owns** | — | — | — | — |
| Root lock verification (CIS 5.4.3) | **owns** | — | — | — | — |
| ~/.ssh/authorized_keys | — | **owns** | — | — | — |
| SSH key generation (user side) | — | **owns** | — | — | — |
| Deploy keys (CI/CD) | — | **owns** | — | — | — |
| sshd_config | — | — | **owns** | — | — |
| Host keys (ed25519, RSA) | — | — | **owns** | — | — |
| Cryptography (KEX, ciphers, MACs) | — | — | **owns** | — | — |
| Anti-lockout preflight | — | — | **owns** | — | — |
| DH moduli cleanup | — | — | **owns** | — | — |
| SSH banner | — | — | **owns** | — | — |
| TrustedUserCAKeys (Teleport CA) | — | — | configures | **provides** | — |
| SSH CA (short-lived certs) | — | — | — | **owns** | — |
| Session recording | — | — | — | **owns** | — |
| SSO / MFA | — | — | — | **owns** | — |
| Bastion / ProxyJump | — | — | — | **owns** | — |
| User enrollment (runtime) | — | — | — | **owns** | — |
| IP ban on brute-force | — | — | — | — | **owns** |
| jail.d/sshd configuration | — | — | — | — | **owns** |

---

## Role 1: users (refactored from existing `user`)

### Changes from current user-role-redesign

**Removed:** `user_manage_ssh_keys`, `tasks/ssh_keys.yml` → moved to `ssh_keys` role
**Added:** `state: present/absent` support for user lifecycle

### Data model

Uses `accounts` variable (shared). Role-specific defaults:

```yaml
# defaults/main.yml
users_sudo_group: "{{ 'wheel' if ansible_facts['os_family'] == 'Archlinux' else 'sudo' }}"
users_sudo_timestamp_timeout: >-
  {{ 15 if 'developer' in (workstation_profiles | default([]))
     else 0 if 'security' in (workstation_profiles | default([]))
     else 5 }}
users_sudo_use_pty: true
users_sudo_logfile: /var/log/sudo.log
users_manage_password_aging: true
users_manage_umask: true
users_verify_root_lock: true
```

### Task flow

```
1. Assert supported OS
2. Include OS-specific vars
3. Install sudo (OS dispatch)
4. Remove absent users (state: absent → user module state: absent, remove: true)
5. Create/configure present users (owner + additional)
6. Deploy sudo policy
7. Deploy umask profiles
8. Verify root account lock
9. Run verification
10. Report (dual logging)
```

### Key addition: state management

```yaml
- name: Remove absent users
  ansible.builtin.user:
    name: "{{ item.name }}"
    state: absent
    remove: true
  loop: "{{ accounts | selectattr('state', 'equalto', 'absent') | list }}"
  tags: [users, security]
```

---

## Role 2: ssh_keys (new)

### Purpose

Manage SSH authorized_keys and key generation, separated from user lifecycle.

### Data model

```yaml
# defaults/main.yml
ssh_keys_manage_authorized_keys: true
ssh_keys_generate_user_keys: false        # generate ed25519 on target
ssh_keys_key_type: ed25519
ssh_keys_exclusive: false                 # if true, remove unmanaged keys
ssh_keys_system_authorized_keys_dir: ""   # e.g. /etc/ssh/authorized_keys (debops pattern)
```

### File structure

```
ansible/roles/ssh_keys/
  defaults/main.yml
  tasks/
    main.yml              # orchestrator
    authorized_keys.yml   # deploy keys from accounts[].ssh_keys
    keygen.yml            # optional: generate keys on target
    verify.yml            # verify keys exist and permissions correct
  meta/main.yml           # dependencies: [users]
  molecule/default/
    molecule.yml
    converge.yml
    verify.yml
```

### Task flow

```
1. Assert users exist (dependency check)
2. Create ~/.ssh directories (0700)
3. Deploy authorized_keys from accounts[].ssh_keys
4. Optional: generate user keypair on target
5. Optional: deploy to /etc/ssh/authorized_keys/%u (system-wide)
6. Verify permissions
7. Report
```

### Key pattern

```yaml
- name: Add SSH authorized keys
  ansible.posix.authorized_key:
    user: "{{ item.0.name }}"
    key: "{{ item.1 }}"
    manage_dir: true
    exclusive: "{{ ssh_keys_exclusive }}"
    state: "{{ item.0.state | default('present') }}"
  with_subelements:
    - "{{ accounts | selectattr('state', 'equalto', 'present') | list }}"
    - ssh_keys
    - skip_missing: true
  no_log: true
  tags: [ssh_keys, security]

- name: Remove authorized_keys for absent users
  ansible.builtin.file:
    path: "/home/{{ item.name }}/.ssh/authorized_keys"
    state: absent
  loop: "{{ accounts | selectattr('state', 'equalto', 'absent') | list }}"
  tags: [ssh_keys, security]
```

---

## Role 3: ssh (enhanced existing)

### Changes from current ssh role

**Added:**
- 3 missing distros (Fedora/RedHat, Void, Gentoo)
- Init-system agnostic service management (systemd, runit, openrc, s6, dinit)
- Reporting integration (common role dual logging)
- Teleport CA integration (TrustedUserCAKeys when teleport enabled)
- `state: absent` aware (skip anti-lockout for absent users)
- Replace shell/awk in moduli.yml with ansible.builtin modules

**Kept:** All current hardening parameters, preflight, crypto config

### Data model additions

```yaml
# defaults/main.yml additions
ssh_teleport_integration: false           # when true, configure TrustedUserCAKeys
ssh_teleport_ca_keys_file: /etc/ssh/teleport_user_ca.pub
```

### sshd_config.j2 additions

```jinja2
{% if ssh_teleport_integration %}
# Teleport SSH CA — trust certificates signed by Teleport auth server
TrustedUserCAKeys {{ ssh_teleport_ca_keys_file }}
{% endif %}
```

### File structure additions

```
tasks/
  install-redhat.yml     # new
  install-void.yml       # new
  install-gentoo.yml     # new
  service-systemd.yml    # extracted from service.yml
  service-runit.yml      # new
  service-openrc.yml     # new
  service-s6.yml         # new
  service-dinit.yml      # new
```

---

## Role 4: teleport (new)

### Purpose

Deploy Teleport agent on managed nodes, register with auth server, configure SSH CA trust.

### Data model

```yaml
# defaults/main.yml
teleport_enabled: true
teleport_version: "17"                    # major version
teleport_auth_server: ""                  # required: auth.example.com:443
teleport_join_token: ""                   # vault-encrypted join token
teleport_node_name: "{{ ansible_hostname }}"
teleport_labels: {}                       # key-value labels for RBAC
teleport_ssh_enabled: true
teleport_proxy_mode: false                # true if this node is a proxy/bastion
teleport_session_recording: "node"        # node | proxy | off
teleport_enhanced_recording: false        # BPF-based (needs kernel support)
```

### File structure

```
ansible/roles/teleport/
  defaults/main.yml
  vars/
    archlinux.yml         # package source / install method
    debian.yml
    redhat.yml
    void.yml
    gentoo.yml
  tasks/
    main.yml              # orchestrator
    install.yml           # OS-specific installation
    configure.yml         # /etc/teleport.yaml template
    join.yml              # register node with auth server
    ca_export.yml         # export CA public key for ssh role integration
    verify.yml            # verify teleport status + connectivity
  templates/
    teleport.yaml.j2      # node configuration
  handlers/
    main.yml              # restart teleport
  meta/main.yml           # dependencies: [ssh]
  molecule/default/
    molecule.yml
    converge.yml
    verify.yml
```

### Integration with ssh role

When `teleport_enabled: true`, the teleport role:
1. Installs and configures teleport agent
2. Exports CA public key to `ssh_teleport_ca_keys_file`
3. Sets `ssh_teleport_integration: true` as a fact
4. ssh role picks up TrustedUserCAKeys on next run (or handler)

### Workflow: new machine bootstrap

```
1. Ansible provisions machine
2. teleport role installs agent, joins auth server
3. Teleport CA public key exported to /etc/ssh/teleport_user_ca.pub
4. ssh role configures TrustedUserCAKeys
5. Users connect via: tsh ssh user@machine (certificate-based)
6. Fallback: ssh user@machine (authorized_keys from ssh_keys role)
```

### Workflow: new team member

```
1. Add to Identity Provider (Google Workspace / Okta)
2. Teleport SSO grants access automatically (RBAC by labels)
3. No Ansible re-run needed
4. Short-lived certificate (TTL: 12h default) — auto-expires
```

### Workflow: team member leaves

```
1. Remove from Identity Provider
2. Teleport immediately revokes access (SSO-based)
3. Optional: state: absent in accounts.yml → Ansible removes local account
```

---

## Role 5: fail2ban (new)

### Purpose

Brute-force protection for SSH. Additional defense layer alongside Teleport.

### Data model

```yaml
# defaults/main.yml
fail2ban_enabled: true
fail2ban_sshd_enabled: true
fail2ban_sshd_port: "{{ ssh_port | default(22) }}"
fail2ban_sshd_maxretry: 5
fail2ban_sshd_findtime: 600               # 10 minutes window
fail2ban_sshd_bantime: 3600               # 1 hour ban
fail2ban_sshd_bantime_increment: true     # exponential backoff
fail2ban_sshd_bantime_maxtime: 86400      # max 24h ban
fail2ban_ignoreip:
  - 127.0.0.1/8
  - ::1
fail2ban_sshd_backend: auto               # auto | systemd | polling
```

### File structure

```
ansible/roles/fail2ban/
  defaults/main.yml
  vars/
    archlinux.yml
    debian.yml
    redhat.yml
    void.yml
    gentoo.yml
  tasks/
    main.yml
    install.yml           # OS dispatch
    configure.yml         # jail.d/sshd.conf template
    verify.yml
  templates/
    jail_sshd.conf.j2
  handlers/
    main.yml              # restart fail2ban
  meta/main.yml
  molecule/default/
    molecule.yml
    converge.yml
    verify.yml
```

---

## Security Standards Mapping

### Full Zero-Trust Stack

| Layer | Role | Standards | Controls |
|-------|------|-----------|----------|
| Identity | teleport | NIST 800-53 IA-2, IA-5 | Short-lived certs, SSO, MFA |
| Authentication | ssh + teleport | CIS 5.2.6, 5.2.9, 5.2.10 | Pubkey only, no password, no root |
| Authorization | users + teleport | CIS 5.2.15, 5.3.4-5.3.7 | AllowGroups, sudo hardening, RBAC |
| Transport | ssh | CIS 5.2.12-5.2.14 | AEAD ciphers, ETM MACs, modern KEX |
| Monitoring | teleport + fail2ban | CIS 5.2.5, 5.2.21 | VERBOSE logging, session recording, ban |
| Key Management | ssh_keys + teleport | CIS 5.2.18, dev-sec | authorized_keys fallback, CA certs |

### Per-Role CIS Controls

**users:**
- CIS 5.3.4: sudo timestamp_timeout
- CIS 5.3.5: sudo use_pty
- CIS 5.3.7: sudo logfile
- CIS 5.4.2: umask 027
- CIS 5.4.3: root account locked
- CIS 5.5.1/5.5.2: password aging

**ssh:**
- CIS 5.2.5: LogLevel VERBOSE
- CIS 5.2.6: PasswordAuthentication no
- CIS 5.2.7: MaxAuthTries 3
- CIS 5.2.9: PermitEmptyPasswords no
- CIS 5.2.10: PermitRootLogin no
- CIS 5.2.11: X11Forwarding no
- CIS 5.2.12-14: Modern crypto (KEX, ciphers, MACs)
- CIS 5.2.15: AllowGroups
- CIS 5.2.16-17: ClientAlive keepalive
- CIS 5.2.21: MaxStartups
- CIS 5.2.22: MaxSessions

**fail2ban:**
- CIS 5.2.21: DoS protection (complementary to MaxStartups)

---

## Playbook Integration

```yaml
# playbooks/workstation.yml (Phase 3: User & access)
- role: users
  tags: [users]

- role: ssh_keys
  tags: [ssh_keys, security]

- role: ssh
  tags: [ssh, security]

- role: teleport
  tags: [teleport, security]
  when: teleport_enabled | default(false)

- role: fail2ban
  tags: [fail2ban, security]
  when: fail2ban_enabled | default(true)
```

---

## Migration from Current State

### Breaking changes

1. `user` role loses `tasks/ssh_keys.yml` → moved to `ssh_keys` role
2. Variable rename: `user_owner.ssh_keys` still works (read by `ssh_keys` role from `accounts`)
3. `user_manage_ssh_keys` toggle removed from `user` defaults

### Migration steps

1. Refactor `user` role: remove ssh_keys tasks, add state: absent support
2. Create `ssh_keys` role with extracted logic
3. Enhance `ssh` role: add 3 distros, 4 init systems, reporting, Teleport integration
4. Create `teleport` role
5. Create `fail2ban` role
6. Update playbook ordering
7. Update molecule tests for each role

---

## What Is NOT in Scope

- Teleport auth server deployment (separate infrastructure, not per-workstation)
- LDAP/Active Directory integration (YAGNI for current scale)
- SSH client configuration (~/.ssh/config — handled by dotfiles/chezmoi)
- VPN/WireGuard (separate network layer)
- Firewall rules (separate role, not SSH-specific)

---

## User Value Summary

| Persona | Pain Point | Solution | Value |
|---------|-----------|----------|-------|
| Admin bootstrapping machine | "SSH is insecure by default" | `ssh` role → CIS-hardened sshd in one run | Security without expertise |
| Admin adding team member | "Copy keys to 10+ machines manually" | `accounts.yml` + Ansible OR Teleport SSO | One action → access everywhere |
| Admin removing team member | "Did I revoke all access?" | `state: absent` + Teleport SSO revocation | Instant, complete revocation |
| Security auditor | "Who accessed what, when?" | Teleport session recording + VERBOSE logs | Full audit trail |
| Team member | "My key expired / was compromised" | Teleport short-lived certs (12h TTL) | Keys auto-expire, no manual rotation |
| On-call engineer | "Need emergency access at 3am" | Teleport SSO + authorized_keys fallback | Always have a way in |

---

## Sources

- [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening) — 5226 stars, SSH hardening reference
- [debops/ansible-sshd](https://github.com/debops/ansible-sshd) — mature SSH role with LDAP and firewall
- [Teleport](https://goteleport.com/features/) — open source access platform
- [Smallstep step-ca](https://github.com/smallstep/certificates) — open source SSH/TLS CA
- [StrongDM comparison](https://www.strongdm.com/blog/alternatives-to-gravitational-teleport) — tool landscape
- [Teleport vs Boundary](https://www.peerspot.com/products/comparisons/hashicorp-boundary_vs_teleport) — detailed comparison
