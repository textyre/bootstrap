# Workstation Profiles

A profile system that allows Ansible roles to adjust their behavior based on the machine's intended use case. A developer workstation needs different kernel parameters than a gaming rig; a security-hardened machine needs stricter PAM and audit rules than a media production box.

Profiles are **additive** -- a machine can be `[developer, gaming]`. The `base` profile is implicit and always applied. Incompatible combinations fail at preflight validation before any role executes.

---

## Architecture

### Variable Declaration

```yaml
# inventory/group_vars/all/system.yml
workstation_profiles: []  # Empty list = base profile only
```

Per-host override:

```yaml
# inventory/host_vars/devbox/system.yml
workstation_profiles:
  - developer
  - gaming
```

### How Roles Consume Profiles

Roles reference `workstation_profiles` in two places: **defaults** (Jinja2 expressions that compute the correct value) and **tasks** (conditional blocks gated by profile membership).

**Profile-aware defaults** (in `defaults/main.yml`):

```yaml
sysctl_kernel_yama_ptrace_scope: >-
  {{ 0 if 'gaming' in (workstation_profiles | default([]))
     else (1 if 'developer' in (workstation_profiles | default([]))
     else 2) }}
```

**Conditional task blocks** (in `tasks/main.yml` or OS-specific files):

```yaml
- name: Apply gaming kernel optimizations
  when: "'gaming' in (workstation_profiles | default([]))"
  tags: [sysctl, gaming]
  block:
    - name: Set CPU scheduler autogroup
      ansible.builtin.sysctl:
        name: kernel.sched_autogroup_enabled
        value: "1"
        sysctl_file: /etc/sysctl.d/99-ansible.conf
```

### Priority Resolution

When multiple profiles set the same parameter, the **highest-priority** profile wins. Priority order (1 = highest):

| Priority | Profile    | Rationale                                       |
|----------|------------|-------------------------------------------------|
| 1        | `security` | Security constraints must not be overridden      |
| 2        | `gaming`   | Performance overrides developer for latency-sensitive settings |
| 3        | `developer`| Development ergonomics override base defaults    |
| 4        | `media`    | Audio/video production overrides base defaults   |
| 5        | `base`     | Implicit default -- always applied               |

In Jinja2 expressions this translates to a cascade of `if` checks, evaluated from highest to lowest priority. The first matching profile determines the value.

---

## Profile Definitions

### base (implicit)

**Purpose:** Secure, functional workstation with CIS Level 1 Workstation baseline.

| Area        | Configuration                                                   |
|-------------|-----------------------------------------------------------------|
| Kernel      | `ptrace_scope: 2`, `perf_event_paranoid: 3`, ASLR (`randomize_va_space: 2`), `kptr_restrict: 2`, `dmesg_restrict: 1`, `unprivileged_bpf_disabled: 1` |
| Network     | SYN cookies, reverse path filtering, ICMP redirect disabled, TCP timestamps disabled, ARP hardening |
| Firewall    | Default deny inbound, SSH rate limiting (`4/minute` per source IP, burst 2) |
| Docker      | `userns-remap: default`, `icc: false`, `no-new-privileges: true`, `live-restore: true`, journald log driver |
| PAM         | faillock: `deny: 3`, `unlock_time: 900`, `even_deny_root: true`, audit enabled |
| SSH         | Key-only auth, `MaxStartups: 10:30:60`, `MaxAuthTries: 3`, `AllowGroups: wheel`, AEAD ciphers only |
| Services    | chronyd, sshd, nftables                                        |
| CPU         | `schedutil` governor                                            |
| Filesystem  | `suid_dumpable: 0`, protected hardlinks/symlinks/fifos, `inotify_max_user_watches: 524288` |

### developer

**Purpose:** Software development workstation -- IDE, debuggers, containers, Kubernetes, profiling tools.

| Area        | Override from base                                              | Rationale                                        |
|-------------|----------------------------------------------------------------|--------------------------------------------------|
| Kernel      | `ptrace_scope: 1`                                              | Allows `gdb ./app`, `strace -p`, debugger attach to child processes |
| Kernel      | `perf_event_paranoid: 1`                                       | Enables `perf record`, `perf stat` without root  |
| Docker      | `icc: true`                                                    | Container-to-container communication for microservice development on docker0 bridge |
| Docker      | `userns-remap: ""`                                             | Avoids volume permission issues during active development; named volumes recommended in production |
| SSH         | `MaxStartups: 10:30:60`                                        | VS Code Remote SSH + multiple terminal sessions  |
| Network     | No additional firewall changes                                 | Outbound is already unrestricted                 |
| Shell       | Dev-oriented prompt, git integration, language version managers | Enhanced developer ergonomics                    |

