# Testing Requirements Specification

> Source of truth for Ansible role testing. All roles MUST comply.
> Role implementation standards: [[Role Requirements|standards/role-requirements]]
> README testing section: [[README Requirements|standards/readme-requirements]] (README-008)
> CI workflow standards: [[CI Requirements|standards/ci-requirements]]
> Reference implementation: `ansible/roles/ntp/molecule/`

## Scope

This specification applies to all Ansible roles in the `ansible/roles/` directory.
Every role MUST have automated tests that verify the role does what it claims — and catch when it doesn't.

### Relationship to Other Standards

These three documents form a closed loop:

| Document | Answers | Depends on |
|----------|---------|------------|
| Role Requirements (ROLE-0XX) | **What** the role does | Testing proves it works |
| Testing Requirements (TEST-0XX) | **How** to verify the role works + beyond | Role defines what to test |
| README Requirements (README-0XX) | **How to run and interpret** tests for humans | Testing defines what to document |

"Beyond" means: tests MUST verify not just that tasks ran, but that the system is in the expected state. A service is not just "installed" — it responds. A config is not just "deployed" — it contains the right values.

## Supported Platforms

Tests MUST cover at minimum:

| Platform | Scenario | Driver | Use case |
|----------|----------|--------|----------|
| Arch Linux | docker + vagrant | Docker / Vagrant-libvirt | Primary target, fast feedback |
| Ubuntu | docker + vagrant | Docker / Vagrant-libvirt | Cross-platform validation |

---

## Requirements

### TEST-001: Molecule as Test Framework

**Category:** Framework
**Priority:** MUST
**Rationale:** Molecule is the industry standard for Ansible role testing. It provides scenario management, idempotence checking, multi-platform support, and CI integration. All conference talks surveyed (VK Tech, EPAM, RT Labs, Yadro, Jeff Geerling) converge on Molecule as the standard tool.

**Implementation Pattern:**
```bash
# Install molecule with required plugins
pip install molecule molecule-plugins[docker,vagrant] ansible-lint yamllint

# Initialize default scenario in existing role
cd ansible/roles/<role_name>
molecule init scenario -d default

# Run full test suite
molecule test
```

**Verification Criteria:**
- `molecule/` directory exists in every role
- `molecule.yml` is valid and parseable
- `molecule test` completes without manual intervention
- Molecule version >= 24.x with `molecule-plugins`

**Anti-patterns:**
- Testing only via `ansible-playbook --check` (check mode does not verify real state)
- Shell scripts that run ansible-playbook and grep output
- No `molecule/` directory — role is untested
- Using deprecated molecule versions (v3, v6) with incompatible scenario format

---

### TEST-002: Mandatory Scenarios

**Category:** Framework
**Priority:** MUST
**Rationale:** Docker tests are fast but limited (no real systemd, no kernel). Vagrant tests are slow but complete (real VM, real init system). Both are required to catch different classes of bugs. Docker catches logic errors early; Vagrant catches platform-specific and init-system issues before merge.

