# Role Requirements Specification

> Source of truth for Ansible role requirements. All roles MUST comply.
> Implementation patterns: [[Ansible-Patterns]]
> Security control mappings: [[Security Standards|standards/security-standards]]
> Profile definitions: [[Workstation Profiles|standards/workstation-profiles]]

## Scope

This specification applies to all Ansible roles in the `ansible/roles/` directory.
Reference implementation: `ansible/roles/ntp/` (demonstrates all requirements).

## Supported Platforms

| Distro | OS Family | Package Manager | Default Init |
|--------|-----------|-----------------|-------------|
| Arch Linux | Archlinux | pacman | systemd |
| Ubuntu | Debian | apt | systemd |
| Fedora | RedHat | dnf | systemd |
| Void Linux | Void | xbps | runit |
| Gentoo | Gentoo | portage | openrc |

**Init systems:** systemd, runit, openrc, s6, dinit

---

## Requirements

### ROLE-001: Distro-Agnostic Architecture

**Category:** Architecture
**Priority:** MUST
**Rationale:** Roles must work across all five supported distro families without hardcoded package names or OS-specific assumptions leaking into shared task files.
**Standards:** ---

**Implementation Pattern:**
```yaml
# tasks/main.yml — OS dispatch
- name: Include OS-specific tasks
  ansible.builtin.include_tasks: "{{ ansible_facts['os_family'] | lower }}.yml"
  when: ansible_facts['os_family'] in _<role>_supported_os
  tags: ['<role>']

# vars/archlinux.yml — package map per distro family
_<role>_packages:
  - chrony
_<role>_service_name: chronyd

# vars/debian.yml
_<role>_packages:
  - chrony
_<role>_service_name: chrony

# tasks/main.yml — install using the map
- name: Install packages
  ansible.builtin.package:
    name: "{{ _<role>_packages }}"
    state: present
```

**Verification Criteria:**
- `tasks/main.yml` contains `include_tasks` with `ansible_facts['os_family'] | lower`
- `vars/` directory contains one file per supported OS family (at minimum `archlinux.yml`)
- No raw package manager commands (`pacman -S`, `apt-get install`, `dnf install`) in task files
- `ansible.builtin.package` (generic) used for installation, not distro-specific modules

**Anti-patterns:**
- Hardcoded `pacman -S` or `apt-get` in shell/command tasks
- Package names embedded directly in tasks instead of vars files
- OS-specific logic in `tasks/main.yml` via `when: ansible_facts['distribution'] == 'Archlinux'` chains instead of dispatch files

---

### ROLE-002: Init-System Agnostic

**Category:** Architecture
**Priority:** MUST
**Rationale:** The project supports five init systems (systemd, runit, openrc, s6, dinit). Roles must detect the active init system and dispatch to the correct service management tasks rather than assuming systemd.
**Standards:** ---

**Implementation Pattern:**
```yaml
# tasks/main.yml — init dispatch using with_first_found
- name: Disable competing services (init-specific)
  ansible.builtin.include_tasks: "{{ item }}"
  with_first_found:
    - files:
        - "disable_{{ ansible_facts['service_mgr'] }}.yml"
      skip: true
  tags: ['<role>']

# tasks/main.yml — generic service management
- name: Enable and start service
  ansible.builtin.service:
    name: "{{ _<role>_service[ansible_facts['service_mgr']] | default('<default>') }}"
    enabled: true
    state: started

# vars/environments.yml — service name map per init
_<role>_service:
  systemd: chronyd
  runit: chronyd
  openrc: chronyd
  s6: chronyd
  dinit: chronyd
```

**Verification Criteria:**
- `ansible.builtin.service` (generic module) used for service enable/start, not `ansible.builtin.systemd`
- Init-specific tasks dispatched via `with_first_found` pattern or `service_mgr` fact
- Service name lookup uses `ansible_facts['service_mgr']` as the key
- `ansible.builtin.systemd` used ONLY when systemd-specific features are required (e.g., `daemon_reload`), guarded by `when: ansible_facts['service_mgr'] == 'systemd'`

