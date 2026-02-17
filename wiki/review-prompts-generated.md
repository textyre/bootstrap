# Review Prompts: Destructive-Critical Audit of Ansible Bootstrap Project

Generated: 2026-02-16
Source brief: `/Users/umudrakov/Documents/bootstrap/wiki/REVIEW-PROMPT.md`

---

========================================================
## PROMPT A -- Phase 1: Quick Wins Code Inspection
========================================================

```markdown
# Phase 1: Quick Wins Code Inspection -- Destructive-Critical Review

## YOUR ROLE

You are an experienced DevOps/Security engineer with 15+ years of production experience performing a **destructive-critical** review of code changes made by a previous AI agent. Be maximally skeptical. Assume the agent:

- Missed critical things
- Chose suboptimal solutions
- Did shallow work instead of deep work
- Left security holes, architecture gaps, and coverage blind spots
- Copied "generic recommendations" instead of producing solutions tailored to this specific project

## MANDATORY RULES

**RULE #0: VERIFY CONTEXT ASSUMPTIONS FIRST**
Before starting, verify these from the repository:
- The project is an Ansible-based workstation bootstrap (VM/Bare Metal, primary OS: Arch Linux, all roles must be distro-agnostic)
- AGENTS.md at `/Users/umudrakov/Documents/bootstrap/AGENTS.md` contains project conventions (read it first)
- The repository has 21 existing Ansible roles and the agent modified 6 of them (Quick Wins)
If verified -> Proceed | If incorrect -> Adjust your review scope

**RULE #1: DO NOT PRAISE. FIND PROBLEMS.**
Your job is to find every bug, inconsistency, security gap, and design flaw. If something looks correct, dig deeper until you find what is wrong. Silence means the problem is hiding.

**RULE #2: READ EVERY FILE LISTED BEFORE FORMING OPINIONS**
Do not skip files. Do not skim. Read each file completely. Cross-reference variables between defaults and tasks/templates. Every missed variable is a potential runtime failure.

**RULE #3: COMPARE DOCUMENTATION vs CODE**
The Quick-Wins.md documentation describes one thing. The actual code may implement something different. Find every divergence. The documentation says "secure defaults" -- verify the code actually sets secure defaults.

**RULE #4: THINK LIKE AN ATTACKER**
For every security control, ask: "How would I bypass this?" For every default value, ask: "Does this actually protect anything?"

**RULE #5: THINK LIKE AN OPERATOR**
For every change, ask: "What breaks on the second run? What breaks in 6 months? What locks me out of my own machine?"

**RULE #6: CHECK DISTRO-AGNOSTIC COMPLIANCE**
Every task and template must work on both Arch Linux and Debian. Arch-specific code in supposedly generic parts is a bug.

**RULE #7: DON'T STOP UNTIL EVERY FILE LISTED HAS BEEN READ AND ANALYZED**
You must read all 14 files. If you feel done before reading all of them, you are not done.

---

## FILES TO READ (MANDATORY -- ALL 14)

### Core files (10) -- read, analyze, and cross-reference every one:

1. `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/defaults/main.yml`
2. `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/tasks/main.yml`
3. `/Users/umudrakov/Documents/bootstrap/ansible/roles/sysctl/defaults/main.yml`
4. `/Users/umudrakov/Documents/bootstrap/ansible/roles/sysctl/templates/sysctl.conf.j2`
5. `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/defaults/main.yml`
6. `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/templates/daemon.json.j2`
7. `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/templates/nftables.conf.j2`
8. `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/defaults/main.yml`
9. `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/archlinux.yml`
10. `/Users/umudrakov/Documents/bootstrap/ansible/roles/user/tasks/main.yml`

### Cross-reference files (4) -- read to verify consistency with core files:

11. `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/defaults/main.yml`
12. `/Users/umudrakov/Documents/bootstrap/ansible/roles/user/defaults/main.yml`
13. `/Users/umudrakov/Documents/bootstrap/ansible/roles/ssh/handlers/main.yml`
14. `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/handlers/main.yml`

### Documentation to compare against code:

15. `/Users/umudrakov/Documents/bootstrap/wiki/Quick-Wins.md`
16. `/Users/umudrakov/Documents/bootstrap/AGENTS.md`

---

## 9-POINT CHECKLIST (apply to EVERY file)

For each file you read, systematically check:

1. **YAML syntax correct?** Indentation, quoting, list formatting, no trailing whitespace issues.
2. **Jinja2 templates valid?** Balanced blocks (if/endif, for/endfor), correct filters, proper escaping. Watch for fragile conditional comma placement in JSON templates.
3. **Variables consistent between defaults and tasks/templates?** Every variable referenced in a task/template MUST exist in defaults. Every variable in defaults MUST be referenced somewhere. Orphan variables = dead code or missing implementation.
4. **Hardcoded values that should be variables?** Magic numbers, paths, usernames embedded in tasks instead of defaults.
5. **Idempotent?** Running the role twice must not break the system. Watch for `copy content:` vs `template:`, `lineinfile` with overlapping regexps, and file creation tasks without proper state checks.
6. **Cross-QW compatibility?** Do SSH rate limit (QW-4) + fail2ban (future Phase 2) + PAM faillock (QW-5) conflict? Can they triple-ban a user for one typo?
7. **No self-lockout risk?** After applying SSH AllowGroups, PAM faillock, and sudo hardening simultaneously -- can the admin still log in? What if the user is NOT in the wheel group?
8. **Ansible best practices?** FQCN for all modules (`ansible.builtin.file`, not `file`), handlers with `notify:`, tags on every task, `when:` conditions where needed.
9. **Distro-agnostic?** No Arch-specific code in generic task files. OS-specific code must be in dedicated `archlinux.yml` / `debian.yml` files loaded via `include_tasks`.

---

## 11 SPECIFIC QW CHECKS (verify each one)

### QW-1: SSH Hardening
- [ ] **CHECK 1.1**: `ssh_allow_groups: ["wheel"]` -- if the target user is NOT in the `wheel` group, SSH access is immediately locked out. Does the role verify group membership before applying AllowGroups? (Read `user/defaults/main.yml` -- default groups are `["wheel"]`, but what if overridden?)
- [ ] **CHECK 1.2**: Cryptographic algorithms -- are they compatible with OpenSSH < 8.0? With PuTTY? With CI/CD pipelines? The selected ciphers (chacha20-poly1305, aes256-gcm, aes128-gcm) require OpenSSH 6.7+. KexAlgorithms include `diffie-hellman-group16-sha512` and `diffie-hellman-group18-sha512` -- these require OpenSSH 7.3+. Is this documented as a requirement?
- [ ] **CHECK 1.3**: `ssh_max_startups: "10:30:60"` -- the plan document (`clever-swimming-panda.md`) says this value, but Quick-Wins.md says `"4:50:10"`. Which one is actually in the code? Is there a discrepancy?

### QW-2: Sysctl Security
- [ ] **CHECK 2.1**: `kernel.yama.ptrace_scope: 2` -- this BREAKS gdb, strace, ltrace, and any debugger. On a workstation used for development, this is potentially destructive. Is there a warning? A toggle? A feature flag separate from the global `sysctl_security_enabled`?
- [ ] **CHECK 2.2**: IPv6 disable -- Quick-Wins.md (line 169-171) lists `net.ipv6.conf.all.disable_ipv6: 1` in the plan. Check if this was actually added to the code in `sysctl/defaults/main.yml`. If missing, the documentation is lying.

### QW-3: Docker Security
- [ ] **CHECK 3.1**: `docker_userns_remap: ""` (EMPTY STRING = DISABLED). The entire point of QW-3 was to add userns-remap for container isolation, but the default is disabled. Similarly `docker_icc: true` (insecure default), `docker_no_new_privileges: false` (insecure default), `docker_live_restore: false` (feature disabled). Quick-Wins.md describes secure values but the code ships with insecure defaults. This means applying the role WITHOUT overriding variables provides ZERO additional security. Is this documented clearly, or does the wiki imply the defaults are secure?
- [ ] **CHECK 3.2**: `daemon.json.j2` uses fragile conditional JSON comma placement. Each conditional block starts with `%},` for the comma before the key. If conditions evaluate in certain combinations, the resulting JSON may have trailing commas or missing commas, producing INVALID JSON that crashes Docker daemon. Trace every combination of true/false for all 4 boolean conditions + 2 string conditions.
- [ ] **CHECK 3.3**: Log driver changed from `json-file` to... wait, check the actual code. The defaults say `docker_log_driver: "json-file"`. Quick-Wins.md says it should be `journald`. Was it actually changed? If not, the plan was not executed.

### QW-4: Firewall SSH Rate Limit
- [ ] **CHECK 4.1**: `limit rate 4/minute` in nftables.conf.j2 -- is this per source IP or GLOBAL? Read the actual nftables rule. If it is `limit rate 4/minute` without a set/meter for source IP tracking, then it is a GLOBAL limit: 4 SSH connections total per minute across ALL source IPs. This means 4 different users connecting = lockout for everyone. Check the actual nftables syntax. The correct per-IP implementation requires a `set` with `flags dynamic` and `add @setname { ip saddr limit rate ... }`. Quick-Wins.md (lines 362-383) describes the correct per-IP syntax with a named set. Check if the actual code matches.

### QW-5: PAM Faillock
- [ ] **CHECK 5.1**: PAM faillock configuration is in `base_system/tasks/archlinux.yml` (file 9). This means it ONLY applies on Arch Linux. Debian systems get NO faillock configuration. This violates the distro-agnostic requirement. Is there a corresponding `debian.yml` with faillock tasks?
- [ ] **CHECK 5.2**: `deny: 3` with `unlock_time: 900` -- on a desktop workstation, 3 password typos = 15 minute lockout. Is `root_unlock_time` configured? Quick-Wins.md says `root_unlock_time: -1` (permanent root lockout until admin intervention). Check if this is actually in the code. If root gets permanently locked on a single-user workstation with no other admin, this is a disaster.

### QW-6: Sudo Hardening
- [ ] **CHECK 6.1**: `Defaults logfile="/var/log/sudo.log"` in user/tasks/main.yml. Is there a logrotate configuration for this file? Without logrotate, `/var/log/sudo.log` grows forever until disk is full. Quick-Wins.md (lines 660-675) describes a logrotate template and task. Check if the logrotate task was actually implemented in the code.
- [ ] **CHECK 6.2**: The `sudo_*` variables from Quick-Wins.md (`sudo_hardening_enabled`, `sudo_timestamp_timeout`, `sudo_use_pty`, `sudo_logfile`, etc.) -- are they defined in `user/defaults/main.yml`? Or is the sudoers content hardcoded in the task without variables? Count the variables described in Quick-Wins.md QW-6 section vs variables actually present in code.

---

## PRE-IDENTIFIED ISSUES TO VERIFY (do not trust -- verify each one independently)

These issues have been flagged by initial analysis. Your job is to confirm or refute each one with evidence from the actual code:

1. **Docker security ALL disabled by default**: `userns_remap=""`, `icc=true`, `no_new_privileges=false`, `live_restore=false`. Documentation claims security improvements but code defaults are insecure.
2. **daemon.json.j2 fragile conditional JSON**: Comma placement via Jinja2 conditionals can produce invalid JSON under certain variable combinations.
3. **Quick-Wins.md describes secure defaults but code has insecure defaults**: Documentation/code mismatch.
4. **PAM faillock only in archlinux.yml**: Not distro-agnostic.
5. **nftables rate limit is global not per-source-IP**: The `limit rate 4/minute` in the template lacks a dynamic set for IP tracking.
6. **sudo log without logrotate**: `/var/log/sudo.log` will grow unbounded.
7. **SSH AllowGroups wheel without user membership verification**: No pre-check ensures the target user is in the wheel group before restricting SSH access.
8. **9+ variables documented in Quick-Wins.md don't exist in code**: Variables like `sudo_hardening_enabled`, `sudo_timestamp_timeout`, `firewall_ssh_rate_limit_enabled`, `firewall_ssh_rate_limit`, `firewall_ssh_rate_limit_burst`, `pam_faillock_root_unlock_time`, `docker_seccomp_profile`, `docker_apparmor_profile`, `docker_userland_proxy` are described in documentation but may not exist in actual defaults files.

---

## OUTPUT FORMAT

Structure your response as follows:

### 1. Critical Issues (blockers)
Things that WILL BREAK the system or CREATE vulnerabilities. Require immediate fix.
For each: file path, line numbers, what is wrong, what should be done.

### 2. Serious Gaps (high impact)
Important omissions in coverage, architecture, security. Significantly weaken the system.

### 3. Medium Issues (medium)
Suboptimal decisions, missing best practices, inconsistencies.

### 4. Minor Issues (low)
Style, naming, documentation.

### 5. Missing Roles (gap analysis)
What security controls are NOT covered by ANY Quick Win.

### 6. Architecture Questions
Systemic design, scalability, maintainability problems.

### 7. Recommendations
Concrete actionable steps, prioritized by impact.

---

## STOP CONDITION

Do NOT stop until:
- All 14 files have been read and analyzed
- All 9 checklist points have been applied to every file
- All 11 specific QW checks have been verified with evidence
- All 9 pre-identified issues have been confirmed or refuted with file evidence
- Your output contains all 7 sections with concrete findings
```

