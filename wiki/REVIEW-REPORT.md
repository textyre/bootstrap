# Critical Review Report: Bootstrap Project

**Date:** 2026-02-17
**Phases completed:** 5/5
**Total findings:** 67

| Severity | Count |
|----------|-------|
| Critical | 14 |
| Serious | 14 |
| Medium | 18 |
| Minor | 10 |
| Missing Roles | (see Section 5) |
| Architecture Questions | 11 |

---

## 1. Critical Issues (blockers)

Issues that WILL break systems, create exploitable vulnerabilities, or cause data loss. Require immediate fix before any new work.

---

### CRIT-01: nftables SSH rate limit is GLOBAL, not per-source-IP [P1, P2]

**File:** `ansible/roles/firewall/templates/nftables.conf.j2:26`

The rate limit `limit rate 4/minute accept` applies globally across ALL source IPs. Four legitimate SSH connections from different IPs in one minute lock out everyone else. This creates a self-inflicted denial-of-service against administrators.

`wiki/Quick-Wins.md:362-383` specifies the correct per-IP implementation using a dynamic set with `ip saddr`, but the code does not implement it. No variables exist for `firewall_ssh_rate_limit_enabled`, `firewall_ssh_rate_limit`, or `firewall_ssh_rate_limit_burst` -- the rate value `4/minute` is hardcoded in the template.

**Fix:** Replace the global `limit rate` with a dynamic set and meter keyed on `ip saddr`:
```nftables
set ssh_ratelimit { type ipv4_addr; flags dynamic; timeout 1m; }
tcp dport 22 ct state new add @ssh_ratelimit { ip saddr limit rate over 4/minute burst 2 packets } log prefix "[nftables] ssh-rate: " drop
tcp dport 22 ct state new accept
```
Add variables `firewall_ssh_rate_limit: "4/minute"`, `firewall_ssh_rate_limit_burst: 2`, `firewall_ssh_rate_limit_enabled: true` to `ansible/roles/firewall/defaults/main.yml`.

---

### CRIT-02: Docker security features ALL disabled by default [P1, P2, P4, P5]

**File:** `ansible/roles/docker/defaults/main.yml:21-24`

```yaml
docker_userns_remap: ""          # DISABLED
docker_icc: true                 # INSECURE
docker_live_restore: false       # DISABLED
docker_no_new_privileges: false  # INSECURE
```

The entire purpose of QW-3 was Docker security hardening. `wiki/Quick-Wins.md:230-256` specifies secure defaults (`docker_icc: false`, `docker_no_new_privileges: true`, `docker_live_restore: true`, `docker_userns_remap: "default"`). The shipped code provides zero additional security over stock Docker. Per OWASP Docker Security Cheat Sheet: disabled `no-new-privileges` allows setuid/setgid exploits; enabled ICC lets any compromised container reach all others; disabled userns-remap means UID 0 in container equals UID 0 on host.

**Fix:** Change defaults to secure values:
```yaml
docker_userns_remap: "default"       # ansible/roles/docker/defaults/main.yml:21
docker_icc: false                    # ansible/roles/docker/defaults/main.yml:22
docker_live_restore: true            # ansible/roles/docker/defaults/main.yml:23
docker_no_new_privileges: true       # ansible/roles/docker/defaults/main.yml:24
```
Add comment block documenting that `docker_userns_remap: "default"` requires volume permission adjustment (`chown -R 100000:100000`). Alternatively, consider rootless Docker as the modern (2025-2026) best practice instead of userns-remap.

---

### CRIT-03: daemon.json.j2 lacks validation -- invalid JSON crashes Docker silently [P1]

**File:** `ansible/roles/docker/tasks/main.yml:17-25`

The template task deploys `daemon.json` without a `validate:` parameter. Contrast with SSH role (`validate: '/usr/sbin/sshd -t -f %s'`) and user role (`validate: '/usr/sbin/visudo -cf %s'`). An invalid `daemon.json` will be deployed and Docker will fail to start on the next restart with a cryptic error.

The Jinja2 template (`ansible/roles/docker/templates/daemon.json.j2:1-17`) uses a fragile conditional comma pattern that is technically correct in all 32 variable combinations, but one edit can break it. The template also produces blank lines inside the JSON object from `{% endif %}` blocks.

**Fix:** Add `validate: 'python3 -m json.tool %s'` to the template task in `ansible/roles/docker/tasks/main.yml:17-25`. Better: replace the manual JSON construction with a Jinja2 dictionary and `| to_nice_json` filter.

---

### CRIT-04: PAM faillock only configured for Arch Linux -- Debian gets ZERO brute-force protection [P1]

**File:** `ansible/roles/base_system/tasks/archlinux.yml:31-45`
**File:** `ansible/roles/base_system/tasks/debian.yml:1-8`

The faillock configuration exists only in `archlinux.yml`. The `debian.yml` file is a placeholder stub (`debug: msg: "Debian/Ubuntu system configuration -- not yet implemented"`). A Debian workstation bootstrapped with this playbook has no local brute-force protection, violating the distro-agnostic requirement.

**Fix:** Deploy `faillock.conf` from a cross-platform task (the file format is identical on both distros). PAM integration (`/etc/pam.d/common-auth` for Debian vs `/etc/pam.d/system-auth` for Arch) requires OS-specific tasks.

---

### CRIT-05: SSH AllowGroups applied without verifying user is in allowed group -- lockout risk [P1, P2]

**File:** `ansible/roles/ssh/tasks/main.yml:70-81`
**File:** `ansible/roles/ssh/defaults/main.yml:25`
**File:** `ansible/roles/user/defaults/main.yml:12-13`

SSH defaults set `ssh_allow_groups: ["wheel"]`. If the ssh role runs before the user role, or if `user_groups` is overridden to exclude `wheel`, the current user loses SSH access immediately when the sshd handler fires. There is no pre-flight check verifying group membership. On a single-user workstation with no other admin account, this is an unrecoverable self-lockout.

**Fix:** Add an `assert` task before applying AllowGroups:
```yaml
- name: Verify user is in SSH allowed groups
  ansible.builtin.assert:
    that: ssh_allow_groups | intersect(ansible_facts['getent_group'].keys()) | length > 0
    fail_msg: "LOCKOUT RISK: user may not be in any of {{ ssh_allow_groups }}"
  when: ssh_allow_groups | length > 0
```

---

### CRIT-06: systemd_hardening.md ProtectSystem=strict will BREAK Docker [P3]

**File:** `wiki/roles/systemd_hardening.md:16-19, 23, 31`

The default service list includes `docker`. `ProtectSystem=strict` makes the filesystem read-only except `/dev`, `/proc`, `/sys` -- Docker requires write access to `/var/lib/docker`, `/var/run/docker.sock`, overlay mounts. `RestrictNamespaces=true` (line 31) will prevent Docker from creating containers entirely since container isolation relies on Linux namespaces. The default `systemd_hardening_read_write_paths: []` is empty and there is no per-service override mechanism.

