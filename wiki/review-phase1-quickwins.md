# Phase 1: Quick Wins Code Inspection -- Destructive-Critical Review

**Date:** 2026-02-16
**Reviewer:** Claudette (destructive-critical mode)
**Scope:** 6 Quick Wins (QW-1 through QW-6), 14 files read and analyzed

---

## Context Verification

- Project is Ansible-based workstation bootstrap: **CONFIRMED** (AGENTS.md, role structure)
- Primary OS: Arch Linux, roles must be distro-agnostic: **CONFIRMED**
- 21 existing roles, agent modified 6 (Quick Wins): **CONFIRMED** (ssh, sysctl, docker, firewall, base_system, user)

---

## 1. Critical Issues (blockers)

### CRIT-01: nftables SSH rate limit is GLOBAL, not per-source-IP

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/templates/nftables.conf.j2`, line 26
**Evidence:**
```nftables
tcp dport 22 ct state new limit rate 4/minute accept
tcp dport 22 ct state new log prefix "[nftables] ssh-rate: " drop
```

This is a **global** rate limit: 4 SSH connections total per minute across ALL source IPs. If 4 different legitimate users connect within one minute, the 5th connection from ANY IP is dropped. On a shared workstation or during automated deployments, this will cause intermittent SSH failures that are extremely difficult to diagnose.

**Quick-Wins.md (lines 362-383) specifies the correct implementation** with a dynamic set:
```nftables
set ssh_ratelimit {
    type ipv4_addr
    flags dynamic
    timeout 1m
}
# ... add @ssh_ratelimit { ip saddr limit rate over 4/minute burst 2 packets }
```

The code does NOT implement this. The documentation describes per-IP rate limiting; the code implements a global rate limit. This is a **documentation-vs-code mismatch that creates a denial-of-service vulnerability against the host's own administrators**.

**Pre-identified issue #5: CONFIRMED.**

**Fix:** Replace `limit rate 4/minute accept` with a dynamic set and meter using `ip saddr` for per-source-IP tracking. The template must also add a `set ssh_ratelimit` block inside the `table inet filter` definition.

---

### CRIT-02: Docker security features ALL disabled by default -- documentation claims security improvement

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/defaults/main.yml`, lines 21-24
**Evidence:**
```yaml
docker_userns_remap: ""          # DISABLED
docker_icc: true                 # INSECURE (inter-container communication allowed)
docker_live_restore: false       # DISABLED
docker_no_new_privileges: false  # INSECURE (privilege escalation allowed)
```

The **entire point of QW-3** was to improve Docker security. Quick-Wins.md (lines 230-256) specifies secure defaults:
- `docker_userns_remap: "default"` -- code has `""`
- `docker_icc: false` -- code has `true`
- `docker_live_restore: true` -- code has `false`
- `docker_no_new_privileges: true` -- code has `false`

Running this role with default variables provides **zero additional security** over a stock Docker installation. The only way to enable security is to manually override every variable. The Quick-Wins.md documentation describes this as a security improvement, but the code ships in a fully insecure state.

**Pre-identified issue #1: CONFIRMED.**
**Pre-identified issue #3: CONFIRMED.**

**Fix:** Either (a) change defaults to secure values with clear documentation that they may break existing workloads, or (b) add a prominent warning in the defaults file and Quick-Wins.md that security features are opt-in and NOT enabled by default. The current state is deceptive -- the documentation implies security while the code provides none.

---

