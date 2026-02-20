# package_manager Role Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Рефакторинг `ansible/roles/package_manager` — замена `lineinfile` на Jinja2-шаблоны, добавление paccache timer, makepkg.conf drop-in и реальной конфигурации apt для Debian.

**Architecture:** `pacman.conf.j2` — полный шаблон с условными секциями (options + repos). Debian использует нативный `/etc/apt/apt.conf.d/` conf.d-паттерн. paccache настраивается через systemd drop-in. makepkg — через `/etc/makepkg.conf.d/ansible.conf`.

**Tech Stack:** Ansible 2.15+, Jinja2, systemd, pacman, apt

**Run commands via:** `/ansible` skill (remote VM). Never run Ansible/molecule locally.

---

### Task 1: Обновить molecule tests (TDD — сначала тесты)

**Files:**
- Modify: `ansible/roles/package_manager/molecule/default/converge.yml`
- Modify: `ansible/roles/package_manager/molecule/default/verify.yml`
- Modify: `ansible/roles/package_manager/molecule/default/molecule.yml`

**Step 1: Убрать vault из converge.yml**

Заменить содержимое `molecule/default/converge.yml`:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  pre_tasks:
    - name: Ensure we're running on Arch Linux
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] == 'Archlinux'
        fail_msg: "This test requires Arch Linux"

  roles:
    - role: package_manager
```

**Step 2: Убрать vault из molecule.yml**

Заменить секцию `provisioner.config_options.defaults`:

```yaml
provisioner:
  name: ansible
  config_options:
    defaults:
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
```

**Step 3: Переписать verify.yml с новыми ассертами**

Заменить содержимое `molecule/default/verify.yml`:

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Check pacman.conf is managed by Ansible
      ansible.builtin.command: grep -q 'Managed by Ansible' /etc/pacman.conf
      changed_when: false

    - name: Check pacman.conf has ParallelDownloads
      ansible.builtin.command: grep -q '^ParallelDownloads' /etc/pacman.conf
      changed_when: false

    - name: Check pacman.conf has Color
      ansible.builtin.command: grep -q '^Color' /etc/pacman.conf
      changed_when: false

    - name: Check pacman.conf has VerbosePkgLists
      ansible.builtin.command: grep -q '^VerbosePkgLists' /etc/pacman.conf
      changed_when: false

    - name: Check paccache.timer is enabled
      ansible.builtin.command: systemctl is-enabled paccache.timer
      register: _verify_paccache_timer
      changed_when: false
      failed_when: _verify_paccache_timer.rc != 0

    - name: Check makepkg.conf.d/ansible.conf exists
      ansible.builtin.stat:
        path: /etc/makepkg.conf.d/ansible.conf
      register: _verify_makepkg
      failed_when: not _verify_makepkg.stat.exists

    - name: Show verify results
      ansible.builtin.debug:
        msg:
          - "pacman.conf: managed by Ansible, ParallelDownloads + Color + VerbosePkgLists present"
          - "paccache.timer: enabled"
          - "makepkg.conf.d/ansible.conf: exists"
```

**Step 4: Запустить molecule — ожидаем FAIL на verify**

```bash
cd /path/to/project && molecule test -s default
```

Ожидается: syntax pass, converge pass (lineinfile-таски ещё работают), verify FAIL — `grep 'Managed by Ansible'` не найдёт строку.

---

### Task 2: Расширить defaults/main.yml

**Files:**
- Modify: `ansible/roles/package_manager/defaults/main.yml`

**Step 1: Заменить содержимое файла**

```yaml
---
# === Конфигурация пакетного менеджера ===

# Поддерживаемые OS families
_pkgmgr_supported_os:
  - Archlinux
  - Debian

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
```

---

### Task 3: Создать handlers/main.yml

**Files:**
- Create: `ansible/roles/package_manager/handlers/main.yml`

**Step 1: Создать файл**

```yaml
---
- name: daemon-reload
  ansible.builtin.systemd:
    daemon_reload: true
```

---

### Task 4: Создать шаблон templates/archlinux/pacman.conf.j2

**Files:**
- Create: `ansible/roles/package_manager/templates/archlinux/pacman.conf.j2`

**Step 1: Создать директорию и файл**

```jinja2
# Managed by Ansible — do not edit manually
# Role: package_manager

[options]
HoldPkg     = pacman glibc
Architecture = auto
{% if pkgmgr_pacman_color %}
Color
{% endif %}
{% if pkgmgr_pacman_check_space %}
CheckSpace
{% endif %}
{% if pkgmgr_pacman_verbose_pkg_lists %}
VerbosePkgLists
{% endif %}
ParallelDownloads = {{ pkgmgr_pacman_parallel_downloads }}
SigLevel    = {{ pkgmgr_pacman_siglevel }}
LocalFileSigLevel = Optional
{% if pkgmgr_pacman_external_cache and pkgmgr_pacman_cache_root %}
CacheDir    = {{ pkgmgr_pacman_cache_root }}/var/cache/pacman/pkg/
DBPath      = {{ pkgmgr_pacman_cache_root }}/var/lib/pacman/
LogFile     = /var/log/pacman.log
GPGDir      = /etc/pacman.d/gnupg/
HookDir     = /etc/pacman.d/hooks/
{% endif %}

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
{% if pkgmgr_pacman_multilib %}

[multilib]
Include = /etc/pacman.d/mirrorlist
{% endif %}
```