**Anti-patterns:**
- `ansible.builtin.systemd` without an `ansible_facts['service_mgr']` guard condition
- Assuming `systemctl` is available on all hosts
- Hardcoded service unit paths (`/etc/systemd/system/`) without init detection

---

### ROLE-003: Five Distros Only

**Category:** Architecture
**Priority:** MUST
**Rationale:** Scope control. Supporting additional distros without explicit request creates untested code paths and maintenance burden. The five chosen distros cover systemd, runit, and openrc init families.
**Standards:** ---

**Implementation Pattern:**
```yaml
# defaults/main.yml
_<role>_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# tasks/main.yml — preflight assert (first task)
- name: Assert supported operating system
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] in _<role>_supported_os
    fail_msg: >-
      OS family '{{ ansible_facts['os_family'] }}' is not supported.
      Supported: {{ _<role>_supported_os | join(', ') }}
    success_msg: "OS family '{{ ansible_facts['os_family'] }}' is supported"
  tags: ['<role>']
```

**Verification Criteria:**
- `_<role>_supported_os` list exists in `defaults/main.yml` with exactly these five values: `Archlinux`, `Debian`, `RedHat`, `Void`, `Gentoo`
- Preflight `ansible.builtin.assert` checks `ansible_facts['os_family']` membership before any configuration
- OS-specific task files exist at minimum for the primary target (`archlinux.yml`); stubs with `debug` messages acceptable for others

**Anti-patterns:**
- Adding Alpine, SUSE, or other distro families without explicit request
- Missing preflight assertion — role silently runs on unsupported OS
- Using `ansible_distribution` instead of `ansible_facts['os_family']` for the support list (Ubuntu is `Debian` family, Fedora is `RedHat` family)

---

### ROLE-004: Security Standards Compliance

**Category:** Security
**Priority:** MUST (for security-relevant roles) / SHOULD (for all other roles)
**Rationale:** Workstation hardening requires traceable alignment with established security benchmarks. Tags linking tasks to CIS/STIG control IDs enable audit reporting and selective compliance enforcement.
**Standards:** CIS Benchmark Level 1 Workstation, DISA STIG, dev-sec.io ansible-collection-hardening

**Implementation Pattern:**
```yaml
# defaults/main.yml — boolean toggles per security subsystem
sysctl_security_enabled: true
sysctl_security_kernel_hardening: true
sysctl_security_network_hardening: true
sysctl_security_filesystem_hardening: true

# defaults/main.yml — dict-based config for complex parameters
sysctl_config:
  kernel.randomize_va_space: 2
  kernel.kptr_restrict: 2
sysctl_overwrite: {}   # user-provided overrides merged on top

# tasks/security.yml — CIS/STIG tagged tasks
- name: "CIS 1.6.2 | DISA V-258076 — Restrict ptrace scope"
  ansible.posix.sysctl:
    name: kernel.yama.ptrace_scope
    value: "{{ sysctl_kernel_yama_ptrace_scope }}"
  when: sysctl_security_kernel_hardening | bool
  tags: ['sysctl', 'security', 'cis_1.6.2', 'stig_v258076']

# defaults/main.yml — per-parameter toggle for high-impact settings
sysctl_kernel_yama_ptrace_scope: 1   # 1=child-only (dev), 2=root-only (prod)
```

**Verification Criteria:**
- Security-relevant tasks have CIS level and/or STIG control ID in the task name
- Each security subsystem has a `manage_<feature>` or `<role>_security_<subsystem>` boolean toggle
- High-impact settings (those that break development tools) have per-parameter variables with documented tradeoffs in comments
- Complex parameter sets use dict variables with a separate `_overwrite` dict for user customization
- Reference to `wiki/standards/security-standards.md` for control ID mappings

**Anti-patterns:**
- Hardcoded security values with no variable or toggle
- No CIS/STIG tags on security-relevant tasks
- Monolithic `security_enabled: true` flag that controls all security settings as a single unit
- Security defaults that break common workflows without documenting the tradeoff

---

### ROLE-005: In-Role Verification