**Unchanged from base:** CPU governor (`schedutil`), PAM faillock settings, filesystem hardening, firewall SSH rate limiting, ARP hardening.

### gaming

**Purpose:** PC gaming -- single-player and multiplayer, including titles with kernel-level anti-cheat.

| Area        | Override from base                                              | Rationale                                        |
|-------------|----------------------------------------------------------------|--------------------------------------------------|
| Kernel      | `ptrace_scope: 0`                                              | EAC, BattlEye, and Vanguard require unrestricted ptrace for anti-cheat injection |
| Kernel      | `sched_autogroup_enabled: 1`                                   | Isolates game thread groups from background tasks for consistent frame times |
| CPU         | `performance` governor                                         | Maximum clock speed; no frequency scaling latency |
| GPU         | Power saving disabled                                          | Prevents GPU downclocking mid-frame              |
| Docker      | `no-new-privileges: false`                                     | Some game servers and Wine prefixes require setuid helpers |
| Docker      | `userns-remap: ""`                                             | Compatibility with game server containers that bind-mount host directories |
| Audio       | Low-latency PipeWire configuration                             | Reduces audio crackle during high CPU load       |
| Network     | Standard rate limiting preserved                               | Gaming traffic is outbound; inbound SSH protection still applies |

**Unchanged from base:** PAM faillock settings, SSH configuration, filesystem hardening, most network sysctl parameters.

**Notes:**
- Anti-cheat systems (EAC, BattlEye, Vanguard) require relaxed kernel security. This is a deliberate tradeoff.
- `ptrace_scope: 0` allows any process to ptrace any other process owned by the same user. Acceptable on single-user gaming workstations.
- Steam/Proton may require `gpu_drivers_multilib: true` for 32-bit library support.

### media

**Purpose:** Audio/video production, image editing, media library management.

| Area        | Override from base                                              | Rationale                                        |
|-------------|----------------------------------------------------------------|--------------------------------------------------|
| Audio       | PipeWire with JACK compatibility, low-latency buffer settings  | Real-time audio processing (Ardour, Audacity, JACK-dependent DAWs) |
| GPU         | Hardware video acceleration enabled (VA-API/VDPAU)             | GPU-accelerated encode/decode for video editing  |
| Filesystem  | `inotify_max_user_watches: 1048576`                            | Large media libraries (Plex, Jellyfin, photo managers) trigger inotify exhaustion at default limits |
| CPU         | `schedutil` governor (unchanged)                               | Balanced -- media workloads benefit from frequency scaling more than fixed high clocks |

**Unchanged from base:** All kernel security parameters, Docker configuration, SSH, PAM faillock, firewall. Media production does not require security relaxation.

### security

**Purpose:** Hardened workstation aligned with CIS Level 2 Workstation + DISA STIG CAT I.

| Area        | Override from base                                              | Rationale                                        |
|-------------|----------------------------------------------------------------|--------------------------------------------------|
| Kernel      | `ptrace_scope: 2`                                              | Same as base; explicitly locked to prevent profile combination from weakening it |
| Kernel      | `perf_event_paranoid: 3`                                       | Same as base; blocks all perf access for unprivileged users |
| Kernel      | `unprivileged_bpf_disabled: 1`                                 | Same as base; blocks BPF exploit surface         |
| Docker      | All hardening ON; `userns-remap: default` mandatory            | No exceptions for volume convenience             |
| SSH         | `MaxStartups: 4:50:10`                                         | Stricter DoS protection; 4 unauthenticated connections before probabilistic drop |
| SSH         | No agent forwarding, no TCP forwarding                         | Already base defaults; explicitly enforced here  |
| Firewall    | SSH rate limit tightened to `2/minute`                          | Aggressive brute-force protection                |
| PAM         | `faillock_deny: 3` (same as base), `faillock_unlock_time: 1800` | 30-minute lockout instead of 15                  |
| Audit       | `auditd` with immutable rules (`-e 2`)                         | Prevents runtime audit rule modification         |
| Audit       | AIDE file integrity monitoring                                  | Detects unauthorized file modifications          |
| AppArmor    | Enforcing profiles for all services                            | Mandatory access control                         |
| Network     | DNS-over-TLS mandatory, strict egress filtering                | Prevents DNS leaks and unauthorized outbound connections |