### CRIT-03: daemon.json.j2 produces invalid JSON under specific variable combinations

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/templates/daemon.json.j2`, lines 1-17
**Evidence:**
```jinja2
{
  "log-driver": "{{ docker_log_driver }}",
  "log-opts": {
    "max-size": "{{ docker_log_max_size }}",
    "max-file": "{{ docker_log_max_file }}"
  }{% if docker_storage_driver | length > 0 %},
  "storage-driver": "{{ docker_storage_driver }}"
{% endif %}{% if docker_userns_remap | length > 0 %},
  "userns-remap": "{{ docker_userns_remap }}"
{% endif %}{% if not docker_icc %},
  "icc": false
{% endif %}{% if docker_live_restore %},
  "live-restore": true
{% endif %}{% if docker_no_new_privileges %},
  "no-new-privileges": true
{% endif %}
}
```

**Problem 1: Trailing whitespace/newlines in JSON.** The `{% endif %}` blocks produce blank lines inside the JSON object. While most JSON parsers tolerate trailing whitespace, some strict parsers or tooling validating Docker configs may choke.

**Problem 2: Conditional comma placement pattern is fragile but technically correct.** The comma-before pattern (`}{% if ... %},`) works because the unconditional `log-opts` block always provides a trailing `}` before any conditional comma. Tracing all 32 combinations (2^5 boolean conditions -- `docker_icc` inverted, `docker_live_restore`, `docker_no_new_privileges`, plus 2 string length checks):

- All false/empty: Valid JSON (`log-opts` block closes, no trailing comma)
- Any single condition true: Valid (comma after `}` before the key)
- Multiple conditions true: Valid (each conditional block adds `,\n  "key": value`)
- All conditions true: Valid

The comma logic is technically correct in all 32 combinations. However, the template has **no validation step**. Docker will crash silently on invalid JSON, and the task (`ansible/roles/docker/tasks/main.yml`, line 17-25) does not include a `validate:` parameter to check the JSON before deployment. Compare this with the SSH role which uses `validate: '/usr/sbin/sshd -t -f %s'` and the user role which uses `validate: '/usr/sbin/visudo -cf %s'`.

**Pre-identified issue #2: PARTIALLY CONFIRMED.** The comma logic is correct, but the template is fragile (one edit can break it), produces non-standard whitespace, and lacks validation.

**Fix:** Add `validate: 'python3 -m json.tool %s'` to the template task, or better: construct the JSON using a Jinja2 dictionary and `| to_nice_json` filter, which eliminates the fragile comma management entirely.

---

### CRIT-04: PAM faillock only configured on Arch Linux -- Debian gets NO brute-force protection

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/archlinux.yml`, lines 31-45
**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/debian.yml`, lines 1-8
**Evidence:**

The faillock configuration exists only in `archlinux.yml`:
```yaml
- name: Configure pam_faillock defaults
  ansible.builtin.copy:
    dest: /etc/security/faillock.conf
    content: |
      # Managed by Ansible
      dir = /run/faillock
      deny = {{ base_system_faillock_deny }}
      fail_interval = {{ base_system_faillock_fail_interval }}
      unlock_time = {{ base_system_faillock_unlock_time }}
      audit
      silent
```

The `debian.yml` file is a placeholder:
```yaml
- name: Debian system configuration placeholder
  ansible.builtin.debug:
    msg: "Debian/Ubuntu system configuration -- not yet implemented"
```

On Debian systems, the faillock task is never executed. This violates the distro-agnostic requirement. A Debian workstation bootstrapped with this playbook has **zero local brute-force protection**.

**Pre-identified issue #4: CONFIRMED.**

**Fix:** Create faillock tasks for Debian in `debian.yml`, or move the faillock configuration to `main.yml` (it uses `/etc/security/faillock.conf` which exists on both distros). The PAM integration (`/etc/pam.d/common-auth` for Debian vs `/etc/pam.d/system-auth` for Arch) requires OS-specific tasks as documented in Quick-Wins.md lines 507-529, but the `faillock.conf` itself is cross-platform.

---

### CRIT-05: SSH AllowGroups applied without verifying user is in the allowed group

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/tasks/main.yml`, lines 70-81
**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`, line 25
**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/user/defaults/main.yml`, lines 12-13
**Evidence:**

SSH defaults:
```yaml
ssh_allow_groups: ["wheel"]
```

User defaults:
```yaml
user_groups:
  - wheel
```

The SSH role sets `AllowGroups wheel` in sshd_config without verifying that the target user is actually in the `wheel` group. The user role adds the user to `wheel` by default, but:

1. **The ssh role and user role are independent.** If ssh runs before user, or if ssh runs without user, the current user may NOT be in `wheel`.
2. **If `user_groups` is overridden** (e.g., `user_groups: ["developers"]`), the user is NOT in `wheel`, and SSH access is immediately lost.
3. **There is no pre-flight check** that verifies `ssh_user` is a member of at least one group in `ssh_allow_groups` before applying the restriction.
4. **The sshd restart is immediate** via handler notification -- once the handler fires, the lockout is in effect.

This is a **self-lockout scenario** on a single-user workstation with no other admin account.

**Pre-identified issue #7: CONFIRMED.**

**Fix:** Add a pre-task that verifies `ssh_user` is a member of at least one group listed in `ssh_allow_groups`, and fail with a clear error message if not. Alternatively, add an `assert` task that checks group membership before applying AllowGroups.

---

## 2. Serious Gaps (high impact)

### GAP-01: No logrotate for sudo.log -- unbounded disk growth

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/user/tasks/main.yml`, line 26
**Evidence:**

The sudoers hardening writes:
```
Defaults logfile="/var/log/sudo.log"
```

Quick-Wins.md (lines 651-675) describes a logrotate template and task:
```yaml
- name: Configure logrotate for sudo log
  template:
    src: sudo_logrotate.j2
    dest: /etc/logrotate.d/sudo
