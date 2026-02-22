# Security Standards Reference

This document defines the security control ID mappings for the bootstrap project's Ansible roles. It establishes which external standards each setting aligns with, how to tag security tasks, and how profile-based security levels modify the baseline.

## Tiered Approach

The project uses a three-tier system to balance rigor with practicality:

- **Tier 1 (Primary)**: CIS Benchmark Level 1 Workstation + dev-sec.io ansible-collection-hardening -- the implementation baseline.
- **Tier 2 (Supplementary)**: DISA STIG CAT I + ANSSI BP-028 -- applied in the `security` profile or used to inform hardening decisions.
- **Tier 3 (Reference Only)**: NIST 800-53 Rev. 5 -- for cross-mapping tags, not direct implementation.

CIS L1 Workstation is the default security posture. The `security` profile adds CIS L2 controls and STIG CAT I requirements.

---

## Tier 1: Primary Standards

### CIS Benchmark Level 1 -- Workstation

The Center for Internet Security (CIS) Benchmarks are consensus-based configuration guidelines maintained by security practitioners. Level 1 (L1) recommendations are practical hardening measures that can be applied without significant impact on system usability.

**Control ID format:** `<section>.<subsection>.<item>` (e.g., `5.2.10` = SSH PermitRootLogin)

**CIS sections relevant to this project:**

| Section | Scope | Bootstrap Roles |
|---------|-------|-----------------|
| 1.x | Initial Setup -- filesystem config, bootloader, process hardening, core dumps | sysctl, base_system |
| 2.x | Services -- time synchronization, network services | ntp, ntp_audit |
| 3.x | Network Configuration -- firewall, sysctl network parameters | firewall, sysctl |
| 4.x | Logging and Auditing -- journald, auditd, logrotate | (planned: auditd, journald) |
| 5.x | Access, Authentication, Authorization -- SSH, PAM, sudo, user accounts | ssh, pam_hardening, user |
| 6.x | System Maintenance -- file permissions, user/group audit | base_system, user |

**How to tag in Ansible:**
```yaml
tags:
  - level1-workstation
  - cis_5.2.10
```

### dev-sec.io ansible-collection-hardening

The dev-sec.io project (5200+ GitHub stars) provides community-maintained Ansible roles for OS, SSH, and MySQL hardening. It is the de facto reference for Ansible security variable naming and inline documentation of sysctl parameters.

**Variable naming convention:**

| Role | Prefix | Examples |
|------|--------|----------|
| os_hardening | `os_*` | `os_auth_retries`, `os_auth_pw_max_age` |
| ssh_hardening | `ssh_*`, `sshd_*` | `sshd_permit_root_login`, `ssh_server_ports` |

**Key patterns adopted or referenced by this project:**

1. **`sysctl_config: {}` dict with inline comments** -- each kernel parameter has a comment explaining the security rationale and source standard (KSPP, DISA STIG, CIS).
2. **`sysctl_overwrite: {}` for user customization** -- users merge their overrides without losing the hardened defaults.
3. **`manage_*` boolean toggles per subsystem** -- e.g., `sysctl_security_kernel_hardening`, `sysctl_security_network_hardening`, `sysctl_security_filesystem_hardening`.
4. **`os_auth_*` variables for PAM/auth settings** -- unified naming for faillock, pwquality, and password aging.

---

## Tier 2: Supplementary Standards

### DISA STIG CAT I

Defense Information Systems Agency (DISA) Security Technical Implementation Guides (STIGs) categorize findings by severity. CAT I findings represent the highest risk -- vulnerabilities that could lead to direct system compromise if left unmitigated.

**Control ID format:** `RHEL-09-XXXXXX` (e.g., `RHEL-09-211015`)

**When to apply:** Security profile (`'security' in workstation_profiles`), or as a cross-reference tag on controls that happen to overlap with CIS L1.

**How to tag:**
```yaml
tags:
  - stig_cat1
  - RHEL-09-211015
```

### ANSSI BP-028 (French National Cybersecurity Agency)

