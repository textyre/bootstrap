# package_manager: Multi-Distro + Feature Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Расширить роль package_manager: разбить archlinux.yml/debian.yml по фичам в subdirectory, сменить dispatch с os_family на ansible_distribution, добавить поддержку Ubuntu/Fedora/Void.

**Architecture:** Dispatch меняется с `os_family` на `ansible_distribution` (единственный способ разделить Debian и Ubuntu). Каждый дистрибутив — тонкий dispatcher-файл + поддиректория с файлами по одной фиче. Void использует cron вместо systemd для cache cleanup.

**Tech Stack:** Ansible 2.15+, Jinja2, pacman, apt, dnf, xbps

**Run commands via:** `/ansible` skill (remote VM). Never run Ansible/molecule locally.

---

### Task 1: Обновить defaults/main.yml — новые переменные

**Files:**
- Modify: `ansible/roles/package_manager/defaults/main.yml`

**Step 1: Заменить `_pkgmgr_supported_os` на `_pkgmgr_supported_distributions` и добавить новые vars**

```yaml
---
# === Конфигурация пакетного менеджера ===

# Поддерживаемые дистрибутивы (ansible_distribution)
_pkgmgr_supported_distributions:
  - Archlinux
  - Debian
  - Ubuntu
  - Fedora
  - Void

# --- Arch Linux / pacman ---
pkgmgr_pacman_parallel_downloads: 5
pkgmgr_pacman_color: true
pkgmgr_pacman_verbose_pkg_lists: true
pkgmgr_pacman_check_space: true
pkgmgr_pacman_siglevel: "Required DatabaseOptional"
pkgmgr_pacman_multilib: false

# Внешний кэш pacman (опционально)
pkgmgr_pacman_external_cache: false
pkgmgr_pacman_cache_root: ""

# paccache (очистка устаревших версий из кэша)
pkgmgr_paccache_enabled: true
pkgmgr_paccache_keep: 3

# makepkg (оптимизация сборки пакетов из AUR)
pkgmgr_makepkg_enabled: true
pkgmgr_makepkg_makeflags: "-j{{ ansible_processor_nproc | default(2) }}"
pkgmgr_makepkg_pkgext: ".pkg.tar.zst"

# --- Debian / apt ---
pkgmgr_apt_parallel_queue_mode: "host"
pkgmgr_apt_retries: 3
pkgmgr_apt_dpkg_force_confdef: true
pkgmgr_apt_dpkg_force_confold: true

# --- Ubuntu / apt (те же настройки что и Debian) ---
# Ubuntu использует pkgmgr_apt_* переменные

# --- Fedora / dnf ---
pkgmgr_dnf_parallel_downloads: 5
pkgmgr_dnf_fastestmirror: true
pkgmgr_dnf_color: "always"
pkgmgr_dnf_defaultyes: true
pkgmgr_dnf_keepcache: false
pkgmgr_dnf_installonly_limit: 3

# --- Void / xbps ---
pkgmgr_xbps_cache_cleanup_enabled: true
pkgmgr_xbps_cache_cron_minute: "0"
pkgmgr_xbps_cache_cron_hour: "3"
pkgmgr_xbps_cache_cron_weekday: "0"
```

**Step 2: Verify YAML корректен**

Прочитай файл, проверь что все секции присутствуют.

---

### Task 2: Обновить tasks/main.yml — dispatch по ansible_distribution

**Files:**
- Modify: `ansible/roles/package_manager/tasks/main.yml`

**Step 1: Заменить содержимое**

```yaml
---
# === Конфигурация пакетного менеджера ===
# Подключает distribution-специфичную конфигурацию

- name: Include distribution-specific package manager configuration
  ansible.builtin.include_tasks: "{{ ansible_distribution | lower }}.yml"
  when: ansible_distribution in _pkgmgr_supported_distributions
  tags: ['packages', 'package-manager']
```

**Step 2: Verify**

Прочитай файл — старая переменная `_pkgmgr_supported_os` не должна присутствовать.

---

### Task 3: Разбить tasks/archlinux.yml → archlinux/ subdirectory