```

**Neither the template (`sudo_logrotate.j2`) nor the logrotate task exists in the codebase.** The `ansible/roles/user/templates/` directory does not exist at all (verified by glob). There is no logrotate configuration anywhere in the user role.

`/var/log/sudo.log` will grow indefinitely until the disk fills up. On a long-running workstation, this is a guaranteed operational failure -- potentially filling `/var/log` which can cascade into system instability (journal full, services failing to log, etc.).

**Pre-identified issue #6: CONFIRMED.**

**Fix:** Create `ansible/roles/user/templates/sudo_logrotate.j2` and add a logrotate task to the user role as documented in Quick-Wins.md.

---

### GAP-02: PAM faillock has no `root_unlock_time` -- root can auto-unlock after 15 minutes

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/archlinux.yml`, lines 34-41
**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/defaults/main.yml`, lines 30-33
**Evidence:**

Quick-Wins.md (line 453) specifies:
```yaml
pam_faillock_root_unlock_time: -1  # Root: -1 = permanent lock (requires admin)
```

The actual faillock.conf content in the code:
```
dir = /run/faillock
deny = 3
fail_interval = 900
unlock_time = 900
audit
silent
```

There is **no `root_unlock_time` parameter** in the code at all. The variable `pam_faillock_root_unlock_time` does not exist in `defaults/main.yml`. Without `root_unlock_time`, root uses the same `unlock_time = 900` (15 minutes), meaning a brute-force attacker who locks root simply waits 15 minutes and tries again -- indefinitely.

On a single-user workstation, however, `root_unlock_time: -1` (permanent lock) is equally dangerous -- if root gets locked and there is no other admin account, the only recovery is booting from live media.

**The code made the safer choice for a single-user workstation** by omitting permanent root lockout. But this was done silently (no documentation, no variable, no comment) rather than as a deliberate, documented decision.

**Pre-identified issue (related to #8): CONFIRMED** -- `pam_faillock_root_unlock_time` does not exist in code.

---

### GAP-03: No `pam_faillock_enabled` toggle -- faillock is always applied on Arch

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/archlinux.yml`, lines 31-45
**Evidence:**

Quick-Wins.md (line 447) specifies:
```yaml
pam_faillock_enabled: true
```

The actual code has **no conditional**. The faillock configuration task always runs on Arch Linux systems. There is no `when: pam_faillock_enabled | bool` guard. The variable `pam_faillock_enabled` does not exist in `defaults/main.yml`.

This means there is **no way to disable faillock** without either:
- Removing the task from the role
- Setting `base_system_faillock_deny` to a very high number

This violates the principle of optional security features and deviates from the pattern used in the sysctl role (`sysctl_security_enabled: true`) and docker role (individual feature toggles).

---

### GAP-04: 9+ documented variables do not exist in code

**Pre-identified issue #8: CONFIRMED.** Here is the complete list of variables described in Quick-Wins.md that do NOT exist anywhere in the codebase:

| Variable | Described in QW | Status |
|----------|----------------|--------|
| `sudo_hardening_enabled` | QW-6 | MISSING -- sudo hardening has no toggle, always applies when `user_create_sudo_rule` is true |
| `sudo_timestamp_timeout` | QW-6 | MISSING -- hardcoded as `5` in task content |
| `sudo_use_pty` | QW-6 | MISSING -- hardcoded as `use_pty` in task content |
| `sudo_logfile` | QW-6 | MISSING -- hardcoded as `/var/log/sudo.log` in task content |
| `sudo_log_input` | QW-6 | MISSING -- not implemented |
| `sudo_log_output` | QW-6 | MISSING -- not implemented |
| `sudo_passwd_timeout` | QW-6 | MISSING -- not implemented |
| `sudo_authenticate_always` | QW-6 | MISSING -- not implemented |
| `firewall_ssh_rate_limit_enabled` | QW-4 | MISSING -- rate limit is always on when `firewall_allow_ssh` is true |
| `firewall_ssh_rate_limit` | QW-4 | MISSING -- hardcoded as `4/minute` in template |
| `firewall_ssh_rate_limit_burst` | QW-4 | MISSING -- burst not implemented at all |
| `pam_faillock_enabled` | QW-5 | MISSING -- no toggle |
| `pam_faillock_root_unlock_time` | QW-5 | MISSING -- not implemented |
| `pam_faillock_audit` | QW-5 | MISSING -- hardcoded as `audit` |
| `pam_faillock_silent` | QW-5 | MISSING -- hardcoded as `silent` |
| `docker_seccomp_profile` | QW-3 | MISSING |
| `docker_apparmor_profile` | QW-3 | MISSING |
| `docker_userland_proxy` | QW-3 | MISSING |
| `docker_iptables` | QW-3 | MISSING |
| `docker_ip_forward` | QW-3 | MISSING |
| `docker_ip_masq` | QW-3 | MISSING |
| `docker_log_opts` (with tag) | QW-3 | MISSING -- log-opts are hardcoded max-size/max-file only |
| `ssh_host_key_algorithms` | QW-1 | MISSING |
| `ssh_max_sessions` | QW-1 | MISSING |