**Category:** Quality
**Priority:** MUST
**Rationale:** Roles must verify their own configuration is correct after applying changes, not rely solely on external molecule tests. This catches deployment failures at runtime rather than only in CI.
**Standards:** ---

**Implementation Pattern:**
```yaml
# tasks/main.yml — include verification after configuration
- name: Verify <role>
  ansible.builtin.include_tasks: verify.yml
  tags: ['<role>']

# tasks/verify.yml — three verification techniques

# 1. Config file verification (lineinfile + check_mode)
- name: Verify setting in config file
  ansible.builtin.lineinfile:
    path: /etc/chrony.conf
    regexp: '^makestep'
    line: "makestep {{ ntp_makestep_threshold }} {{ ntp_makestep_limit }}"
  check_mode: true
  register: _<role>_verify_config
  failed_when: _<role>_verify_config is changed
  tags: ['<role>']

# 2. Runtime verification (shell + changed_when: false)
- name: Verify runtime state
  ansible.builtin.command:
    cmd: chronyc tracking
  register: _<role>_check
  changed_when: false
  failed_when: _<role>_check.rc != 0
  tags: ['<role>']

# 3. State assertion (depends on runtime check above)
- name: Assert service is running
  ansible.builtin.assert:
    that:
      - "'Stratum' in _<role>_check.stdout"
    fail_msg: "Service is not functioning correctly"
    success_msg: "Service verified and operational"
  tags: ['<role>']
```

**Verification Criteria:**
- `tasks/verify.yml` exists and is included from `tasks/main.yml`
- At least two of the three verification techniques are used (config file check, assertion, runtime check)
- Register variables follow naming convention: `_<role>_verify_<check>`
- Verification tasks use `changed_when: false` for read-only commands
- Results are reported via `common/report_phase.yml`

**Anti-patterns:**
- Verification only exists in `molecule/default/verify.yml`, not in the role itself
- Using `ignore_errors: true` instead of `failed_when` with specific conditions
- Verification tasks that modify state (no `check_mode`, no `changed_when: false`)

---

### ROLE-006: Tests for Actions AND Verifications

**Category:** Testing
**Priority:** MUST
**Rationale:** Molecule tests must validate both the role's configuration actions and that the in-role verification logic (ROLE-005) correctly detects misconfigurations. Without negative tests, verification code may pass regardless of actual state.
**Standards:** ---

**Implementation Pattern:**
```yaml
# molecule/default/converge.yml — apply role with standard config
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  pre_tasks:
    - name: Assert test environment
      ansible.builtin.assert:
        that: ansible_facts['os_family'] == 'Archlinux'
  roles:
    - role: <role_name>

# molecule/default/verify.yml — verify post-apply state
---
- name: Verify
  hosts: all
  become: true
  gather_facts: false
  tasks:
    # Positive: verify config was applied
    - name: Check config file exists
      ansible.builtin.stat:
        path: /etc/chrony.conf
      register: _<role>_verify_conf
      failed_when: not _<role>_verify_conf.stat.exists

    # Positive: verify service state
    - name: Check service is enabled
      ansible.builtin.command:
        cmd: systemctl is-enabled chronyd
      register: _<role>_verify_svc
      changed_when: false
      failed_when: "'enabled' not in _<role>_verify_svc.stdout"

# molecule/default/molecule.yml
---
driver:
  name: default
platforms:
  - name: instance
    managed: false
provisioner:
  name: ansible
  inventory:
    host_vars:
      instance:
        ansible_connection: local
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
  env:
    ANSIBLE_ROLES_PATH: ${MOLECULE_PROJECT_DIRECTORY}/../
verifier:
  name: ansible
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Verification Criteria:**
- `molecule/default/converge.yml` exercises the role with representative configuration
- `molecule/default/verify.yml` checks actual system state (files, services, permissions), not just Ansible return codes
- Register variables in verify.yml follow `_<role>_verify_<check>` naming convention
- `molecule.yml` uses `driver: default` with `managed: false` for localhost testing
- Test sequence includes at minimum: `syntax`, `converge`, `verify`

**Anti-patterns:**
- Tests that only check "role ran without errors" (no state verification)
- Verify.yml that duplicates converge.yml logic instead of checking outcomes
- Missing `vault_password_file` when role depends on vault variables
- Using `docker` or `vagrant` drivers (project uses localhost execution)

---

### ROLE-007: Audit/Monitoring/Logging for System Roles

**Category:** Observability
**Priority:** MUST (for system roles) / MAY (for application roles)
**Rationale:** System roles that interact with kernel, network, or hardware must document what to monitor and how to detect drift or failure. This enables integration with the observability stack (Phase 8: prometheus, node_exporter, alloy).
**Standards:** ---

System roles subject to this requirement: `ntp`, `firewall`, `gpu_drivers`, `sysctl`, `power_management`, `network`, `auditd`, `ssh`, `base_system`.

**Implementation Pattern:**
```yaml
# defaults/main.yml — audit toggle and configuration
power_management_audit_enabled: true
power_management_audit_schedule: "daily"
power_management_drift_detection: true
power_management_drift_state_dir: /var/lib/ansible-power-management

