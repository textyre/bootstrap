# Phase 2: Roadmap Inspection -- Destructive-Critical Review

**Reviewed**: 2026-02-16
**Reviewer**: Claudette (DevOps/Security audit mode)
**Files analyzed**:
- `wiki/Roadmap.md` (244 lines)
- `.claude/plans/clever-swimming-panda.md` (363 lines)
- `wiki/Quick-Wins.md` (749 lines)

**Context verification**:
- Project: Ansible-based workstation bootstrap (VM/Bare Metal, primary OS: Arch Linux, distro-agnostic)
- Implemented roles: **21** (verified via `ansible/roles/` directory listing)
- Planned new roles: **~34** across 13 phases
- Wiki role pages: **28** (in `wiki/roles/`)
- AGENTS.md: confirmed at `/Users/umudrakov/Documents/bootstrap/AGENTS.md`

---

## 1. Critical Issues (blockers)

### CRIT-1: fail2ban (Phase 2) depends on firewall/nftables (Phase 6) -- BROKEN CHAIN

**Dependency**: fail2ban needs a firewall backend (nftables or iptables) to ban IPs. The `fail2ban` wiki page (line 7) explicitly states: "adds ban rules to firewall (nftables/iptables)". The `firewall` role is listed in **Phase 6** of the roadmap. fail2ban is in **Phase 2**.

**Actual state**: The firewall role IS already implemented (exists in `ansible/roles/firewall/`), so the binary dependency is technically satisfied. However, the roadmap presents this as a clean Phase 2 -> Phase 6 sequence, and QW-4 (SSH rate limiting in nftables) is listed under Phase 6 changes. This means:

1. fail2ban is deployed in Phase 2, but the SSH rate limiting rule it should complement (QW-4) is not applied until Phase 6.
2. The roadmap does NOT document that fail2ban has a hard dependency on an already-deployed firewall role.
3. If someone follows the roadmap literally on a fresh system (phases in order, no pre-existing roles), fail2ban has no firewall backend to work with until Phase 6.

**Verdict**: **Undocumented dependency**. The dependency chain is not broken for the current system (firewall exists), but the roadmap fails to declare this cross-phase dependency. A fresh deployment following the phase order would hit this.

**Fix**: Add explicit note in Phase 2 that fail2ban requires firewall role to be pre-deployed. Add `dependencies: [firewall]` to fail2ban's future `meta/main.yml`.

---

### CRIT-2: Logging chain Docker -> journald -> Alloy -> Loki -> Grafana is BROKEN until Phase 6+8

**The chain**:
- journald is configured in Phase 2
- Docker is in Phase 6 with default `docker_log_driver: "json-file"` (confirmed in `ansible/roles/docker/defaults/main.yml` line 15)
- QW-3 changes the default to `journald`, but QW-3 is listed for Phase 6 application
- Alloy (Phase 8) reads from journald
- Loki and Grafana (Phase 8) consume from Alloy

**Problem**: Until QW-3 is applied AND Phase 8 is complete, Docker container logs do NOT flow through journald. The default `json-file` driver means Docker logs are invisible to journald, invisible to Alloy, invisible to Loki. The entire observability architecture described in the roadmap requires ALL of Phases 2, 6 (with QW-3), and 8 to be complete simultaneously.

This is not documented as a cross-phase dependency anywhere. The roadmap presents Phases 2, 6, and 8 as independent sequential steps.

**Verdict**: **Broken chain**. The logging architecture requires a 3-phase simultaneous deployment that contradicts the sequential phase model.

**Fix**: Document the logging pipeline as a cross-cutting concern spanning Phases 2/6/8. Add a "Logging Architecture" dependency diagram showing that the pipeline only becomes functional after Phase 8 completion.

---

### CRIT-3: sysctl appears in BOTH Phase 1.5 AND Phase 2 -- execution conflict

**Phase 1.5**: `sysctl` role is listed as existing and complete (performance tuning params).
**Phase 2**: `sysctl (+ security params -- QW-2)` is listed as a Security Foundation item.

**Verified state**: The `ansible/roles/sysctl/defaults/main.yml` file already contains BOTH performance params (lines 10-28) and security params (lines 29-51, under `# ---- Security ----`). The security section is already merged in with `sysctl_security_enabled: true` as default.

**Problem**: The roadmap says QW-2 needs to "add" security params, but they are already present in the current defaults. This means either:
1. QW-2 has already been implemented (not reflected in the roadmap status)
2. The roadmap is stale and does not reflect current code
3. Phase 2 will re-run the sysctl role, which is fine for idempotency, but the roadmap does not explain this

The implementation plan (clever-swimming-panda.md, line 76-102) describes adding these params as if they don't exist, but they DO exist in the codebase.