**Count: 23 variables documented in Quick-Wins.md are not implemented in code.** The prompt estimated 9+; the actual count is 23. This represents a massive documentation-to-code divergence.

---

### GAP-05: Sudo hardening values are hardcoded, not variable-driven

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/user/tasks/main.yml`, lines 18-32
**Evidence:**

```yaml
- name: Ensure wheel group has sudo access with hardening
  ansible.builtin.copy:
    dest: /etc/sudoers.d/wheel
    content: |
      # Managed by Ansible
      %wheel ALL=(ALL:ALL) ALL
      Defaults timestamp_timeout=5
      Defaults use_pty
      Defaults logfile="/var/log/sudo.log"
```

The values `timestamp_timeout=5`, `use_pty`, and `logfile="/var/log/sudo.log"` are hardcoded strings in the `copy` module's `content:` parameter. They are not driven by variables from `defaults/main.yml`.

Quick-Wins.md describes these as separate variables (`sudo_timestamp_timeout: 5`, `sudo_use_pty: true`, `sudo_logfile: "/var/log/sudo.log"`) that should be configurable. The current implementation makes it impossible to change these values without editing the task file directly.

Additionally, Quick-Wins.md specifies the file should be a template (`sudoers_hardening.j2`), but the code uses `ansible.builtin.copy` with inline content instead of `ansible.builtin.template`. This is a design shortcut that reduces flexibility and testability.

---

### GAP-06: Sysctl missing 7 security parameters documented in Quick-Wins.md

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/sysctl/defaults/main.yml`
**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/sysctl/templates/sysctl.conf.j2`
**Evidence:**

Quick-Wins.md (lines 118-177) specifies these parameters. The following are **NOT present** in either the defaults or the template:

| Parameter | Quick-Wins.md | Code Status |
|-----------|--------------|-------------|
| `kernel.perf_event_paranoid: 3` | Line 127 | MISSING |
| `kernel.unprivileged_bpf_disabled: 1` | Line 128 | MISSING |
| `net.ipv4.tcp_timestamps: 0` | Line 162 | MISSING |
| `net.ipv6.conf.all.disable_ipv6: 1` | Line 169 | MISSING |
| `net.ipv6.conf.default.disable_ipv6: 1` | Line 170 | MISSING |
| `net.ipv6.conf.lo.disable_ipv6: 1` | Line 171 | MISSING |
| `fs.suid_dumpable: 0` | Line 176 | MISSING |
| `net.ipv6.conf.all.accept_redirects: 0` | Line 142 | MISSING |
| `net.ipv6.conf.default.accept_redirects: 0` | Line 143 | MISSING |
| `net.ipv6.conf.all.accept_source_route: 0` | Line 152 | MISSING |
| `net.ipv6.conf.default.accept_source_route: 0` | Line 153 | MISSING |

**11 security parameters** from the documented plan were not implemented. Notably:

- **IPv6 disable** (CHECK 2.2): Quick-Wins.md explicitly lists `net.ipv6.conf.all.disable_ipv6: 1`. The code does not contain any IPv6-related parameters at all -- not in defaults, not in the template. The documentation is misleading.
- **`kernel.perf_event_paranoid: 3`** and **`kernel.unprivileged_bpf_disabled: 1`**: These are critical for preventing side-channel attacks and BPF-based exploits. Their absence significantly weakens the kernel hardening.
- **`fs.suid_dumpable: 0`**: Prevents core dumps of SUID binaries (which may contain sensitive data). Missing.

**Pre-identified issue (related to #3 -- docs vs code): CONFIRMED for sysctl.**

---

## 3. Medium Issues (medium)

### MED-01: SSH `ssh_max_startups` value differs from Quick-Wins.md

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`, line 29
**Evidence:**

Code: `ssh_max_startups: "10:30:60"`
Quick-Wins.md (line 34): `ssh_max_startups: "4:50:10"`

These are significantly different policies:
- Code: Allow 10 unauthenticated connections, then 30% drop rate, max 60 connections
- Documentation: Allow 4 unauthenticated connections, then 50% drop rate, max 10 connections

The documentation value is significantly more restrictive. The code value (`10:30:60`) is barely restrictive at all -- 60 simultaneous unauthenticated connections is generous for a workstation. Neither value matches the other, and there is no explanation for the divergence.

