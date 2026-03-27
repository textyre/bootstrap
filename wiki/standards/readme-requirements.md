# README Requirements Specification

> Source of truth for role README structure. All roles MUST comply.
> Role implementation standards: [[Role Requirements|standards/role-requirements]]
> Testing specification: [[Testing Requirements|standards/testing-requirements]]
> Reference implementation: `ansible/roles/ntp/README.md`

## Scope

This specification applies to `README.md` in every Ansible role under `ansible/roles/`.

## Target Audience

Support engineer with Linux, Docker, Ansible background. Sees this specific role for the first time. Must be able to — without reading task files or templates:

1. **Understand** what the role does and in what order
2. **Configure** — toggle settings without fear of breaking things
3. **Fix** — diagnose and resolve common failures
4. **Verify** — run tests and know if they passed
5. **Find logs** — locate output, understand format, manage rotation

---

## Required Sections

Every README MUST contain the following sections in this order.

### README-001: Header

**Priority:** MUST

One-line description of what the role does, in plain language. No implementation details.

```markdown
# ntp

Synchronizes system clock via chrony with encrypted NTS servers.
```

**Verification Criteria:**
- First line: `# <role_name>`
- Second line: one sentence, answers "what does this role do for the system?"
- No Ansible/Jinja2 jargon in the header

**Anti-patterns:**
- `NTP time synchronization via chrony with NTS-enabled servers and full parametrization` — implementation details in the header
- Missing header entirely

---

### README-002: Execution Flow

**Priority:** MUST
**Rationale:** Support needs to know the full order of operations — including nested tasks and handlers. When the role fails at step 5, they need to understand what already ran (1–4) and what didn't (6+). The numbered list must cover the complete execution path: `tasks/main.yml` orchestration, nested task files it includes, and handlers that fire between or after steps.

````markdown
## Execution flow

1. **Validate** (`tasks/validate.yml`) — checks input variables; fails if no servers configured, minsources out of range, or threshold invalid
2. **Detect environment** (`tasks/detect_environment.yml`) — identifies hypervisor (KVM/VMware/Hyper-V/VirtualBox/bare metal), loads environment-specific config from `vars/environments.yml`, resolves refclock list
3. **Load KVM module** (`tasks/load_ptp_kvm.yml`) — KVM only: loads `ptp_kvm` kernel module, persists in `/etc/modules-load.d/`, verifies `/dev/ptp0` exists. Warns if device not found.
4. **Disable competitors** (`tasks/disable_systemd.yml`, `disable_ntpd.yml`, `disable_openntpd.yml`, `vmware_disable_timesync.yml`) — stops systemd-timesyncd, ntpd, openntpd if present. VMware: disables periodic timesync via `vmware-toolbox-cmd`. Skips gracefully if service not found.
5. **Install** — installs chrony via package manager
6. **Configure** — deploys `/etc/chrony.conf` (Arch) or `/etc/chrony/chrony.conf` (Ubuntu) from template. **Triggers handler:** if config changed, chrony will be restarted before verification.
7. **Start** — enables and starts chrony service
8. **Flush handlers** — applies pending restart (from step 6) so verification runs against new config
9. **Verify** (`tasks/verify.yml`) — checks internet connectivity, chronyc tracking, sources, waits for sync (60s), asserts synced source exists
10. **Report** — writes execution report via common/report_phase + report_render

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `restart ntp` | Config file change (step 6) | Restarts chrony service. Flushed before verification (step 8). |
````

**Verification Criteria:**
- Numbered list, one step per line
- Each step: **bold name** + plain-language description of what happens
- Nested task files named explicitly — support can find the file if they need to dig deeper
- Steps that trigger handlers explicitly say so ("Triggers handler: ...")
- Handlers section lists every handler with its trigger and effect
- Step names match phase comments/separators in `tasks/main.yml`
- Where a step produces files on the system, the path is mentioned (config, logs, modules-load.d)
- Where a step can fail, the failure behavior is described ("fails if...", "warns if...", "skips gracefully if...")