**Files:**
- Modify: `ansible/roles/package_manager/tasks/archlinux.yml`
- Create: `ansible/roles/package_manager/tasks/archlinux/pacman.yml`
- Create: `ansible/roles/package_manager/tasks/archlinux/paccache.yml`
- Create: `ansible/roles/package_manager/tasks/archlinux/makepkg.yml`

**Step 1: Создать `tasks/archlinux/pacman.yml`**

```yaml
---
# === Arch Linux: конфигурация pacman ===

- name: Assert external cache config is valid
  ansible.builtin.assert:
    that:
      - pkgmgr_pacman_cache_root | length > 0
    msg: "pkgmgr_pacman_cache_root must be set when pkgmgr_pacman_external_cache is true"
  when: pkgmgr_pacman_external_cache
  tags: ['packages', 'pacman']

- name: Deploy pacman.conf from template
  ansible.builtin.template:
    src: archlinux/pacman.conf.j2
    dest: /etc/pacman.conf
    owner: root
    group: root
    mode: '0644'
    backup: true
  tags: ['packages', 'pacman']

- name: Setup external pacman cache
  when: pkgmgr_pacman_external_cache and pkgmgr_pacman_cache_root | length > 0
  tags: ['packages', 'pacman-cache']
  block:
    - name: Create pacman cache directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - "{{ pkgmgr_pacman_cache_root }}/var/lib/pacman/sync"
        - "{{ pkgmgr_pacman_cache_root }}/var/cache/pacman/pkg"
        - "{{ pkgmgr_pacman_cache_root }}/etc/pacman.d"

    - name: Check if alpm user exists
      ansible.builtin.getent:
        database: passwd
        key: alpm
      register: _pkgmgr_alpm_user
      failed_when: false

    - name: Set alpm ownership on pacman cache dirs
      ansible.builtin.file:
        path: "{{ item }}"
        owner: root
        group: alpm
        state: directory
        mode: '2775'
      loop:
        - "{{ pkgmgr_pacman_cache_root }}/var/lib/pacman/sync"
        - "{{ pkgmgr_pacman_cache_root }}/var/cache/pacman/pkg"
        - "{{ pkgmgr_pacman_cache_root }}/etc/pacman.d"
      when: >
        _pkgmgr_alpm_user.ansible_facts.getent_passwd is defined
        and 'alpm' in _pkgmgr_alpm_user.ansible_facts.getent_passwd
```

**Step 2: Создать `tasks/archlinux/paccache.yml`**

```yaml
---
# === Arch Linux: paccache timer ===

- name: Install pacman-contrib (provides paccache)
  community.general.pacman:
    name: pacman-contrib
    state: present
  when: pkgmgr_paccache_enabled
  tags: ['packages', 'paccache']

- name: Create paccache drop-in directory
  ansible.builtin.file:
    path: /etc/systemd/system/paccache.service.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: pkgmgr_paccache_enabled
  tags: ['packages', 'paccache']

- name: Configure paccache keep count via systemd drop-in
  ansible.builtin.copy:
    dest: /etc/systemd/system/paccache.service.d/keep.conf
    owner: root
    group: root
    mode: '0644'
    content: |
      [Service]
      ExecStart=
      ExecStart=/usr/bin/paccache -r -k {{ pkgmgr_paccache_keep }}
  when: pkgmgr_paccache_enabled
  notify: daemon-reload
  tags: ['packages', 'paccache']

- name: Enable and start paccache.timer
  ansible.builtin.systemd:
    name: paccache.timer
    enabled: true
    state: started
    daemon_reload: false
  when: pkgmgr_paccache_enabled
  tags: ['packages', 'paccache']
```

**Step 3: Создать `tasks/archlinux/makepkg.yml`**

```yaml
---
# === Arch Linux: makepkg configuration ===

- name: Ensure /etc/makepkg.conf.d directory exists
  ansible.builtin.file:
    path: /etc/makepkg.conf.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: pkgmgr_makepkg_enabled
  tags: ['packages', 'makepkg']

- name: Deploy makepkg drop-in config
  ansible.builtin.template:
    src: archlinux/makepkg.conf.j2
    dest: /etc/makepkg.conf.d/ansible.conf
    owner: root
    group: root
    mode: '0644'
  when: pkgmgr_makepkg_enabled
  tags: ['packages', 'makepkg']
```