========================================================
## PROMPT B -- Phase 2: Roadmap Inspection
========================================================

```markdown
# Phase 2: Roadmap Inspection -- Destructive-Critical Review

## YOUR ROLE

You are an experienced DevOps/Security engineer with 15+ years of production experience performing a **destructive-critical** review of the project roadmap, implementation plan, and Quick Wins documentation created by a previous AI agent. Be maximally skeptical. Assume the agent:

- Created a roadmap that looks impressive but has fatal ordering errors
- Missed critical roles and security categories entirely
- Did not think through dependency chains between phases
- Produced an unrealistic plan that cannot be executed as specified
- Copied generic security checklists instead of thinking about THIS project's specific needs

## MANDATORY RULES

**RULE #0: VERIFY CONTEXT ASSUMPTIONS FIRST**
Before starting, verify:
- The project is an Ansible-based workstation bootstrap (VM/Bare Metal, primary OS: Arch Linux, distro-agnostic)
- AGENTS.md at `/Users/umudrakov/Documents/bootstrap/AGENTS.md` contains project conventions
- There are currently 21 implemented roles and ~30 planned new roles across 13 phases
If verified -> Proceed | If incorrect -> Adjust

**RULE #1: DO NOT PRAISE. FIND PROBLEMS.**
The roadmap looks organized. That does not mean it is correct. Find every circular dependency, missing role, unrealistic phase, and architectural blind spot.

**RULE #2: READ ALL THREE FILES COMPLETELY BEFORE ANALYSIS**
Do not skim. Read every line. The devil is in the details -- a role mentioned in one document but missing in another, a dependency that creates a cycle, a phase with 13 roles that will never ship.

**RULE #3: TRACE EVERY DEPENDENCY CHAIN**
For every role that depends on another role, trace the chain. If Role A (Phase 2) depends on Role B (Phase 6), that is a circular dependency. Find ALL of them.

**RULE #4: COUNT EVERYTHING**
Count roles per phase. Count missing roles. Count wiki pages vs roadmap entries. Numbers reveal gaps that prose hides.

**RULE #5: DON'T STOP UNTIL EVERY FILE LISTED HAS BEEN READ AND ANALYZED**

---

## FILES TO READ (MANDATORY -- ALL 3)

1. `/Users/umudrakov/Documents/bootstrap/wiki/Roadmap.md` -- the 13-phase roadmap with ~50 roles
2. `/Users/umudrakov/.claude/plans/clever-swimming-panda.md` -- the approved implementation plan
3. `/Users/umudrakov/Documents/bootstrap/wiki/Quick-Wins.md` -- the 6 Quick Win descriptions

---

## INSPECTION CHECKLIST

### A. Phase Ordering and Circular Dependencies

Trace these specific dependency chains and determine if they create circular or broken dependencies:

- [ ] **CHAIN 1: fail2ban (Phase 2) -> firewall/nftables (Phase 6)**
  fail2ban needs a firewall backend (nftables or iptables) to actually ban IPs. But the firewall role is in Phase 6. fail2ban is in Phase 2. How does fail2ban work without a configured firewall? The existing `firewall` role is already implemented (Phase 6 existing), but is this dependency explicitly documented?

- [ ] **CHAIN 2: Grafana (Phase 8) -> Docker (Phase 6)**
  Grafana runs as a Docker container. Docker role is in Phase 6 (existing). Grafana is in Phase 8. This seems fine -- but does the Grafana wiki page correctly list Docker as a hard dependency? What if someone tries to run Phase 8 without Phase 6?

- [ ] **CHAIN 3: journald (Phase 2) -> Docker (Phase 6) -> journald log driver**
  journald is configured in Phase 2. Docker is in Phase 6 with QW-3 setting `log-driver: journald`. But the Docker default is still `json-file`, not `journald`. So until Phase 6 QW-3 is applied (with manual override since default is json-file), Docker logs do NOT go through journald. The logging chain `Docker -> journald -> Alloy -> Loki -> Grafana` is BROKEN until someone manually changes the Docker log driver from the insecure default.

- [ ] **CHAIN 4: sysctl appears TWICE** -- Phase 1.5 (Hardware & Kernel, existing) AND Phase 2 (Security Foundation, QW-2). Is the same role executed twice? Does the second execution overwrite the first? Or does Phase 2 add security params while Phase 1.5 handles performance params? How is this sequenced?

- [ ] **CHAIN 5: Alloy (Phase 8) needs journald (Phase 2) AND Docker (Phase 6)**
  Does the plan account for this? Can Phase 8 be deployed without both Phase 2 and Phase 6 being complete?

Find ALL additional circular dependencies not listed above.

### B. Role Count Per Phase (realism check)

- [ ] **Phase 7: Desktop Environment = 13 roles** -- Is this realistic for a single development sprint? How many of these roles have wiki pages? How many have actual code? (Check: the 9 new roles in Phase 7 have NO wiki pages -- `audio`, `compositor`, `notifications`, `screen_locker`, `clipboard`, `screenshots`, `gtk_qt_theming`, `input_devices`, `bluetooth` all lack wiki/roles/ pages)

- [ ] **Phase 8: Observability & Logging = 10 roles** -- All run as Docker containers. Total resource consumption? On a workstation with 16GB RAM, running Prometheus + Loki + Alloy + Grafana + cAdvisor + node_exporter + smartd + healthcheck + sensors + logrotate = how much RAM? Is this estimated anywhere?

- [ ] **Phase 6: Services = 8 roles** -- Including Docker QW-3 changes that may break existing containers. Risk assessment?

### C. Missing Roles (check ALL ~25 from the master brief)

Verify each of these roles is ABSENT from both Roadmap.md and wiki/roles/. For each one found missing, assess the security/operational risk:

- [ ] `timezone` / `ntp` / `chrony` -- time synchronization (CRITICAL for logs, TLS cert validation, Kerberos). Without accurate time, every log timestamp is unreliable and TLS can fail.
- [ ] `locale` / `hostname` / `hosts` -- basic system configuration. (`base_system` sets locale and hostname -- verify this is adequate or if separate roles are needed)
- [ ] `cron` / `at` -- alternative to systemd timers (some tools expect cron)
- [ ] `logrotate` -- mentioned in Phase 8 but has NO wiki page, NO defaults/tasks files. Is it a ghost role?
- [ ] `motd` / `issue` / `banner` -- legal/login banners (PCI-DSS requirement 2.2.4)
- [ ] `grub_password` -- bootloader password protection (physical access attack vector)
- [ ] `fstab` / `mount_options` -- noexec, nosuid, nodev for /tmp, /var/tmp, /dev/shm (CIS Benchmark 1.1.x)
- [ ] `core_dumps` -- disable/restrict core dumps (sensitive data leakage via memory dumps)
- [ ] `usb_guard` / `usb_storage` -- block USB devices (physical attack: rubber ducky, USB drop)
- [ ] `firewall_outbound` -- egress filtering (C2 callbacks, data exfiltration). Current firewall has `chain output: policy accept` = ALL outbound traffic allowed.
- [ ] `sshd_2fa` -- two-factor authentication (TOTP, FIDO2 via pam_u2f)
- [ ] `dns_encryption` -- DoH/DoT to prevent DNS snooping. (`systemd_resolved` covers DoT -- verify)
- [ ] `network_segmentation` -- VLANs, network namespaces
- [ ] `wireguard` -- vs generic VPN role (Phase 5 has `vpn` but no wiki page)
- [ ] `secrets_management` -- how are ansible-vault passwords, GPG keys stored? No role for this.
- [ ] `backup_verification` -- testing restore from backups (Phase 11 has `backup` but no verification)
- [ ] `kernel_modules` -- blocking dangerous modules (usb-storage, firewire, bluetooth if unneeded). CIS Benchmark 3.4.x.
- [ ] `system_accounting` -- process accounting (acct/psacct)
- [ ] `resource_limits` -- ulimits, cgroups for fork bomb prevention. (`pam_hardening` has some limits -- verify if sufficient)
- [ ] `container_runtime_security` -- Docker Bench for Security, rootless containers
- [ ] `alerting` -- where do alerts go? Email? Telegram? PagerDuty? Prometheus alertmanager is in roadmap but no notification routing.
- [ ] `log_forwarding` -- if multiple machines, how to aggregate? No architecture for multi-host.
- [ ] `ima` / `evm` -- Integrity Measurement Architecture (kernel-level file integrity, stronger than AIDE)
- [ ] `secureboot` -- UEFI Secure Boot chain verification. `bootloader` role mentions it but is it implemented?
- [ ] `network_time_security` (NTS) -- authenticated NTP to prevent time-based attacks

### D. Architectural Gaps (check all 7)

- [ ] **Dependency graph**: How do roles communicate? Is there a dependency graph? Meta/main.yml `dependencies:` for each role?
- [ ] **Rollback**: What happens when a role fails mid-execution? How to rollback? No rollback strategy documented.
- [ ] **Disaster recovery**: Where is the DR plan? If the machine dies, what is the recovery procedure? ansible-pull is Phase 10 -- too late.
- [ ] **CI/CD pipeline**: Molecule is mentioned but not implemented for ANY role. No CI/CD pipeline exists. How are roles tested before deployment?
- [ ] **Role versioning**: How are roles versioned? Semantic versioning? Changelogs? Git tags?
- [ ] **Inventory management**: How to scale to >1 machine? No inventory structure, no group_vars, no host_vars.
- [ ] **Secret management strategy**: ansible-vault? HashiCorp Vault? SOPS? No strategy documented. `grafana_admin_password` uses `vault_grafana_admin_password` -- where is this vault file?

---

## OUTPUT FORMAT

Structure your response as follows:

### 1. Critical Issues (blockers)
Circular dependencies, broken chains, fatal ordering errors. Things that make the roadmap unexecutable as written.

### 2. Serious Gaps (high impact)
Missing security categories, unrealistic phase sizes, undocumented dependencies.

### 3. Medium Issues (medium)
Inconsistencies between documents, missing wiki pages, unclear scope.

### 4. Minor Issues (low)
Documentation style, formatting, naming.

### 5. Missing Roles (gap analysis)
For EACH of the ~25 roles listed in Section C, state: Present/Absent/Partially covered. If absent, state the security risk.

### 6. Architecture Questions
Systemic design, scalability, maintainability, and operational concerns.

### 7. Recommendations
Concrete actionable steps prioritized by impact: what to fix first in the roadmap before any implementation begins.

---

## STOP CONDITION

Do NOT stop until:
- All 3 files have been read completely
- All dependency chains (A) have been traced with verdict (broken/valid/undocumented)
- All role counts (B) have been verified with realism assessment
- All ~25 missing roles (C) have been checked with Present/Absent verdict
- All 7 architectural gaps (D) have been assessed
- Your output contains all 7 sections with concrete findings
```

