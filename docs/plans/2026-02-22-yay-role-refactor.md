# Yay Role Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Рефакторинг роли `yay` — выделенный `aur_builder` user, двухфазная структура задач `setup-*/manage-*`, разрыв coupling с `packages_*`, надёжный cleanup и ldd-проверка.

**Architecture:** Четыре task-файла с чёткой ответственностью: `setup-aur-builder.yml` (user + sudoers), `setup-yay-binary.yml` (build/install/verify), `manage-aur-packages.yml` (conflict check + install). Старые три файла удаляются. Переменные `yay_build_user` / `yay_aur_url` заменяются на `yay_builder_user` / `yay_source_url`. Coupling разрывается через `packages_official` в group_vars.

**Tech Stack:** Ansible 2.15+, kewlfft.aur collection, community.general.pacman, molecule (verify only)

**Design doc:** `docs/plans/2026-02-22-yay-role-refactor-design.md`

---

## Execution order

Порядок задач важен: сначала тесты (TDD), потом реализация, потом линтинг.

```
Task 1 → defaults/main.yml         (переменные — контракт роли)
Task 2 → group_vars/all/packages.yml (packages_official + обновление yay vars)
Task 3 → molecule/default/verify.yml (тесты СНАЧАЛА — TDD)
Task 4 → setup-aur-builder.yml     (новый файл)
Task 5 → setup-yay-binary.yml      (из install-yay-binary.yml + 3 добавления)
Task 6 → manage-aur-packages.yml   (из install-aur-packages.yml + decoupling)
Task 7 → tasks/main.yml            (оркестратор — обновить include_tasks)
Task 8 → Удалить старые файлы
Task 9 → ansible-lint + commit
```

---

### Task 1: Обновить defaults/main.yml

**Files:**
- Modify: `ansible/roles/yay/defaults/main.yml`

**Step 1: Заменить содержимое файла целиком**

```yaml
---
# === yay: AUR helper — defaults ===
# Переопределяются в group_vars/all/packages.yml

# URL репозитория yay в AUR
yay_source_url: "https://aur.archlinux.org/yay.git"

# Системный пользователь для сборки AUR-пакетов.
# makepkg нельзя запускать от root; этот user НЕ совпадает с личным аккаунтом.
# Ref: https://github.com/kewlfft/ansible-aur#create-the-aur_builder-user
yay_builder_user: "aur_builder"

# Имя файла в /etc/sudoers.d/ для NOPASSWD pacman
yay_builder_sudoers_file: "yay-aur-builder"

# Зависимости для сборки yay из исходников
yay_build_deps:
  - base-devel
  - git
  - go

# AUR package management — заполняются в group_vars/all/packages.yml
packages_aur: []                   # noqa: var-naming[no-role-prefix]
packages_aur_remove_conflicts: []  # noqa: var-naming[no-role-prefix]
packages_official: []              # noqa: var-naming[no-role-prefix]
```

**Step 2: Проверить что файл сохранился корректно**

```bash
cat ansible/roles/yay/defaults/main.yml
```

Ожидаем: `yay_builder_user`, `yay_source_url`, НЕТ `yay_build_user`, НЕТ `yay_aur_url`.

**Step 3: Commit**

```bash
git add ansible/roles/yay/defaults/main.yml
git commit -m "refactor(yay): rename variables — yay_source_url, yay_builder_user; add packages_official"
```

---

### Task 2: Обновить group_vars/all/packages.yml

**Files:**
- Modify: `ansible/inventory/group_vars/all/packages.yml`

**Step 1: Обновить блок yay-переменных (строки 19–29)**

Найти блок:
```yaml
# URL репозитория yay в AUR
yay_aur_url: "https://aur.archlinux.org/yay.git"

# Пользователь для сборки (makepkg не работает от root)
yay_build_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"

# Зависимости для сборки yay из исходников
yay_build_deps:
  - base-devel
  - git
  - go
```

Заменить на:
```yaml
# URL репозитория yay в AUR
yay_source_url: "https://aur.archlinux.org/yay.git"

# Зависимости для сборки yay из исходников
yay_build_deps:
  - base-devel
  - git
  - go
```