**Implementation Pattern:**
```yaml
# molecule/default/molecule.yml — Docker scenario
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
    - idempotence
    - verify

# molecule/vagrant/molecule.yml — Vagrant scenario
---
driver:
  name: vagrant
  provider:
    name: libvirt
platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
    memory: 1024
    cpus: 1
    groups:
      - all
  - name: ubuntu-base
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
    memory: 1024
    cpus: 1
    groups:
      - all
provisioner:
  name: ansible
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
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

**Verification Criteria:**
- `molecule/default/` directory exists with `molecule.yml`, `converge.yml`, `verify.yml`
- `molecule/vagrant/` directory exists with `molecule.yml`, `converge.yml`, `verify.yml`, `prepare.yml`
- Both scenarios include `idempotence` in `test_sequence`
- Docker scenario uses `driver: default` with `managed: false` for localhost testing
- Vagrant scenario includes at minimum `arch-vm` and `ubuntu-base` platforms
- Docker scenario: gate for CI on every push
- Vagrant scenario: gate for merge into master

**Anti-patterns:**
- Only one scenario (Docker or Vagrant, not both)
- `idempotence` missing from `test_sequence`
- Vagrant scenario with only one platform (missing cross-platform validation)
- Docker scenario using `docker` driver instead of `default` with `managed: false`
- `test_sequence` that skips `syntax` or `verify`

---

### TEST-003: Scenario File Structure

**Category:** Structure
**Priority:** MUST
**Rationale:** Consistent file structure across roles reduces onboarding time and prevents "where do I find the tests?" questions. Every conference talk emphasized standardized structure as the foundation of scalable testing.

**Implementation Pattern:**
```
ansible/roles/<role_name>/
├── molecule/
│   ├── shared/                    # Shared test assets (SHOULD)
│   │   ├── converge.yml           # Common converge playbook
│   │   └── verify.yml             # Common verification playbook
│   ├── default/                   # Docker scenario (MUST)
│   │   ├── molecule.yml           # Scenario configuration
│   │   ├── converge.yml           # → includes shared or standalone
│   │   ├── verify.yml             # → includes shared or standalone
│   │   └── prepare.yml            # Pre-conditions (if needed)
│   └── vagrant/                   # Vagrant scenario (MUST)
│       ├── molecule.yml           # Scenario configuration
│       ├── converge.yml           # → includes shared or standalone
│       ├── verify.yml             # → includes shared or standalone
│       └── prepare.yml            # Pre-conditions (MUST for vagrant)
├── requirements.yml               # Role dependencies for molecule
└── vault-pass.sh                  # Vault password helper (if needed)
```

**Verification Criteria:**
- Every scenario directory contains at minimum: `molecule.yml`, `converge.yml`, `verify.yml`
- Vagrant scenario MUST have `prepare.yml` (VM preparation is always needed)
- `requirements.yml` exists at role root if role has dependencies (see TEST-010)
- File naming follows convention exactly — no `playbook.yml`, no `test.yml`

**Anti-patterns:**
- Test files scattered outside `molecule/` directory
- Scenario without `verify.yml` (verification is not optional)
- `prepare.yml` missing from vagrant scenario (VMs always need preparation)
- Custom file names that break molecule convention

---

### TEST-004: Shared Test Assets

**Category:** Structure
**Priority:** SHOULD
**Rationale:** Docker and Vagrant scenarios often share 80%+ of converge and verify logic. Duplicating this logic creates drift — a fix in Docker verify doesn't reach Vagrant verify. The shared/ pattern (used by Yadro and others) eliminates this drift.

**Implementation Pattern:**
```yaml
# molecule/shared/converge.yml — shared converge logic
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  pre_tasks:
    - name: Assert test environment
      ansible.builtin.assert:
        that: ansible_facts['os_family'] in ['Archlinux', 'Debian']
  roles:
    - role: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"

# molecule/default/converge.yml — Docker includes shared
---
- import_playbook: ../shared/converge.yml

# molecule/vagrant/converge.yml — Vagrant includes shared
---
- import_playbook: ../shared/converge.yml

# Alternative: use provisioner.playbooks in molecule.yml instead of stub files
# provisioner:
#   playbooks:
#     converge: ../shared/converge.yml
#     verify: ../shared/verify.yml
```

**Verification Criteria:**
- When both scenarios use identical converge/verify logic, it MUST live in `molecule/shared/`
- Scenario-specific files include shared via `import_playbook`
- If a scenario requires its own converge/verify (e.g., vagrant needs platform-specific verification), the deviation MUST be justified with a comment in `molecule.yml`

**Anti-patterns:**
- Copy-pasted converge.yml between docker and vagrant with minor differences
- Shared verify.yml that skips checks "because Docker can't do X" — use `when:` guards instead
- Shared files that import scenario-specific files (circular dependency)

---

### TEST-005: Static Analysis Pipeline

**Category:** Structure
**Priority:** MUST
**Rationale:** Static analysis catches errors before any VM is created. yamllint catches syntax issues. ansible-lint catches bad practices, non-idempotent patterns, and module misuse. Both are cheap to run and prevent wasted CI time on tests that would fail anyway.

**Implementation Pattern:**
```yaml
# .yamllint — project-level yamllint config
---
extends: default
rules:
  line-length:
    max: 200
  truthy:
    allowed-values: ['true', 'false', 'yes', 'no']
  comments:
    min-spaces-from-content: 1

