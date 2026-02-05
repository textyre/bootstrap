# Ansible Role Patterns Reference

This document consolidates the existing Ansible role patterns used in the bootstrap project, extracted from `base_system`, `firewall`, and `docker` roles.

## File Structure Summary

| File Path | Purpose |
|-----------|---------|
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/defaults/main.yml` | Default variables for locale, timezone, hostname, pacman config |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/main.yml` | Main cross-platform tasks with OS dispatch |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/archlinux.yml` | Arch Linux-specific config (pacman, pam_faillock) |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/tasks/debian.yml` | Debian placeholder (not yet implemented) |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/meta/main.yml` | Galaxy metadata, dependencies |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/base_system/handlers/main.yml` | Handlers (locale-gen) |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/defaults/main.yml` | Docker defaults (user, service, daemon config) |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/tasks/main.yml` | Docker configuration tasks |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/handlers/main.yml` | Docker handlers (restart) |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/docker/meta/main.yml` | Galaxy metadata |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/molecule/default/molecule.yml` | Molecule test config |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/molecule/default/converge.yml` | Molecule converge playbook |
| `/Users/umudrakov/Documents/bootstrap/ansible/roles/firewall/molecule/default/verify.yml` | Molecule verify tasks |

---

## 1. Defaults Variables Pattern

### Example: base_system/defaults/main.yml

```yaml
---
# === Comment describing role purpose ===
# Sub-headings explain sections

# Supported OS families list
_base_system_supported_os:
  - Archlinux
  - Debian

# Configuration parameters
base_system_locale: "en_US.UTF-8"
base_system_timezone: "Asia/Almaty"
base_system_hostname: "archbox"

# Pacman-specific (Arch only)
base_system_pacman_parallel_downloads: 5
base_system_pacman_color: true

# Optional features with conditional enable flag
base_system_setup_pacman_cache: false
base_system_pacman_cache_root: ""
```

**Key Patterns:**
- Prefix all variables with role name (e.g., `base_system_*`, `docker_*`)
- Define supported OS families as `_<role>_supported_os` list
- Use section comments with `# ---- Section Name ----` format
- Boolean flags for conditional features (e.g., `base_system_setup_pacman_cache`)
- Provide sensible defaults for all variables

### Example: docker/defaults/main.yml

```yaml
---
# === Конфигурация Docker ===
# Daemon, сервис, группа пользователя

docker_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
docker_add_user_to_group: true
docker_enable_service: true

# Daemon configuration
docker_log_driver: "json-file"
docker_log_max_size: "10m"
docker_log_max_file: "3"
docker_storage_driver: ""
```

**Key Patterns:**
- Runtime user detection with fallback
- Boolean feature flags
- Clear grouping of related settings with comments

---

## 2. Main Tasks Pattern (Cross-Platform with OS Dispatch)

### Example: base_system/tasks/main.yml

```yaml
---
# === Brief description ===
# OS-специфичные задачи: tasks/<os_family>.yml

# ---- Tagging for organization ----

- name: Set timezone
  community.general.timezone:
    name: "{{ base_system_timezone }}"
  tags: ['system', 'timezone']

- name: Uncomment locale in locale.gen
  ansible.builtin.lineinfile:
    path: /etc/locale.gen
    regexp: '^#?\s*{{ base_system_locale }}'
    line: "{{ base_system_locale }} UTF-8"
    state: present
  notify: Generate locale
  tags: ['system', 'locale']

# ---- OS-специфичная конфигурация (OS Dispatch Pattern) ----

- name: Include OS-specific configuration
  ansible.builtin.include_tasks: "{{ ansible_facts['os_family'] | lower }}.yml"
  when: ansible_facts['os_family'] in _base_system_supported_os
  tags: ['system']

# ---- Report/Debug ----

- name: Report base system configuration
  ansible.builtin.debug:
    msg:
      - "OS: {{ ansible_facts['os_family'] }}"
      - "Таймзона: {{ base_system_timezone }}"
  tags: ['system']
```

**Key Patterns:**
- Clear section comments with `# ---- Name ----` format
- Every task has `tags` for fine-grained control
- OS dispatch using `include_tasks` with file lowercased OS family
- Conditional check against supported OS list
- Debug task at end to report applied configuration
- Use `notify` to trigger handlers when config changes

### Example: docker/tasks/main.yml (Configuration Only - No OS Dispatch)