**Step 2: Добавить packages_official перед блоком packages_aur_remove_conflicts**

Найти строку:
```yaml
# --- Пакеты конфликтующие с AUR заменами ---
```

Перед ней вставить:
```yaml
# --- Агрегированный список официальных пакетов (для conflict validation в роли yay) ---
# Роль yay не знает о внутренней структуре packages_*; она получает один список.
packages_official: >-
  {{ packages_base
     + packages_editors
     + packages_docker
     + packages_xorg
     + packages_wm
     + packages_filemanager
     + packages_network
     + packages_media
     + packages_desktop
     + packages_graphics
     + packages_session
     + packages_terminal
     + packages_fonts
     + packages_theming
     + packages_search
     + packages_viewers
     + (packages_distro[ansible_facts['os_family']] | default([])) }}

```

**Step 3: Проверить синтаксис YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/inventory/group_vars/all/packages.yml'))" && echo "OK"
```

Ожидаем: `OK`

**Step 4: Commit**

```bash
git add ansible/inventory/group_vars/all/packages.yml
git commit -m "refactor(yay): add packages_official to group_vars; remove yay_build_user"
```

---

### Task 3: Обновить molecule/default/verify.yml (TDD — тесты первыми)

**Files:**
- Modify: `ansible/roles/yay/molecule/default/verify.yml`

**Step 1: Заменить содержимое файла**

```yaml
---
# Molecule verify playbook
# Проверяет что yay корректно установлен после рефакторинга

- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/roles/yay/defaults/main.yml"

  tasks:
    # --- aur_builder user ---
    - name: Check that aur_builder user exists
      ansible.builtin.getent:
        database: passwd
        key: "{{ yay_builder_user }}"
      register: _verify_aur_builder

    - name: Check that aur_builder has nologin shell
      ansible.builtin.assert:
        that: _verify_aur_builder.ansible_facts.getent_passwd[yay_builder_user][5] == '/usr/bin/nologin'
        fail_msg: "aur_builder shell is not /usr/bin/nologin"

    # --- sudoers ---
    - name: Check that sudoers file exists
      ansible.builtin.stat:
        path: "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
      register: _verify_sudoers
      failed_when: not _verify_sudoers.stat.exists

    - name: Check sudoers file mode is 0440
      ansible.builtin.assert:
        that: _verify_sudoers.stat.mode == '0440'
        fail_msg: "sudoers file mode is {{ _verify_sudoers.stat.mode }}, expected 0440"

    - name: Validate sudoers syntax
      ansible.builtin.command: /usr/sbin/visudo -cf "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
      changed_when: false

    # --- yay binary ---
    - name: Check that build dependencies are installed
      ansible.builtin.package:
        name: "{{ item }}"
        state: present
      check_mode: true
      register: _verify_dep_check
      failed_when: _verify_dep_check is changed
      loop: "{{ yay_build_deps }}"

    - name: Check that yay binary exists
      ansible.builtin.command: which yay
      changed_when: false
      register: _verify_yay_path

    - name: Check that yay is executable
      ansible.builtin.command: yay --version
      changed_when: false
      register: _verify_yay_version

    - name: Check that yay has no broken shared libs
      ansible.builtin.command: ldd /usr/bin/yay
      changed_when: false
      register: _verify_yay_ldd
      failed_when: "'not found' in _verify_yay_ldd.stdout"

    # --- cleanup ---
    - name: Check that temp build directory was cleaned up
      ansible.builtin.find:
        paths: /tmp
        patterns: "yay_build_*"
        file_type: directory
      register: _verify_build_dirs
      failed_when: _verify_build_dirs.matched > 0

    # --- AUR packages ---
    - name: Check that AUR packages are installed
      ansible.builtin.command: "pacman -Q {{ item }}"
      loop: "{{ packages_aur }}"
      changed_when: false

    # --- результаты ---
    - name: Show test results
      ansible.builtin.debug:
        msg:
          - "All checks passed!"
          - "aur_builder user: exists, shell=/usr/bin/nologin"
          - "sudoers: /etc/sudoers.d/{{ yay_builder_sudoers_file }} (mode 0440)"
          - "yay binary: {{ _verify_yay_path.stdout }}"
          - "yay version: {{ _verify_yay_version.stdout }}"
          - "yay ldd: OK (no broken shared libs)"
          - "Build deps: installed"
          - "Temp build dirs: cleaned up"
          - "AUR packages: {{ packages_aur | join(', ') }}"