ANSSI's recommendations for GNU/Linux system hardening (BP-028) define four increasing levels of security. They provide a European perspective on system hardening that complements CIS and DISA with additional context on kernel parameters and service isolation.

**Levels:** Minimal, Intermediate, Enhanced, High

**When to apply:** As a reference when making hardening decisions, particularly for kernel parameter selection. Not directly tagged in Ansible tasks unless a control exists only in ANSSI guidance.

---

## Tier 3: Reference Only

### NIST 800-53 Rev. 5

The NIST Special Publication 800-53 Revision 5 defines security and privacy controls for federal information systems. It is a high-level control framework, not an implementation guide.

**Use case:** Cross-mapping only. Following the ansible-lockdown pattern, NIST control families appear as tags on tasks that already implement a CIS or STIG control (e.g., `NIST800-53R5_IA-5` on an SSH authentication task).

**Control families relevant to this project:**

| Family | Name | Typical Mapping |
|--------|------|-----------------|
| AC | Access Control | SSH AllowGroups, firewall rules |
| AU | Audit and Accountability | auditd, journald, sudo logging |
| CM | Configuration Management | sysctl, package manager config |
| IA | Identification and Authentication | SSH key auth, PAM faillock, password policy |
| SC | System and Communications Protection | Crypto algorithms, firewall, network sysctl |
| SI | System and Information Integrity | ASLR, SUID protections, BPF restrictions |

---

## Control Mapping Table

This table maps the project's implemented security settings to external standards. The **CIS Control** column uses CIS Benchmark for Linux (Workstation profile) numbering. The **dev-sec Variable** column shows the equivalent variable name in the dev-sec.io ansible-collection-hardening project. Where CIS has no direct control, the column shows `--`.

### SSH (`ssh` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| PermitRootLogin no | `ssh_permit_root_login: "no"` | 5.2.10 | `sshd_permit_root_login: false` | |
| PasswordAuthentication no | `ssh_password_authentication: "no"` | 5.2.6 | `sshd_password_authentication: false` | |
| MaxAuthTries 3 | `ssh_max_auth_tries: 3` | 5.2.7 | `sshd_max_auth_tries: 3` | |
| AllowGroups wheel | `ssh_allow_groups: ["wheel"]` | 5.2.15 | `sshd_allow_groups` | |
| Ciphers (AEAD only) | `ssh_ciphers` | 5.2.13 | `sshd_ciphers` | chacha20, aes256-gcm, aes128-gcm |
| MACs (ETM only) | `ssh_macs` | 5.2.14 | `sshd_macs` | hmac-sha2-512-etm, hmac-sha2-256-etm, umac-128-etm |
| KexAlgorithms (modern) | `ssh_kex_algorithms` | 5.2.12 | `sshd_kex_algorithms` | curve25519, DH group16/18, DH group-exchange-sha256 |
| HostKeyAlgorithms | `ssh_host_key_algorithms` | -- | `sshd_host_key_algorithms` | ed25519, rsa-sha2-512, rsa-sha2-256 |
| LogLevel VERBOSE | `ssh_log_level: "VERBOSE"` | 5.2.5 | `sshd_log_level: verbose` | Logs key fingerprint on login |
| PermitEmptyPasswords no | `ssh_permit_empty_passwords: "no"` | 5.2.9 | `sshd_permit_empty_passwords: false` | |
| X11Forwarding no | `ssh_x11_forwarding: "no"` | 5.2.11 | `sshd_x11_forwarding: false` | Prevents X11 sniffing |
| MaxStartups 10:30:60 | `ssh_max_startups: "10:30:60"` | 5.2.21 | `sshd_max_startups` | DoS protection |
| MaxSessions 10 | `ssh_max_sessions: 10` | 5.2.22 | `sshd_max_sessions` | |
| ClientAliveInterval 300 | `ssh_client_alive_interval: 300` | 5.2.16 | `sshd_client_alive_interval` | |
| ClientAliveCountMax 2 | `ssh_client_alive_count_max: 2` | 5.2.17 | `sshd_client_alive_count_max` | Timeout = 600s |
| Banner | `ssh_banner_enabled: false` | 5.2.18 | `sshd_banner` | Optional legal warning |
| Compression no | `ssh_compression: "no"` | -- | `sshd_compression: false` | CRIME-like attack mitigation |
| AllowTcpForwarding no | `ssh_allow_tcp_forwarding: "no"` | -- | `sshd_allow_tcp_forwarding: false` | |
| AllowAgentForwarding no | `ssh_allow_agent_forwarding: "no"` | -- | `sshd_allow_agent_forwarding: false` | |
| RekeyLimit 512M 1h | `ssh_rekey_limit: "512M 1h"` | -- | -- | dev-sec recommendation |

