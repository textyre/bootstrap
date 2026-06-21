# Role Requirements Specification

This document defines ALL requirements for Ansible roles in this project. Every role MUST comply with these rules. No exceptions.

---

## 1. Role Architecture

Reference implementations: `locale`, `timezone`, `hostname`.

### 1.1 File Structure

```
role/
├── defaults/main.yml      # External contract (user-facing variables)
├── vars/main.yml           # Immutable internal details (computed values)
├── vars/per-distro/        # Distro-specific package names
│   ├── archlinux.yml
│   ├── debian.yml
│   ├── redhat.yml
│   ├── void.yml
│   └── gentoo.yml
├── tasks/
│   ├── main.yml            # Orchestrator ONLY
│   ├── validate/main.yml   # Input contract validation
│   ├── verify/             # Runtime state checks
│   │   ├── systemd.yml
│   │   ├── openrc.yml
│   │   └── runit.yml
│   └── init/               # Init-specific task files
│       ├── systemd.yml
│       ├── openrc.yml
│       └── runit.yml
├── handlers/main.yml
└── meta/main.yml
```

### 1.2 main.yml Rules

`tasks/main.yml` is an **orchestrator ONLY**:

- ❌ NO business logic
- ❌ NO `when` conditions
- ❌ NO `with_first_found`
- ✅ ONLY `include_tasks` and `include_vars`

Example:
```yaml
---
- name: Validate vconsole configuration
  ansible.builtin.include_tasks: validate/main.yml
  tags: ['vconsole']

- name: Apply keymap
  ansible.builtin.include_tasks: keymap.yml
  tags: ['vconsole']

- name: Apply init-specific configuration
  ansible.builtin.include_tasks: "init/{{ ansible_service_mgr }}.yml"
  tags: ['vconsole']
```

### 1.3 Validate vs Verify

**Validate** = checks input contract BEFORE role runs:
- OS is supported
- Init system is supported
- Required variables are defined
- Custom files exist (if provided)

**Verify** = checks runtime state AFTER role runs:
- Service is running (if applicable)
- Runtime state is correct (e.g., `localectl` for keymap)

### 1.4 Verify Rules

Verify must NOT re-check what Ansible modules guarantee:

| Module | Guarantees | Don't verify |
|--------|-----------|--------------|
| `lineinfile` | Line exists in file, file created, permissions | File existence, content, permissions |
| `copy`/`template` | File exists with correct content | File existence, content |
| `file` | File exists with correct permissions | File existence, permissions |
| `package` | Package installed | Package installation |
| `service` | Service started/enabled | Service state |

**Only verify what modules DON'T guarantee:**
- Runtime state (e.g., `localectl status`)
- Service actually running (e.g., `service_facts`)
- External state (e.g., DNS resolution)

### 1.5 Variables

**`defaults/main.yml`** = external contract:
- User-facing variables
- Can be overridden by users
- All variables MUST have defaults

**`vars/main.yml`** = immutable internal details:
- Computed values (e.g., `vconsole_value`)
- Internal flags (e.g., `_vconsole_is_container`)
- MUST NOT use `set_fact` — use Jinja expressions

**`vars/per-distro/*.yml`** = distro-specific:
- Package names
- Paths
- Loaded via `include_vars`

### 1.6 Distro Support

- 5 supported distros: Arch, Ubuntu, Fedora, Void, Gentoo
- NEVER add other distros
- Package names in `vars/per-distro/*.yml`
- Distro logic in init-specific task files

### 1.7 Init System Support

- 5 supported init systems: systemd, openrc, runit, s6, dinit
- Dispatch via `include_tasks: "init/{{ ansible_service_mgr }}.yml"`
- s6 and dinit are stubs (debug message only)

---

## 2. Handlers

### 2.1 Handler Rules

- Handlers use `when` for init-system dispatch — this is **necessary selective dispatch**, not imperative branching
- Keep handlers minimal — 3-5 handlers maximum
- No probe→apply→skip patterns
- Use `failed_when: false` for optional services

Example:
```yaml
---
- name: Apply vconsole settings (systemd)
  ansible.builtin.systemd:
    name: systemd-vconsole-setup.service
    state: restarted
  listen: "apply vconsole"

- name: Apply keymap (openrc)
  ansible.builtin.command: "loadkeys {{ vconsole_value }}"
  listen: "apply vconsole"
  when: ansible_service_mgr == 'openrc'

- name: Apply font (openrc)
  ansible.builtin.command: "setfont {{ vconsole_console_font }}"
  listen: "apply vconsole"
  when: ansible_service_mgr == 'openrc'
```

---

## 3. Testing Requirements

### 3.1 Molecule Test Philosophy

**Core principle:** Tests verify what CANNOT be covered by the role itself.

- ✅ Role runs without errors
- ✅ Role is idempotent
- ✅ Role doesn't break environment
- ❌ Tests don't duplicate role verify
- ❌ Tests don't invent variables
- ❌ Tests don't override defaults
- ❌ Tests don't create artificial scenarios