```yaml
---
# === Конфигурация Docker ===
# daemon.json, сервис, группа пользователя

# ---- Конфигурация daemon ----

- name: Ensure /etc/docker directory exists
  ansible.builtin.file:
    path: /etc/docker
    state: directory
    owner: root
    group: root
    mode: '0755'
  tags: ['docker', 'configure']

- name: Deploy Docker daemon.json
  ansible.builtin.template:
    src: daemon.json.j2
    dest: /etc/docker/daemon.json
    owner: root
    group: root
    mode: '0644'
  notify: Restart docker
  tags: ['docker', 'configure']

# ---- Сервис ----

- name: Enable and start docker service
  ansible.builtin.service:
    name: docker
    enabled: true
    state: started
  when: docker_enable_service
  tags: ['docker', 'service']
```

**Key Patterns:**
- Section comments organize related tasks
- All file operations have explicit owner/group/mode
- Templates use Jinja2 (.j2 extension)
- Conditional task execution with `when` for feature flags
- Handlers triggered on config changes

---

## 3. OS-Specific Tasks Pattern

### Example: base_system/tasks/archlinux.yml

```yaml
---
# === Arch Linux: конфигурация pacman ===

# ---- Pacman configuration ----

- name: Enable ParallelDownloads in pacman.conf
  ansible.builtin.lineinfile:
    path: /etc/pacman.conf
    regexp: '^#?\s*ParallelDownloads'
    line: "ParallelDownloads = {{ base_system_pacman_parallel_downloads }}"
  tags: ['system', 'pacman']

- name: Enable Color in pacman.conf
  ansible.builtin.lineinfile:
    path: /etc/pacman.conf
    regexp: '^#?\s*Color'
    line: "Color"
  when: base_system_pacman_color
  tags: ['system', 'pacman']

# ---- Block for conditional features ----

- name: Setup external pacman cache
  when: base_system_setup_pacman_cache and base_system_pacman_cache_root | length > 0
  tags: ['system', 'pacman-cache']
  block:
    - name: Create pacman cache directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - "{{ base_system_pacman_cache_root }}/var/lib/pacman/sync"
        - "{{ base_system_pacman_cache_root }}/var/cache/pacman/pkg"

    - name: Check if alpm user exists
      ansible.builtin.getent:
        database: passwd
        key: alpm
      register: _base_system_alpm_user
      failed_when: false

    - name: Set alpm group ownership on pacman cache dirs
      ansible.builtin.file:
        path: "{{ item }}"
        owner: root
        group: alpm
        mode: '2775'
        recurse: true
      loop:
        - "{{ base_system_pacman_cache_root }}/var"
      when: >
        _base_system_alpm_user.ansible_facts.getent_passwd is defined
        and 'alpm' in _base_system_alpm_user.ansible_facts.getent_passwd
```

**Key Patterns:**
- File name matches lowercase OS family (archlinux.yml for Archlinux)
- Included only if OS is in supported list
- Uses `block` for grouping related conditional tasks
- Registers for conditional task dependencies (e.g., check user exists, then set ownership)
- Complex `when` conditions use multiline format with `>`
- All internal tasks inherit `tags` from block

### Example: base_system/tasks/debian.yml (Placeholder Pattern)

```yaml
---
# === Debian/Ubuntu: системная конфигурация ===
# Заглушка для будущей реализации

- name: Debian system configuration placeholder
  ansible.builtin.debug:
    msg: "Debian/Ubuntu system configuration — not yet implemented"
  tags: ['system']
```

**Key Pattern:**
- Placeholder for future OS implementation
- Clear comment indicating this is not yet implemented

---

## 4. Meta Configuration Pattern

### Example: base_system/meta/main.yml

```yaml
---
galaxy_info:
  role_name: base_system
  author: textyre
  description: Базовая настройка системы (локаль, таймзона, hostname, pacman)
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
  galaxy_tags: [system, arch, locale, timezone, hostname, pacman]
dependencies: []
```

**Key Patterns:**
- `role_name` matches directory name
- Descriptive `description` in English (optional Russian allowed)
- License clearly stated (MIT)
- `min_ansible_version: "2.15"` (confirmed minimum)
- `platforms` lists supported OS
- `galaxy_tags` are lowercase, hyphenated
- `dependencies: []` explicit (even if empty)

### Example: docker/meta/main.yml

```yaml
---
galaxy_info:
  role_name: docker
  author: textyre
  description: Конфигурация Docker (daemon, сервис, группа пользователя)
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
  galaxy_tags: [docker, container, service]
dependencies: []
```

---

## 5. Handlers Pattern

### Example: base_system/handlers/main.yml