### Sysctl -- Kernel Hardening (`sysctl` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| randomize_va_space: 2 | `sysctl_kernel_randomize_va_space: 2` | 1.5.2 | `kernel.randomize_va_space: 2` | ASLR full randomization |
| kptr_restrict: 2 | `sysctl_kernel_kptr_restrict: 2` | -- | `kernel.kptr_restrict: 2` | Hide kernel pointers |
| dmesg_restrict: 1 | `sysctl_kernel_dmesg_restrict: 1` | -- | `kernel.dmesg_restrict: 1` | KSPP recommended |
| ptrace_scope: 1 | `sysctl_kernel_yama_ptrace_scope: 1` | -- | `kernel.yama.ptrace_scope: 2` | We use 1 for dev workstation (gdb works) |
| perf_event_paranoid: 3 | `sysctl_kernel_perf_event_paranoid: 3` | -- | `kernel.perf_event_paranoid: 2` | Side-channel protection, DISA STIG V-258076 |
| unprivileged_bpf_disabled: 1 | `sysctl_kernel_unprivileged_bpf_disabled: 1` | -- | `kernel.unprivileged_bpf_disabled: 1` | BPF exploit mitigation, KSPP |
| tty_ldisc_autoload: 0 | `sysctl_kernel_tty_ldisc_autoload: 0` | -- | -- | CVE-2017-2636 class, KSPP |
| unprivileged_userfaultfd: 0 | `sysctl_vm_unprivileged_userfaultfd: 0` | -- | -- | Heap spray mitigation, KSPP |
| mmap_min_addr: 65536 | `sysctl_vm_mmap_min_addr: 65536` | -- | `vm.mmap_min_addr: 65536` | Null deref protection, KSPP |

### Sysctl -- Network Hardening (`sysctl` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| tcp_syncookies: 1 | `sysctl_net_ipv4_tcp_syncookies: 1` | 3.2.8 | `net.ipv4.tcp_syncookies: 1` | SYN flood protection |
| rp_filter: 1 | `sysctl_net_ipv4_rp_filter: 1` | 3.2.7 | `net.ipv4.conf.all.rp_filter: 1` | Reverse path filtering |
| accept_redirects: 0 | `sysctl_net_ipv4_accept_redirects: 0` | 3.2.2 | `net.ipv4.conf.all.accept_redirects: 0` | MITM prevention |
| send_redirects: 0 | `sysctl_net_ipv4_send_redirects: 0` | 3.2.1 | `net.ipv4.conf.all.send_redirects: 0` | |
| accept_source_route: 0 | `sysctl_net_ipv4_accept_source_route: 0` | 3.2.3 | `net.ipv4.conf.all.accept_source_route: 0` | |
| log_martians: 1 | `sysctl_net_ipv4_log_martians: 1` | 3.2.4 | `net.ipv4.conf.all.log_martians: 1` | Spoofed packet logging |
| icmp_echo_ignore_broadcasts: 1 | `sysctl_net_ipv4_icmp_echo_ignore_broadcasts: 1` | 3.2.5 | `net.ipv4.icmp_echo_ignore_broadcasts: 1` | Smurf attack mitigation |
| icmp_ignore_bogus_error_responses: 1 | `sysctl_net_ipv4_icmp_ignore_bogus_error_responses: 1` | -- | `net.ipv4.icmp_ignore_bogus_error_responses: 1` | |
| tcp_timestamps: 0 | `sysctl_net_ipv4_tcp_timestamps: 0` | 3.3.10 | -- | Uptime fingerprint prevention |
| tcp_rfc1337: 1 | `sysctl_net_ipv4_tcp_rfc1337: 1` | -- | `net.ipv4.tcp_rfc1337: 1` | TIME_WAIT assassination |
| bpf_jit_harden: 2 | `sysctl_net_core_bpf_jit_harden: 2` | -- | `net.core.bpf_jit_harden: 2` | JIT spray mitigation, KSPP |
| IPv6 accept_redirects: 0 | `sysctl_net_ipv6_accept_redirects: 0` | 3.2.2 | `net.ipv6.conf.all.accept_redirects: 0` | |
| IPv6 accept_source_route: 0 | `sysctl_net_ipv6_accept_source_route: 0` | 3.2.3 | `net.ipv6.conf.all.accept_source_route: 0` | |