**CHECK 1.3: CONFIRMED -- there is a discrepancy.** The code has the more permissive value.

---

### MED-02: SSH `ssh_kex_algorithms` includes algorithms not in Quick-Wins.md

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`, lines 39-43
**Evidence:**

Code KexAlgorithms:
```yaml
ssh_kex_algorithms:
  - curve25519-sha256
  - curve25519-sha256@libssh.org
  - diffie-hellman-group16-sha512
  - diffie-hellman-group18-sha512
```

Quick-Wins.md KexAlgorithms (line 53-55):
```yaml
ssh_kex_algorithms:
  - "curve25519-sha256"
  - "curve25519-sha256@libssh.org"
  - "diffie-hellman-group-exchange-sha256"
```

The code includes `diffie-hellman-group16-sha512` and `diffie-hellman-group18-sha512` (which require OpenSSH 7.3+) but omits `diffie-hellman-group-exchange-sha256` (which is more widely compatible). The documentation includes `diffie-hellman-group-exchange-sha256` but not the group16/group18 variants.

Neither the code nor the documentation lists the minimum OpenSSH version required for the selected algorithms.

**CHECK 1.2: PARTIALLY CONFIRMED.** The selected ciphers and KexAlgorithms require OpenSSH 6.7-7.3+. This is not documented as a requirement. PuTTY compatibility is not addressed.

---

### MED-03: SSH `ssh_host_key_algorithms` not implemented

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`
**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/tasks/main.yml`
**Evidence:**

Quick-Wins.md (lines 62-65) specifies:
```yaml
ssh_host_key_algorithms:
  - "ssh-ed25519"
  - "rsa-sha2-512"
  - "rsa-sha2-256"
```

**Neither the variable nor the `HostKeyAlgorithms` sshd_config directive exists in the code.** The SSH hardening task's loop (lines 53-65) does not include a `HostKeyAlgorithms` entry. This means the server will accept connections using any host key algorithm including older, weaker ones.

---

### MED-04: SSH `ssh_max_sessions` not implemented

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`
**Evidence:**

Quick-Wins.md (line 35) specifies:
```yaml
ssh_max_sessions: 10
```

This variable does not exist in the code. The `MaxSessions` directive is not set in sshd_config. Default OpenSSH value is 10, which happens to match, but this is implicit rather than explicit hardening.

---

### MED-05: SSH `ssh_macs` list differs from Quick-Wins.md

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`, lines 36-38
**Evidence:**

Code:
```yaml
ssh_macs:
  - hmac-sha2-512-etm@openssh.com
  - hmac-sha2-256-etm@openssh.com
```

Quick-Wins.md (lines 58-60):
```yaml
ssh_macs:
  - "hmac-sha2-512-etm@openssh.com"
  - "hmac-sha2-256-etm@openssh.com"
  - "umac-128-etm@openssh.com"
```

The code omits `umac-128-etm@openssh.com`. This is actually a more conservative choice (fewer MACs = smaller attack surface), but it diverges from the documentation without explanation.

---

### MED-06: Docker `docker_log_driver` default does not match Quick-Wins.md

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/defaults/main.yml`, line 15
**Evidence:**

Code: `docker_log_driver: "json-file"`
Quick-Wins.md (line 247): `docker_log_driver: "journald"`

Quick-Wins.md identifies `json-file` without rotation as a problem (line 221: "Logging through json-file without rotation (disk overflow)"). The code keeps `json-file` as default but adds `max-size` and `max-file` rotation options. This addresses the rotation concern but does not switch to journald as documented.

**CHECK 3.3: CONFIRMED.** The log driver was NOT changed to `journald` as specified in Quick-Wins.md. The code has `json-file` with rotation, which is a reasonable alternative but does not match the documented plan.

---

### MED-07: `kernel.yama.ptrace_scope: 2` breaks debuggers with no toggle

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/sysctl/defaults/main.yml`, line 36
**Evidence:**

```yaml
sysctl_kernel_yama_ptrace_scope: 2    # Prohibit ptrace except root
```

`ptrace_scope: 2` means only processes with `CAP_SYS_PTRACE` can ptrace. This **breaks gdb, strace, ltrace, perf, and any debugging tool** for non-root users. On a workstation used for development (which this is -- it's a "workstation bootstrap"), this is potentially destructive.

The only toggle is the global `sysctl_security_enabled: true`. There is no separate variable to control ptrace independently, so disabling ptrace requires disabling ALL sysctl security parameters.

**CHECK 2.1: CONFIRMED.** There is no per-parameter toggle and no warning in the defaults file about the development impact.

---

### MED-08: SSH handler lacks `listen:` directive

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/handlers/main.yml`, lines 1-5
**Evidence:**