# tasks/main.yml — audit integration point
- name: Configure drift detection
  ansible.builtin.template:
    src: drift-check.sh.j2
    dest: "{{ power_management_drift_state_dir }}/drift-check.sh"
    mode: "0750"
  when: power_management_drift_detection | bool
  tags: ['power_management', 'audit']
```

```markdown
# wiki/roles/<role_name>.md — audit documentation section

## Audit Events

| Event | Source | Severity | Threshold |
|-------|--------|----------|-----------|
| Clock offset exceeds 50ms | chronyc tracking | CRITICAL | > 0.05s for 2m |
| NTP source lost sync | chronyc sources | WARNING | no ^* marker for 5m |
| Stratum > 4 | chronyc tracking | WARNING | stratum field > 4 |

## Monitoring Integration

- **Prometheus metric:** `chrony_tracking_last_offset_seconds` (via chrony_exporter)
- **Alloy pipeline:** scrape chrony_exporter, forward to Loki
- **Alert rule:** NtpOffsetCritical, NtpUnsynchronised
```

**Verification Criteria:**
- System roles include audit/monitoring variables in `defaults/main.yml`
- `wiki/roles/<role_name>.md` contains "Audit Events" section with event table
- Monitoring integration points documented (metrics, exporters, alert rules)
- Drift detection mechanism exists for roles with persistent state

**Anti-patterns:**
- System role with no observability consideration at all
- Audit/monitoring hardcoded with no toggle to disable
- Monitoring documentation exists only in the observability role, not in the source role

---

### ROLE-008: Dual Logging (Machine + Human)

**Category:** Observability
**Priority:** MUST
**Rationale:** Every role must produce both human-readable output for interactive runs and machine-readable output for CI/CD pipeline consumption. The existing `common/report_phase.yml` and `common/report_render.yml` provide a standardized reporting framework.
**Standards:** ---

**Implementation Pattern:**
```yaml
# tasks/main.yml — report each logical phase
- name: "Report: NTP configuration"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_ntp_phases"
    _rpt_phase: "Configure NTP"
    _rpt_detail: >-
      chrony ({{ _ntp_service[ansible_facts['service_mgr']] | default('chronyd') }})
      env={{ _ntp_virt_type | default('unknown') }}
      refclocks={{ _ntp_active_refclocks | default([]) | length }}
  tags: ['ntp', 'report']

# tasks/main.yml — render final report (last task)
- name: "ntp -- Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_ntp_phases"
    _rpt_title: "ntp"
  tags: ['ntp', 'report']

# Machine-readable JSON fact (set alongside human report)
- name: Set JSON execution report
  ansible.builtin.set_fact:
    _<role>_json_report:
      role: "<role_name>"
      status: "ok"
      phases:
        - name: "Configure NTP"
          status: "done"
          detail: "chrony configured with 4 NTS servers"
      timestamp: "{{ ansible_date_time.iso8601 }}"
  tags: ['<role>', 'report']