### Sysctl -- Filesystem Protection (`sysctl` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| suid_dumpable: 0 | `sysctl_fs_suid_dumpable: 0` | 1.5.1 | `fs.suid_dumpable: 0` | No core dumps from SUID binaries |
| protected_hardlinks: 1 | `sysctl_fs_protected_hardlinks: 1` | -- | `fs.protected_hardlinks: 1` | |
| protected_symlinks: 1 | `sysctl_fs_protected_symlinks: 1` | -- | `fs.protected_symlinks: 1` | |
| protected_fifos: 2 | `sysctl_fs_protected_fifos: 2` | -- | -- | TOCTOU race mitigation, KSPP |
| protected_regular: 2 | `sysctl_fs_protected_regular: 2` | -- | -- | KSPP recommended |

### Firewall (`firewall` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| Default deny inbound | `firewall_enabled: true` | 3.4.1.1 | -- | nftables drop policy |
| SSH rate limit per-IP | `firewall_ssh_rate_limit_enabled: true` | 3.4.1.4 | -- | 4/minute burst 2, per-source-IP |

### Docker (`docker` role)

Docker settings reference the CIS Docker Benchmark (separate from the OS benchmark).

| Setting | Our Variable | CIS Docker | dev-sec Variable | Notes |
|---------|-------------|------------|------------------|-------|
| userns-remap: default | `docker_userns_remap: "default"` | 2.8 | -- | User namespace isolation |
| icc: false | `docker_icc: false` | 2.1 | -- | Disable inter-container communication |
| no-new-privileges: true | `docker_no_new_privileges: true` | 5.25 | -- | Block setuid escalation |
| live-restore: true | `docker_live_restore: true` | 2.14 | -- | Containers survive daemon restart |
| log-driver: journald | `docker_log_driver: "journald"` | 2.12 | -- | Centralized logging |

### User and Sudo (`user` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| timestamp_timeout: 5 | `user_sudo_timestamp_timeout: 5` | 5.3.1 | -- | CIS requires <= 5 minutes |
| use_pty | `user_sudo_use_pty: true` | 5.3.2 | -- | PTY injection protection |
| logfile | `user_sudo_logfile: "/var/log/sudo.log"` | 5.3.3 | -- | Command audit trail |
| logrotate | `user_sudo_logrotate_enabled: true` | 4.3 | -- | Prevent unbounded log growth |

### PAM Hardening (`pam_hardening` role)

| Setting | Our Variable | CIS Control | dev-sec Variable | Notes |
|---------|-------------|-------------|------------------|-------|
| faillock deny=3 | `pam_faillock_deny: 3` | 5.4.2 | `os_auth_retries: 5` | We use stricter value than dev-sec |
| faillock unlock_time=900 | `pam_faillock_unlock_time: 900` | 5.4.2 | `os_auth_lockout_time: 600` | 15-minute lockout |
| faillock even_deny_root | `pam_faillock_even_deny_root: true` | -- | -- | Root subject to lockout |
| faillock audit | `pam_faillock_audit: true` | -- | -- | Log failed attempts to audit |