```yaml
---
- name: Restart sshd
  ansible.builtin.service:
    name: sshd
    state: restarted
```

Per MEMORY.md project conventions: "Handlers use `listen:` for cross-role notification." The SSH handler does not have a `listen:` directive. This means other roles cannot trigger an sshd restart via a generic notification name.

Similarly, the Docker handler (`docker/handlers/main.yml`) lacks `listen:` on the "Restart docker" handler.

---

### MED-09: `base_system/tasks/main.yml` uses `/etc/vconsole.conf` which is Arch/systemd-specific

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/main.yml`, lines 50-57
**Evidence:**

```yaml
- name: Set console keymap
  ansible.builtin.copy:
    dest: /etc/vconsole.conf
    content: "KEYMAP={{ base_system_keymap }}\n"
```

This is in `main.yml` (the cross-platform task file), not in `archlinux.yml`. `/etc/vconsole.conf` is specific to systemd-based distributions and may not exist or be relevant on all Debian variants. On minimal Debian installations without systemd-consoled, this file does nothing. The task should be in the OS-specific include file or have a `when:` condition.

---

### MED-10: Docker daemon.json template lacks validation

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/tasks/main.yml`, lines 17-25
**Evidence:**

```yaml
- name: Deploy Docker daemon.json
  ansible.builtin.template:
    src: daemon.json.j2
    dest: /etc/docker/daemon.json
    owner: root
    group: root
    mode: '0644'
  notify: Restart docker
```

No `validate:` parameter. Contrast with:
- SSH role: `validate: '/usr/sbin/sshd -t -f %s'`
- User role: `validate: '/usr/sbin/visudo -cf %s'`

An invalid `daemon.json` will be deployed and Docker will crash on restart with a cryptic error. Adding `validate: 'python3 -m json.tool %s'` would catch JSON syntax errors before deployment.

---

## 4. Minor Issues (low)

### MIN-01: Inconsistent variable naming for faillock

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/defaults/main.yml`, lines 30-33

Variables use `base_system_faillock_*` prefix, which is correct per project conventions (`variable prefix matches role name`). However, Quick-Wins.md uses `pam_faillock_*` prefix. This naming inconsistency means someone reading the documentation will search for `pam_faillock_deny` and not find it -- it's actually `base_system_faillock_deny`.

---

### MIN-02: SSH defaults file missing YAML quoting consistency

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`

Some string values are quoted (`ssh_permit_root_login: "no"`), some are not (`ssh_key_type: ed25519`). While YAML handles this correctly, it is inconsistent. The ciphers/MACs/kex algorithms are not quoted in defaults but are quoted in Quick-Wins.md.

---

### MIN-03: Docker role comment says "volume permissions" but no mitigation is offered

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/defaults/main.yml`, line 21

```yaml
docker_userns_remap: ""          # "default" for user namespace isolation (breaks volume permissions!)
```

The comment mentions the breakage but offers no mitigation (e.g., documentation on how to fix volume permissions, or a companion task to set up subordinate UID/GID mappings).

---

### MIN-04: Firewall defaults missing rate-limit configuration variables

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/defaults/main.yml`

The defaults file has no rate-limit variables at all (`firewall_ssh_rate_limit_enabled`, `firewall_ssh_rate_limit`, `firewall_ssh_rate_limit_burst`). The rate limit is unconditionally embedded in the template via the `firewall_allow_ssh` conditional. There is no way to allow SSH without rate limiting, or to adjust the rate limit value, without editing the template.

---

### MIN-05: `base_system/tasks/archlinux.yml` uses `copy` instead of `template` for faillock.conf

**File:** `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/archlinux.yml`, lines 31-45

The task uses `ansible.builtin.copy` with `content:` containing Jinja2 variable interpolation. This works because Ansible evaluates `content:` at runtime, but it is semantically misleading -- `copy` with `content:` is meant for static content. Using `ansible.builtin.template` with a `.j2` file would be cleaner, more testable, and consistent with how Quick-Wins.md describes the implementation (line 499: `template: src: faillock.conf.j2`).

---

## 5. Missing Roles (gap analysis)

The following security controls are NOT covered by any Quick Win:

| Control | Risk | Notes |
|---------|------|-------|
| **Automatic security updates** | High | No unattended-upgrades (Debian) or pacman-auto-update (Arch) |
| **Disk encryption verification** | High | No LUKS check or enforcement |
| **Audit framework (auditd)** | High | No system call auditing beyond PAM faillock audit flag |
| **AppArmor/SELinux** | High | No MAC enforcement -- Docker AppArmor profile referenced in QW docs but not implemented |
| **USB device control** | Medium | No USBGuard or udev rules for removable media |
| **Automatic screen lock** | Medium | No idle timeout lockscreen enforcement |
| **Password quality** (pwquality) | Medium | PAM faillock counts attempts but no password complexity rules |
| **Network segmentation** (VLANs) | Medium | Flat network assumed |
| **Intrusion detection** (AIDE/OSSEC) | Medium | No file integrity monitoring |
| **Secure boot verification** | Low | No Secure Boot or TPM checks |
| **Kernel module blacklisting** | Low | No firewire, thunderbolt, or usb-storage blacklisting |

---

## 6. Architecture Questions

### ARCH-01: Should security defaults be secure or conservative?

The Docker role defaults to "insecure but compatible." The sysctl role defaults to "secure." There is no consistent project-wide policy on whether security features should be opt-in or opt-out. This architectural inconsistency means an operator cannot predict the behavior of a new role.

**Question:** Should the project adopt a policy of "secure by default with opt-out" or "compatible by default with opt-in"?

### ARCH-02: Role dependency ordering and self-lockout prevention

The SSH role (`AllowGroups wheel`) and user role (`user_groups: [wheel]`) are independent roles with no declared dependency. If the playbook runs `ssh` before `user`, or if `user` fails mid-run, the SSH restriction is applied before the user is in the correct group. There is no orchestration layer that prevents this.

**Question:** Should there be an explicit dependency declared in `ssh/meta/main.yml` on the `user` role, or should a pre-flight playbook verify prerequisites?

### ARCH-03: Global vs per-parameter security toggles

The sysctl role has one toggle (`sysctl_security_enabled`) for all security parameters. The Docker role has per-feature toggles but insecure defaults. The faillock configuration has no toggle at all. The sudo hardening has no toggle (tied to `user_create_sudo_rule`). The SSH rate limit has no toggle (tied to `firewall_allow_ssh`).

**Question:** Should all security features follow a consistent pattern (e.g., `<role>_<feature>_enabled: true` with individual parameter variables)?

### ARCH-04: lineinfile accumulation in SSH role

The SSH role uses `lineinfile` to modify `/etc/ssh/sshd_config` in-place. Over multiple runs with different variable values, orphaned directives from previous configurations are not cleaned up. For example, if `ssh_allow_groups` changes from `["wheel"]` to `["ssh-users"]`, the old `AllowGroups wheel` line is replaced. But if `ssh_allow_groups` is later set to `[]`, the `when: ssh_allow_groups | length > 0` condition skips the task, leaving the old `AllowGroups` directive in place. There is no task to remove `AllowGroups` when the list is empty.

**Question:** Should the SSH role use a full template (`sshd_config.j2`) instead of piecemeal `lineinfile` modifications? This would ensure complete state management and prevent orphaned directives.

### ARCH-05: PAM faillock in archlinux.yml mixes concerns

The `archlinux.yml` file is titled "Arch Linux: pacman configuration" but contains both pacman configuration AND PAM faillock configuration. These are unrelated concerns. The PAM faillock configuration is cross-platform in principle (the `faillock.conf` file format is the same), but the PAM module integration (which PAM file to edit) is OS-specific.

**Question:** Should faillock configuration be split into a separate task file (`pam.yml`) with OS-specific PAM integration subtasks, keeping `archlinux.yml` focused on pacman?

---

## 7. Recommendations

Prioritized by impact (highest first):

### P0 -- Immediate (security/operational blockers)

1. **Fix nftables rate limit to be per-source-IP** (CRIT-01). Implement the dynamic set pattern from Quick-Wins.md. Add variables `firewall_ssh_rate_limit_enabled`, `firewall_ssh_rate_limit`, and `firewall_ssh_rate_limit_burst` to `firewall/defaults/main.yml`.

2. **Add SSH AllowGroups pre-flight check** (CRIT-05). Add an `assert` or `fail` task that verifies the target user is in at least one of the allowed groups before applying `AllowGroups` to sshd_config. Example:
   ```yaml
   - name: Verify user is in SSH allowed groups
     ansible.builtin.assert:
       that: ssh_allow_groups | intersect(ansible_facts['getent_group'].keys()) | length > 0
       fail_msg: "LOCKOUT RISK: User {{ ssh_user }} may not be in any of {{ ssh_allow_groups }}"
     when: ssh_allow_groups | length > 0
   ```

3. **Add PAM faillock to Debian** (CRIT-04). At minimum, deploy `faillock.conf` in the cross-platform section. PAM integration tasks should be OS-specific.

### P1 -- High Priority (security/correctness)