```

**Verification Criteria:**
- `report_phase.yml` called for each logical phase in the role (install, configure, verify, etc.)
- `report_render.yml` called as the last task in the role
- `_rpt_fact` variable follows `_<role>_phases` naming convention
- Each phase report includes meaningful `_rpt_detail` with runtime specifics

**Anti-patterns:**
- Role with no execution report at all
- Only `debug` messages for output (not structured)
- Report tasks not tagged with `report` (prevents selective reporting runs)
- Missing `report_render.yml` call at the end of the role

---

### ROLE-009: Workstation Profiles Support

**Category:** Architecture
**Priority:** SHOULD
**Rationale:** Different workstation profiles (developer, creative, server, minimal) require different default values for the same role. Profile-aware roles avoid fork-bombing the role tree into per-profile copies.
**Standards:** ---

**Implementation Pattern:**
```yaml
# inventory/group_vars/all/system.yml
workstation_profiles:
  - developer

# defaults/main.yml — profile-dependent defaults
sysctl_kernel_yama_ptrace_scope: >-
  {{ 1 if 'developer' in (workstation_profiles | default([])) else 2 }}

# tasks/main.yml — profile-specific tasks
- name: Install developer debugging tools
  ansible.builtin.package:
    name: "{{ _<role>_dev_packages }}"
    state: present
  when: "'developer' in (workstation_profiles | default([]))"
  tags: ['<role>', 'profile:developer']

# playbook pre_tasks — preflight conflict detection
- name: Validate workstation profiles
  ansible.builtin.assert:
    that:
      - workstation_profiles | intersect(['minimal', 'developer']) | length <= 1
    fail_msg: "Conflicting profiles: 'minimal' and 'developer' cannot coexist"
  when: workstation_profiles is defined
```

**Verification Criteria:**
- Profile-dependent settings guarded with `when: "'<profile>' in (workstation_profiles | default([]))"` -- never bare `workstation_profiles`
- Default values function correctly when `workstation_profiles` is undefined (empty list fallback)
- Profile-specific tasks tagged with `profile:<name>` for selective execution
- Conflicting profiles detected in playbook `pre_tasks`
- Reference: `wiki/standards/workstation-profiles.md`

**Anti-patterns:**
- Hardcoded profile assumptions (`when: workstation_profiles == 'developer'` -- must be list membership)
- No fallback when `workstation_profiles` variable is undefined (Jinja2 error at runtime)
- Profile logic that changes role behavior without any tag for filtering

---

### ROLE-010: Modular Configuration

**Category:** Configuration
**Priority:** MUST
**Rationale:** Roles configure multiple subsystems. Operators must be able to enable/disable each subsystem independently and override specific parameters without forking the role. The dev-sec.io pattern of dict-based config with a separate overwrite dict is the proven approach.
**Standards:** ---

**Implementation Pattern:**
```yaml
# defaults/main.yml — per-subsystem boolean toggles
sysctl_security_enabled: true
sysctl_security_kernel_hardening: true
sysctl_security_network_hardening: true
sysctl_security_filesystem_hardening: true
sysctl_security_ipv6_disable: false

# defaults/main.yml — dict-based config for complex parameters
docker_daemon_config:
  storage-driver: overlay2
  log-driver: json-file
  log-opts:
    max-size: "10m"
    max-file: "3"
docker_daemon_overwrite: {}   # merged on top of docker_daemon_config

# templates/daemon.json.j2 — merge user overrides
{{ docker_daemon_config | combine(docker_daemon_overwrite, recursive=True) | to_nice_json }}