**Step 4: Заменить `tasks/archlinux.yml` тонким dispatcher'ом**

```yaml
---
# === Arch Linux: dispatcher ===

- name: Configure pacman
  ansible.builtin.include_tasks: archlinux/pacman.yml

- name: Configure paccache
  ansible.builtin.include_tasks: archlinux/paccache.yml

- name: Configure makepkg
  ansible.builtin.include_tasks: archlinux/makepkg.yml
```

---

### Task 4: Разбить tasks/debian.yml → debian/ subdirectory

**Files:**
- Modify: `ansible/roles/package_manager/tasks/debian.yml`
- Create: `ansible/roles/package_manager/tasks/debian/apt.yml`
- Create: `ansible/roles/package_manager/tasks/debian/dpkg.yml`

**Step 1: Создать `tasks/debian/apt.yml`**

```yaml
---
# === Debian: apt configuration ===

- name: Ensure /etc/apt/apt.conf.d exists
  ansible.builtin.file:
    path: /etc/apt/apt.conf.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  tags: ['packages', 'apt']

- name: Deploy apt parallel downloads config
  ansible.builtin.template:
    src: debian/10-parallel.conf.j2
    dest: /etc/apt/apt.conf.d/10-ansible-parallel.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['packages', 'apt']
```

**Step 2: Создать `tasks/debian/dpkg.yml`**

```yaml
---
# === Debian: dpkg options ===

- name: Deploy apt dpkg options config
  ansible.builtin.template:
    src: debian/20-dpkg.conf.j2
    dest: /etc/apt/apt.conf.d/20-ansible-dpkg.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['packages', 'apt']
```

**Step 3: Заменить `tasks/debian.yml` dispatcher'ом**

```yaml
---
# === Debian: dispatcher ===

- name: Configure apt
  ansible.builtin.include_tasks: debian/apt.yml

- name: Configure dpkg
  ansible.builtin.include_tasks: debian/dpkg.yml
```

---

### Task 5: Ubuntu — dispatcher + subtasks + templates

**Files:**
- Create: `ansible/roles/package_manager/tasks/ubuntu.yml`
- Create: `ansible/roles/package_manager/tasks/ubuntu/apt.yml`
- Create: `ansible/roles/package_manager/tasks/ubuntu/dpkg.yml`
- Create: `ansible/roles/package_manager/templates/ubuntu/10-parallel.conf.j2`
- Create: `ansible/roles/package_manager/templates/ubuntu/20-dpkg.conf.j2`

**Step 1: `tasks/ubuntu.yml`**

```yaml
---
# === Ubuntu: dispatcher ===

- name: Configure apt
  ansible.builtin.include_tasks: ubuntu/apt.yml

- name: Configure dpkg
  ansible.builtin.include_tasks: ubuntu/dpkg.yml
```

**Step 2: `tasks/ubuntu/apt.yml`**

```yaml
---
# === Ubuntu: apt configuration ===

- name: Ensure /etc/apt/apt.conf.d exists
  ansible.builtin.file:
    path: /etc/apt/apt.conf.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  tags: ['packages', 'apt']

- name: Deploy apt parallel downloads config
  ansible.builtin.template:
    src: ubuntu/10-parallel.conf.j2
    dest: /etc/apt/apt.conf.d/10-ansible-parallel.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['packages', 'apt']
```

**Step 3: `tasks/ubuntu/dpkg.yml`**

```yaml
---
# === Ubuntu: dpkg options ===

- name: Deploy apt dpkg options config
  ansible.builtin.template:
    src: ubuntu/20-dpkg.conf.j2
    dest: /etc/apt/apt.conf.d/20-ansible-dpkg.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['packages', 'apt']
```

**Step 4: `templates/ubuntu/10-parallel.conf.j2`**