4. **Change Docker security defaults or add clear warnings** (CRIT-02). Either set `docker_icc: false`, `docker_no_new_privileges: true`, `docker_live_restore: true` as defaults, or add a prominent comment block in the defaults file stating that security features must be explicitly enabled.

5. **Add logrotate for sudo.log** (GAP-01). Create the template and task as documented in Quick-Wins.md.

6. **Add daemon.json validation** (MED-10). Add `validate: 'python3 -m json.tool %s'` to the Docker template task.

7. **Implement missing sysctl security parameters** (GAP-06). Add the 11 missing parameters, especially `kernel.perf_event_paranoid`, `kernel.unprivileged_bpf_disabled`, and `fs.suid_dumpable`.

### P2 -- Medium Priority (completeness/maintainability)

8. **Add per-parameter toggles to sysctl** (MED-07, ARCH-03). Allow `ptrace_scope` to be disabled independently for development workstations without disabling all security sysctl parameters.

9. **Implement missing SSH parameters** (MED-03, MED-04). Add `ssh_host_key_algorithms` and `ssh_max_sessions` variables and their corresponding sshd_config directives.

10. **Add missing variables for sudo hardening** (GAP-05). Replace the hardcoded `copy content:` with a proper template driven by variables from `defaults/main.yml`.

11. **Add `pam_faillock_enabled` toggle** (GAP-03). Add the variable to `defaults/main.yml` and guard the faillock task with `when: pam_faillock_enabled | default(true) | bool`.

12. **Add `listen:` directives to SSH and Docker handlers** (MED-08). Follow project conventions.

### P3 -- Low Priority (polish/consistency)

13. **Move vconsole.conf task to OS-specific file** (MED-09).

14. **Reconcile Quick-Wins.md documentation with actual code** for all discrepancies identified above. Either update the code to match the docs, or update the docs to match the code. The current state where 23 documented variables don't exist is a maintenance and onboarding hazard.

15. **Use `ansible.builtin.template` instead of `ansible.builtin.copy content:`** for faillock.conf (MIN-05) and sudoers hardening (GAP-05).

---

## Appendix: QW Check Results Summary

| Check | Description | Result |
|-------|-------------|--------|
| CHECK 1.1 | SSH AllowGroups lockout risk | **CONFIRMED** -- no group membership verification |
| CHECK 1.2 | Cryptographic algorithm compatibility | **PARTIALLY CONFIRMED** -- requires OpenSSH 7.3+, not documented |
| CHECK 1.3 | MaxStartups discrepancy | **CONFIRMED** -- code has `10:30:60`, docs have `4:50:10` |
| CHECK 2.1 | ptrace_scope breaks debuggers | **CONFIRMED** -- no separate toggle |
| CHECK 2.2 | IPv6 disable missing | **CONFIRMED** -- not in code, described in docs |
| CHECK 3.1 | Docker security defaults insecure | **CONFIRMED** -- all 4 security features disabled by default |
| CHECK 3.2 | daemon.json fragile JSON | **PARTIALLY CONFIRMED** -- comma logic works but template lacks validation |
| CHECK 3.3 | Log driver not changed to journald | **CONFIRMED** -- code has `json-file` |
| CHECK 4.1 | nftables rate limit is global | **CONFIRMED** -- no per-IP tracking |
| CHECK 5.1 | PAM faillock Arch-only | **CONFIRMED** -- Debian has placeholder stub |
| CHECK 5.2 | root_unlock_time missing | **CONFIRMED** -- not implemented |
| CHECK 6.1 | sudo logrotate missing | **CONFIRMED** -- no logrotate task or template |
| CHECK 6.2 | sudo variables hardcoded | **CONFIRMED** -- 7+ variables from docs not in code |

## Appendix: Pre-Identified Issues Verification

| # | Issue | Verdict |
|---|-------|---------|
| 1 | Docker security ALL disabled by default | **CONFIRMED** |
| 2 | daemon.json.j2 fragile conditional JSON | **PARTIALLY CONFIRMED** -- comma logic correct, but no validation step |
| 3 | Quick-Wins.md describes secure defaults but code has insecure defaults | **CONFIRMED** -- applies to Docker, sysctl (missing params), firewall (global rate limit) |
| 4 | PAM faillock only in archlinux.yml | **CONFIRMED** |
| 5 | nftables rate limit is global not per-source-IP | **CONFIRMED** |
| 6 | sudo log without logrotate | **CONFIRMED** |
| 7 | SSH AllowGroups without user membership verification | **CONFIRMED** |
| 8 | 9+ documented variables don't exist in code | **CONFIRMED** -- actual count is 23 |
| 9 | N/A (prompt lists 9 issues, #9 is included in #8) | **CONFIRMED** as part of #8 |