# defaults/main.yml — granular per-parameter control for high-impact settings
sysctl_kernel_yama_ptrace_scope: 1   # 1=child-only, 2=root-only
# NOTE: Level 2 breaks gdb --pid, strace -p, perf record -p
```

**Verification Criteria:**
- Each configurable subsystem has its own boolean toggle: `<role>_manage_<subsystem>` or `<role>_<subsystem>_enabled`
- Complex configurations use dict variables, not 20+ flat variables for related settings
- User overrides via separate `_overwrite` dict that merges on top of defaults
- High-impact settings have individual variables with comments explaining tradeoffs
- Settings organized by domain: network, disk, gpu, cpu, security, permissions, access

**Anti-patterns:**
- Monolithic `<role>_config_enabled: true` that controls everything as one switch
- Flat variables for 20+ related settings that should be a dict
- No override mechanism -- users must edit `defaults/main.yml` directly
- Missing comments on settings that have non-obvious side effects

---

### ROLE-011: Ansible-Native Only

**Category:** Quality
**Priority:** MUST
**Rationale:** Ansible modules provide idempotency, check mode support, diff output, and cross-platform abstraction. Shell commands bypass all of these. Roles must use Ansible modules for all tasks that have module equivalents.
**Standards:** ---

**Implementation Pattern:**
```yaml
# CORRECT: Ansible-native file management
- name: Deploy configuration
  ansible.builtin.template:
    src: chrony.conf.j2
    dest: /etc/chrony.conf
    owner: root
    group: root
    mode: "0644"
    validate: "chronyd -p -f %s"
  notify: restart ntp

# CORRECT: Ansible-native package management
- name: Install packages
  ansible.builtin.package:
    name: "{{ _ntp_packages }}"
    state: present

# CORRECT: shell for runtime verification only (no module equivalent)
- name: Verify chronyd is responding
  ansible.builtin.command:
    cmd: chronyc tracking
  register: _ntp_verify
  changed_when: false
  failed_when: _ntp_verify.rc != 0

# CORRECT: FQCN for all modules
- name: Create network
  community.docker.docker_network:
    name: proxy
    state: present
```

**Verification Criteria:**
- All module references use FQCN: `ansible.builtin.file`, not `file`
- `ansible.builtin.shell` / `ansible.builtin.command` used ONLY for:
  - Runtime verification (`changed_when: false`)
  - Commands with no Ansible module equivalent
- No bash scripts in `files/` directory invoked by tasks
- All Jinja2 expressions properly quoted: `"{{ var }}"`, never bare `{{ var }}`
- Templates use `validate:` parameter where applicable (JSON, YAML, config syntax)

**Anti-patterns:**
- `ansible.builtin.shell: "apt-get install ..."` -- use `ansible.builtin.package`
- `ansible.builtin.shell: "mkdir -p /etc/foo"` -- use `ansible.builtin.file`
- `ansible.builtin.shell: "cp /tmp/foo /etc/foo"` -- use `ansible.builtin.copy` or `ansible.builtin.template`
- Bash scripts in `files/*.sh` invoked by role tasks
- Unquoted Jinja2: `name: {{ var }}` instead of `name: "{{ var }}"`
- Short module names without `ansible.builtin.` prefix

---

## Post-Creation Checklist

Use this checklist when creating or reviewing a role. One checkbox per requirement.

### Structure

- [ ] ROLE-001: OS dispatch via `include_tasks`, `vars/` per distro family
- [ ] ROLE-002: Init-agnostic service management via `service_mgr` detection
- [ ] ROLE-003: `_<role>_supported_os` includes all 5 distro families, preflight assert present

### Quality

- [ ] ROLE-005: `tasks/verify.yml` exists with assert + runtime checks
- [ ] ROLE-011: Only `ansible.builtin.*` modules, no shell hacks, FQCN everywhere

### Security

- [ ] ROLE-004: Security-relevant settings tagged with CIS/STIG IDs, `manage_*` toggles present

### Testing

- [ ] ROLE-006: `molecule/default/verify.yml` tests both applied state and verification logic

### Observability

- [ ] ROLE-007: System roles document audit events and monitoring integration points
- [ ] ROLE-008: `report_phase.yml` called for each phase, `report_render.yml` at end

### Configuration

- [ ] ROLE-009: Profile-dependent settings guarded with `workstation_profiles` check and safe default
- [ ] ROLE-010: Per-subsystem toggles, dict-based config for complex settings, `_overwrite` dict for user customization

### Documentation

- [ ] `wiki/roles/<role_name>.md` exists with variables, dependencies, tags, and audit events
- [ ] `defaults/main.yml` has inline comments explaining each variable and its tradeoffs

---

Back to [[Ansible-Patterns]] | [[Home]]