```

**Step 2: Проверить синтаксис YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/yay/molecule/default/verify.yml'))" && echo "OK"
```

Ожидаем: `OK`

**Step 3: Commit**

```bash
git add ansible/roles/yay/molecule/default/verify.yml
git commit -m "test(yay): update molecule verify — aur_builder user, nologin shell, ldd check"
```

---

### Task 4: Создать setup-aur-builder.yml

**Files:**
- Create: `ansible/roles/yay/tasks/setup-aur-builder.yml`

**Step 1: Создать файл**

```yaml
---
# === setup-aur-builder: создание изолированного пользователя для сборки AUR ===
# makepkg нельзя запускать от root.
# Этот user НЕ совпадает с личным аккаунтом — привилегия NOPASSWD: pacman
# ограничена только им.
# Ref: https://github.com/kewlfft/ansible-aur#create-the-aur_builder-user

- name: Create aur_builder system user
  ansible.builtin.user:
    name: "{{ yay_builder_user }}"
    system: true
    create_home: true
    shell: /usr/bin/nologin
    comment: "AUR build user (managed by Ansible)"
  tags: ['aur', 'setup']

- name: Allow aur_builder to run pacman without password
  ansible.builtin.lineinfile:
    path: "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
    line: "{{ yay_builder_user }} ALL=(root) NOPASSWD: /usr/bin/pacman"
    create: true
    mode: '0440'
    owner: root
    group: root
    validate: '/usr/sbin/visudo -cf %s'
  tags: ['aur', 'setup']
```

**Step 2: Проверить синтаксис**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/yay/tasks/setup-aur-builder.yml'))" && echo "OK"
```

**Step 3: Commit**

```bash
git add ansible/roles/yay/tasks/setup-aur-builder.yml
git commit -m "feat(yay): add setup-aur-builder.yml — dedicated system user with NOPASSWD pacman"
```

---

### Task 5: Создать setup-yay-binary.yml

**Files:**
- Create: `ansible/roles/yay/tasks/setup-yay-binary.yml`

Это переименование `install-yay-binary.yml` плюс три новых блока: assert, ldd-проверка, always: cleanup.

**Step 1: Создать файл**

```yaml
---
# === setup-yay-binary: сборка и установка yay из исходников ===

- name: Assert yay_builder_user is not root
  ansible.builtin.assert:
    that: yay_builder_user != 'root'
    fail_msg: >-
      yay_builder_user resolved to 'root' — makepkg cannot run as root.
      Set yay_builder_user explicitly in defaults or group_vars.
  tags: ['aur', 'setup']

- name: Check if yay is already installed
  ansible.builtin.command: yay --version
  register: _yay_exists
  changed_when: false
  failed_when: false
  tags: ['aur', 'setup']

- name: Check for broken yay binary (missing shared libs after Go upgrade)
  ansible.builtin.command: ldd /usr/bin/yay
  register: _yay_ldd
  failed_when: false
  changed_when: false
  when: _yay_exists.rc == 0
  tags: ['aur', 'setup']

- name: Set fact — yay needs rebuild due to broken shared libs
  ansible.builtin.set_fact:
    _yay_needs_rebuild: "{{ 'not found' in (_yay_ldd.stdout | default('')) }}"
  tags: ['aur', 'setup']

- name: Remove broken yay binary to trigger rebuild
  ansible.builtin.file:
    path: /usr/bin/yay
    state: absent
  when: _yay_needs_rebuild | default(false)
  tags: ['aur', 'setup']