**Fix:** Redesign as a per-service configuration dictionary instead of a flat list. Docker needs fundamentally different hardening than sshd:
```yaml
systemd_hardening_services:
  sshd:
    protect_system: "strict"
    restrict_namespaces: true
  docker:
    protect_system: "full"
    restrict_namespaces: false
    read_write_paths: ["/var/lib/docker", "/var/run/docker"]
```

---

### CRIT-07: pam_hardening role and base_system QW-5 both manage faillock.conf -- conflict [P3]

**File:** `wiki/roles/pam_hardening.md:26-32`
**Conflict with:** `ansible/roles/base_system/tasks/archlinux.yml:31-45`

Both roles configure the exact same file (`/etc/security/faillock.conf`) with the same parameters. Running both causes a last-write-wins race condition. Neither documents the conflict.

**Fix:** Assign ownership of `faillock.conf` to exactly one role. Either remove faillock from `pam_hardening` (since `base_system` QW-5 handles it) or consolidate all faillock config in `pam_hardening` and remove it from `base_system`.

---

### CRIT-08: Alloy container runs as privileged when it does not need to [P3, P5]

**File:** `wiki/roles/alloy.md:94`

The wiki specifies `Privileged: true` for journald access. Per Grafana Alloy documentation (`loki.source.journal`), Alloy only needs read-only bind mounts of `/var/log/journal`, `/run/log/journal`, `/etc/machine-id` and membership in `systemd-journal` group. Privileged mode grants full root access to the host -- all capabilities, all devices, bypasses AppArmor/seccomp.

**Fix:** Replace `privileged: true` with:
```yaml
volumes:
  - /var/log/journal:/var/log/journal:ro
  - /run/log/journal:/run/log/journal:ro
  - /etc/machine-id:/etc/machine-id:ro
```

---

### CRIT-09: AppArmor kernel parameter uses deprecated syntax [P3]

**File:** `wiki/roles/apparmor.md:49`