**Verdict**: **Stale roadmap / plan mismatch with reality**. QW-2 appears to be partially or fully implemented. The roadmap and plan do not reflect current state.

**Fix**: Audit all 6 Quick Wins against current code to determine which are already implemented. Update roadmap status accordingly.

---

### CRIT-4: QW-4 (SSH rate limiting) is already implemented -- plan is stale

The `ansible/roles/firewall/templates/nftables.conf.j2` (lines 26-27) already contains:

```
tcp dport 22 ct state new limit rate 4/minute accept
tcp dport 22 ct state new log prefix "[nftables] ssh-rate: " drop
```

This is exactly what QW-4 describes. The roadmap and Quick-Wins document describe this as a future change, but it already exists in the codebase.

**Verdict**: **Plan contradicts codebase**. At minimum QW-2 and QW-4 are already implemented. Other QW items may also be implemented -- full audit required.

---

### CRIT-5: Playbook phase numbering does not match Roadmap phase numbering

The `ansible/playbooks/workstation.yml` uses this phase numbering:
- Phase 1: System foundation (base_system, vm, reflector)
- Phase 1.5: Hardware & Kernel (gpu_drivers, sysctl, power_management)
- Phase 2: Package infrastructure (yay, packages)
- Phase 3: User & access (user, ssh)
- Phase 4: Development tools (git, shell)
- Phase 5: Services (docker, firewall, caddy, vaultwarden)
- Phase 6: Desktop environment (xorg, lightdm, greeter, zen_browser)
- Phase 7: User dotfiles (chezmoi)

The Roadmap uses:
- Phase 1: System Foundation
- Phase 1.5: Hardware & Kernel
- Phase 2: **Security Foundation** (NEW)
- Phase 3: Package Infrastructure
- Phase 4: User & Access
- Phase 5: Networking
- Phase 6: Services
- Phase 7: Desktop Environment
- Phase 8-13: New phases

**Problem**: The roadmap renumbered all phases starting from Phase 2 (inserting Security Foundation), but the playbook was never updated. Phase 2 in the playbook is "Package Infrastructure" while Phase 2 in the roadmap is "Security Foundation". This will cause confusion when implementing new roles -- "add to Phase 6" means different things in the playbook vs the roadmap.

**Verdict**: **Naming collision**. The roadmap and playbook disagree on what each phase number means.

**Fix**: Either update the playbook comments to match the new roadmap numbering, or use named phases instead of numbers.

---

## 2. Serious Gaps (high impact)

### SER-1: Phase 7 contains 13 roles -- unrealistic scope

**Roles in Phase 7**: xorg, lightdm, greeter, zen_browser (4 existing) + audio, compositor, notifications, screen_locker, clipboard, screenshots, gtk_qt_theming, input_devices, bluetooth (9 new).

**Wiki page status for the 9 new roles**: ZERO wiki pages exist. None of `audio.md`, `compositor.md`, `notifications.md`, `screen_locker.md`, `clipboard.md`, `screenshots.md`, `gtk_qt_theming.md`, `input_devices.md`, `bluetooth.md` exist in `wiki/roles/`.

**Assessment**: 13 roles in a single phase is the largest phase in the roadmap. 9 of 13 have no documentation, no design, no defaults defined. These roles are feature-request placeholders, not planned work items. Implementing 9 new roles with zero design documentation in a single sprint is unrealistic.

**Risk**: Phase 7 will stall, blocking Phase 8+ which depends on a working desktop environment for monitoring dashboards.

---

### SER-2: Phase 8 contains 10 Docker containers -- no resource estimation

**Containers**: prometheus, node_exporter, cadvisor, alloy, loki, grafana, smartd, healthcheck, sensors, logrotate.

**Typical RAM usage** (conservative estimates):
- Prometheus: 500MB-2GB (depends on scrape targets/retention)
- Loki: 256MB-1GB (depends on log volume)
- Grafana: 256MB-512MB
- Alloy: 128MB-256MB
- cAdvisor: 128MB-256MB
- node_exporter: 32MB-64MB
- smartd: 16MB-32MB
- healthcheck: 16MB-64MB
- sensors: 16MB-32MB
- logrotate: negligible (runs as timer, not persistent)

**Total estimated**: 1.3GB-4.2GB RAM for observability alone.

On a workstation with 16GB RAM, this is 8-26% of total memory dedicated to monitoring. On a VM with 8GB or less, this becomes untenable.

**Problem**: No resource estimation exists anywhere in the roadmap, plan, or wiki pages. No `deploy_resources` section in any wiki role page defines memory/CPU limits. No Docker Compose resource constraints are specified.

**Fix**: Add resource estimation to Phase 8 wiki pages. Define `mem_limit` and `cpus` for each container. Consider whether ALL 10 are needed for a single workstation (node_exporter + Prometheus + Grafana may be sufficient; cAdvisor + Alloy + Loki adds observability depth at significant cost).