**Anti-patterns:**
- Unnumbered bullet list (support can't say "it failed at step 5")
- Steps that describe Ansible internals (`include_tasks`, `with_first_found`) instead of outcomes
- Checkbox list (`- [x]`) — implies completion status, not execution flow
- Omitting nested task files — support sees "Disable competitors" but doesn't know there are 4 separate task files involved
- Omitting handlers — support doesn't know that a config change triggers a service restart before verification

---

### README-003: Variables

**Priority:** MUST
**Rationale:** Variables are the role's public API. Support must know what each variable does, what value is safe, and what happens if they change it. This covers both user-facing variables (`defaults/main.yml`) and internal mappings (`vars/`).

**Structure:** Two subsections — configurable variables (table with safety levels) and internal variables (summary of what `vars/` files contain and when support might need to look at them).

Safety levels for configurable variables:

| Level | Meaning |
|-------|---------|
| safe | Change freely, no risk of breaking the role |
| careful | Understand the consequences before changing |
| internal | Do not change unless you understand chrony/systemd/etc. internals |

````markdown
## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ntp_enabled` | `true` | safe | Set `false` to skip this role entirely |
| `ntp_servers` | 4 NTS servers | safe | NTP servers list. See [Changing servers](#changing-servers) for examples |
| `ntp_minsources` | `2` | careful | Minimum servers that must agree before clock is adjusted. Must be ≤ number of servers. If set higher than server count, clock will never update |
| `ntp_ntsdumpdir` | `/var/lib/chrony/nts-data` | internal | NTS session cookie cache. Changing breaks NTS reconnection |

### Internal mappings (`vars/`)

These files contain cross-platform and environment mappings. Do not override via inventory — edit the files directly only when adding new platform or hypervisor support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | OS-family mappings: service name (`chronyd`/`chrony`), config path, package name, system user per distro | Adding support for a new distro |
| `vars/environments.yml` | Hypervisor-specific settings: refclocks, rtcsync, makestep per environment (KVM, VMware, Hyper-V, VirtualBox, bare metal) | Adding support for a new hypervisor |
````

**Verification Criteria:**
- Every variable from `defaults/main.yml` is listed in the configurable table — no hidden variables
- Every configurable variable has a safety level
- `careful` and `internal` variables explain the consequence of a wrong value
- Complex types (lists of objects) have a link to an examples section or inline example
- Variables are grouped by function (core, logging, security, environment) with subheadings if more than 10
- Every `vars/*.yml` file is listed in the internal mappings table with its purpose and "when to edit"
- Clear instruction: configurable = override via inventory; internal = edit file directly

**Anti-patterns:**
- Variables listed without safety level — support doesn't know what's dangerous
- `List of {host, nts, iburst} objects` — unexplained fields in a complex type
- Variable present in `defaults/main.yml` but absent from README
- `vars/` files not mentioned at all — support doesn't know they exist or what they control
- Mixing configurable and internal variables in one table — different audiences, different edit rules

---

### README-004: Configuration Examples

**Priority:** MUST
**Rationale:** The most common support operation is changing a setting. Examples prevent mistakes by showing the exact YAML to write and where to put it.

````markdown
## Examples

### Changing NTP servers

```yaml
# In group_vars/all/ntp.yml or host_vars/<hostname>/ntp.yml:
ntp_servers:
  - { host: "ntp.company.local", nts: false, iburst: true }
  - { host: "time.cloudflare.com", nts: true, iburst: true }
```

- `nts: true` — encrypted time sync (NTS). Requires outbound TCP 4460.
- `nts: false` — plain NTP. Uses UDP 123.
- `iburst: true` — fast initial sync (sends 4 packets instead of 1 on startup).

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/ntp.yml:
ntp_enabled: false
```

### Using pool servers instead of individual servers

```yaml
ntp_servers: []
ntp_pools:
  - { host: "pool.ntp.org", iburst: true, maxsources: 4 }
ntp_minsources: 1
```
````

**Verification Criteria:**
- At least 2 examples covering the most common operations
- Each example shows the exact file path where to put the configuration
- Each example explains field values in plain language after the YAML block
- Complex types (lists of objects) have at least one example showing all fields

**Anti-patterns:**
- `Example: ["192.168.1.0/24"]` in the variables table without showing the full YAML context and file path
- Examples that edit `defaults/main.yml` directly instead of inventory files

---

### README-005: Cross-Platform Details

**Priority:** MUST (for roles supporting multiple OS families)
**Rationale:** Paths, service names, and package names differ between distros. Support needs to know which file to check on which system.

````markdown
## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Void Linux |
|--------|-----------|-----------------|------------|
| Service name | `chronyd` | `chrony` | `chronyd` |
| Config path | `/etc/chrony.conf` | `/etc/chrony/chrony.conf` | `/etc/chrony.conf` |
| System user | `chrony` | `_chrony` | `chrony` |
````

**Verification Criteria:**
- Table includes every supported OS family where a difference exists
- At minimum: service name, config path, package name
- Additional rows for any other platform-specific values (user, log path, data dir)

**Anti-patterns:**
- Only listing 2 of 5 supported distros
- Saying "handled by `vars/main.yml` mappings" without showing the values — support shouldn't have to read vars files

---

### README-006: Logs

**Priority:** MUST
**Rationale:** Support needs to find logs quickly when investigating issues. They need to know file locations, format, and rotation policy.

````markdown
## Logs

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| tracking.log | `/var/log/chrony/tracking.log` | Clock offset, stratum, correction frequency | logrotate: 14 days |
| measurements.log | `/var/log/chrony/measurements.log` | Per-server delay measurements | logrotate: 14 days |
| statistics.log | `/var/log/chrony/statistics.log` | Per-server statistics | logrotate: 14 days |
| syslog | journalctl -u chronyd | Clock steps > 0.5s, service start/stop | system journal rotation |

### Reading the logs

- Large clock offset: `chronyc tracking` → look at "System time" line
- Server reachability: `chronyc sources` → `^*` = synced, `^?` = unreachable
````

**Verification Criteria:**
- Every log file the role creates is listed with full path
- Format or key fields described (what to grep for)
- Rotation policy stated (logrotate config, or explicit "no rotation — see issue #N")
- syslog/journald output described separately from file-based logs
- At least 2 "how to read" examples for common diagnostic questions

**Anti-patterns:**
- `Log directory (Promtail/Loki reads this)` — mentions tooling instead of showing log content
- No mention of log rotation — logs grow indefinitely without anyone noticing
- Log files mentioned in `defaults/main.yml` comments but not in README

---

### README-007: Troubleshooting

**Priority:** MUST
**Rationale:** Support's primary job is fixing things. A troubleshooting section with symptom→diagnosis→fix triples lets them resolve issues without escalating.

````markdown
## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| System time is wrong | `chronyc tracking` — check "System time" offset | If offset > 1s: `chronyc makestep`. If Stratum 0: no servers reachable |
| Role fails at Validate | Read the `fail_msg` in output | Check `ntp_servers` is not empty, `ntp_minsources` ≤ server count |
| Chrony won't start | `journalctl -u chronyd -n 50` | Usually bad config: `chronyd -p -f /etc/chrony.conf` shows syntax errors |
| NTS not working | `chronyc ntssources` — all zeros? | Outbound TCP 4460 required. Check firewall. Verify CA certificates installed |
| "No synchronized source" after 60s | `chronyc sources` — all `^?`? | DNS or firewall blocking UDP 123. Try: `chronyc -n sources` to see IPs |
````

**Verification Criteria:**
- At least 5 entries covering: service failure, config error, network issues, sync failure, role execution failure
- Each entry has all three columns: symptom (what support sees), diagnosis (command to run), fix (action to take)
- Diagnosis commands are copy-pasteable
- Covers both Ansible-level failures (role execution) and system-level failures (service not working)

**Anti-patterns:**
- Empty troubleshooting section or "see chrony docs"
- Only Ansible-level failures, no system-level diagnostics
- Diagnosis without a specific command to run

---

### README-008: Testing

**Priority:** MUST
**Rationale:** After changing configuration, support must verify nothing broke. They need to know which test to run, what success looks like, and what common failures mean. The testing section MUST reflect the actual test scenarios defined by [[Testing Requirements|standards/testing-requirements]] (TEST-002).
**Standards:** [[Testing Requirements|standards/testing-requirements]]

```markdown
## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test` | After changing variables, templates, or task logic | Logic correctness, idempotence, config deployment |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic, services, or init tasks | Real systemd, real packages, Arch + Ubuntu matrix |

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Packages | chrony installed, binary in PATH | TEST-008 |
| Config files | `/etc/chrony.conf` exists with correct content | TEST-008 |
| Services | chronyd running + enabled | TEST-008 |
| Runtime | `chronyc tracking` responds | TEST-008 |
| Permissions | Config file mode 0644, owned by root | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `chrony package not found` | Stale package cache in container | Rebuild: `molecule destroy && molecule test` |
| `systemd-timesyncd is still running` | prepare step didn't run | Run full sequence: `molecule test`, not just `molecule converge` |
| Idempotence failure on config deploy | Template produces different output on second run | Check for timestamps or random values in template |
| `Assertion failed` with no details | Missing `fail_msg` in verify.yml assert | Add `fail_msg` with expected + actual values (TEST-014) |
| Vagrant: `Python not found` | prepare.yml missing or Arch bootstrap skipped | Check `prepare.yml` has raw Python install (TEST-009) |
```

**Verification Criteria:**
- Both mandatory scenarios (Docker + Vagrant) listed with commands and when to use each (per TEST-002)
- Success criteria include: all steps complete, idempotence zero changes, verify all pass
- "What the tests verify" table present — maps verification categories (TEST-008) to role-specific examples
- At least 5 common test failures with cause and fix (covers both Docker and Vagrant scenarios)
- Command examples are copy-pasteable from the role directory

**Anti-patterns:**
- Just listing `molecule test` without explaining Docker vs Vagrant and when to use which
- No success criteria — support doesn't know if output is good or bad
- No common failures — support has to escalate every test failure
- Missing Vagrant scenario from the testing table (only Docker documented)
- No "what the tests verify" section — support can't understand what tests cover

---

### README-009: Tags

**Priority:** MUST
**Rationale:** Tags enable partial role execution. Support needs to know which tag to use for which operation.

````markdown
## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `ntp` | Entire role | Full apply |
| `ntp:state` | Service enable/start only | Restart chronyd without re-deploying config |
| `report` | Logging/report tasks only | Re-generate execution report |
````

**Verification Criteria:**
- Every tag used in the role is listed
- Each tag has a use case explaining when support would use it
- Command example: `ansible-playbook playbook.yml --tags ntp:state`

**Anti-patterns:**
- Tags listed without use cases: `ntp, ntp:state, ntp,report`
- Ansible command syntax not shown

---

### README-010: File Map

**Priority:** SHOULD
**Rationale:** Support opens the role directory and sees 15–30 files. Without a map, they don't know where to look. The map tells them what to read, what to edit, and what to never touch.

````markdown
## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No — override via inventory |
| `vars/main.yml` | OS-family mappings (service name, paths) | Only when adding distro support |
| `vars/environments.yml` | Hypervisor-specific settings | Only when adding hypervisor support |
| `templates/chrony.conf.j2` | chrony config template | When changing config structure |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `handlers/main.yml` | Service restart handler | Rarely |
| `molecule/` | Test scenarios | When changing test coverage |
````

**Verification Criteria:**
- Every top-level file and directory listed
- "Edit?" column tells support whether and when they'd touch this file
- Files support should never edit are clearly marked

**Anti-patterns:**
- No file map — support reads files at random trying to find the config
- Listing files without "when to edit" guidance

---

## Section Order

README sections MUST appear in this order:

1. Header (README-001)
2. Execution flow (README-002)
3. Variables (README-003)
4. Examples (README-004)
5. Cross-platform details (README-005)
6. Logs (README-006)
7. Troubleshooting (README-007)
8. Testing (README-008)
9. Tags (README-009)
10. File map (README-010)

Additional role-specific sections (default servers, environment detection, security) may be inserted between Examples and Cross-platform details.

---

## Post-Review Checklist

- [ ] README-001: Header — one-line plain-language description
- [ ] README-002: Execution flow — numbered pipeline matching `tasks/main.yml`
- [ ] README-003: Variables — every default listed with safety level
- [ ] README-004: Examples — at least 2 common operations with file paths
- [ ] README-005: Cross-platform — table with all OS-specific differences
- [ ] README-006: Logs — files, paths, format, rotation policy
- [ ] README-007: Troubleshooting — at least 5 symptom→diagnosis→fix entries
- [ ] README-008: Testing — both scenarios listed, success criteria, verification categories table, 5+ common failures
- [ ] README-009: Tags — every tag with use case
- [ ] README-010: File map — every file with "when to edit" guidance
- [ ] No variable from `defaults/main.yml` is missing from README
- [ ] No Ansible/Jinja2 internals leak into user-facing descriptions

---

Back to [[Role Requirements|standards/role-requirements]] | [[Home]]