- name: Install build dependencies
  community.general.pacman:
    name: "{{ yay_build_deps }}"
    state: present
  when: _yay_exists.rc != 0 or _yay_needs_rebuild | default(false)
  tags: ['aur', 'setup']

- name: Create temp build directory
  become: true
  become_user: "{{ yay_builder_user }}"
  ansible.builtin.tempfile:
    state: directory
    prefix: yay_build_
  register: _yay_build_dir
  when: _yay_exists.rc != 0 or _yay_needs_rebuild | default(false)
  tags: ['aur', 'setup']

- name: Build and install yay
  when: _yay_exists.rc != 0 or _yay_needs_rebuild | default(false)
  tags: ['aur', 'setup']
  block:
    - name: Clone yay from AUR
      become: true
      become_user: "{{ yay_builder_user }}"
      ansible.builtin.git:
        repo: "{{ yay_source_url }}"
        dest: "{{ _yay_build_dir.path }}/yay"
        depth: 1
        version: master

    - name: Build yay package
      become: true
      become_user: "{{ yay_builder_user }}"
      ansible.builtin.command:
        cmd: makepkg --noconfirm
        chdir: "{{ _yay_build_dir.path }}/yay"
      changed_when: true

    - name: Find built yay package
      ansible.builtin.find:
        paths: "{{ _yay_build_dir.path }}/yay"
        patterns: "yay-*.pkg.tar.*"
        excludes: "*-debug-*"
      register: _yay_pkg

    - name: Install yay package
      community.general.pacman:
        name: "{{ _yay_pkg.files[0].path }}"
        state: present

  always:
    - name: Clean up build directory
      ansible.builtin.file:
        path: "{{ _yay_build_dir.path }}"
        state: absent
      when: _yay_build_dir is defined

- name: Verify yay installed
  ansible.builtin.command: yay --version
  register: _yay_version
  changed_when: false
  tags: ['aur', 'setup']

- name: Report yay version
  ansible.builtin.debug:
    msg: "yay установлен: {{ _yay_version.stdout }}"
  tags: ['aur']
```

**Step 2: Проверить синтаксис**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/yay/tasks/setup-yay-binary.yml'))" && echo "OK"
```

**Step 3: Commit**

```bash
git add ansible/roles/yay/tasks/setup-yay-binary.yml
git commit -m "feat(yay): add setup-yay-binary.yml — assert, ldd check, always: cleanup"
```

---

### Task 6: Создать manage-aur-packages.yml

**Files:**
- Create: `ansible/roles/yay/tasks/manage-aur-packages.yml`

Это переименование `install-aur-packages.yml` с заменой хардкода `_yay_packages_all` на `packages_official`.

**Step 1: Создать файл**

```yaml
---
# === manage-aur-packages: установка AUR пакетов через yay ===
# Использует yay backend из kewlfft.aur.
# Требует NOPASSWD sudoers для pacman (настраивается в setup-aur-builder.yml).
# Контракт: caller передаёт packages_official и packages_aur из group_vars.

- name: Remove packages conflicting with AUR replacements
  community.general.pacman:
    name: "{{ packages_aur_remove_conflicts }}"
    state: absent
  when: packages_aur_remove_conflicts | length > 0
  tags: ['install', 'aur']

- name: Validate AUR packages don't conflict with official packages
  ansible.builtin.script:
    cmd: validate-aur-conflicts.sh
  environment:
    AUR_PACKAGES: "{{ packages_aur | join('\n') }}"
    OFFICIAL_PACKAGES: "{{ packages_official | join('\n') }}"
    CONFLICT_EXCEPTIONS: "{{ packages_aur_remove_conflicts | join('\n') }}"
  changed_when: false
  tags: ['install', 'aur']

- name: Install AUR packages
  kewlfft.aur.aur:
    name: "{{ packages_aur }}"
    use: yay
    state: present
  become: true
  become_user: "{{ yay_builder_user }}"
  tags: ['install', 'aur']
```