**Notes:**
- The security profile is designed for machines handling sensitive data or operating in regulated environments.
- Debuggers (`gdb`, `strace`, `perf`) will not work for non-root users. This is intentional.
- `auditd` immutable rules require a reboot to modify audit configuration. Plan maintenance accordingly.

---

## Conflict Matrix

| Combination                    | Status       | Reason                                            | Resolution                              |
|--------------------------------|-------------|---------------------------------------------------|-----------------------------------------|
| `developer` + `gaming`         | OK          | Gaming relaxes what developer already relaxes      | `gaming` wins on ptrace (0 beats 1)     |
| `developer` + `media`          | OK          | No conflicting parameters                          | Both applied additively                 |
| `developer` + `security`       | WARN        | Security restricts debuggers that developer needs  | `security` wins; warning logged at preflight |
| `gaming` + `media`             | OK          | No conflicting parameters                          | Both applied additively                 |
| `gaming` + `security`          | **CONFLICT** | Incompatible kernel security requirements          | **Preflight assert FAILS** -- choose one |
| `media` + `security`           | OK          | Minor tension on GPU acceleration                  | `security` wins on kernel params; media audio settings preserved |
| `developer` + `gaming` + `media` | OK        | Triple combination works                           | Priority order applies per parameter    |
| `developer` + `gaming` + `security` | **CONFLICT** | Contains `gaming` + `security`               | **Preflight assert FAILS**              |
| `developer` + `media` + `security` | WARN    | Developer tools restricted by security profile     | `security` wins; warning logged         |
| All four non-base              | **CONFLICT** | Contains `gaming` + `security`                    | **Preflight assert FAILS**              |

**Why `gaming` + `security` is a hard conflict:**
- Gaming requires `ptrace_scope: 0` for anti-cheat; security requires `ptrace_scope: 2`.
- Gaming disables `no-new-privileges` for Wine/setuid helpers; security mandates it.
- Gaming uses `performance` CPU governor with no power saving; security prefers minimal attack surface through `schedutil`.
- These are not tunable differences -- they represent fundamentally opposed threat models.

---

## Preflight Validation

Add to `workstation.yml` as a `pre_tasks` block. The `always` tag ensures validation runs regardless of tag filtering.

```yaml
- name: Setup workstation
  hosts: workstations
  become: true
  gather_facts: true

  pre_tasks:
    # ---- Profile validation ----
    - name: Validate workstation_profiles contains only known profiles
      ansible.builtin.assert:
        that:
          - item in _valid_profiles
        fail_msg: >-
          Unknown profile '{{ item }}'. Valid profiles: {{ _valid_profiles | join(', ') }}.
      loop: "{{ workstation_profiles | default([]) }}"
      vars:
        _valid_profiles: [base, developer, gaming, media, security]  # 'base' accepted but ignored (implicit)
      when: workstation_profiles | default([]) | length > 0
      tags: [always]

    - name: Detect incompatible profile combinations
      ansible.builtin.assert:
        that:
          - not ('gaming' in workstation_profiles and 'security' in workstation_profiles)
        fail_msg: >-
          CONFLICT: 'gaming' and 'security' profiles are incompatible.
          Gaming requires relaxed kernel security (ptrace_scope: 0, no-new-privileges: false).
          Security requires maximum hardening (ptrace_scope: 2, immutable audit rules).
          Remove one profile or create a custom host_vars override.
      when: workstation_profiles | default([]) | length > 1
      tags: [always]

    - name: Warn about developer + security tension
      ansible.builtin.debug:
        msg: >-
          WARNING: 'developer' + 'security' profiles are both active.
          Security profile overrides developer relaxations (ptrace_scope stays at 2,
          perf_event_paranoid stays at 3). Debuggers and profilers will require root.
      when:
        - "'developer' in (workstation_profiles | default([]))"
        - "'security' in (workstation_profiles | default([]))"
      tags: [always]

  roles:
    # ... existing role list unchanged ...
```

---

## Role x Profile Matrix