# .ansible-lint — project-level ansible-lint config
---
skip_list:
  - name[template]
  - galaxy[no-changelog]
exclude_paths:
  - .github/
  - docs/
```

```bash
# Run lint before molecule test (CI pipeline order)
yamllint ansible/roles/<role_name>/
ansible-lint ansible/roles/<role_name>/
molecule test -s default
```

**Verification Criteria:**
- `yamllint` passes with zero errors on all role YAML files
- `ansible-lint` passes with zero errors (warnings acceptable with documented skip)
- Lint runs BEFORE molecule test in CI pipeline — fail fast on syntax
- All FQCN used (`ansible.builtin.file`, not `file`) — ansible-lint enforces this
- All `command`/`shell` tasks have `changed_when` — ansible-lint enforces this

**Anti-patterns:**
- Disabling ansible-lint entirely (`skip_list: [all]`)
- Lint runs after molecule test (wasted 10 minutes on VM creation before catching a typo)
- Per-role `.ansible-lint` that disables project rules
- `# noqa` without a comment explaining why the exception is needed

---

### TEST-006: Converge Playbook Standards

**Category:** Execution
**Priority:** MUST
**Rationale:** The converge playbook is the test's "act" step — it applies the role. A poorly written converge (wrong vars, missing edge cases, hardcoded values) makes the entire test worthless. RT Labs and Jeff Geerling emphasized: converge must exercise the role as a real user would.

**Implementation Pattern:**
```yaml
# molecule/shared/converge.yml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  pre_tasks:
    - name: Assert supported OS
      ansible.builtin.assert:
        that: ansible_facts['os_family'] in ['Archlinux', 'Debian']
  vars:
    # Representative configuration — not defaults, not extreme
    ntp_servers:
      - { host: "time.cloudflare.com", nts: true, iburst: true }
      - { host: "time.google.com", nts: false, iburst: true }
    ntp_minsources: 1
  roles:
    - role: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"
```

**Verification Criteria:**
- Converge playbook applies the role with representative (non-default) configuration
- Variables used in converge are passed to verify via `extra-vars` or `vars_files` — never hardcoded separately in verify
- `gather_facts: true` is set (roles depend on facts)
- `become: true` matches production usage
- Edge cases exercised: at least one converge run with minimal/empty inputs (see TEST-011)
- Role name resolved dynamically via `MOLECULE_PROJECT_DIRECTORY`, not hardcoded

**Anti-patterns:**
- Converge with zero variables (tests only role defaults — misses real-world usage)
- Hardcoded role name: `role: ntp` instead of dynamic resolution
- Different variable values in converge and verify (diverges silently)
- `gather_facts: false` when role depends on `ansible_facts`
- Converge that ignores errors (`ignore_errors: true` on role import)

---

### TEST-007: Idempotence Verification

**Category:** Execution
**Priority:** MUST
**Rationale:** Idempotence is the cornerstone of configuration management. A role that changes state on every run breaks monitoring, causes unnecessary service restarts, and masks real changes. Every video surveyed (VK Tech: "biggest pain", EPAM: "engineers tried to bypass it", RT Labs: "mandatory") stressed idempotence as non-negotiable.

**Implementation Pattern:**
```yaml
# molecule.yml — idempotence in test_sequence
scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence    # Second converge: MUST show zero changed tasks
    - verify
    - destroy
```

```yaml
# CORRECT: read-only command is idempotent
- name: Check chronyd tracking
  ansible.builtin.command: chronyc tracking
  changed_when: false    # Read-only — never counts as change

# CORRECT: conditional execution prevents false changes
- name: Download binary
  ansible.builtin.get_url:
    url: "{{ _binary_url }}"
    dest: "{{ _install_dir }}/binary"
  when: _current_version.stdout != _desired_version

# CORRECT: handler fires only on real change
- name: Deploy configuration
  ansible.builtin.template:
    src: chrony.conf.j2
    dest: /etc/chrony.conf
  notify: restart chronyd
```