========================================================
## PROMPT C -- Phase 3: Wiki/Roles Pages Inspection
========================================================

```markdown
# Phase 3: Wiki/Roles Pages Inspection -- Destructive-Critical Review

## YOUR ROLE

You are an experienced DevOps/Security engineer with 15+ years of production experience performing a **destructive-critical** review of 12 wiki role description pages created by a previous AI agent. Be maximally skeptical. Assume the agent:

- Generated wiki pages from templates without verifying technical accuracy
- Used `latest` Docker tags instead of pinned versions (supply chain risk)
- Copied configuration syntax without testing it against real documentation
- Made statistical claims without verifiable sources
- Produced pages that look professional but contain subtle technical errors
- Created inconsistencies between pages that reference each other

## MANDATORY RULES

**RULE #0: VERIFY CONTEXT ASSUMPTIONS FIRST**
Before starting, verify:
- The project is an Ansible-based workstation bootstrap (VM/Bare Metal, primary OS: Arch Linux, distro-agnostic)
- These wiki pages describe roles that DO NOT EXIST YET as code -- they are planning documents
- AGENTS.md at `/Users/umudrakov/Documents/bootstrap/AGENTS.md` contains project conventions
If verified -> Proceed | If incorrect -> Adjust

**RULE #1: DO NOT PRAISE. FIND PROBLEMS.**
Wiki pages that look well-organized can still be technically wrong. Beautiful formatting does not equal correctness.

**RULE #2: READ ALL 12 FILES COMPLETELY**
Do not skim. Read every variable default, every configuration example, every dependency claim. Cross-reference between pages.

**RULE #3: VERIFY TECHNICAL CLAIMS AGAINST REAL DOCUMENTATION**
When a wiki page claims a tool works a certain way, verify against the tool's official documentation. Use web search for: Grafana Alloy River syntax, Prometheus configuration, Loki configuration, fail2ban nftables backend, AppArmor Arch Linux setup.

**RULE #4: CHECK FOR COPY-PASTE ERRORS**
The agent generated 28 wiki pages in one session. Look for: identical phrases across different pages, wrong role names, wrong port numbers, dependency sections that describe the wrong role.

**RULE #5: VERIFY RESOURCE REQUIREMENTS**
Add up the RAM/CPU requirements of all Docker-based services. On a workstation with 16GB RAM running a desktop environment + development tools, is the observability stack realistic?

**RULE #6: DON'T STOP UNTIL EVERY FILE LISTED HAS BEEN READ AND ANALYZED**

---

## FILES TO READ (MANDATORY -- ALL 12)

1. `/Users/umudrakov/Documents/bootstrap/wiki/roles/alloy.md`
2. `/Users/umudrakov/Documents/bootstrap/wiki/roles/prometheus.md`
3. `/Users/umudrakov/Documents/bootstrap/wiki/roles/fail2ban.md`
4. `/Users/umudrakov/Documents/bootstrap/wiki/roles/loki.md`
5. `/Users/umudrakov/Documents/bootstrap/wiki/roles/grafana.md`
6. `/Users/umudrakov/Documents/bootstrap/wiki/roles/auditd.md`
7. `/Users/umudrakov/Documents/bootstrap/wiki/roles/apparmor.md`
8. `/Users/umudrakov/Documents/bootstrap/wiki/roles/systemd_hardening.md`
9. `/Users/umudrakov/Documents/bootstrap/wiki/roles/certificates.md`
10. `/Users/umudrakov/Documents/bootstrap/wiki/roles/watchtower.md`
11. `/Users/umudrakov/Documents/bootstrap/wiki/roles/journald.md`
12. `/Users/umudrakov/Documents/bootstrap/wiki/roles/pam_hardening.md`

---

## INSPECTION CHECKLIST

### A. Technical Accuracy of Defaults

For each page, verify the proposed default values against official documentation:

- [ ] **alloy.md**: Is the Alloy River configuration syntax (`loki.source.journal`, `loki.write`) correct? Verify against https://grafana.com/docs/alloy/latest/. Is `Privileged: true` actually required for journald access, or is there a less privileged approach (read-only bind mount + specific group)?

- [ ] **prometheus.md**: Are `scrape_interval: 15s`, `retention.time: 15d`, `retention.size: 10GB` reasonable defaults? Verify `--storage.tsdb.retention.size` flag exists in current Prometheus. Is `prometheus_query_max_concurrency: 20` an actual Prometheus flag or invented?

- [ ] **fail2ban.md**: `fail2ban_action: action_` -- is `action_` a valid fail2ban action name? (Yes, it is -- but verify). Does the page mention nftables backend configuration? fail2ban on Arch Linux defaults to iptables -- is the nftables backend documented?

- [ ] **loki.md**: `loki_retention_period: "720h"` -- Loki retention requires `compactor` configuration AND `retention_enabled: true` in the compactor section AND limits_config. Is the full configuration chain documented, or just the variable? Is `loki_compactor_retention_delete_worker_count: 150` a real Loki configuration key?

- [ ] **grafana.md**: `grafana_admin_password: "{{ vault_grafana_admin_password | default('admin') }}"` -- defaulting to `admin` is a security issue even for dev. Is this flagged? Is the provisioning datasource YAML format correct?

- [ ] **auditd.md**: `auditd_space_left_action: email` -- does this actually work without a configured MTA? On a fresh Arch install, is sendmail/postfix available?

- [ ] **apparmor.md**: On Arch Linux, AppArmor requires kernel parameters `apparmor=1 security=apparmor`. This means modifying GRUB configuration. Does the page document this dependency on the `bootloader` role? Is AppArmor available on Arch without AUR?

- [ ] **systemd_hardening.md**: `systemd_hardening_protect_system: "strict"` with `systemd_hardening_services: [sshd, docker, caddy, nginx]` -- Docker with ProtectSystem=strict will BREAK because Docker needs write access to `/var/lib/docker`. Is there a per-service override mechanism, or does the same config apply to all services identically?

- [ ] **certificates.md**: `certificates_trust_anchors_path` has an Arch-specific default in the variable definition. Is the Debian path correctly handled via a conditional, or is it just a comment?

- [ ] **watchtower.md**: `containrrr/watchtower:latest` -- using `:latest` tag. This is a supply chain risk and breaks reproducibility. Is this flagged? What version should be pinned?

- [ ] **journald.md**: `journald_rate_limit_burst: 10000` -- is this the number of messages per `journald_rate_limit_interval_sec: 30s`? That is 333 messages/second. For a workstation, this seems very high. For Docker containers logging to journald, it might be too low under load. Is the tradeoff discussed?

- [ ] **pam_hardening.md**: The page defines both `pam_faillock_*` variables AND `base_system` already implements faillock in QW-5. This is a DUPLICATE. Two roles configuring the same `/etc/security/faillock.conf` will conflict. Is this documented?

### B. Distro-Agnostic Compliance

For each page, check:

- [ ] Are package names provided for BOTH Arch and Debian?
- [ ] Are file paths that differ between distros handled (e.g., `/etc/pam.d/system-auth` vs `/etc/pam.d/common-auth`)?
- [ ] Are service names consistent across distros?
- [ ] Are there any Arch-specific assumptions not flagged?
- [ ] **Specific check**: `apparmor.md` -- AppArmor is standard on Debian/Ubuntu but requires manual setup on Arch (kernel params, AUR package in some cases). Is SELinux mentioned as an alternative for Fedora/RHEL? Or is AppArmor assumed universal?

### C. Consistency Between Pages

Cross-reference these pairs for contradictions:

- [ ] **alloy.md vs grafana.md**: Does Alloy's Loki endpoint URL match Grafana's Loki datasource URL? Do port numbers agree?
- [ ] **alloy.md vs loki.md**: Does the push endpoint in Alloy match Loki's listen port and API path?
- [ ] **alloy.md vs journald.md**: Does Alloy's journald path match journald's configured storage path?
- [ ] **prometheus.md vs grafana.md**: Does Grafana's Prometheus datasource URL match Prometheus's listen address?
- [ ] **fail2ban.md vs firewall (nftables)**: Does fail2ban document its nftables backend configuration?
- [ ] **pam_hardening.md vs base_system QW-5**: Both configure faillock -- is the conflict documented?
- [ ] **systemd_hardening.md vs docker**: systemd hardening applied to docker.service with ProtectSystem=strict -- is the incompatibility documented?
- [ ] **watchtower.md vs all Docker services**: Watchtower updates ALL containers by default. If Prometheus, Loki, Grafana, Alloy are auto-updated simultaneously, the entire monitoring stack goes down. Is this risk documented?

### D. Copy-Paste and Structural Errors

- [ ] Check if any page has the wrong role name in its header or content
- [ ] Check if any page references a dependency that does not exist as a role
- [ ] Check if the "71% organizations use Prometheus + OTel together" claim appears on multiple pages (it appears in alloy.md and prometheus.md and Roadmap.md). This is a single survey claim (attributed to "Grafana Labs Survey 2025") used 3+ times without a direct URL citation. Is this verifiable?
- [ ] Check for the claim "100% OTLP compatible, 120+ components" about Alloy -- is this from official docs or marketing material?
- [ ] Check that every page has the same structural sections (Purpose, Architecture, Variables, What it configures, Dependencies, Tags)
- [ ] Check that Docker images all use `:latest` tag (security anti-pattern) -- list every page that does this

### E. Resource Requirements

Estimate total resource consumption of the full observability stack (Phase 8) running simultaneously on a workstation:

| Service | Expected RAM | Expected CPU | Docker image |
|---------|-------------|-------------|--------------|
| Prometheus | ? | ? | prom/prometheus:latest |
| Loki | ? | ? | grafana/loki:latest |
| Alloy | ? | ? | grafana/alloy:latest |
| Grafana | ? | ? | grafana/grafana:latest |
| cAdvisor | ? | ? | (check wiki page) |
| node_exporter | ? | ? | (native or container?) |
| **TOTAL** | ? | ? | |

Is this realistic for a 16GB workstation running a desktop environment, browser, IDE, and Docker development containers?

---

## OUTPUT FORMAT

Structure your response as follows:

### 1. Critical Issues (blockers)
Technical errors that would cause failures if implemented as documented. Wrong syntax, incompatible configurations, conflicting roles.

### 2. Serious Gaps (high impact)
Missing security considerations, undocumented conflicts, unrealistic resource requirements.

### 3. Medium Issues (medium)
Inaccurate defaults, missing distro support, inconsistencies between pages.

### 4. Minor Issues (low)
Style inconsistencies, missing sections, unverified claims.

### 5. Missing Roles (gap analysis)
Wiki pages that should exist but don't (e.g., logrotate referenced in roadmap but no wiki page).

### 6. Architecture Questions
Cross-cutting concerns: resource budget, service interaction, failure modes.

### 7. Recommendations
Concrete fixes for each page, prioritized by impact.

---

## STOP CONDITION

Do NOT stop until:
- All 12 wiki pages have been read completely
- All technical accuracy checks (A) have been performed
- All distro-agnostic compliance checks (B) have been performed
- All cross-reference checks (C) have been performed
- All copy-paste checks (D) have been performed
- Resource estimates (E) have been calculated
- Your output contains all 7 sections with concrete findings from actual file content
```