```yaml
---
# Handlers for base_system role

- name: Generate locale
  ansible.builtin.command: locale-gen
  changed_when: true
```

**Key Patterns:**
- Handlers triggered by `notify` in tasks
- `changed_when: true` for handlers that should always report change
- Handler names should be descriptive

### Example: docker/handlers/main.yml

```yaml
---
- name: Reload service manager
  ansible.builtin.systemd:
    daemon_reload: true
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Restart docker
  ansible.builtin.service:
    name: docker
    state: restarted
```

**Key Patterns:**
- Conditional handlers with `when` (e.g., check if systemd)
- Service restart pattern
- Service manager check pattern

---

## 6. Molecule Testing Pattern

### Example: firewall/molecule/default/molecule.yml

```yaml
---
driver:
  name: default
  options:
    managed: false

platforms:
  - name: localhost

provisioner:
  name: ansible
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
  playbooks:
    converge: converge.yml
    verify: verify.yml
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Key Patterns:**
- `driver: default` with `managed: false` (local testing)
- `ansible_connection: local` for testing on localhost
- Custom playbook paths for converge/verify
- Vault integration with `vault-pass.sh`
- Environment variables set for roles path
- Test sequence: syntax → converge → verify

### Example: firewall/molecule/default/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  pre_tasks:
    - name: Ensure we're running on Arch Linux
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] == 'Archlinux'
        fail_msg: "This test requires Arch Linux"

  roles:
    - role: firewall
```

**Key Patterns:**
- Single play format
- `become: true` for privileged operations
- `gather_facts: true` (always required for fact-based tasks)
- Vault file loading with environment variable lookup
- Pre-task assertions to verify test environment
- Simple role inclusion in `roles` section

### Example: firewall/molecule/default/verify.yml

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  tasks:
    - name: Check nftables is installed
      ansible.builtin.package:
        name: nftables
        state: present
      check_mode: true
      register: _firewall_verify_nftables
      failed_when: _firewall_verify_nftables is changed

    - name: Check /etc/nftables.conf exists
      ansible.builtin.stat:
        path: /etc/nftables.conf
      register: _firewall_verify_nftables_conf
      failed_when: not _firewall_verify_nftables_conf.stat.exists

    - name: Check nftables config contains filter table
      ansible.builtin.command: grep 'table inet filter' /etc/nftables.conf
      register: _firewall_verify_nftables_table
      changed_when: false
      failed_when: _firewall_verify_nftables_table.rc != 0

    - name: Check nftables service is enabled
      ansible.builtin.service:
        name: nftables
        enabled: true
      check_mode: true
      register: _firewall_verify_service
      failed_when: _firewall_verify_service is changed

    - name: Check nftables rules are loaded
      ansible.builtin.command: nft list tables
      register: _firewall_verify_rules
      changed_when: false
      failed_when: "'inet filter' not in _firewall_verify_rules.stdout"

    - name: Show test results
      ansible.builtin.debug:
        msg:
          - "All checks passed!"
          - "nftables installed"
```

**Key Patterns:**
- Verification tasks check role state without changing it
- `check_mode: true` + `failed_when: is changed` = idempotency check
- `changed_when: false` for informational commands (grep, nft list)
- Register variables with `_<role>_verify_<check>` naming
- Multiple failure conditions using `failed_when`
- Debug output shows test results

---

## 7. Task Naming Conventions

### Pattern Examples

| Pattern | Example | Purpose |
|---------|---------|---------|
| `_<role>_<purpose>` | `_base_system_alpm_user`, `_firewall_verify_nftables` | Internal register variables |
| `<role>_<setting>` | `base_system_locale`, `docker_user` | Role configuration variables |
| `<role>_<feature>` | `base_system_setup_pacman_cache` | Feature enable/disable flags |
| `_<role>_supported_os` | `_base_system_supported_os` | Lists of supported values |

---

## 8. Tagging Strategy

### Standard Tag Format

```yaml
tags: ['<role>', '<feature>']
```

**Examples:**
- `tags: ['system', 'timezone']` — timezone setup in system role
- `tags: ['system', 'locale']` — locale setup
- `tags: ['system', 'pacman']` — Arch-specific pacman config
- `tags: ['docker', 'configure']` — docker daemon config
- `tags: ['docker', 'service']` — docker service management

**Usage:**
```bash
ansible-playbook playbook.yml --tags system
ansible-playbook playbook.yml --tags docker,configure
ansible-playbook playbook.yml --skip-tags pacman
```

---

## 9. File Mode & Permission Pattern

### Standard Permission Values

```yaml
# Directories
mode: '0755'    # rwxr-xr-x (public read/execute)