```jinja2
// Managed by Ansible — do not edit manually
// Role: package_manager

Acquire::Queue-Mode "{{ pkgmgr_apt_parallel_queue_mode }}";
Acquire::Retries "{{ pkgmgr_apt_retries }}";
```

**Step 5: `templates/ubuntu/20-dpkg.conf.j2`**

```jinja2
// Managed by Ansible — do not edit manually
// Role: package_manager

Dpkg::Options {
{% if pkgmgr_apt_dpkg_force_confdef %}
   "--force-confdef";
{% endif %}
{% if pkgmgr_apt_dpkg_force_confold %}
   "--force-confold";
{% endif %}
};
```

---

### Task 6: Fedora — dispatcher + subtasks + template

**Files:**
- Create: `ansible/roles/package_manager/tasks/fedora.yml`
- Create: `ansible/roles/package_manager/tasks/fedora/dnf.yml`
- Create: `ansible/roles/package_manager/templates/fedora/dnf.conf.j2`

**Step 1: `tasks/fedora.yml`**

```yaml
---
# === Fedora: dispatcher ===

- name: Configure dnf
  ansible.builtin.include_tasks: fedora/dnf.yml
```

**Step 2: `tasks/fedora/dnf.yml`**

```yaml
---
# === Fedora: dnf configuration ===

- name: Deploy dnf.conf from template
  ansible.builtin.template:
    src: fedora/dnf.conf.j2
    dest: /etc/dnf/dnf.conf
    owner: root
    group: root
    mode: '0644'
    backup: true
  tags: ['packages', 'dnf']
```

**Step 3: `templates/fedora/dnf.conf.j2`**

```jinja2
# Managed by Ansible — do not edit manually
# Role: package_manager

[main]
gpgcheck=1
installonly_limit={{ pkgmgr_dnf_installonly_limit }}
clean_requirements_on_remove=True
best=True
skip_if_unavailable=False
max_parallel_downloads={{ pkgmgr_dnf_parallel_downloads }}
fastestmirror={{ pkgmgr_dnf_fastestmirror | lower }}
color={{ pkgmgr_dnf_color }}
defaultyes={{ pkgmgr_dnf_defaultyes | lower }}
keepcache={{ pkgmgr_dnf_keepcache | ternary('1', '0') }}
```

---

### Task 7: Void — dispatcher + subtasks + template

**Files:**
- Create: `ansible/roles/package_manager/tasks/void.yml`
- Create: `ansible/roles/package_manager/tasks/void/xbps.yml`
- Create: `ansible/roles/package_manager/tasks/void/cache.yml`
- Create: `ansible/roles/package_manager/templates/void/xbps.conf.j2`

**Step 1: `tasks/void.yml`**

```yaml
---
# === Void Linux: dispatcher ===

- name: Configure xbps
  ansible.builtin.include_tasks: void/xbps.yml

- name: Configure cache cleanup
  ansible.builtin.include_tasks: void/cache.yml
```

**Step 2: `tasks/void/xbps.yml`**

```yaml
---
# === Void Linux: xbps configuration ===

- name: Ensure /etc/xbps.d directory exists
  ansible.builtin.file:
    path: /etc/xbps.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  tags: ['packages', 'xbps']

- name: Deploy xbps ansible settings
  ansible.builtin.template:
    src: void/xbps.conf.j2
    dest: /etc/xbps.d/ansible.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['packages', 'xbps']
```

**Step 3: `tasks/void/cache.yml`**

```yaml
---
# === Void Linux: cache cleanup via cron ===
# xbps не использует systemd, очистка кэша через cron

- name: Schedule xbps cache cleanup via cron
  ansible.builtin.cron:
    name: "xbps cache cleanup"
    minute: "{{ pkgmgr_xbps_cache_cron_minute }}"
    hour: "{{ pkgmgr_xbps_cache_cron_hour }}"
    weekday: "{{ pkgmgr_xbps_cache_cron_weekday }}"
    job: "/usr/bin/xbps-remove -O"
    user: root
    state: "{{ pkgmgr_xbps_cache_cleanup_enabled | ternary('present', 'absent') }}"
  tags: ['packages', 'xbps-cache']
```