Concrete values for each setting per active profile. When multiple profiles are active, the highest-priority profile's value wins (see Priority Resolution above).

### Kernel Parameters (sysctl role)

| Parameter                            | base | developer | gaming | media | security |
|--------------------------------------|------|-----------|--------|-------|----------|
| `kernel.yama.ptrace_scope`           | 2    | 1         | 0      | 2     | 2        |
| `kernel.perf_event_paranoid`         | 3    | 1         | 3      | 3     | 3        |
| `kernel.sched_autogroup_enabled`     | 0    | 0         | 1      | 0     | 0        |
| `kernel.randomize_va_space`          | 2    | 2         | 2      | 2     | 2        |
| `kernel.kptr_restrict`               | 2    | 2         | 2      | 2     | 2        |
| `kernel.unprivileged_bpf_disabled`   | 1    | 1         | 1      | 1     | 1        |
| `fs.inotify.max_user_watches`        | 524288 | 524288  | 524288 | 1048576 | 524288 |
| `vm.swappiness`                      | 10   | 10        | 10     | 10    | 10       |

### Docker (docker role)

| Parameter            | base      | developer | gaming | media   | security  |
|----------------------|-----------|-----------|--------|---------|-----------|
| `icc`                | `false`   | `true`    | `false`| `false` | `false`   |
| `userns-remap`       | `default` | `""`      | `""`   | `default` | `default` |
| `no-new-privileges`  | `true`    | `true`    | `false`| `true`  | `true`    |
| `live-restore`       | `true`    | `true`    | `true` | `true`  | `true`    |
| `log-driver`         | `journald`| `journald`| `journald` | `journald` | `journald` |

### SSH (ssh role)

| Parameter          | base        | developer   | gaming      | media       | security    |
|--------------------|-------------|-------------|-------------|-------------|-------------|
| `MaxStartups`      | `10:30:60`  | `10:30:60`  | `10:30:60`  | `10:30:60`  | `4:50:10`   |
| `MaxAuthTries`     | `3`         | `3`         | `3`         | `3`         | `3`         |
| `AllowGroups`      | `wheel`     | `wheel`     | `wheel`     | `wheel`     | `wheel`     |
| `AgentForwarding`  | `no`        | `no`        | `no`        | `no`        | `no`        |
| `TCPForwarding`    | `no`        | `no`        | `no`        | `no`        | `no`        |

### Firewall (firewall role)

| Parameter              | base       | developer  | gaming     | media      | security   |
|------------------------|------------|------------|------------|------------|------------|
| `ssh_rate_limit`       | `4/minute` | `4/minute` | `4/minute` | `4/minute` | `2/minute` |
| `ssh_rate_limit_burst` | `2`        | `2`        | `2`        | `2`        | `1`        |

### Power Management (power_management role)

| Parameter          | base        | developer   | gaming        | media       | security    |
|--------------------|-------------|-------------|---------------|-------------|-------------|
| `cpu_governor`     | `schedutil` | `schedutil` | `performance` | `schedutil` | `schedutil` |
| GPU power saving   | auto        | auto        | off           | auto        | auto        |

### PAM (pam_hardening role)

| Parameter          | base | developer | gaming | media | security |
|--------------------|------|-----------|--------|-------|----------|
| `faillock_deny`    | 3    | 3         | 3      | 3     | 3        |
| `faillock_unlock_time` | 900 | 900    | 900    | 900   | 1800     |
| `even_deny_root`   | true | true      | true   | true  | true     |

### Audit (future auditd role)

| Parameter           | base  | developer | gaming | media | security |
|---------------------|-------|-----------|--------|-------|----------|
| `rules_immutable`   | false | false     | false  | false | true     |
| `aide_enabled`      | false | false     | false  | false | true     |

---

## Implementation Pattern

### Jinja2 Expression Template

For parameters where profiles override the base value, use a cascading conditional that evaluates profiles from highest to lowest priority:

```yaml
# defaults/main.yml
# Pattern: security > gaming > developer > media > base
some_role_parameter: >-
  {% set profiles = workstation_profiles | default([]) -%}
  {% if 'security' in profiles -%}
    {{ security_value }}
  {%- elif 'gaming' in profiles -%}
    {{ gaming_value }}
  {%- elif 'developer' in profiles -%}
    {{ developer_value }}
  {%- elif 'media' in profiles -%}
    {{ media_value }}
  {%- else -%}
    {{ base_value }}
  {%- endif %}
```