---

## Tagging Convention

Every security-relevant Ansible task should carry standardized tags for selective execution and auditability.

### Tag Format

```yaml
- name: "5.2.10 | Ensure SSH root login is disabled"
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PermitRootLogin'
    line: 'PermitRootLogin no'
  tags:
    - level1-workstation
    - cis_5.2.10
    - ssh
    - security
    - NIST800-53R5_IA-2
```

### Tag Rules

1. **CIS level tag** -- always one of: `level1-workstation`, `level2-workstation`
2. **CIS control ID** -- format `cis_X.Y.Z` matching the benchmark numbering
3. **NIST cross-reference** (if applicable) -- format `NIST800-53R5_XX-N` (following the ansible-lockdown convention)
4. **STIG ID** (if applicable) -- format `RHEL-09-XXXXXX`
5. **Role name tag** -- always present (e.g., `ssh`, `sysctl`, `firewall`)
6. **`security` tag** -- present on all hardening tasks, enabling `--tags security` to run all hardening at once

### Tag Usage Examples

Run only CIS Level 1 Workstation controls:
```bash
ansible-playbook workstation.yml --tags level1-workstation
```

Run all security hardening:
```bash
ansible-playbook workstation.yml --tags security
```

Run SSH hardening only:
```bash
ansible-playbook workstation.yml --tags ssh,security
```

---

## Profile-Based Security Levels

The project supports multiple security profiles. Each profile adjusts the baseline CIS L1 posture for its intended use case.

| Profile | Security Level | Key Differences |
|---------|---------------|-----------------|
| base | CIS L1 Workstation | Default secure. All controls in the mapping table above are active. Developer-friendly defaults (ptrace_scope: 1, docker ICC off). |
| developer | CIS L1 -- relaxed | ptrace_scope: 1 (gdb/strace work on child processes). Docker ICC optionally allowed for compose-based dev workflows. perf_event_paranoid: 2 instead of 3 if profiling is needed. |
| gaming | CIS L1 -- minimal | Relaxed kernel parameters where they affect performance. tcp_timestamps may be re-enabled for multiplayer networking. Power management takes priority over some filesystem protections. |
| security | CIS L2 + STIG CAT I | Full hardening. ptrace_scope: 2 (root-only). auditd with immutable rules (-e 2). STIG CAT I controls enforced. All optional security features enabled (docker userns-remap, faillock even_deny_root). |

### Profile Application

Profiles are selected via the `workstation_profiles` variable and control which security level applies:

```yaml
# inventory/host_vars/workstation.yml
workstation_profiles:
  - base
  - developer
```

Roles check profile membership to adjust defaults:
```yaml
# Example: adjust ptrace_scope based on profile
sysctl_kernel_yama_ptrace_scope: >-
  {{ 2 if 'security' in workstation_profiles else 1 }}
```

---

## References

| Standard | Document | URL |
|----------|----------|-----|
| CIS Benchmark | CIS Benchmark for Linux (latest) | https://www.cisecurity.org/benchmark/distribution_independent_linux |
| dev-sec.io | ansible-collection-hardening | https://github.com/dev-sec/ansible-collection-hardening |
| DISA STIG | RHEL 9 STIG | https://public.cyber.mil/stigs/ |
| ANSSI BP-028 | Recommendations for GNU/Linux | https://www.ssi.gouv.fr/guide/recommandations-de-securite-relatives-a-un-systeme-gnulinux/ |
| NIST 800-53 | Rev. 5 Security Controls | https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final |
| ansible-lockdown | RHEL9-CIS | https://github.com/ansible-lockdown/RHEL9-CIS |
| konstruktoid | ansible-role-hardening | https://github.com/konstruktoid/ansible-role-hardening |

---

Back to [[Role Requirements|standards/role-requirements]] | [[Home]]