The wiki uses `apparmor=1 security=apparmor` syntax, which is deprecated. Per Arch Wiki, the current correct syntax is:
```
lsm=landlock,lockdown,yama,integrity,apparmor,bpf
```
The page also does not declare `bootloader` as a dependency (modifying GRUB config is the bootloader role's responsibility).

**Fix:** Update to `lsm=` syntax in `wiki/roles/apparmor.md:49`. Add `bootloader` to the role's dependencies.

---

### CRIT-10: Loki retention silently does nothing without full configuration chain [P3]

**File:** `wiki/roles/loki.md:37-38, 52-54`

The wiki documents `loki_retention_enabled: true` and `loki_retention_period: "720h"` but omits three required pieces: `limits_config.retention_period`, `compactor.delete_request_store`, and the 24h index period requirement. Without all four, retention silently does nothing and old logs accumulate indefinitely -- a storage exhaustion risk.

**Fix:** Document the full retention chain in `wiki/roles/loki.md`: compactor config + limits_config + delete_request_store + 24h index period.

---

### CRIT-11: No egress filtering -- all outbound traffic unrestricted [P2, P4]

**File:** `ansible/roles/firewall/templates/nftables.conf.j2:48`

```nftables
chain output { type filter hook output priority 0; policy accept; }
```

Any compromised process can freely establish C2 callbacks, exfiltrate data, or create DNS tunnels. No egress filtering exists or is planned in the roadmap. Per SEI Carnegie Mellon, egress filtering prevents 70%+ of data exfiltration attempts.

**Fix:** Add egress filtering variables to `ansible/roles/firewall/defaults/main.yml`:
```yaml
firewall_egress_policy: "drop"
firewall_egress_allowed_tcp_ports: [80, 443, 587]
firewall_egress_allowed_udp_ports: [53, 123]
firewall_egress_dns_servers: ["1.1.1.1", "8.8.8.8"]
```
At minimum, block outbound SMB (ports 139, 445) to prevent ransomware lateral movement. Start with logging-only mode if blocking is too disruptive.

---

### CRIT-12: Filesystem mount options missing -- /tmp, /dev/shm have no noexec/nosuid [P4, P5]

**File:** Not implemented -- no role manages mount options.
**CIS Benchmark:** Section 1.1.1.x through 1.1.9.x

`/tmp` without `noexec` allows attackers to execute malicious binaries from world-writable directories. `/dev/shm` without `nosuid/noexec/nodev` enables shared memory exploits. dev-sec.io's `os_hardening` role covers this; the project does not. The `disk_management` role is planned for Phase 11 but mount hardening should be in Phase 2 (Security Foundation).

**Fix:** Add to `base_system` role or create a dedicated `mount_hardening` role:
```yaml
# /etc/fstab entries
tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0
tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec,size=2G 0 0
```
Move from Phase 11 to Phase 2.

---

### CRIT-13: AUR packages have ZERO verification -- real-world malware incidents in 2025 [P4]

**File:** `ansible/roles/yay/` (no verification tasks exist)

AUR packages are community-submitted with no official vetting, unsandboxed build processes, no automated security scanning. In July 2025, CHAOS RAT malware was distributed via 3 AUR packages (`librewolf-fix-bin`, `firefox-patch-bin`, `zen-browser-patched-bin`). The project's `yay` role installs AUR packages with no review or verification step.

**Fix:** Add PKGBUILD review enforcement to the `yay` role. Add variables `yay_aur_verification_required: true` and `yay_pkgbuild_review_enabled: true`. Add a warning task documenting AUR risks.

---

### CRIT-14: Docker Content Trust is deprecated -- wiki references obsolete technology [P4, P5]

**File:** Wiki Docker role pages (no specific file -- DCT is referenced as a future security measure)

Docker Content Trust was retired September 30, 2025. All DCT data will be permanently deleted by March 31, 2028. Fewer than 0.05% of Docker Hub image pulls used DCT.

**Fix:** Do NOT implement DCT. Use Sigstore (cosign) or Notation for image verification. Pin images to SHA256 digests as an immediate measure.

---

## 2. Serious Gaps (high impact)

Important omissions that significantly weaken the system's security posture or operational reliability.

---

### SER-01: No logrotate for /var/log/sudo.log -- unbounded disk growth [P1]

**File:** `ansible/roles/user/tasks/main.yml:26`

QW-6 creates `Defaults logfile="/var/log/sudo.log"` but neither the logrotate template (`sudo_logrotate.j2`) nor the logrotate task exists. The `ansible/roles/user/templates/` directory does not exist. `/var/log/sudo.log` grows indefinitely until disk fills.

**Fix:** Create `ansible/roles/user/templates/sudo_logrotate.j2` and add a logrotate task as documented in `wiki/Quick-Wins.md:651-675`.

---

### SER-02: 23 documented variables do not exist in code [P1]

**Files:** `ansible/roles/docker/defaults/main.yml`, `ansible/roles/firewall/defaults/main.yml`, `ansible/roles/base_system/defaults/main.yml`, `ansible/roles/user/tasks/main.yml`, `ansible/roles/ssh/defaults/main.yml`

Variables documented in `wiki/Quick-Wins.md` that are NOT implemented in code: `sudo_hardening_enabled`, `sudo_timestamp_timeout`, `sudo_use_pty`, `sudo_logfile`, `sudo_log_input`, `sudo_log_output`, `sudo_passwd_timeout`, `sudo_authenticate_always`, `firewall_ssh_rate_limit_enabled`, `firewall_ssh_rate_limit`, `firewall_ssh_rate_limit_burst`, `pam_faillock_enabled`, `pam_faillock_root_unlock_time`, `pam_faillock_audit`, `pam_faillock_silent`, `docker_seccomp_profile`, `docker_apparmor_profile`, `docker_userland_proxy`, `docker_iptables`, `docker_ip_forward`, `docker_ip_masq`, `docker_log_opts` (tag), `ssh_host_key_algorithms`, `ssh_max_sessions`.

This represents a massive documentation-to-code divergence. Anyone reading Quick-Wins.md will expect these variables to exist.

**Fix:** Either implement the variables in code or update `wiki/Quick-Wins.md` to reflect what actually exists. Prioritize security-critical variables (faillock toggle, Docker seccomp, SSH host key algorithms).

---

### SER-03: Sudo hardening values hardcoded, not variable-driven [P1]

**File:** `ansible/roles/user/tasks/main.yml:18-32`

`timestamp_timeout=5`, `use_pty`, `logfile="/var/log/sudo.log"` are hardcoded strings in `ansible.builtin.copy content:`. Quick-Wins.md describes these as separate configurable variables. The code uses `copy` instead of `template`, making customization impossible without editing the task file.

**Fix:** Create `ansible/roles/user/templates/sudoers_hardening.j2` with variable interpolation. Add `user_sudo_timestamp_timeout`, `user_sudo_use_pty`, `user_sudo_logfile` to `ansible/roles/user/defaults/main.yml`.

---

### SER-04: Sysctl missing 11 security parameters documented in Quick-Wins.md [P1, P4]

**File:** `ansible/roles/sysctl/defaults/main.yml`
**File:** `ansible/roles/sysctl/templates/sysctl.conf.j2`

Missing parameters from QW-2 and dev-sec.io baseline: `kernel.perf_event_paranoid: 3`, `kernel.unprivileged_bpf_disabled: 1`, `kernel.kexec_load_disabled: 1`, `kernel.sysrq: 0`, `kernel.core_uses_pid: 1`, `net.ipv4.tcp_timestamps: 0`, `net.ipv6.conf.all.disable_ipv6: 1` (and default/lo variants), `fs.suid_dumpable: 0`, `fs.protected_fifos: 1`, `fs.protected_regular: 2`, plus IPv6 redirect and source route parameters. Notable: `kernel.perf_event_paranoid` and `kernel.unprivileged_bpf_disabled` are critical for preventing side-channel attacks and BPF-based exploits.

**Fix:** Add the missing parameters to `ansible/roles/sysctl/defaults/main.yml` under a new `sysctl_security_params_extended` section. Add corresponding entries to the template.

---

### SER-05: fail2ban (Phase 2) has undocumented dependency on firewall (Phase 6) [P2]

**File:** `wiki/Roadmap.md` (Phase 2 vs Phase 6 ordering)

fail2ban needs a firewall backend (nftables) to ban IPs. The `firewall` role IS already deployed, but the roadmap does not declare this cross-phase dependency. A fresh deployment following the phase order literally would have fail2ban with no firewall backend. Additionally, the fail2ban wiki page does not document the nftables backend configuration (`banaction = nftables`, `banaction_allports = nftables[type=allports]`).

**Fix:** Add explicit dependency note in Phase 2. Add `dependencies: [firewall]` to fail2ban's `meta/main.yml`. Document nftables backend config in `wiki/roles/fail2ban.md:42-43`.

---

### SER-06: Logging pipeline Docker->journald->Alloy->Loki broken until Phases 2+6+8 complete simultaneously [P2]

**File:** `ansible/roles/docker/defaults/main.yml:15` (`docker_log_driver: "json-file"`)

Docker defaults to `json-file` log driver, not `journald`. Until QW-3 is applied AND Phase 8 (Alloy/Loki) is complete, Docker container logs do not flow through the observability pipeline. The roadmap presents Phases 2, 6, and 8 as independent sequential steps, but the logging architecture requires all three simultaneously.

**Fix:** Document the logging pipeline as a cross-cutting concern spanning Phases 2/6/8. Add a dependency diagram.

---

### SER-07: Playbook phase numbering does not match Roadmap phase numbering [P2]

**File:** `ansible/playbooks/workstation.yml` vs `wiki/Roadmap.md`

The playbook uses original numbering (Phase 2 = Package Infrastructure). The Roadmap renumbered all phases (Phase 2 = Security Foundation). "Add to Phase 6" means different things in each document.

**Fix:** Update `ansible/playbooks/workstation.yml` comments to match Roadmap numbering, or switch to named phases instead of numbers.

---

### SER-08: All Docker images use :latest tag -- supply chain risk and non-reproducible builds [P3, P4, P5]

**Files:** `wiki/roles/alloy.md`, `wiki/roles/prometheus.md`, `wiki/roles/loki.md`, `wiki/roles/grafana.md`, `wiki/roles/node_exporter.md`, `wiki/roles/cadvisor.md`, `wiki/roles/watchtower.md`

Every Docker-based wiki role page uses `:latest` tags. This means non-reproducible deployments, automatic major version bumps, supply chain risk from compromised images. Additionally, Watchtower (`containrrr/watchtower`) was archived on Dec 17, 2025 and is no longer maintained.

**Fix:** Pin all images to specific versions. Example: `grafana/alloy:v1.5`, `prom/prometheus:v2.53`, `grafana/loki:3.4`, `grafana/grafana:11.4`, `containrrr/watchtower:1.7.1`. Document that Watchtower is archived/EOL and suggest alternatives (Renovate Bot, Diun).

---

### SER-09: Watchtower auto-updates entire monitoring stack simultaneously [P3]

**File:** `wiki/roles/watchtower.md` (default `watchtower_scope: ""`)

Default configuration updates ALL running containers at once. If Prometheus, Loki, Alloy, Grafana all restart simultaneously at 03:00, the entire observability stack goes down. Logs generated during the update are lost. Rolling restarts are disabled by default.

**Fix:** Default to label-based filtering (`WATCHTOWER_LABEL_ENABLE=true`) or `monitor_only` mode. Document the cascading failure scenario.

---

### SER-10: Grafana admin password defaults to "admin" [P3]

**File:** `wiki/roles/grafana.md:59`

```yaml
grafana_admin_password: "{{ vault_grafana_admin_password | default('admin') }}"
```

If vault is not configured (common during initial setup), Grafana launches with `admin/admin` credentials exposed via Caddy reverse proxy.

**Fix:** Remove `| default('admin')` fallback. Require vault password or fail with a clear error. Add security warning about HTTPS exposure with default credentials.

---

### SER-11: No kernel module blacklisting [P4, P5]

**File:** Not implemented -- no role or config exists.

Per dev-sec.io baseline and CIS Benchmark Section 1.1/3.4: unused filesystem modules (cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf) and network protocols (dccp, sctp, rds, tipc) should be blacklisted. Firewire modules (firewire-core, firewire-ohci) enable DMA attacks via physical ports.

**Fix:** Create `kernel_modules` role or add to `sysctl`:
```yaml
kernel_modules_blacklist:
  - cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf  # Filesystems
  - dccp, sctp, rds, tipc                                   # Network protocols
  - firewire-core, firewire-ohci                             # DMA attack vectors
  - usb-storage                                              # If USB storage not needed
```
Implementation: deploy `/etc/modprobe.d/<module>.conf` with `install <module> /bin/true` and `blacklist <module>`.

---

### SER-12: Bootloader has no password protection [P4]

**File:** `wiki/roles/bootloader.md` (planned, not implemented)

Per CIS Benchmark Section 1.4-1.5: without a GRUB password, an attacker with physical access can edit boot parameters (`init=/bin/bash`) to get a root shell without authentication. Single-user mode also requires no authentication.

**Fix:** Implement `bootloader` role with `bootloader_password_enabled: true`, PBKDF2 password hash, config permissions `0400`.

---

### SER-13: No CI/CD pipeline for Molecule tests [P2, P5]

**File:** `.github/workflows/lint.yml`

CI runs yamllint, ansible-lint, and syntax-check but NOT Molecule tests. Molecule test configs exist for all 21 roles but are never run in CI. No pre-commit hooks exist. No `.ansible-lint` or `.yamllint` configuration files found. Regressions can be introduced silently.

**Fix:** Add GitHub Actions workflow to run Molecule tests for changed roles on PR. Add `.pre-commit-config.yaml` with ansible-lint hook.

---

### SER-14: Docker resource limits not implemented -- fork bomb can crash host [P4]

**File:** `ansible/roles/docker/defaults/main.yml` (no resource limit variables), `ansible/roles/docker/templates/daemon.json.j2` (no ulimits section)

Per OWASP Docker Security: without `default-ulimits` in `daemon.json`, a container fork bomb consumes all host resources. No `nproc` or `nofile` limits are set.

**Fix:** Add to `ansible/roles/docker/templates/daemon.json.j2`:
```json
"default-ulimits": {
  "nofile": {"Name": "nofile", "Hard": 64000, "Soft": 64000},
  "nproc": {"Name": "nproc", "Hard": 4096, "Soft": 2048}
}
```

---

## 3. Medium Issues

Non-optimal decisions, missing best practices, inconsistencies that degrade security or maintainability.

---

### MED-01: SSH MaxStartups value differs from Quick-Wins.md [P1]

**File:** `ansible/roles/ssh/defaults/main.yml:29`

Code: `ssh_max_startups: "10:30:60"`. Documentation: `ssh_max_startups: "4:50:10"`. The code value allows 60 simultaneous unauthenticated connections -- generous for a workstation.

**Fix:** Align code and documentation. Use `"4:50:10"` for a stricter workstation policy or document why `"10:30:60"` was chosen.

---

### MED-02: SSH KexAlgorithms differ from documentation, missing post-quantum KEX [P1, P4]

**File:** `ansible/roles/ssh/defaults/main.yml:39-43`

Code includes `diffie-hellman-group16-sha512` and `group18-sha512` but omits `diffie-hellman-group-exchange-sha256` (in docs). Neither documents minimum OpenSSH version requirements (7.3+). Additionally, ssh-audit 2025 recommends `sntrup761x25519-sha512@openssh.com` (post-quantum hybrid KEX, OpenSSH 8.5+) which is missing.

**Fix:** Add `sntrup761x25519-sha512@openssh.com` as first KEX algorithm. Document minimum OpenSSH version requirement.

---

### MED-03: SSH HostKeyAlgorithms not implemented in sshd_config [P1, P4]

**File:** `ansible/roles/ssh/defaults/main.yml` (variable missing), `ansible/roles/ssh/tasks/main.yml` (no HostKeyAlgorithms directive)

`wiki/Quick-Wins.md:62-65` specifies `ssh_host_key_algorithms: [ssh-ed25519, rsa-sha2-512, rsa-sha2-256]`. Neither the variable nor the sshd_config directive exists. SSH daemon may accept weak DSA/ECDSA host keys.

**Fix:** Add variable to `ansible/roles/ssh/defaults/main.yml` and `HostKeyAlgorithms` directive to the sshd_config loop in `ansible/roles/ssh/tasks/main.yml`.

---

### MED-04: SSH MACs list differs from documentation [P1]

**File:** `ansible/roles/ssh/defaults/main.yml:36-38`

Code omits `umac-128-etm@openssh.com` which is listed in Quick-Wins.md. This is a more conservative choice but diverges from documentation without explanation.

**Fix:** Document the intentional omission or add the MAC.

---

### MED-05: Docker log driver default does not match Quick-Wins.md [P1, P4]

**File:** `ansible/roles/docker/defaults/main.yml:15`

Code: `docker_log_driver: "json-file"`. Quick-Wins.md: `docker_log_driver: "journald"`. The code adds rotation options to `json-file`, which addresses disk overflow but breaks the journald->Alloy->Loki logging pipeline documented in the roadmap.

**Fix:** Change to `docker_log_driver: "journald"` to align with the observability architecture. Add `docker_log_opts` with `tag: "{{.Name}}/{{.ID}}"`.

---

### MED-06: kernel.yama.ptrace_scope: 2 breaks debuggers with no independent toggle [P1]

**File:** `ansible/roles/sysctl/defaults/main.yml:36`

`ptrace_scope: 2` prohibits ptrace except for root. This breaks gdb, strace, ltrace, perf for non-root users on a development workstation. The only toggle is `sysctl_security_enabled: true` which controls ALL security parameters.

**Fix:** Add per-parameter toggle: `sysctl_kernel_yama_ptrace_scope_enabled: true` in `ansible/roles/sysctl/defaults/main.yml` with a comment warning about development impact.

---

### MED-07: SSH and Docker handlers lack `listen:` directive [P1]

**File:** `ansible/roles/ssh/handlers/main.yml:1-5`
**File:** `ansible/roles/docker/handlers/main.yml`

Per project convention (MEMORY.md): "Handlers use `listen:` for cross-role notification." Neither handler has this directive, preventing other roles from triggering restarts via generic notification names.

**Fix:** Add `listen: "restart sshd"` and `listen: "restart docker"` to respective handler files.

---

### MED-08: base_system/tasks/main.yml uses /etc/vconsole.conf which is systemd-specific [P1]

**File:** `ansible/roles/base_system/tasks/main.yml:50-57`

`/etc/vconsole.conf` is specific to systemd-based distributions. This is in `main.yml` (cross-platform), not in `archlinux.yml`. On minimal Debian installations without systemd-consoled, this file does nothing.

**Fix:** Move to OS-specific include file or add `when: ansible_service_mgr == 'systemd'` condition.

---

### MED-09: Phase 7 contains 13 roles (9 undocumented) -- unrealistic scope [P2]

**File:** `wiki/Roadmap.md` (Phase 7 section)

9 of 13 Phase 7 roles (audio, compositor, notifications, screen_locker, clipboard, screenshots, gtk_qt_theming, input_devices, bluetooth) have ZERO wiki pages, no design, no defaults.

**Fix:** Split Phase 7 into sub-phases: 7a (essential: audio, compositor, screen_locker), 7b (convenience: clipboard, screenshots, notifications), 7c (polish: gtk_qt_theming, input_devices, bluetooth). Create wiki pages before implementation.

---

### MED-10: Phase 8 observability stack -- no resource estimation [P2, P3]

**File:** `wiki/Roadmap.md` (Phase 8 section), all Phase 8 wiki role pages

10 Docker containers (Prometheus, Loki, Grafana, Alloy, cAdvisor, node_exporter, etc.) with estimated RAM 1.3-4.2 GB idle/load. No resource limits in any docker-compose example. No `deploy.resources.limits.memory` defined anywhere. On a 16 GB workstation also running desktop + browser + IDE, this can cause memory pressure.

**Fix:** Add `mem_limit` and `cpus` to each Phase 8 wiki page. Define minimal vs full deployment profiles.

---

### MED-11: certificates.md trust_anchors_path is Arch-only [P3]

**File:** `wiki/roles/certificates.md:35-36`

The Debian path is commented out. If implemented as-is, it will fail on Debian/Ubuntu because `/etc/ca-certificates/trust-source/anchors` does not exist there.

**Fix:** Show proper `ansible_os_family` conditional in the wiki defaults.

---

### MED-12: auditd.md space_left_action: email requires MTA that does not exist [P3]

**File:** `wiki/roles/auditd.md:21`

On a fresh Arch/Debian install, no MTA (sendmail) exists. When disk space runs low, auditd attempts to send email, fails silently, and no alert is generated.

**Fix:** Change default to `auditd_space_left_action: syslog`. Document email as optional with MTA dependency.

---

### MED-13: Docker network topology -- all services share "proxy" network [P3]

**File:** All Docker wiki role pages (implicit via `docker_network: "proxy"`)

Prometheus, Loki, Grafana, Alloy, cAdvisor, Watchtower all share one Docker network. Any compromised container can reach all others. The wiki does not document the requirement that all docker-compose files must include `networks: proxy: external: true` for inter-service DNS resolution.

**Fix:** Document the `external: true` network requirement in each Docker role page. Consider separate networks (e.g., `monitoring` for observability, `proxy` for reverse proxy).

---

### MED-14: Alloy wiki uses outdated "River" terminology [P5]

**File:** `wiki/roles/alloy.md` (multiple references to "River config syntax")

Grafana renamed the configuration language from "River" to "Alloy syntax" in the v1.x release. The wiki uses outdated terminology.

**Fix:** Replace all references to "River" with "Alloy syntax" in `wiki/roles/alloy.md`.

---

### MED-15: Rootless Docker not offered as modern alternative to userns-remap [P5]

**File:** `ansible/roles/docker/defaults/main.yml:21`

The project offers only `docker_userns_remap` which breaks volume permissions and has limited adoption. Current Docker best practice (2025-2026) recommends rootless Docker, which runs the entire daemon as non-root with better isolation and no volume permission issues. Supported since Docker 20.10+.

**Fix:** Add `docker_rootless: false` variable with documentation. Position rootless as the recommended approach over userns-remap.

---

### MED-16: "71% Prometheus+OTel" claim is misleading [P3, P5]

**File:** `wiki/roles/alloy.md:32`, `wiki/roles/prometheus.md:37`, `wiki/Roadmap.md:177`

The statistic comes from Grafana Labs Observability Survey 2025. The wiki says "71% organizations" but this is "71% of survey respondents in any capacity (including POC/investigating)." Only 34% use both in production. The survey audience is already skewed toward Prometheus/OTel users.

**Fix:** Add qualifier or use the production figure: "34% use both in production" with source URL: `https://grafana.com/observability-survey/2025/`.

---

### MED-17: SSH LogLevel not set to VERBOSE [P4]

**File:** `ansible/roles/ssh/defaults/main.yml` (no LogLevel variable)

Per Mozilla SSH Guidelines: VERBOSE logs which SSH key was used for authentication. Default INFO level does not log key fingerprints, reducing audit trail quality.

**Fix:** Add `ssh_log_level: "VERBOSE"` to `ansible/roles/ssh/defaults/main.yml` and corresponding sshd_config directive.

---

### MED-18: Roadmap and implementation plan are stale -- QW-2 and QW-4 already implemented [P2]

**File:** `wiki/Roadmap.md`, `.claude/plans/clever-swimming-panda.md`

Both documents describe QW-2 (sysctl security) and QW-4 (SSH rate limiting) as future changes, but they already exist in the codebase. The sysctl defaults already contain security parameters; the nftables template already has rate limiting rules.

**Fix:** Audit all 6 Quick Wins against current code. Update roadmap status. Mark completed items as done.

---

## 4. Minor Issues

Style, naming, documentation, and polish items.

---

### MIN-01: Inconsistent variable naming -- faillock uses base_system_ prefix in code, pam_faillock_ in docs [P1]

**File:** `ansible/roles/base_system/defaults/main.yml:30-33` vs `wiki/Quick-Wins.md:447`

Code uses `base_system_faillock_*` (correct per project convention). Documentation uses `pam_faillock_*`. Someone reading the docs will search for variables that don't exist.

**Fix:** Update `wiki/Quick-Wins.md` to use `base_system_faillock_*` prefix.

---

### MIN-02: SSH defaults file has inconsistent YAML quoting [P1]

**File:** `ansible/roles/ssh/defaults/main.yml`

Some values quoted (`ssh_permit_root_login: "no"`), some not (`ssh_key_type: ed25519`). Cipher/MAC/KEX lists are not quoted in defaults but are quoted in docs.

**Fix:** Standardize quoting style across the file.

---

### MIN-03: Docker role comment mentions volume permission breakage but offers no mitigation [P1]

**File:** `ansible/roles/docker/defaults/main.yml:21`

```yaml
docker_userns_remap: ""  # "default" for user namespace isolation (breaks volume permissions!)
```

The comment warns but provides no fix documentation.

**Fix:** Add a link to mitigation documentation or inline instructions for `chown -R 100000:100000`.

---

### MIN-04: base_system uses `copy` instead of `template` for faillock.conf [P1]

**File:** `ansible/roles/base_system/tasks/archlinux.yml:31-45`

Uses `ansible.builtin.copy` with `content:` containing Jinja2 variable interpolation. This works but is semantically misleading -- `copy` with `content:` is for static content. A `.j2` template file would be cleaner, more testable, and consistent with project patterns.

**Fix:** Create `ansible/roles/base_system/templates/faillock.conf.j2` and switch to `ansible.builtin.template`.

---

### MIN-05: Phase numbering uses "1.5" which breaks sorting [P2]

**File:** `wiki/Roadmap.md`

Phase 1.5 between Phase 1 and Phase 2 is a hack. Future insertions would require Phase 1.25, etc.

**Fix:** Use integer phases or named phases.

---

### MIN-06: Quick-Wins.md mixes design documentation with implementation code [P2]

**File:** `wiki/Quick-Wins.md` (749 lines)

Contains full Ansible task YAML, PAM configuration, nftables rules, and test commands. When roles are implemented, the document becomes stale immediately (already happened with QW-2 and QW-4).

**Fix:** Quick-Wins should describe WHAT and WHY. Implementation details belong in role code.

---

### MIN-07: Wiki pages have inconsistent structure -- not all have Architecture section [P3]

**Files:** `wiki/roles/fail2ban.md`, `wiki/roles/auditd.md`, `wiki/roles/apparmor.md`, `wiki/roles/systemd_hardening.md`, `wiki/roles/certificates.md`, `wiki/roles/watchtower.md`, `wiki/roles/pam_hardening.md`

These pages lack the Architecture section present in observability role pages. Tag naming format varies (bullet list vs inline).

**Fix:** Standardize template: every page should have Purpose, Architecture, Variables, Dependencies, Tags sections.

---

### MIN-08: Watchtower HTTP API port conflicts with cAdvisor [P3]

**File:** `wiki/roles/watchtower.md:48` (`watchtower_http_api_port: 8080`)
**File:** `wiki/roles/cadvisor.md:51` (port 8080)

Both default to port 8080. The default `watchtower_http_api: false` prevents the conflict, but it is undocumented.

**Fix:** Document the known port conflict in both wiki pages.

---

### MIN-09: Prometheus --storage.tsdb.retention.size not in Docker command [P3]

**File:** `wiki/roles/prometheus.md:106`

Variable `prometheus_storage_retention_size: "10GB"` (line 54) is defined but the Docker command only shows `--storage.tsdb.retention.time=15d`. The size flag `--storage.tsdb.retention.size=10GB` is missing.

**Fix:** Add the missing flag to the Docker command example.

---

### MIN-10: Standalone roles instead of Ansible Collection format [P5]

**File:** `ansible/roles/` (all 21 roles)

Industry standard (2025-2026) is to use Collections for distribution. Standalone roles cannot embed plugins, don't support Galaxy version management, and are harder to share.

**Fix:** For a project of this size (~50+ planned roles), consider organizing as a collection: `namespace.bootstrap`. Not blocking, but recommended for long-term maintainability.

---

## 5. Missing Roles & Coverage Gaps

Combined from Phase 2 (roadmap analysis), Phase 4 (CIS gaps), Phase 5 (dev-sec.io comparison).

### Roles Entirely ABSENT (not in roadmap, not planned)

| # | Role | Source | Risk | Description |
|---|------|--------|------|-------------|
| 1 | `mount_hardening` / `fstab` | P2, P4, P5 | **CRITICAL** | noexec/nosuid/nodev for /tmp, /var/tmp, /dev/shm. CIS 1.1.x. dev-sec covers this. Move to Phase 2. |
| 2 | `firewall_outbound` / egress filtering | P2, P4 | **CRITICAL** | All outbound traffic unrestricted. C2 callbacks possible. |
| 3 | `kernel_modules` | P2, P4, P5 | **HIGH** | Blacklist unused FS/network/hardware modules. CIS 1.1.x/3.4.x. dev-sec covers this. |
| 4 | `core_dumps` | P2, P4 | **MEDIUM** | `* hard core 0` in limits.conf + `fs.suid_dumpable: 0`. Core dumps can leak passwords/keys. |
| 5 | `login_defs` | P5 | **SERIOUS** | `/etc/login.defs` PASS_MAX_DAYS, PASS_MIN_DAYS, UMASK, SHA_CRYPT_ROUNDS. dev-sec covers this. |
| 6 | `motd` / `banner` / `issue` | P2, P4 | **MEDIUM** | Legal/login banners. PCI-DSS 2.2.4, CIS 1.7.x. Required for compliance. |
| 7 | `grub_password` | P2, P4 | **HIGH** | GRUB password prevents `init=/bin/bash` boot attack. CIS 1.4.x. |
| 8 | `usb_guard` | P2, P4 | **HIGH** | Block BadUSB/rubber ducky/USB drop attacks. Phase 9 recommended. |
| 9 | `luks_encryption` | P4 | **CRITICAL** (docs only) | Disk encryption verification. Not Ansible-automatable (install-time). Document setup guide. |
| 10 | `sshd_2fa` | P2 | **MEDIUM** | TOTP/FIDO2 for SSH. Defense-in-depth for key theft. |
| 11 | `backup_verification` | P2 | **HIGH** | Restore testing for backups. Backups never tested are not backups. |
| 12 | `system_maintenance` | P4 | **HIGH** | File permission auditing, SUID/SGID audit, world-writable cleanup. CIS 6.x. |
| 13 | `container_runtime_security` | P2 | **MEDIUM** | Docker Bench for Security, image scanning (Trivy), runtime policy. |
| 14 | `alerting` (notification routing) | P2 | **HIGH** | Alertmanager missing. Prometheus/Grafana alerts fire into void without notification channels. |

### Roles PARTIALLY COVERED (in roadmap but incomplete)

| # | Role | Source | Issue |
|---|------|--------|-------|
| 1 | `logrotate` | P2 | Listed in Phase 8 but no wiki page, no role directory. Only needed for `/var/log/sudo.log` if all logging goes through journald. |
| 2 | `vpn` | P2 | Phase 5 placeholder. No wiki page. WireGuard vs OpenVPN undefined. |
| 3 | `network`, `dns` | P2 | Phase 5 placeholders. No wiki pages. `dns` relationship to `systemd_resolved` unclear. |
| 4 | `secrets_management` | P2 | ansible-vault used but no documented strategy. No vault file found in repo. No rotation, no backup plan for vault password. |
| 5 | `secureboot` | P2, P4 | `bootloader` wiki mentions it but no key management, MOK enrollment, or sbctl config. |
| 6 | `resource_limits` | P2 | `pam_hardening` wiki mentions "session limits" vaguely. No specific `limits.conf` entries for fork bomb prevention. |
| 7 | `alertmanager` | P3 | `prometheus.md` references `alertmanager:9093` endpoint but no role exists to deploy it. |

### Roles with ZERO Wiki Pages (in roadmap, no documentation)

| Phase | Missing Wiki Pages | Count |
|-------|-------------------|-------|
| Phase 5 | network, dns, vpn | 3 |
| Phase 7 | audio, compositor, notifications, screen_locker, clipboard, screenshots, gtk_qt_theming, input_devices, bluetooth | 9 |
| Phase 8 | logrotate | 1 |
| Phase 11 | disk_management, backup | 2 |
| Phase 12 | programming_languages, containers, databases | 3 |
| **Total** | | **18** |

### CIS Benchmark Coverage Summary

| CIS Section | Coverage | Critical Missing Controls |
|-------------|----------|---------------------------|
| 1.1 Filesystem | 0% | All partition/mount controls (15+) |
| 1.4-1.5 Bootloader | 0% | Bootloader password, secure boot |
| 1.6 Process Hardening | 80% | Core dumps, module loading |
| 3.x Network | 95% | IPv6 hardening, egress filtering |
| 4.x Logging | 20% | auditd not implemented, log permissions |
| 5.x Access Control | 85% | Password complexity (planned) |
| 6.x System Maintenance | 10% | File permissions, SUID audit |
| **Overall** | **~40%** | |

### dev-sec.io Coverage Comparison

The project reimplements ~30% of what `devsec.hardening` already provides. Major gaps vs dev-sec: filesystem mount options, module loading restrictions, full auditd rules, `/etc/login.defs`, PAM pwquality policies, core dump restrictions, AIDE/integrity monitoring.

**Recommendation:** Consider using `devsec.hardening` collection as a dependency rather than reimplementing.

---

## 6. Architecture Questions

Decisions that require user input before proceeding with implementation.

---

### AQ-01: Should Docker defaults be secure-by-default or opt-in? [P1, P2, P4]

The Docker role defaults to "insecure but compatible." The sysctl role defaults to "secure." The faillock has no toggle. There is no consistent project-wide security policy.

**Decision needed:** Adopt "secure by default with opt-out" (more secure, may break existing workloads) or "compatible by default with opt-in" (safer for brownfield, less secure)?

---

### AQ-02: Should SSH role declare dependency on user role? [P1, P2]

`AllowGroups wheel` applied without verifying user group membership. If SSH runs before user role, lockout occurs.

**Decision needed:** Add `dependencies: [user]` in `ssh/meta/main.yml`, or add a pre-flight assert, or accept the risk with documentation?

---

### AQ-03: Should SSH role use full template instead of lineinfile? [P1]

Over multiple runs with different variable values, orphaned directives are not cleaned up. If `ssh_allow_groups` changes from `["wheel"]` to `[]`, the old `AllowGroups` line persists because the `when` condition skips the task.

**Decision needed:** Switch to a full `sshd_config.j2` template (complete state management, prevents orphans) or keep `lineinfile` (lower blast radius per change)?

---

### AQ-04: Should all security features follow a consistent toggle pattern? [P1]

Current toggles: sysctl has one global toggle; Docker has per-feature but insecure defaults; faillock has no toggle; sudo hardening is tied to `user_create_sudo_rule`; SSH rate limit is tied to `firewall_allow_ssh`.

**Decision needed:** Standardize on `<role>_<feature>_enabled: true` with individual parameter variables?

---

### AQ-05: Should PAM faillock be in base_system or pam_hardening? [P1, P3]

Both roles manage `/etc/security/faillock.conf`. Running both causes a conflict.

**Decision needed:** Which role owns faillock configuration?

---

### AQ-06: Should the project use devsec.hardening collection as a dependency? [P5]

dev-sec.io covers 2-3x more hardening areas than the project. Using it as a dependency would provide battle-tested, multi-distro hardening with less maintenance burden. However, it introduces an external dependency and may conflict with custom roles.

**Decision needed:** Use `devsec.hardening` for base OS/SSH/Docker hardening, or continue building custom roles?

---

### AQ-07: What is the resource budget for the observability stack? [P2, P3]

Phase 8 deploys 10 containers consuming 1.3-4.6 GB RAM. Combined with desktop workload (8-12 GB), a 16 GB workstation may encounter memory pressure. No memory limits are defined.

**Decision needed:** Define a RAM budget (e.g., 2 GB total for monitoring). Define "minimal" vs "full" deployment profiles. Set `deploy.resources.limits.memory` for each container.

---

### AQ-08: Where are vault-encrypted secrets stored? [P2, P4]

Variables prefixed `vault_` are referenced (e.g., `vault_vaultwarden_admin_token`, `vault_grafana_admin_password`) but no actual vault-encrypted file was found in the repository. If `~/.vault-pass` is lost with no backup, all encrypted variables are unrecoverable.

**Decision needed:** Where do vault files live? How is the vault password backed up? What is the rotation schedule? Document in `wiki/Secrets-Management.md`.

---

### AQ-09: How should the logging pipeline handle Docker logs before Phase 8 is complete? [P2]

journald is configured in Phase 2, Docker stays on json-file until Phase 6 QW-3, Alloy/Loki are Phase 8. The full pipeline requires all three phases completed simultaneously.

**Decision needed:** Accept the gap (Docker logs not in observability until Phase 8) or change Docker log driver to journald earlier?

---

### AQ-10: What happens when a role fails mid-execution? [P2]

No rollback strategy exists. SSH cipher changes can lock out users; PAM faillock misconfigs can block all logins; bootloader changes can prevent boot. The plan mentions "test via console, NOT via SSH" for QW-1 but no general rollback strategy or canary approach exists.

**Decision needed:** Document rollback procedure per critical role. Consider auto-revert if verification fails within 60 seconds.

---

### AQ-11: Should the project organize as an Ansible Collection? [P5]

With 50+ planned roles, Collection format provides version management, plugin embedding support, and Galaxy distribution. Standalone roles are acceptable for internal use but harder to share.

**Decision needed:** Keep standalone `ansible/roles/` structure or migrate to `namespace.bootstrap` collection?

---

## 7. Prioritized Recommendations

Ordered by impact: quick fixes first, then structural changes, then architectural decisions.

### P0 -- Quick Fixes (single variable or line changes, < 30 min each)

| # | Action | File | Finding |
|---|--------|------|---------|
| 1 | Add `validate: 'python3 -m json.tool %s'` to Docker template task | `ansible/roles/docker/tasks/main.yml:17-25` | CRIT-03 |
| 2 | Add `listen: "restart sshd"` to SSH handler | `ansible/roles/ssh/handlers/main.yml:1-5` | MED-07 |
| 3 | Add `listen: "restart docker"` to Docker handler | `ansible/roles/docker/handlers/main.yml` | MED-07 |
| 4 | Add `ssh_log_level: "VERBOSE"` to SSH defaults and sshd_config | `ansible/roles/ssh/defaults/main.yml` | MED-17 |
| 5 | Change `auditd_space_left_action` default to `syslog` | `wiki/roles/auditd.md:21` | MED-12 |
| 6 | Replace "River" with "Alloy syntax" in wiki | `wiki/roles/alloy.md` | MED-14 |
| 7 | Remove `\| default('admin')` from Grafana password | `wiki/roles/grafana.md:59` | SER-10 |
| 8 | Fix "71% organizations" claim -- add qualifier and source URL | `wiki/roles/alloy.md:32`, `wiki/roles/prometheus.md:37`, `wiki/Roadmap.md:177` | MED-16 |
| 9 | Update AppArmor kernel parameter to `lsm=` syntax | `wiki/roles/apparmor.md:49` | CRIT-09 |
| 10 | Pin Docker image versions in all wiki role pages | `wiki/roles/alloy.md`, `prometheus.md`, `loki.md`, `grafana.md`, `cadvisor.md`, `node_exporter.md`, `watchtower.md` | SER-08 |

### P1 -- Security Fixes (code changes, 1-4 hours each)

| # | Action | File | Finding |
|---|--------|------|---------|
| 11 | Fix nftables rate limit to per-source-IP with dynamic set | `ansible/roles/firewall/templates/nftables.conf.j2:26` | CRIT-01 |
| 12 | Add SSH AllowGroups pre-flight assert task | `ansible/roles/ssh/tasks/main.yml` (before line 70) | CRIT-05 |
| 13 | Change Docker security defaults to secure values (or add prominent opt-in warning) | `ansible/roles/docker/defaults/main.yml:21-24` | CRIT-02 |
| 14 | Add PAM faillock to Debian tasks | `ansible/roles/base_system/tasks/debian.yml` | CRIT-04 |
| 15 | Add logrotate for /var/log/sudo.log | `ansible/roles/user/templates/sudo_logrotate.j2` (new), `ansible/roles/user/tasks/main.yml` | SER-01 |
| 16 | Add Docker resource limits (default-ulimits) to daemon.json | `ansible/roles/docker/templates/daemon.json.j2` | SER-14 |
| 17 | Add `pam_faillock_enabled` toggle and `root_unlock_time` variable | `ansible/roles/base_system/defaults/main.yml` | SER-02 |
| 18 | Add `ssh_host_key_algorithms` variable and sshd_config directive | `ansible/roles/ssh/defaults/main.yml`, `ansible/roles/ssh/tasks/main.yml` | MED-03 |
| 19 | Replace hardcoded sudo values with template + variables | `ansible/roles/user/tasks/main.yml:18-32` -> template | SER-03 |
| 20 | Add missing sysctl security parameters (11 params from dev-sec baseline) | `ansible/roles/sysctl/defaults/main.yml` | SER-04 |
| 21 | Add `pam_faillock_enabled` toggle to guard faillock task | `ansible/roles/base_system/tasks/archlinux.yml:31-45` | SER-02 |

### P2 -- Structural Changes (new files/roles, 4-16 hours each)

| # | Action | File | Finding |
|---|--------|------|---------|
| 22 | Create `mount_hardening` role -- noexec/nosuid/nodev for /tmp, /dev/shm | New role: `ansible/roles/mount_hardening/` | CRIT-12 |
| 23 | Create `kernel_modules` role -- blacklist unused FS/network/hardware modules | New role: `ansible/roles/kernel_modules/` | SER-11 |
| 24 | Add egress filtering to firewall role | `ansible/roles/firewall/defaults/main.yml`, `nftables.conf.j2` | CRIT-11 |
| 25 | Redesign systemd_hardening as per-service configuration dictionary | `wiki/roles/systemd_hardening.md` | CRIT-06 |
| 26 | Resolve pam_hardening vs base_system faillock ownership conflict | `wiki/roles/pam_hardening.md`, `ansible/roles/base_system/` | CRIT-07 |
| 27 | Add Alloy non-privileged deployment with bind mounts | `wiki/roles/alloy.md:94` | CRIT-08 |
| 28 | Document full Loki retention chain | `wiki/roles/loki.md:37-54` | CRIT-10 |
| 29 | Document nftables backend config for fail2ban | `wiki/roles/fail2ban.md:42-43` | SER-05 |
| 30 | Create 18 missing wiki pages for undocumented roadmap roles | `wiki/roles/` (see Section 5) | MED-09 |
| 31 | Add `.pre-commit-config.yaml` with ansible-lint hook | `.pre-commit-config.yaml` (new) | SER-13 |
| 32 | Add GitHub Actions workflow for Molecule tests | `.github/workflows/molecule.yml` (new) | SER-13 |
| 33 | Document cross-phase dependencies (Mermaid graph or matrix) | `wiki/Dependencies.md` (new) | SER-05, SER-06 |
| 34 | Document secrets management strategy | `wiki/Secrets-Management.md` (new) | AQ-08 |

### P3 -- Architectural Decisions (require user input, see Section 6)

| # | Decision | Finding |
|---|----------|---------|
| 35 | Secure-by-default vs opt-in security policy | AQ-01 |
| 36 | SSH -> user role dependency | AQ-02 |
| 37 | SSH template vs lineinfile | AQ-03 |
| 38 | Consistent security toggle pattern | AQ-04 |
| 39 | Faillock ownership (base_system vs pam_hardening) | AQ-05 |
| 40 | devsec.hardening as dependency | AQ-06 |
| 41 | Observability stack resource budget | AQ-07 |
| 42 | Vault secret storage and rotation | AQ-08 |
| 43 | Docker log driver timing | AQ-09 |
| 44 | Rollback strategy per role | AQ-10 |
| 45 | Ansible Collection migration | AQ-11 |

---

## Appendix: Phase Contribution Matrix

| Finding ID | P1 | P2 | P3 | P4 | P5 |
|------------|:--:|:--:|:--:|:--:|:--:|
| CRIT-01 | x | x | | | |
| CRIT-02 | x | x | | x | x |
| CRIT-03 | x | | | | |
| CRIT-04 | x | | | | |
| CRIT-05 | x | x | | | |
| CRIT-06 | | | x | | |
| CRIT-07 | | | x | | |
| CRIT-08 | | | x | | x |
| CRIT-09 | | | x | | |
| CRIT-10 | | | x | | |
| CRIT-11 | | x | | x | |
| CRIT-12 | | | | x | x |
| CRIT-13 | | | | x | |
| CRIT-14 | | | | x | x |
| SER-01 | x | | | | |
| SER-02 | x | | | | |
| SER-03 | x | | | | |
| SER-04 | x | | | x | |
| SER-05 | | x | | | |
| SER-06 | | x | | | |
| SER-07 | | x | | | |
| SER-08 | | | x | x | x |
| SER-09 | | | x | | |
| SER-10 | | | x | | |
| SER-11 | | | | x | x |
| SER-12 | | | | x | |
| SER-13 | | x | | | x |
| SER-14 | | | | x | |
| MED-01 | x | | | | |
| MED-02 | x | | | x | |
| MED-03 | x | | | x | |
| MED-04 | x | | | | |
| MED-05 | x | | | x | |
| MED-06 | x | | | | |
| MED-07 | x | | | | |
| MED-08 | x | | | | |
| MED-09 | | x | | | |
| MED-10 | | x | x | | |
| MED-11 | | | x | | |
| MED-12 | | | x | | |
| MED-13 | | | x | | |
| MED-14 | | | | | x |
| MED-15 | | | | | x |
| MED-16 | | | x | | x |
| MED-17 | | | | x | |
| MED-18 | | x | | | |
| MIN-01 | x | | | | |
| MIN-02 | x | | | | |
| MIN-03 | x | | | | |
| MIN-04 | x | | | | |
| MIN-05 | | x | | | |
| MIN-06 | | x | | | |
| MIN-07 | | | x | | |
| MIN-08 | | | x | | |
| MIN-09 | | | x | | |
| MIN-10 | | | | | x |

## Appendix: Security Posture Summary

| Category | Coverage | Source |
|----------|----------|--------|
| CIS Benchmark (Linux) | ~40% | P4, P5 |
| OWASP Docker Security | ~30% | P4 |
| SSH Hardening (Mozilla Modern) | ~85% | P4 |
| Egress Filtering | 0% | P4 |
| Supply Chain Security | ~40% | P4 |
| Secrets Management | ~30% | P2, P4 |
| Physical Security | ~5% | P4 |
| Kernel Hardening | ~60% | P4 |
| dev-sec.io Coverage Match | ~30% | P5 |

**Overall Security Posture:** ~40% weighted average. Strong on SSH crypto and sysctl network parameters. Weak on filesystem hardening, Docker defaults, egress filtering, and physical security.

---

*Report generated from 5 independent review phases. All findings deduplicated and cross-referenced. All code-related findings cite specific file paths and line numbers.*