### 3.2 Molecule Test Structure

```
molecule/
├── docker/
│   ├── molecule.yml        # Docker driver config
│   ├── prepare.yml         # Container preparation (cache updates)
│   └── (converge.yml)      # Uses shared/converge.yml
├── vagrant/
│   ├── molecule.yml        # Vagrant driver config
│   ├── prepare.yml         # VM preparation
│   └── converge.yml        # Vagrant-specific converge
└── shared/
    └── converge.yml        # Shared converge (default scenario)
```

### 3.3 Converge File Rules

- ❌ NO `vars` section — use role defaults
- ❌ NO `pre_tasks` unless absolutely necessary (e.g., /dev/input mock)
- ✅ ONLY `roles: [{ role: role_name }]`

Example:
```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  pre_tasks:
    - name: Ensure /dev/input exists (mock for GPM in container)
      ansible.builtin.file:
        path: /dev/input
        state: directory
        mode: '0755'
      when: ansible_facts['virtualization_type'] | default('') in ['docker', 'container', '']

  roles:
    - role: vconsole
```

### 3.4 Molecule.yml Rules

- ❌ NO `extra-vars`
- ❌ NO `verify` playbook (role verify covers runtime)
- ✅ ONLY `prepare` and `converge` playbooks

Example:
```yaml
provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - destroy
```

### 3.5 Prepare File Rules

Prepare files handle container/VM preparation:

- ✅ Update package cache (`update_cache: true`)
- ✅ Create necessary directories (e.g., `/dev/input` for GPM)
- ❌ Don't install role dependencies (role manages its own packages)

Example (Docker):
```yaml
---
- name: Prepare -- set up container
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

### 3.6 Deleted Files

The following molecule files are NOT needed:
- `verify.yml` — role verify covers runtime checks
- `custom-keymap/` — invented scenario
- `gpm-enabled/` — invented scenario

---

## 4. Documentation Requirements

### 4.1 README.md

Every role MUST have a `README.md` with:

1. **Description** — what the role does
2. **Requirements** — Ansible version, dependencies
3. **Supported distributions** — Arch, Ubuntu, Fedora, Void, Gentoo
4. **Supported init systems** — systemd, openrc, runit, s6, dinit
5. **Role variables** — table with Variable, Default, Description
6. **Example playbook** — minimal usage
7. **Notes** — important caveats
8. **Test Cases** — scenarios and platforms
9. **Running Tests** — molecule commands
10. **Test Coverage** — what's tested

### 4.2 README Accuracy

README MUST reflect current state:
- ✅ Default values match `defaults/main.yml`
- ✅ Test cases match molecule scenarios
- ✅ No references to deleted files
- ✅ No references to non-existent variables

### 4.3 Project Documentation

Check for references in:
- `README.md` (root)
- `ansible/README.md`
- `docs/`
- `wiki/`

---

## 5. Common Mistakes

### ❌ Don't Do This

```yaml
# main.yml with business logic
- name: Apply keymap
  ansible.builtin.include_tasks: "{{ item }}.yml"
  loop:
    - validate
    - keymap
    - font
    - verify
  when: vconsole_enabled

# Converge with vars
vars:
  vconsole_console: "us"
  vconsole_gpm_enabled: false

# Verify checking file content
- name: Assert KEYMAP is set
  ansible.builtin.assert:
    that:
      - content is regex('^KEYMAP=us$')

# Tests inventing scenarios
# molecule/custom-keymap/ (deleted)
# molecule/gpm-enabled/ (deleted)
```

### ✅ Do This Instead

```yaml
# main.yml as orchestrator
- name: Validate
  ansible.builtin.include_tasks: validate/main.yml

- name: Apply keymap
  ansible.builtin.include_tasks: keymap.yml

# Converge without vars
roles:
  - role: vconsole

# Verify checking runtime state only
- name: Check localectl
  ansible.builtin.command: localectl status
  register: result
  changed_when: false

- name: Assert keymap applied
  ansible.builtin.assert:
    that:
      - "'VC Keymap: us' in result.stdout"
```

---

## 6. Checklist for New Roles

Before submitting a new role, verify:

- [ ] `defaults/main.yml` has all user-facing variables
- [ ] `vars/main.yml` has computed values (no `set_fact`)
- [ ] `vars/per-distro/*.yml` has package names for all 5 distros
- [ ] `tasks/main.yml` is orchestrator only (no `when`, no `with_first_found`)
- [ ] `tasks/validate/main.yml` checks input contract
- [ ] `tasks/verify/*.yml` checks runtime state only
- [ ] `handlers/main.yml` has minimal handlers (3-5 max)
- [ ] `molecule/docker/` has prepare.yml and converge.yml
- [ ] `molecule/vagrant/` has prepare.yml and converge.yml
- [ ] `molecule/shared/converge.yml` has no vars
- [ ] No verify.yml files in molecule
- [ ] No extra-vars in molecule.yml
- [ ] README.md is accurate and up-to-date
- [ ] All tests pass: `molecule test -s docker`