**Verification Criteria:**
- `idempotence` step present in `test_sequence` for EVERY scenario (docker and vagrant). **Spelling:** `idempotence`, not `idempotency` — molecule uses this exact spelling
- Second converge run produces zero `changed` tasks
- All `command`/`shell` tasks declare `changed_when` explicitly
- Handlers with `changed_when: true` do not fire on idempotence run
- No `changed_when: false` on tasks that actually modify state (hiding changes)

**Anti-patterns:**
- Commenting out `idempotence` from `test_sequence` (the #1 bypass from VK Tech talk)
- `changed_when: false` on a task that writes files or restarts services (lying about state)
- Handler that fires unconditionally on every run (causing false `changed` on idempotence)
- Removing `idempotence` "temporarily" and never adding it back

---

### TEST-008: Verification Depth

**Category:** Execution
**Priority:** MUST
**Rationale:** "Tests that always pass regardless of actual state are worse than no tests — they create false confidence" (ROLE-014). Verification must check real system state, not just Ansible return codes. Tests must cover BEYOND what the role does: not just "task ran" but "system works".

**Structure:** verify.yml is organized by execution flow steps (matching README-002), and each step covers relevant verification categories.

**Verification Categories:**

Every category that applies to the role MUST be covered. A category is "applicable" if the role performs the corresponding action. If a category is skipped, it must be listed explicitly in a comment at the top of verify.yml with a one-line justification.

| Category | Applicable when | What it checks | Example |
|----------|----------------|---------------|---------|
| **Packages** | Role installs packages | Software is actually installed | `command -v chronyc`, `dpkg -l chrony` |
| **Config files** | Role writes config files | Config exists with correct content | `slurp` + content assert, `lineinfile check_mode` |
| **Services** | Role manages a service | Service is running and enabled | `service_facts`, `systemctl is-enabled` |
| **Runtime** | Role starts a daemon or exposes an interface | Service actually responds/works | `chronyc tracking`, `curl localhost:8080` |
| **Permissions** | Role creates files/dirs with specific ownership or mode | Files have correct owner/mode | `stat` + assert on mode, uid, gid |

**Skipped category declaration (top of verify.yml):**
```yaml
# Verification categories skipped:
#   services  — role does not manage any service unit
#   runtime   — no daemon or network interface is started by this role
```

**Implementation Pattern:**
```yaml
# molecule/shared/verify.yml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  tasks:
    # ── Step 1: Validate (matches execution flow) ──────────────
    # Covered by converge — assert fires during role execution

    # ── Step 4: Install ────────────────────────────────────────
    - name: "Verify: chrony package installed"            # [packages]
      ansible.builtin.command: command -v chronyc
      register: _ntp_verify_binary
      changed_when: false
      failed_when: _ntp_verify_binary.rc != 0

    # ── Step 5: Configure ──────────────────────────────────────
    - name: "Verify: chrony.conf deployed"                # [config files]
      ansible.builtin.stat:
        path: "{{ _ntp_config_path }}"
      register: _ntp_verify_conf
      failed_when: not _ntp_verify_conf.stat.exists

    - name: "Verify: NTS enabled in config"               # [config files]
      ansible.builtin.slurp:
        src: "{{ _ntp_config_path }}"
      register: _ntp_verify_conf_content

    - name: "Assert: NTS server configured"               # [config files]
      ansible.builtin.assert:
        that:
          - "'nts' in (_ntp_verify_conf_content.content | b64decode)"
        fail_msg: "NTS not found in chrony config"

    - name: "Verify: config file permissions"             # [permissions]
      ansible.builtin.stat:
        path: "{{ _ntp_config_path }}"
      register: _ntp_verify_conf_perms
      failed_when: _ntp_verify_conf_perms.stat.mode != '0644'

    # ── Step 6: Start ─────────────────────────────────────────
    - name: "Verify: chrony service enabled and running"  # [services]
      ansible.builtin.service_facts:
      # service_facts populates ansible_facts.services (also available as `services`)

    - name: "Assert: chrony service state"                # [services]
      ansible.builtin.assert:
        that:
          - "'chronyd.service' in services or 'chrony.service' in services"
        fail_msg: "chrony service not found in service facts"

    # ── Step 7: Verify (runtime) ──────────────────────────────
    - name: "Verify: chronyc tracking responds"           # [runtime]
      ansible.builtin.command: chronyc tracking
      register: _ntp_verify_tracking
      changed_when: false
      failed_when: _ntp_verify_tracking.rc != 0
```

**Verification Criteria:**
- verify.yml contains at least one check per execution flow step (from README-002)
- All applicable verification categories covered; skipped categories declared with justification at top of verify.yml
- Every check has explicit `failed_when` — no reliance on default "ok means success"
- Register variables follow `_<role>_verify_<check>` naming convention
- All `command`/`shell` verification tasks use `changed_when: false`
- Config content checks use `slurp` + `b64decode` or `lineinfile check_mode`, not `shell: grep`
- Runtime checks verify the service actually responds, not just that the process exists
- Values in verify.yml driven from converge vars (via extra-vars), not hardcoded

**Anti-patterns:**
- verify.yml with only "file exists" checks (no runtime verification)
- Hardcoded values: `assert: that: "'1.1.4' in version.stdout"` instead of using extra-vars
- `ignore_errors: true` without follow-up assert
- `command: grep pattern /etc/config` instead of `slurp` + assert (not idempotent-friendly)
- Verification that duplicates converge logic instead of checking outcomes
- Missing `changed_when: false` on read-only commands (contaminates idempotence)

---

### TEST-009: Prepare Playbook Standards

**Category:** Execution
**Priority:** MUST (vagrant) / SHOULD (docker)
**Rationale:** Test environments are not production. Docker containers lack packages, Vagrant VMs have stale keyrings. The prepare playbook bridges this gap — it makes the test environment look like production BEFORE the role runs. Without it, roles fail for environment reasons, not code reasons.

**Implementation Pattern:**

Cross-platform prepare splits into separate files per OS family. The main `prepare.yml` bootstraps Python (before facts), collects facts, then delegates to a platform-specific file:

```
molecule/vagrant/
  prepare.yml              # entry point
  prepare_archlinux.yml    # Arch-specific tasks
  prepare_debian.yml       # Ubuntu/Debian-specific tasks
```

```yaml
# molecule/vagrant/prepare.yml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: "Prepare: install Python (Arch, before facts)"
      ansible.builtin.raw: pacman -Sy --noconfirm python
      when: ansible_facts['os_family'] | default('') != 'Debian'
      changed_when: true

    - name: Gather facts
      ansible.builtin.setup:

    - name: Platform-specific preparation
      ansible.builtin.include_tasks: "prepare_{{ ansible_facts['os_family'] | lower }}.yml"
```

```yaml
# molecule/vagrant/prepare_archlinux.yml
---
- name: "Prepare: refresh keyring"
  ansible.builtin.shell: |
    sed -i 's/SigLevel.*/SigLevel = Never/' /etc/pacman.conf
    pacman -Sy --noconfirm archlinux-keyring
    sed -i 's/SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
    pacman-key --populate archlinux
  changed_when: true

- name: "Prepare: full system upgrade"
  community.general.pacman:
    update_cache: true
    upgrade: true

- name: "Prepare: fix DNS after upgrade"
  ansible.builtin.copy:
    content: |
      nameserver 8.8.8.8
      nameserver 1.1.1.1
    dest: /etc/resolv.conf
    unsafe_writes: true

- name: "Prepare: lock root account (match ubuntu-base)"
  ansible.builtin.command: passwd -l root
  changed_when: true

- name: "Prepare: CI sudo guard"
  ansible.builtin.copy:
    content: "vagrant ALL=(ALL) NOPASSWD: ALL"
    dest: /etc/sudoers.d/zz-molecule-vagrant-nopasswd
    mode: "0440"
```

```yaml
# molecule/vagrant/prepare_debian.yml
---
- name: "Prepare: install CA certificates"
  ansible.builtin.apt:
    name: ca-certificates
    state: present
    update_cache: true
```

**Verification Criteria:**
- Vagrant scenario MUST have `prepare.yml`
- Docker scenario SHOULD have `prepare.yml` if containers need packages not in base image
- `gather_facts: false` at start (Python may not be installed), then explicit `setup:` after bootstrap
- Cross-platform tasks split into `prepare_<os_family>.yml` files, included via `include_tasks: "prepare_{{ ansible_facts['os_family'] | lower }}.yml"`
- Task order: update_cache → create groups → install packages → box state fixes → CI guards
- DNS fix after `pacman -Syu` on Arch (systemd replaces resolv.conf with IPv6 stub)
- `unsafe_writes: true` for bind-mounted files in Docker (`/etc/hosts`, `/etc/resolv.conf`, `/etc/hostname`)

**Anti-patterns:**
- Vagrant scenario without `prepare.yml` (generic/arch has no Python, stale keyring)
- `when: ansible_facts['os_family'] == 'X'` guards on individual tasks in a single file instead of separate platform files
- Calling `pacman` unconditionally when Ubuntu platforms exist in the scenario
- `gather_facts: true` before Python is installed (fails on bare Arch)
- Missing DNS fix after full system upgrade (Go/network tools fail with "connection refused")
- Prepare that installs software the role should install (testing the prepare, not the role)

---

### TEST-010: Dependency Management

**Category:** Coverage
**Priority:** MUST
**Rationale:** Roles depend on other roles (ntp → common, docker → base_system). If dependencies are not declared and tested, roles fail in CI with "role not found" but work locally because the dependency happens to be installed. Explicit `requirements.yml` makes dependencies reproducible.

**Implementation Pattern:**
```yaml
# requirements.yml (role root, NOT inside molecule/)
---
roles:
  - name: common
    src: git+file:///{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/../../common
    version: master

# molecule/default/molecule.yml — reference requirements
---
dependency:
  name: galaxy
  options:
    requirements-file: ${MOLECULE_PROJECT_DIRECTORY}/requirements.yml
    role-file: ${MOLECULE_PROJECT_DIRECTORY}/requirements.yml
```

**Verification Criteria:**
- `requirements.yml` exists at role root if role uses `include_role` or `import_role` for other project roles
- `requirements.yml` lists every role dependency with source and version
- `molecule.yml` references `requirements.yml` in `dependency` section
- `molecule test` installs dependencies before converge (no manual `ansible-galaxy install`)
- Dependencies pinned to a specific version, tag, or branch — never omitted

**Anti-patterns:**
- Role uses `include_role: common` but has no `requirements.yml` (works locally, fails in CI)
- Dependencies installed manually in CI workflow but not in `requirements.yml` (not reproducible)
- `requirements.yml` inside `molecule/default/` instead of role root (not shared between scenarios)
- Missing `version` field entirely (always gets latest, breaks without warning)
- Using `version: master` on external dependencies without understanding that master can break

---

### TEST-011: Edge Cases and Negative Testing

**Category:** Coverage
**Priority:** MUST (edge cases) / SHOULD (negative tests)
**Rationale:** Tests that only exercise the happy path with full configuration miss the most common production failures: empty inputs, missing optional variables, first-run vs re-run behavior. Edge cases MUST be tested. Negative tests (intentionally breaking config to verify error handling) are valuable but SHOULD not block role delivery.

**Implementation Pattern:**
```yaml
# molecule/shared/converge.yml — edge case: minimal config
---
- name: Converge — minimal configuration
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"
      # No vars — test with pure defaults

- name: Converge — full configuration
  hosts: all
  become: true
  gather_facts: true
  vars:
    ntp_servers:
      - { host: "time.cloudflare.com", nts: true, iburst: true }
    ntp_minsources: 1
  roles:
    - role: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"
```

```yaml
# SHOULD: negative test — verify error handling
- name: "Negative test: invalid minsources"
  block:
    - name: Apply role with minsources > server count
      ansible.builtin.include_role:
        name: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"
      vars:
        ntp_servers:
          - { host: "time.google.com", nts: false, iburst: true }
        ntp_minsources: 5    # More than server count — should fail
  rescue:
    - name: Assert role failed with meaningful message
      ansible.builtin.assert:
        that: "'minsources' in ansible_failed_result.msg or
               'Supported' in ansible_failed_result.msg"
        fail_msg: "Role failed but without a meaningful error message"
```

**Verification Criteria:**
- Converge includes at least one run with default-only variables (empty/minimal input)
- If role supports `state: absent` or similar variants, all variants exercised
- Empty inputs (`{}`, `[]`) do not crash the role — they either work or fail with clear message
- SHOULD: at least one negative test that verifies role rejects invalid input with a clear error

**Anti-patterns:**
- Only testing with full, valid configuration (misses default-value bugs)
- No test case for `<role>_enabled: false` (skip path untested)
- Role crashes with Jinja2 error on empty input instead of failing with `assert`
- Negative test that uses `ignore_errors: true` without asserting the error content

---

### TEST-012: Test Data Driven Verification

**Category:** Coverage
**Priority:** MUST
**Rationale:** Hardcoded values in verify.yml diverge silently from converge.yml. When someone changes the version in converge, verify still checks the old version and passes — false confidence. All test data must flow from a single source.

**Implementation Pattern:**
```yaml
# molecule/default/molecule.yml — pass vars to verify
---
provisioner:
  name: ansible
  options:
    extra-vars: "verify_version_string=1.1.4 verify_config_path=/etc/chrony.conf"

# molecule/shared/verify.yml — use passed vars, never hardcode
- name: "Verify: correct version installed"
  ansible.builtin.command: "chronyc --version"
  register: _ntp_verify_version
  changed_when: false

- name: "Assert: version matches expected"
  ansible.builtin.assert:
    that: "verify_version_string in _ntp_verify_version.stdout"
    fail_msg: >-
      Expected version {{ verify_version_string }},
      got {{ _ntp_verify_version.stdout }}
```

**Verification Criteria:**
- Version strings in verify.yml come from `extra-vars` or `vars_files`, never hardcoded
- Config paths in verify.yml use role variables or extra-vars, not literal paths
- Single source of truth: converge variables and verify variables are the same or derived from the same source
- `fail_msg` includes both expected and actual values for debugging

**Anti-patterns:**
- `assert: that: "'1.1.4' in _version.stdout"` — hardcoded version in verify
- `stat: path: /etc/chrony.conf` — hardcoded path that differs between distros
- Converge uses `ntp_version: "1.2.0"` but verify checks for `"1.1.4"` — silent divergence
- No `fail_msg` on assert — failure output is "Assertion failed" with no context

---

### TEST-013: Cross-Platform Test Coverage

**Category:** Coverage
**Priority:** MUST
**Rationale:** The project supports 5 distro families. Tests MUST exercise at minimum Arch (primary) and Ubuntu (secondary). Platform-specific code paths (package names, config paths, service names) are the most common source of bugs. If it's not tested on Ubuntu, it doesn't work on Ubuntu.

**Implementation Pattern:**
```yaml
# molecule/vagrant/molecule.yml — cross-platform matrix
---
platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
    memory: 1024
    cpus: 1
  - name: ubuntu-base
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
    memory: 1024
    cpus: 1

# molecule/shared/verify.yml — platform-aware checks
- name: Platform-specific verification
  ansible.builtin.include_tasks: "verify_{{ ansible_facts['os_family'] | lower }}.yml"
```

```yaml
# molecule/shared/verify_archlinux.yml
- name: "Assert: chronyd service running"
  ansible.builtin.assert:
    that: "services['chronyd.service'].state == 'running'"

# molecule/shared/verify_debian.yml
- name: "Assert: chrony service running"
  ansible.builtin.assert:
    that: "services['chrony.service'].state == 'running'"
```

```yaml
# For Arch-only roles in cross-platform matrix:
# molecule/vagrant/converge.yml (standalone, not shared)
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Skip non-Archlinux hosts
      ansible.builtin.meta: end_host
      when: ansible_facts['os_family'] != 'Archlinux'

  roles:
    - role: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"
```

**Verification Criteria:**
- Both scenarios exercise Arch + Ubuntu platforms at minimum
- Platform-specific verify checks split into `verify_<os_family>.yml` files, included via `include_tasks: "verify_{{ ansible_facts['os_family'] | lower }}.yml"`
- Service names, config paths, package names in verify use role variables (from `vars/<os_family>.yml`), not hardcoded
- Arch-only roles in cross-platform matrix use `meta: end_host` for non-Arch platforms (not excluded from matrix)
- Network-dependent tasks (downloads, API calls) exercised in at least one scenario — not skipped in all scenarios

**Anti-patterns:**
- Vagrant scenario with only Arch platform (Ubuntu never tested)
- `when: ansible_facts['os_family'] == 'X'` guards on individual tasks in verify.yml instead of separate platform files
- Hardcoded `systemctl is-enabled chronyd` (fails on Ubuntu where service is `chrony`)
- Arch-only role excluded from Ubuntu matrix entirely ("Instances missing" error in CI)
- All network tasks tagged `molecule-notest` in every scenario (download path never tested)

---

### TEST-014: Test Debugging and Observability

**Category:** Process
**Priority:** SHOULD
**Rationale:** When tests fail, engineers must quickly identify WHY. Opaque test output ("FAILED! => assertion failed") wastes hours. Tests should produce output that enables diagnosis without logging into the test environment. Both Jeff Geerling and VK Tech emphasized: invest in readable test output.

**Implementation Pattern:**
```yaml
# verify.yml — meaningful failure messages
- name: "Assert: chronyc tracking output valid"
  ansible.builtin.assert:
    that:
      - "'Reference ID' in _ntp_verify_tracking.stdout"
      - "'Stratum' in _ntp_verify_tracking.stdout"
    fail_msg: >-
      chronyc tracking output unexpected.
      Expected 'Reference ID' and 'Stratum' in output.
      Got: {{ _ntp_verify_tracking.stdout_lines | join('\n') }}
    success_msg: >-
      chronyc tracking verified:
      {{ _ntp_verify_tracking.stdout_lines[0] | default('no output') }}

# molecule.yml — enable profile_tasks for timing visibility
provisioner:
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
```

```yaml
# CI environment — force colored output for readable logs
env:
  PY_COLORS: "1"
  ANSIBLE_FORCE_COLOR: "1"
```

**Verification Criteria:**
- Every `assert` has both `fail_msg` and `success_msg` with actual values included
- `profile_tasks` callback enabled in `molecule.yml` (shows time per task — identifies slow tests)
- `PY_COLORS=1` and `ANSIBLE_FORCE_COLOR=1` set in CI environment
- Failed test output includes enough context to diagnose without `molecule login`
- Verify tasks that collect system state (`slurp`, `command`) SHOULD include a `debug` of the raw output on failure

**Anti-patterns:**
- `assert: that: condition` with no `fail_msg` ("Assertion failed" is useless)
- No `profile_tasks` callback (can't identify which task takes 5 minutes)
- CI output in black-and-white (hard to distinguish ok/changed/failed)
- Test failure that requires `molecule login` + manual inspection to understand

---

## Post-Creation Checklist

Use this checklist when creating or reviewing role tests. One checkbox per requirement.

### Framework

- [ ] TEST-001: Molecule installed, `molecule/` directory exists
- [ ] TEST-002: Both `molecule/default/` and `molecule/vagrant/` scenarios present with full `test_sequence`

### Structure

- [ ] TEST-003: Standard file structure followed (molecule.yml, converge.yml, verify.yml, prepare.yml)
- [ ] TEST-004: Shared test assets in `molecule/shared/` where applicable, deviations justified
- [ ] TEST-005: yamllint + ansible-lint pass with zero errors

### Execution

- [ ] TEST-006: Converge uses representative config, dynamic role name, edge cases included
- [ ] TEST-007: Idempotence in every `test_sequence`, second run shows zero `changed`
- [ ] TEST-008: verify.yml covers 4+ categories, one check per execution flow step, runtime verification included
- [ ] TEST-009: Vagrant prepare.yml handles Arch bootstrap + Ubuntu CA + DNS fix

### Coverage

- [ ] TEST-010: `requirements.yml` declares all role dependencies, molecule resolves them
- [ ] TEST-011: Default-only run tested, empty inputs don't crash, negative tests present (SHOULD)
- [ ] TEST-012: No hardcoded values in verify.yml — all from extra-vars or vars_files
- [ ] TEST-013: Both Arch + Ubuntu exercised in both scenarios, platform-specific checks guarded

### Process

- [ ] TEST-014: Every assert has fail_msg with actual values, profile_tasks enabled, CI output colored

---

Back to [[Role Requirements|standards/role-requirements]] | [[README Requirements|standards/readme-requirements]] | [[Home]]