---

### Task 5: Создать шаблон templates/archlinux/makepkg.conf.j2

**Files:**
- Create: `ansible/roles/package_manager/templates/archlinux/makepkg.conf.j2`

**Step 1: Создать файл**

```jinja2
# Managed by Ansible — do not edit manually
# Role: package_manager

MAKEFLAGS="{{ pkgmgr_makepkg_makeflags }}"
PKGEXT='{{ pkgmgr_makepkg_pkgext }}'
```

---

### Task 6: Создать шаблоны для Debian

**Files:**
- Create: `ansible/roles/package_manager/templates/debian/10-parallel.conf.j2`
- Create: `ansible/roles/package_manager/templates/debian/20-dpkg.conf.j2`

**Step 1: 10-parallel.conf.j2**

```jinja2
// Managed by Ansible — do not edit manually
// Role: package_manager

Acquire::Queue-Mode "{{ pkgmgr_apt_parallel_queue_mode }}";
Acquire::Retries "{{ pkgmgr_apt_retries }}";
```

**Step 2: 20-dpkg.conf.j2**

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

### Task 7: Переписать tasks/archlinux.yml

**Files:**
- Modify: `ansible/roles/package_manager/tasks/archlinux.yml`

**Step 1: Заменить содержимое файла**

```yaml
---
# === Arch Linux: конфигурация pacman, paccache, makepkg ===

# ---- Валидация входных данных ----

- name: Assert external cache config is valid
  ansible.builtin.assert:
    that:
      - pkgmgr_pacman_cache_root | length > 0
    msg: "pkgmgr_pacman_cache_root must be set when pkgmgr_pacman_external_cache is true"
  when: pkgmgr_pacman_external_cache
  tags: ['packages', 'pacman']

# ---- Конфигурация pacman ----

- name: Deploy pacman.conf from template
  ansible.builtin.template:
    src: archlinux/pacman.conf.j2
    dest: /etc/pacman.conf
    owner: root
    group: root
    mode: '0644'
    backup: true
  tags: ['packages', 'pacman']

# ---- Внешний кэш (опционально) ----

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

# ---- paccache (очистка кэша) ----

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

# ---- makepkg ----

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

---

### Task 8: Переписать tasks/debian.yml

**Files:**
- Modify: `ansible/roles/package_manager/tasks/debian.yml`

**Step 1: Заменить содержимое файла**

```yaml
---
# === Debian/Ubuntu: конфигурация apt ===

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

- name: Deploy apt dpkg options config
  ansible.builtin.template:
    src: debian/20-dpkg.conf.j2
    dest: /etc/apt/apt.conf.d/20-ansible-dpkg.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['packages', 'apt']
```

---

### Task 9: Запустить molecule — убедиться что все verify проходят

**Step 1: Запустить полный тестовый цикл**

Используй `/ansible` skill:
```bash
cd /path/to/project
molecule test -s default -- --diff
```

Ожидается: syntax ✓ → converge ✓ → verify ✓ (все 7 ассертов зелёные).

**Step 2: Если verify падает — диагностировать**

Используй `/ansible-debug` skill.

**Step 3: Запустить ansible-lint**

```bash
ansible-lint ansible/roles/package_manager/
```

Ожидается: 0 violations.

**Step 4: Commit**

```bash
git add ansible/roles/package_manager/
git commit -m "feat(package_manager): refactor to Jinja2 templates, add paccache timer and makepkg conf"
```

---

## Итоговая структура роли после рефакторинга

```
ansible/roles/package_manager/
├── defaults/main.yml              # расширен: paccache, makepkg, apt vars
├── handlers/main.yml              # NEW: daemon-reload
├── tasks/
│   ├── main.yml                   # без изменений (OS dispatch)
│   ├── archlinux.yml              # переписан: template + paccache + makepkg
│   └── debian.yml                 # переписан: apt.conf.d templates
├── templates/
│   ├── archlinux/
│   │   ├── pacman.conf.j2         # NEW: полный шаблон
│   │   └── makepkg.conf.j2        # NEW: makepkg drop-in
│   └── debian/
│       ├── 10-parallel.conf.j2    # NEW: apt parallel
│       └── 20-dpkg.conf.j2        # NEW: dpkg options
├── meta/main.yml                  # без изменений
└── molecule/default/
    ├── molecule.yml               # убран vault
    ├── converge.yml               # убран vault
    └── verify.yml                 # переписан: новые ассерты
```

## Контракты из 50, закрытые этим планом

1 (OS-agnostic), 3 (настройка PM), 4 (кэш + CacheDir), 6 (параллельные загрузки),
10 (подписи через SigLevel), 12 (неинтерактивный режим через dpkg options),
13 (очистка кэша — paccache timer), 18 (идемпотентность — template vs lineinfile),
26 (валидация переменных), 27 (fail при неверном конфиге), 31 (Jinja2 шаблон),
32 (полное состояние конфига), 33 (backup), 38 (установка ≠ настройка),
46 (zero changed при повторном запуске), 50 (новая OS — новый файл tasks).