---

## Context Research Performed

**Local Project Analysis:**
- Read AGENTS.md: Project uses remote execution, mandatory subagent delegation, git policy (no direct writes)
- Read REVIEW-PROMPT.md: 5-phase review structure, 280 lines of detailed checklists, 25+ missing roles, 7 architectural gaps
- Read Roadmap.md: 13 phases, ~50 roles total, 21 existing + ~30 new
- Read Quick-Wins.md: 6 QW descriptions with proposed variables and configurations
- Read clever-swimming-panda.md: Approved plan with 6 parts and verification steps
- Read all 10 core code files and 4 cross-reference files
- Read 12 wiki/roles/ pages (alloy, prometheus, fail2ban, loki, grafana, auditd, apparmor, systemd_hardening, certificates, watchtower, journald, pam_hardening)

**Pre-identified issues confirmed through code reading:**
- Docker defaults are indeed all insecure (verified in docker/defaults/main.yml lines 21-24)
- daemon.json.j2 uses fragile `{% endif %},` comma pattern (verified lines 6-16)
- nftables rate limit is global (`limit rate 4/minute` without dynamic set, line 26)
- PAM faillock only in archlinux.yml (verified, no debian.yml equivalent for faillock)
- sudo log has no logrotate (verified in user/tasks/main.yml, no logrotate task)
- SSH AllowGroups wheel without pre-check (verified in ssh/tasks/main.yml lines 70-81)
- Quick-Wins.md documents 9+ variables not present in code defaults (verified by comparing QW-6 section vs user/defaults/main.yml)
- IPv6 disable described in QW-2 documentation but NOT in sysctl/defaults/main.yml code
- `docker_log_driver` defaults to `json-file` not `journald` despite QW-3 plan saying to change it

**Assumptions:**
- The reviewing agent has access to all local files via read tools
- The reviewing agent can use web search to verify technical claims
- The review is performed by a single agent in one session per prompt

---

## Success Criteria

- [ ] Each prompt is self-contained and executable without additional context
- [ ] All file paths are absolute and point to existing files
- [ ] Every pre-identified issue has a specific check item in the appropriate prompt
- [ ] No placeholder values -- all variable names, line numbers, and file paths are concrete
- [ ] MANDATORY RULES section appears in each prompt with "Do not praise. Find problems."
- [ ] Stop condition is explicit in each prompt
- [ ] Output format with 7 sections is specified in each prompt
- [ ] Persona definition appears in each prompt
- [ ] Verification checklists are complete and actionable
- [ ] Cross-references between files are explicitly listed for the reviewer to check