---

### SER-3: Phase 5 Networking has 4 roles, ZERO wiki pages

**Roles**: network, systemd_resolved, dns, vpn.

**Wiki pages**: Only `systemd_resolved.md` exists. `network.md`, `dns.md`, `vpn.md` do NOT exist.

**Problem**: 3 out of 4 networking roles have zero documentation. The `dns` role's relationship to `systemd_resolved` is unclear -- systemd_resolved IS a DNS resolver with DoT support. What does a separate `dns` role do? Local DNS server (dnsmasq)? Custom /etc/resolv.conf? This is undefined.

The `vpn` role has no wiki page and no specification. Is it WireGuard? OpenVPN? Generic? The plan mentions `vpn` but provides zero details.

---

### SER-4: Docker role has `dependencies: []` -- no declared dependencies

The `ansible/roles/docker/meta/main.yml` declares `dependencies: []`. Roles that depend on Docker (caddy, vaultwarden, and ALL of Phase 8) rely on the playbook ordering, not on declared Ansible dependencies.

If anyone runs `ansible-playbook --tags grafana` without `--tags docker`, Docker will not be installed. This silent failure pattern applies to ALL container-based roles.

**Contrast**: caddy correctly declares `dependencies: [docker]`, and vaultwarden declares `dependencies: [docker, caddy]`. But the planned Phase 8 roles (grafana, loki, prometheus, etc.) have no meta/main.yml files yet. There is no documented convention requiring Docker as a dependency for container roles.

**Fix**: Establish a mandatory convention: all container-based roles MUST declare `dependencies: [docker]` in meta/main.yml. Document this in AGENTS.md.

---

### SER-5: Firewall output chain has `policy accept` -- all outbound traffic unrestricted

Confirmed in `ansible/roles/firewall/templates/nftables.conf.j2` line 48:
```
chain output { type filter hook output priority 0; policy accept; }
```

This means:
- Any compromised process can establish outbound connections to any destination
- Command-and-control (C2) callbacks are unrestricted
- Data exfiltration has no firewall-level barrier
- DNS tunneling and other covert channels are unblocked

The roadmap does not plan any egress filtering. No `firewall_outbound` role exists or is planned.

---

### SER-6: QW-3 Docker security defaults are deliberately insecure

The current `ansible/roles/docker/defaults/main.yml` (lines 20-24) sets:
- `docker_userns_remap: ""` (disabled)
- `docker_icc: true` (inter-container communication allowed)
- `docker_live_restore: false` (containers die on daemon restart)
- `docker_no_new_privileges: false` (privilege escalation allowed)

The Quick-Wins document describes changing these, but the defaults file explicitly keeps them insecure with comments explaining why. The roadmap says "feature flags, include carefully" for QW-3.

**Problem**: The "safe defaults" philosophy (insecure-by-default, opt-in security) contradicts the Security Foundation premise of Phase 2. A security-focused roadmap should not ship insecure defaults that require manual opt-in.

---

## 3. Medium Issues (medium)

### MED-1: Phase 11/12 roles have ZERO wiki pages and ZERO detail

**Phase 11**: disk_management, backup -- no wiki pages.
**Phase 12**: programming_languages, containers, databases -- no wiki pages.

These 5 roles are listed in the roadmap with one-line descriptions but zero design. The "containers" role in Phase 12 (podman, containerd) conflicts conceptually with the Docker role in Phase 6 -- are they alternatives? Complements? The roadmap does not clarify.

---

### MED-2: Implementation plan (clever-swimming-panda.md) is stale

The plan describes changes to make (QW-2 sysctl security, QW-4 SSH rate limiting) that have already been implemented in the codebase. The plan was approved but not updated after partial execution. This creates confusion about what work remains.

**Affected items**: At minimum QW-2 (sysctl security params), QW-4 (SSH rate limiting). Possibly others -- full audit of QW-1, QW-3, QW-5, QW-6 against current code required.

---

### MED-3: No wiki pages for Phase 5 roles: network, dns, vpn