# Configuration files
mode: '0644'    # rw-r--r-- (world-readable)

# Sensitive files
mode: '0600'    # rw------- (owner only, rare)

# Group-writable directories
mode: '2775'    # rwxrwsr-x (setgid for group ownership)
```

### Ownership Patterns

```yaml
# System files
owner: root
group: root

# Group-specific files (e.g., docker group)
owner: root
group: docker

# User-specific files
owner: "{{ ansible_user }}"
group: "{{ ansible_user }}"
```

---

## 10. Conditional Patterns

### Feature Flag Pattern

```yaml
- name: Add user to docker group
  ansible.builtin.user:
    name: "{{ docker_user }}"
    groups: docker
    append: true
  when: docker_add_user_to_group
  tags: ['docker', 'configure']
```

### OS Check Pattern

```yaml
- name: Include OS-specific configuration
  ansible.builtin.include_tasks: "{{ ansible_facts['os_family'] | lower }}.yml"
  when: ansible_facts['os_family'] in _base_system_supported_os
  tags: ['system']
```

### Service Manager Check Pattern

```yaml
- name: Reload service manager
  ansible.builtin.systemd:
    daemon_reload: true
  when: ansible_facts['service_mgr'] == 'systemd'
```

### Complex Condition Pattern

```yaml
- name: Set alpm group ownership on pacman cache dirs
  ansible.builtin.file:
    path: "{{ item }}"
    owner: root
    group: alpm
    mode: '2775'
    recurse: true
  when: >
    _base_system_alpm_user.ansible_facts.getent_passwd is defined
    and 'alpm' in _base_system_alpm_user.ansible_facts.getent_passwd
```

---

## 11. Block Pattern for Conditional Feature Groups

```yaml
- name: Setup external pacman cache
  when: base_system_setup_pacman_cache and base_system_pacman_cache_root | length > 0
  tags: ['system', 'pacman-cache']
  block:
    - name: Create pacman cache directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
      loop:
        - "{{ base_system_pacman_cache_root }}/var/lib/pacman/sync"
        - "{{ base_system_pacman_cache_root }}/var/cache/pacman/pkg"

    - name: Check if alpm user exists
      ansible.builtin.getent:
        database: passwd
        key: alpm
      register: _base_system_alpm_user
      failed_when: false
```

**Key Patterns:**
- Wrap related tasks in `block`
- Apply `when` and `tags` at block level
- Tasks within block inherit parent conditions
- Use `failed_when: false` to allow optional checks

---

## 12. Variable Expansion Patterns

### Ansible Facts

```yaml
# OS family (lowercased for includes)
{{ ansible_facts['os_family'] | lower }}

# Current user
{{ ansible_facts['env']['SUDO_USER'] }}

# User ID fallback
{{ ansible_facts['user_id'] }}

# Service manager
{{ ansible_facts['service_mgr'] }}
```

### Jinja2 Filters

```yaml
# Lowercase for includes
{{ ansible_facts['os_family'] | lower }}

# String length check
{{ base_system_pacman_cache_root | length > 0 }}
```

---

## Summary of Key Patterns

1. **Variable Naming**: `<role>_<setting>`, `_<role>_<internal>`, `_<role>_supported_os`
2. **File Organization**: `defaults/`, `tasks/`, `handlers/`, `meta/`, `templates/`, `molecule/`
3. **OS Dispatch**: `include_tasks` + lowercase OS family + `when` supported check
4. **Tagging**: `['<role>', '<feature>']` for granular control
5. **Permissions**: `0755` (dirs), `0644` (configs), `2775` (group-writable)
6. **Handlers**: Triggered by `notify`, conditional with `when`
7. **Blocks**: Group conditional features, inherit parent conditions
8. **Molecule**: Local testing with `default` driver, vault integration
9. **Verification**: Check-mode idempotency, `changed_when: false` for info commands
10. **Comments**: Section headers with `# ---- Name ----` format

---

## When to Use Each Pattern

| Pattern | Use Case | Example |
|---------|----------|---------|
| Include OS-specific | Multi-OS support with different config | base_system (Arch vs Debian) |
| Block for conditional | Group related optional features | pacman cache setup |
| Handler + notify | Trigger on configuration change | locale-gen after locale.conf change |
| Check mode in verify | Ensure idempotency | Package state in check mode |
| Register + when | Dependency between tasks | Check user exists, then set ownership |
| Feature flags | Optional role functionality | `docker_enable_service`, `base_system_setup_pacman_cache` |