**Step 4: `templates/void/xbps.conf.j2`**

```jinja2
# Managed by Ansible — do not edit manually
# Role: package_manager
#
# Note: xbps does not support parallel downloads via config file.
# Cache cleanup is managed via cron (see void/cache.yml).
#
# This file sets syslog logging preference.

syslog=false
```

---

### Task 8: Обновить meta/main.yml — добавить новые платформы

**Files:**
- Modify: `ansible/roles/package_manager/meta/main.yml`

**Step 1: Добавить Ubuntu, Fedora, Void в platforms**

```yaml
---
galaxy_info:
  role_name: package_manager
  author: textyre
  description: Конфигурация пакетного менеджера (pacman, apt, dnf, xbps)
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: Fedora
      versions: [all]
    - name: Void
      versions: [all]
  galaxy_tags: [packages, pacman, apt, dnf, xbps, system]
dependencies: []
```

---

### Task 9: Запустить molecule + ansible-lint + commit

**Step 1: Синхронизировать роль на remote VM**

```bash
bash scripts/ssh-scp-to.sh -r ansible/roles/package_manager/ /home/textyre/bootstrap/ansible/roles/package_manager/
```

**Step 2: Синтаксис-чек**

Используй `/ansible` skill:
```bash
cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && \
  ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg \
  MOLECULE_PROJECT_DIRECTORY=/home/textyre/bootstrap/ansible \
  molecule syntax -s default -- --roles-path /home/textyre/bootstrap/ansible/roles
```

Ожидается: 0 errors.

**Step 3: molecule converge + verify**

```bash
cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && \
  ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg \
  MOLECULE_PROJECT_DIRECTORY=/home/textyre/bootstrap/ansible \
  molecule test -s default
```

Ожидается: syntax ✓ → converge ✓ → verify ✓ (все 7 тасков зелёные).

**Step 4: ansible-lint**

```bash
cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && \
  ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg \
  ansible-lint ansible/roles/package_manager/
```

Ожидается: 0 violations. Если есть нарушения — исправить и повторить.

**Step 5: Commit**

```bash
git add ansible/roles/package_manager/
git add docs/plans/2026-02-20-package-manager-multidistro.md
git add docs/plans/2026-02-20-package-manager-multidistro-design.md
git commit -m "feat(package_manager): multi-distro support (Ubuntu/Fedora/Void) + split tasks by feature"
```

---

## Итоговая структура после плана

```
ansible/roles/package_manager/
├── defaults/main.yml              # расширен: dnf, xbps vars + _pkgmgr_supported_distributions
├── handlers/main.yml              # daemon-reload
├── meta/main.yml                  # Ubuntu/Fedora/Void добавлены
├── tasks/
│   ├── main.yml                   # dispatch по ansible_distribution
│   ├── archlinux.yml              # thin dispatcher → archlinux/*
│   ├── archlinux/
│   │   ├── pacman.yml
│   │   ├── paccache.yml
│   │   └── makepkg.yml
│   ├── debian.yml                 # thin dispatcher → debian/*
│   ├── debian/
│   │   ├── apt.yml
│   │   └── dpkg.yml
│   ├── ubuntu.yml                 # thin dispatcher → ubuntu/*
│   ├── ubuntu/
│   │   ├── apt.yml
│   │   └── dpkg.yml
│   ├── fedora.yml                 # thin dispatcher → fedora/*
│   ├── fedora/
│   │   └── dnf.yml
│   ├── void.yml                   # thin dispatcher → void/*
│   └── void/
│       ├── xbps.yml
│       └── cache.yml
├── templates/
│   ├── archlinux/
│   │   ├── pacman.conf.j2
│   │   └── makepkg.conf.j2
│   ├── debian/
│   │   ├── 10-parallel.conf.j2
│   │   └── 20-dpkg.conf.j2
│   ├── ubuntu/
│   │   ├── 10-parallel.conf.j2
│   │   └── 20-dpkg.conf.j2
│   ├── fedora/
│   │   └── dnf.conf.j2
│   └── void/
│       └── xbps.conf.j2
└── molecule/default/              # без изменений — тестирует Arch
```