### Concrete Example: sysctl role

```yaml
# ansible/roles/sysctl/defaults/main.yml

sysctl_kernel_yama_ptrace_scope: >-
  {% set p = workstation_profiles | default([]) -%}
  {% if 'security' in p -%}2
  {%- elif 'gaming' in p -%}0
  {%- elif 'developer' in p -%}1
  {%- else -%}2{%- endif %}

sysctl_kernel_perf_event_paranoid: >-
  {% set p = workstation_profiles | default([]) -%}
  {% if 'developer' in p and 'security' not in p -%}1
  {%- else -%}3{%- endif %}

sysctl_kernel_sched_autogroup_enabled: >-
  {% set p = workstation_profiles | default([]) -%}
  {% if 'gaming' in p -%}1
  {%- else -%}0{%- endif %}
```

### Concrete Example: Conditional Task Block

```yaml
# ansible/roles/power_management/tasks/main.yml

- name: Gaming CPU governor override
  when: "'gaming' in (workstation_profiles | default([]))"
  tags: [power, gaming]
  block:
    - name: Set CPU governor to performance
      ansible.builtin.copy:
        content: "performance"
        dest: /sys/devices/system/cpu/cpu{{ item }}/cpufreq/scaling_governor
        mode: "0644"
      loop: "{{ range(0, ansible_processor_vcpus) | list }}"
      changed_when: true
```

---

## Adding a New Profile

Follow this checklist when introducing a new profile (e.g., `kiosk`, `server`, `htpc`):

1. **Define the profile in this document.**
   - Add a section under Profile Definitions with purpose, overrides table, and rationale.
   - Add rows to the Role x Profile Matrix for every parameter the new profile changes.
   - Add entries to the Conflict Matrix for every existing profile combination.

2. **Add preflight validation.**
   - If the new profile conflicts with any existing profile, add an `assert` to the preflight block in `workstation.yml`.
   - If it creates tension (workable but suboptimal), add a `debug` warning.

3. **Update affected role defaults.**
   - Modify the Jinja2 cascade in each affected role's `defaults/main.yml` to include the new profile at its correct priority position.
   - Ensure `workstation_profiles | default([])` is always used (never bare `workstation_profiles`) to maintain backward compatibility with inventories that do not define the variable.

4. **Add conditional task blocks if needed.**
   - If the profile requires tasks that other profiles do not (e.g., installing packages, deploying extra configs), add `when:` gated blocks to the appropriate role.

5. **Test with Molecule.**
   - Create or update molecule scenarios that exercise the new profile:
     ```yaml
     # molecule/default/converge.yml
     vars:
       workstation_profiles: [new_profile]
     ```
   - Test both standalone (`[new_profile]`) and combination (`[new_profile, developer]`) scenarios.
   - Verify that preflight asserts fire correctly for incompatible combinations.

6. **Update wiki documentation.**
   - Add the profile to the sidebar if it is a major addition.
   - Update role-specific wiki pages to document profile-dependent behavior.

---

## Design Decisions

### Why a single playbook, not per-profile playbooks?

Separate playbooks per profile (e.g., `developer.yml`, `gaming.yml`) create a combinatorial explosion. With 4 profiles and multi-profile support, you would need 15 playbook files (all combinations). A single `workstation.yml` with profile-aware defaults keeps the role list in one place and lets Jinja2 handle the variation.

### Why `workstation_profiles` list instead of boolean flags?

Boolean flags (`is_developer: true`, `is_gaming: true`) spread profile logic across many variables and make conflict detection harder. A single list variable enables:
- Conflict detection with `assert` (check for two items in one list).
- Priority resolution with ordered `if/elif` chains.
- Inventory readability (`workstation_profiles: [developer, gaming]` is self-documenting).

### Why preflight assert instead of runtime guards?

A role that silently ignores conflicting settings creates a machine in an undefined state. Failing early with a clear error message forces the operator to make an explicit choice. The `always` tag ensures validation runs even when specific role tags are targeted.

### Why is `base` implicit?

Every machine needs a secure foundation. Making `base` explicit (`workstation_profiles: [base, developer]`) adds noise without information. The absence of profiles means base-only. The Jinja2 `else` clause in every cascade handles this naturally.

---

Back to [[Role Requirements|standards/role-requirements]] | [[Home]]