**Step 2: Проверить синтаксис**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/yay/tasks/manage-aur-packages.yml'))" && echo "OK"
```

**Step 3: Commit**

```bash
git add ansible/roles/yay/tasks/manage-aur-packages.yml
git commit -m "feat(yay): add manage-aur-packages.yml — decouple from packages_* via packages_official"
```

---

### Task 7: Обновить tasks/main.yml

**Files:**
- Modify: `ansible/roles/yay/tasks/main.yml`

**Step 1: Заменить содержимое**

```yaml
---
# === yay: AUR helper installation + AUR package management ===

- name: Ensure host is Arch Linux
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] == 'Archlinux'
    fail_msg: "yay role requires Arch Linux"
  tags: ['aur', 'setup', 'install']

- name: Set up AUR builder user
  ansible.builtin.include_tasks: setup-aur-builder.yml
  tags: ['aur', 'setup']

- name: Set up yay binary
  ansible.builtin.include_tasks: setup-yay-binary.yml
  tags: ['aur', 'setup']

- name: Manage AUR packages
  ansible.builtin.include_tasks: manage-aur-packages.yml
  when: packages_aur | default([]) | length > 0
  tags: ['aur', 'install']
```

**Step 2: Проверить синтаксис**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/yay/tasks/main.yml'))" && echo "OK"
```

**Step 3: Commit**

```bash
git add ansible/roles/yay/tasks/main.yml
git commit -m "refactor(yay): update main.yml orchestrator — two-phase setup-*/manage-* structure"
```

---

### Task 8: Удалить старые файлы

**Files:**
- Delete: `ansible/roles/yay/tasks/install-yay-binary.yml`
- Delete: `ansible/roles/yay/tasks/configure-sudoers.yml`
- Delete: `ansible/roles/yay/tasks/install-aur-packages.yml`

**Step 1: Удалить файлы**

```bash
git rm ansible/roles/yay/tasks/install-yay-binary.yml \
       ansible/roles/yay/tasks/configure-sudoers.yml \
       ansible/roles/yay/tasks/install-aur-packages.yml
```

**Step 2: Убедиться что в tasks/ только нужные файлы**

```bash
ls ansible/roles/yay/tasks/
```

Ожидаем:
```
main.yml
manage-aur-packages.yml
setup-aur-builder.yml
setup-yay-binary.yml
```

**Step 3: Commit**

```bash
git commit -m "refactor(yay): remove old task files — install-yay-binary, configure-sudoers, install-aur-packages"
```

---

### Task 9: Lint и финальная валидация

**Step 1: Запустить ansible-lint через /ansible skill на VM**

```bash
# Через /ansible skill:
ansible-lint ansible/roles/yay/
```

Ожидаем: 0 ошибок / только informational warnings.

**Step 2: Проверить синтаксис всей роли через ansible**

```bash
ansible-playbook ansible/playbooks/workstation.yml --syntax-check
```

Ожидаем: `playbook: ansible/playbooks/workstation.yml`

**Step 3: Если lint чистый — commit итогового состояния**

```bash
git log --oneline -8
```

Убедиться что все 8 коммитов выше присутствуют.

**Step 4: Опциональный smoke-test на VM**

Запустить только yay-теги чтобы убедиться что роль отрабатывает без ошибок:

```bash
# Через /ansible skill на VM:
ansible-playbook ansible/playbooks/workstation.yml --tags aur --check
```

---

## Итог

После выполнения всех задач:

| Файл | Статус |
|------|--------|
| `tasks/main.yml` | Обновлён |
| `tasks/setup-aur-builder.yml` | Создан |
| `tasks/setup-yay-binary.yml` | Создан |
| `tasks/manage-aur-packages.yml` | Создан |
| `tasks/install-yay-binary.yml` | Удалён |
| `tasks/configure-sudoers.yml` | Удалён |
| `tasks/install-aur-packages.yml` | Удалён |
| `defaults/main.yml` | Обновлён |
| `molecule/default/verify.yml` | Обновлён |
| `inventory/group_vars/all/packages.yml` | Обновлён |

**Инварианты (не трогаем):**
- `files/validate-aur-conflicts.sh`
- `molecule/default/molecule.yml`
- `molecule/default/converge.yml`
- `meta/main.yml`