As noted in SER-3, three of four Phase 5 networking roles lack wiki pages. Additionally, the `network` role was flagged in the plan (Critical Error #1) as a duplicate that should be removed from Priority 1 and kept in Networking. The current roadmap has it only in Phase 5, but there is no wiki page defining its scope.

---

### MED-4: logrotate is listed in Phase 8 but has NO wiki page and NO role directory

The roadmap (line 97) lists `logrotate` in Phase 8 (Observability). No `wiki/roles/logrotate.md` exists. No `ansible/roles/logrotate/` directory exists. The role is mentioned once in the roadmap section listing and once in the plan (line 292). It has no design, no scope definition, and no clear purpose -- systemd-journald handles its own rotation, Docker with journald driver delegates to journald, and only traditional syslog/text log files need logrotate.

**Question**: What exactly does the logrotate role rotate? If all logging goes through journald (Phase 2), the only remaining text log is `/var/log/sudo.log` (created by QW-6). A full logrotate role for one file is over-engineering.

---

### MED-5: Roadmap counts 21 existing roles but playbook only includes 18

The roadmap's "current state" table lists 21 roles across 8 phases. The playbook (`ansible/playbooks/workstation.yml`) includes 18 roles. The 3 missing from the playbook are the git, shell, and... let me recount.

Playbook roles: base_system, vm, reflector, gpu_drivers, sysctl, power_management, yay, packages, user, ssh, git, shell, docker, firewall, caddy, vaultwarden, xorg, lightdm, greeter, zen_browser, chezmoi = **21 roles**.

Roadmap lists: base_system, vm, reflector, gpu_drivers, sysctl, power_management, yay, packages, user, ssh, git, shell, docker, firewall, caddy, vaultwarden, xorg, lightdm, greeter, zen_browser, chezmoi = **21 roles**.

Correction: counts match at 21. No discrepancy here.

---

### MED-6: Molecule tests exist for all 21 roles but CI only runs lint, not Molecule

The `.github/workflows/lint.yml` runs yamllint, ansible-lint, and syntax-check. It does NOT run Molecule tests. The roadmap mentions "Molecule tests for CI/CD" as an obligation for new roles (line 238), but no existing CI pipeline actually executes them.

Molecule test files exist for all 21 roles (confirmed via glob), but they are only run manually, never in CI. This means regressions can be introduced silently.

---

## 4. Minor Issues (low)

### MIN-1: Inconsistent wiki page structure between sections

Roles in sections 1-6 of the roadmap ("Новые роли по направлениям") have `[[role_name]]` wiki links and a "Детали" column pointing to `wiki/roles/`. Roles in section 7 (Desktop Experience) have a dash `--` in the Детали column, indicating no wiki page exists. Sections 8-9 (Storage & Development) have no Детали column at all.

---

### MIN-2: Phase numbering uses "1.5" which breaks integer-based sorting

Phase 1.5 between Phase 1 and Phase 2 is a hack. If more phases are inserted later, this becomes unmanageable (Phase 1.25?). Use integer phases or named phases.

---

### MIN-3: Quick-Wins document includes implementation code snippets

`wiki/Quick-Wins.md` contains 749 lines, including full Ansible task YAML, PAM configuration, nftables rules, and test commands. This is design documentation mixed with implementation code. When the actual roles are implemented, the Quick-Wins doc becomes stale immediately (as already happened with QW-2 and QW-4).

**Fix**: Quick-Wins should describe WHAT to change and WHY. Implementation details belong in the role code and comments.

---

### MIN-4: Roadmap uses Russian comments; some wiki pages mix Russian and English

The roadmap and plan are consistently in Russian, which is fine. But wiki role pages like `grafana.md` mix Russian section headers with English code comments. Consistency would improve readability.

---

## 5. Missing Roles (gap analysis)

For each of the ~25 roles from the review prompt's Section C, assessed against the roadmap, wiki/roles/, and ansible/roles/:

| # | Role | Status | Location if present | Security risk if absent |
|---|------|--------|---------------------|------------------------|
| 1 | `timezone` / `ntp` / `chrony` | **COVERED** | `base_system` role handles timezone (line 9-11 in tasks/main.yml) and NTP via systemd-timesyncd (lines 59-67). Uses `community.general.timezone` module and enables `systemd-timesyncd` service. | N/A -- adequate for single workstation. chrony would be better for sub-ms accuracy but not required here. |
| 2 | `locale` / `hostname` / `hosts` | **COVERED** | `base_system` role handles all three: locale (lines 15-31), hostname (lines 35-37), /etc/hosts (lines 40-46). | N/A -- adequate. |
| 3 | `cron` / `at` | **ABSENT** | Not in roadmap, not planned. | **LOW** -- systemd timers replace cron/at for all planned roles. However, some third-party tools (certbot pre-hook, logrotate on non-systemd-timer systems) may expect cron. Not a blocker for this project. |
| 4 | `logrotate` | **PARTIALLY COVERED** | Listed in Phase 8 roadmap (line 97). No wiki page, no role directory, no implementation. QW-6 creates a logrotate config for sudo.log in the user role. | **LOW** -- journald handles most rotation. Only needed for text log files like sudo.log. Current QW-6 handles the one known case. A full role is likely unnecessary. |
| 5 | `motd` / `issue` / `banner` | **ABSENT** | Not in roadmap, not planned. | **MEDIUM** -- Legal/login banners are required by PCI-DSS 2.2.4 and CIS Benchmark 1.7.x. Without them, there is no legal notice before login. For a personal workstation this is low risk; for any compliance scenario it is a gap. |
| 6 | `grub_password` | **ABSENT** | The `bootloader` wiki page mentions secure boot and kernel lockdown but does NOT include GRUB password protection. | **MEDIUM** -- Physical access attacker can edit GRUB entries at boot to add `init=/bin/bash` and get root shell. Kernel lockdown (in bootloader role) mitigates some vectors but not GRUB entry editing. |
| 7 | `fstab` / `mount_options` | **PARTIALLY COVERED** | `disk_management` role (Phase 11) mentions "fstab, mount options, trim" but has no wiki page, no implementation. The `tmpfiles` role handles /tmp cleanup but not mount options like noexec/nosuid/nodev. | **HIGH** -- Without noexec on /tmp, /var/tmp, and /dev/shm, malware can execute from world-writable directories. This is CIS Benchmark 1.1.x. Phase 11 is too late -- mount hardening should be in Phase 2 (Security Foundation). |
| 8 | `core_dumps` | **ABSENT** | Not in roadmap. `sysctl` has `fs.suid_dumpable: 0` in QW-2 (and it IS present in the current sysctl defaults at line -- wait, it's NOT in the current defaults). Actually checking: `fs.suid_dumpable` is NOT present in `ansible/roles/sysctl/defaults/main.yml`. It IS mentioned in Quick-Wins.md line 176 but only within the QW-2 proposed additions block, which is a documentation artifact (sysctl defaults only go up to `fs.protected_symlinks`). So core dumps are NOT restricted at the sysctl level. Additionally, no `/etc/security/limits.conf` entry for `* hard core 0` exists. | **MEDIUM** -- Core dumps can contain passwords, encryption keys, and other sensitive data from process memory. Without restriction, any crashing process writes a core dump readable by the process owner. |
| 9 | `usb_guard` / `usb_storage` | **ABSENT** | Not in roadmap, not planned. | **MEDIUM** -- USB-based attacks (rubber ducky, USB drop, BadUSB) are unmitigated. For a personal workstation where the user controls physical access, risk is lower. For shared environments, this is HIGH. |
| 10 | `firewall_outbound` | **ABSENT** | Not in roadmap. Confirmed: `chain output { policy accept; }` in nftables template. | **HIGH** -- All outbound traffic is unrestricted. A compromised process can freely exfiltrate data or establish C2 channels. No egress filtering exists or is planned. |
| 11 | `sshd_2fa` | **ABSENT** | Not in roadmap. No mention of TOTP, FIDO2, or pam_u2f anywhere. | **MEDIUM** -- SSH authentication relies solely on password or key. Adding TOTP or FIDO2 (pam_u2f) provides defense-in-depth against key theft. For a personal workstation with key-only auth, risk is lower. |
| 12 | `dns_encryption` | **COVERED** | `systemd_resolved` role (Phase 5) handles DNS-over-TLS with `systemd_resolved_dns_over_tls: "yes"` option. Wiki page explicitly documents DoT strict vs opportunistic modes. | N/A -- adequate coverage via systemd-resolved. DoH is not supported by systemd-resolved natively but DoT provides equivalent encryption. |
| 13 | `network_segmentation` | **ABSENT** | Not in roadmap. No VLANs, no network namespaces planned. | **LOW** for single workstation. **HIGH** if running untrusted containers alongside sensitive services (vaultwarden). Docker networks provide some segmentation, but no host-level network namespace isolation exists. |
| 14 | `wireguard` | **PARTIALLY COVERED** | Phase 5 lists generic `vpn` role. No wiki page for vpn. No specification of WireGuard vs OpenVPN vs other. | **LOW** -- VPN is planned but undefined. For a personal workstation, this is a nice-to-have, not a security blocker. |
| 15 | `secrets_management` | **PARTIALLY COVERED** | ansible-vault is used (vault-pass.sh exists, ansible.cfg references it, vaultwarden uses `vault_vaultwarden_admin_token`). But there is NO documented strategy for: where vault files live, how they're backed up, how vault passwords are rotated, or how non-Ansible secrets (GPG keys, SSH keys) are managed. | **HIGH** -- Secrets exist but management is ad-hoc. No vault file was found in the repository (only the vault-pass.sh helper and variable references). Where is the actual encrypted vault file? Is it in group_vars? In inventory? Not found. |
| 16 | `backup_verification` | **ABSENT** | Phase 11 has `backup` role but no wiki page, no implementation, and no backup verification/restore testing. | **HIGH** -- Backups that are never tested are not backups. No restore procedure is documented. No verification automation is planned. |
| 17 | `kernel_modules` | **ABSENT** | Not in roadmap. No blacklisting of dangerous modules (usb-storage, firewire, thunderbolt, cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf). CIS Benchmark 3.4.x. | **MEDIUM** -- Uncommon filesystem modules (cramfs, freevxfs, etc.) can be exploited if auto-loaded. Blacklisting reduces attack surface. The bootloader role includes `lockdown=confidentiality` kernel param which restricts module loading in lockdown mode, providing PARTIAL coverage. |
| 18 | `system_accounting` | **ABSENT** | Not in roadmap. No process accounting (acct/psacct). | **LOW** -- auditd (Phase 9) provides detailed audit trails. Process accounting adds resource usage tracking but is less security-critical than audit logging. |
| 19 | `resource_limits` | **PARTIALLY COVERED** | `pam_hardening` (Phase 2) is planned and has a wiki page. The wiki page mentions "session limits (limits.conf)". This likely covers ulimits. However, no cgroup-based fork bomb prevention exists, and the pam_hardening wiki page does not specify exact limits.conf entries. | **MEDIUM** -- Without `* hard nproc 4096` or similar, a fork bomb can crash the system. pam_hardening may cover this but the specification is vague. |
| 20 | `container_runtime_security` | **ABSENT** | Not in roadmap. No Docker Bench for Security, no rootless containers, no container image scanning. QW-3 adds userns-remap and no-new-privileges but these are daemon-level, not per-container runtime security. | **MEDIUM** -- Container security beyond daemon defaults is not addressed. No image vulnerability scanning, no runtime policy enforcement (Falco/Sysdig), no CIS Docker Benchmark automation. |
| 21 | `alerting` | **PARTIALLY COVERED** | Prometheus (Phase 8) has "alerting rules" mentioned. Grafana has "alerting" in its wiki page. But NO notification routing is defined -- where do alerts go? Email? Telegram? PagerDuty? No Alertmanager role exists. No notification channel configuration is documented. | **HIGH** -- An observability stack without alerting is a dashboard nobody watches. Alerts fire into the void without notification routing. |
| 22 | `log_forwarding` | **ABSENT** | Not in roadmap. No multi-host log aggregation architecture. | **LOW** for single workstation. The inventory hints at future multi-host (archvm, gentoobox commented out in hosts.yml) but no log forwarding plan exists for when those hosts are enabled. |
| 23 | `ima` / `evm` | **ABSENT** | Not in roadmap. IMA/EVM provide kernel-level file integrity, stronger than AIDE (Phase 9). | **LOW** -- AIDE provides user-space file integrity monitoring. IMA/EVM is kernel-level and significantly more complex to deploy. For a personal workstation, AIDE is sufficient. |
| 24 | `secureboot` | **PARTIALLY COVERED** | The `bootloader` wiki page includes `apparmor=1`, `security=apparmor`, `audit=1`, and `lockdown=confidentiality` kernel params. It mentions "secure boot" in the role description. However, no actual UEFI Secure Boot key management, MOK enrollment, or sbctl configuration is present in the wiki page defaults. | **MEDIUM** -- Secure Boot is mentioned but not implemented. Without enrolled keys, Secure Boot either uses Microsoft's default chain (no custom kernel verification) or is disabled entirely. |
| 25 | `network_time_security` (NTS) | **ABSENT** | Not in roadmap. systemd-timesyncd does NOT support NTS. Only chrony supports NTS. | **LOW** -- NTS prevents time-based MITM attacks on NTP. For a personal workstation using systemd-timesyncd with hardcoded NTP servers, the attack surface is small. NTS becomes important in hostile network environments. |

**Summary**: Of 25 checked items:
- **COVERED**: 3 (timezone/ntp, locale/hostname/hosts, dns_encryption)
- **PARTIALLY COVERED**: 7 (logrotate, fstab, wireguard, secrets_management, resource_limits, alerting, secureboot)
- **ABSENT**: 15 (cron, motd/banner, grub_password, core_dumps, usb_guard, firewall_outbound, sshd_2fa, network_segmentation, backup_verification, kernel_modules, system_accounting, container_runtime_security, log_forwarding, ima/evm, NTS)

**HIGH risk absent items**: firewall_outbound, backup_verification, fstab/mount_options (partially covered but in wrong phase)

---

## 6. Architecture Questions

### ARCH-1: Dependency graph -- partial, inconsistent

Some roles declare dependencies in `meta/main.yml`:
- caddy depends on docker
- vaultwarden depends on docker + caddy

Most roles declare `dependencies: []`. The 28 planned roles have no meta/main.yml files yet.

**Problem**: There is no visual dependency graph. Cross-phase dependencies (fail2ban -> firewall, grafana -> docker, alloy -> journald + docker) are not declared anywhere. The roadmap implies dependencies through phase ordering, but phase ordering is not enforced by Ansible unless `meta/main.yml` declares them.

**Recommendation**: Create a DOT/Mermaid dependency graph and add it to the wiki. Mandate `dependencies:` in meta/main.yml for all roles that require other roles.

---

### ARCH-2: Rollback strategy -- completely absent

No document describes what happens when a role fails mid-execution. Examples:
- QW-1 changes SSH ciphers -- if the new ciphers are incompatible with the client, SSH access is lost
- QW-5 changes PAM faillock -- if misconfigured, ALL logins are blocked
- bootloader role changes kernel params -- if incompatible, system may not boot

The plan mentions "test via console, NOT via SSH" for QW-1 (line 360), which is a single mitigation for one risk. No general rollback strategy exists.

**Recommendation**: For each QW and critical role, document: (1) pre-flight check, (2) rollback procedure, (3) out-of-band access method. Consider a "canary" approach: apply changes, verify within 60 seconds, auto-revert if verification fails.

---

### ARCH-3: Disaster recovery -- Phase 10 is too late

The `ansible_pull` role (Phase 10) enables self-healing via git-based pulls. But if the machine dies BEFORE Phase 10 is implemented (i.e., during Phases 1-9), there is no recovery procedure.

Additionally:
- No backup role exists until Phase 11
- No documented "rebuild from scratch" procedure
- No state export (list of installed packages, running services, etc.)
- The vault password (stored in `~/.vault-pass`) is a single point of failure -- if lost, all encrypted variables are unrecoverable

**Recommendation**: Phase 0 should include: (1) document rebuild procedure, (2) backup vault password to secure external location, (3) export minimal state (package list, service list) to external storage.

---

### ARCH-4: CI/CD pipeline -- lint exists, Molecule does not run in CI

The `.github/workflows/lint.yml` runs yamllint, ansible-lint, and syntax-check. This is good but insufficient:
- Molecule tests exist for all 21 roles but are NEVER run in CI
- No integration testing (running the full playbook against a test VM)
- No scheduled tests (drift detection)
- No PR gate that requires Molecule to pass

The roadmap lists "Molecule tests for CI/CD" as an obligation for new roles, but the infrastructure to run them in CI does not exist.

**Recommendation**: Add a GitHub Actions workflow that runs Molecule tests, at least for changed roles. Use Docker driver for fast feedback (not the localhost driver used in existing molecule configs).

---

### ARCH-5: Role versioning -- no strategy

No role uses semantic versioning, changelogs, or git tags. All roles are at "whatever is in master". When multiple machines use this repository (inventory hints at archvm, gentoobox), there is no way to pin a specific version of a role for a specific host.

**Recommendation**: For a single-user project, git commits serve as implicit versions. If scaling to multiple machines, consider git tags for stable releases.

---

### ARCH-6: Inventory management -- single-host only

The inventory (`ansible/inventory/hosts.yml`) defines only `localhost` as active. Two additional hosts are commented out. There is no:
- `host_vars/` directory (confirmed: does not exist)
- Per-host variable overrides
- Host-specific role selection (all hosts get all roles)
- Multi-host playbook structure

**Recommendation**: Not a problem NOW (single workstation), but becomes blocking when uncommented hosts are enabled. Plan for host_vars and per-host role selection before activating remote hosts.

---

### ARCH-7: Secret management strategy -- ad-hoc, undocumented

**What exists**:
- `ansible.cfg` references `vault_password_file = vault-pass.sh`
- `vault-pass.sh` reads from `~/.vault-pass` file
- `vaultwarden` role uses `vault_vaultwarden_admin_token`
- `grafana` wiki page uses `vault_grafana_admin_password`

**What is missing**:
- No actual vault-encrypted file was found in the repository. The `vault_` prefixed variables are referenced but where are they defined? Presumably in an untracked file or a file not yet created.
- No documentation of which secrets exist, where they're stored, or how to rotate them
- No strategy for non-Ansible secrets (GPG keys, SSH private keys, browser profiles)
- No backup plan for the vault password itself

**Risk**: If `~/.vault-pass` is lost and there is no backup, all vault-encrypted variables become unrecoverable. This is a single point of failure with no documented mitigation.

---

## 7. Recommendations

Prioritized by impact -- what to fix BEFORE any new implementation begins.

### Priority 1: IMMEDIATE (before any new role work)

1. **Audit all 6 Quick Wins against current code**. QW-2 and QW-4 appear to be already implemented. Determine exact status of QW-1, QW-3, QW-5, QW-6. Update roadmap and plan to reflect reality. Mark completed items as done.

2. **Reconcile playbook phase numbering with roadmap**. Either update `workstation.yml` comments to use the new 13-phase numbering, or adopt named phases (e.g., `# --- Security Foundation ---` instead of `# --- Phase 2 ---`).

3. **Document cross-phase dependencies explicitly**. Create a dependency matrix or Mermaid graph showing:
   - fail2ban -> firewall (Phase 2 -> already deployed)
   - All Phase 8 roles -> docker (Phase 6)
   - alloy -> journald (Phase 2) + docker (Phase 6)
   - Logging pipeline: journald (P2) -> docker+QW-3 (P6) -> alloy+loki+grafana (P8)

4. **Move fstab/mount_options hardening from Phase 11 to Phase 2**. Mount hardening (noexec on /tmp, nosuid on /dev/shm) is a security foundation item, not a storage management item. It should be in Phase 2 (Security Foundation) alongside sysctl security and PAM hardening.

### Priority 2: HIGH (before Phase 2 implementation)

5. **Add egress filtering plan**. The current `policy accept` on the output chain is the biggest security gap in the entire roadmap. Plan a `firewall_outbound` role or extend the existing firewall role to restrict outbound traffic. At minimum, whitelist expected outbound ports (80, 443, 53, 123) and drop everything else.

6. **Document secrets management strategy**. Answer: where is the vault file? How is the vault password backed up? How are secrets rotated? Document in wiki/Security.md or similar.

7. **Add resource estimation to Phase 8**. Define RAM/CPU budgets for each observability container. Consider a "minimal" vs "full" deployment option (e.g., skip cAdvisor and sensors if RAM is limited).

8. **Shrink Phase 7 to a realistic scope**. Split the 9 undocumented desktop roles into sub-phases:
   - Phase 7a: Essential (audio, compositor, screen_locker) -- 3 roles
   - Phase 7b: Convenience (clipboard, screenshots, notifications) -- 3 roles
   - Phase 7c: Polish (gtk_qt_theming, input_devices, bluetooth) -- 3 roles
   Create wiki pages for each before implementation.

### Priority 3: MEDIUM (before Phase 5+ implementation)

9. **Create wiki pages for all undocumented roles**. Currently missing:
   - Phase 5: network, dns, vpn (3 pages)
   - Phase 7: audio, compositor, notifications, screen_locker, clipboard, screenshots, gtk_qt_theming, input_devices, bluetooth (9 pages)
   - Phase 8: logrotate (1 page, or remove from roadmap if unnecessary)
   - Phase 11: disk_management, backup (2 pages)
   - Phase 12: programming_languages, containers, databases (3 pages)
   Total: **18 missing wiki pages**.

10. **Add Molecule to CI pipeline**. Extend `.github/workflows/lint.yml` (or create a new workflow) to run Molecule tests for changed roles on PR. Without this, the "Molecule tests for CI/CD" requirement is aspirational, not real.

11. **Define rollback procedures for destructive changes**. At minimum for: SSH config changes (QW-1), PAM changes (QW-5), bootloader changes, firewall changes. Document out-of-band access method (VM console, physical keyboard).

### Priority 4: LOW (long-term improvements)

12. **Consider adding absent HIGH-risk roles**: firewall_outbound (egress filtering), backup_verification (restore testing), core_dumps (memory dump restriction).

13. **Evaluate whether logrotate role is needed at all**. If all logging flows through journald, and only sudo.log uses traditional file logging (already handled by QW-6), a separate logrotate role adds complexity without value.

14. **Plan for multi-host inventory**. Before uncommenting archvm/gentoobox in hosts.yml, create host_vars structure and per-host role selection logic.

15. **Add alerting notification routing**. Phase 8 deploys Prometheus alerting and Grafana alerts, but without Alertmanager notification channels (email, Telegram, webhook), alerts are silent. Define where alerts should be delivered.

---

## Appendix: Verified Counts

| Category | Count | Details |
|----------|-------|---------|
| Implemented roles | 21 | Verified via `ls ansible/roles/` |
| Planned new roles (roadmap) | ~34 | Across Phases 1.5-12 (new items only) |
| Wiki role pages | 28 | In `wiki/roles/`, all for planned NEW roles |
| Missing wiki pages | 18 | Phase 5: 3, Phase 7: 9, Phase 8: 1, Phase 11: 2, Phase 12: 3 |
| Roles with Molecule tests | 21 | All existing roles have molecule configs |
| Roles with meta/main.yml | 21 | All existing roles |
| Roles declaring dependencies | 2 | caddy (docker), vaultwarden (docker, caddy) |
| Phase 7 total roles | 13 | 4 existing + 9 new (0 wiki pages for new) |
| Phase 8 total roles | 10 | All new, all Docker containers |
| Critical issues found | 5 | CRIT-1 through CRIT-5 |
| Serious gaps found | 6 | SER-1 through SER-6 |
| Missing roles (ABSENT) | 15 | Of 25 checked |
| Partially covered roles | 7 | Of 25 checked |

---

*End of review. All 3 files read completely. All 5 dependency chains traced. All role counts verified. All 25 missing roles assessed. All 7 architectural gaps evaluated.*
