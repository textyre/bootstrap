# Design: Рефакторинг роли `yay`

**Дата:** 2026-02-22
**Статус:** Approved
**Контекст:** Анализ выявил несколько архитектурных проблем в роли — смешение ответственностей, небезопасный build user, tight coupling с переменными других ролей, ненадёжный cleanup.

---

## Проблемы, которые решаем

| # | Проблема | Критичность |
|---|---------|-------------|
| P1 | Build user = SUDO_USER рабочей станции → получает NOPASSWD: pacman | HIGH |
| P2 | configure-sudoers.yml смешивает создание user и sudoers (SRP нарушен) | MEDIUM |
| P3 | install-aur-packages.yml хардкодит 15+ переменных других ролей | MEDIUM |
| P4 | Cleanup временного каталога только при success, не в always: | MEDIUM |
| P5 | Нет проверки сломанного yay после Go upgrade (broken shared libs) | MEDIUM |
| P6 | Нет assert: yay_builder_user != 'root' | MEDIUM |
| P7 | Имена файлов не отражают семантику (install vs setup vs manage) | LOW |

---

## Архитектура: двухфазная структура

### Структура файлов

**Было:**
```
tasks/
  main.yml
  install-yay-binary.yml
  configure-sudoers.yml
  install-aur-packages.yml
```

**Станет:**
```
tasks/
  main.yml                  # оркестратор: assert + 3 include_tasks
  setup-aur-builder.yml     # NEW — user creation + sudoers (фаза setup)
  setup-yay-binary.yml      # RENAME — build/install/verify yay (фаза setup)
  manage-aur-packages.yml   # RENAME — conflict check + package install (фаза manage)
```

**Семантика именования:**
- `setup-*` — разовые задачи инициализации инфраструктуры
- `manage-*` — повторяемое управление желаемым состоянием

### main.yml — линейный оркестратор

```yaml
- name: Ensure host is Arch Linux
  ansible.builtin.assert: ...

- name: Set up AUR builder user
  ansible.builtin.include_tasks: setup-aur-builder.yml
  tags: ['aur', 'setup']

- name: Set up yay binary
  ansible.builtin.include_tasks: setup-yay-binary.yml
  tags: ['aur', 'setup']

- name: Manage AUR packages
  ansible.builtin.include_tasks: manage-aur-packages.yml
  when: packages_aur | default([]) | length > 0
  tags: ['aur', 'manage']
```

---

## Компоненты

### setup-aur-builder.yml (новый файл)

Создаёт изолированного системного пользователя для сборки AUR-пакетов.
makepkg нельзя запускать от root; этот user не совпадает с личным аккаунтом.

```yaml
- name: Create aur_builder system user
  ansible.builtin.user:
    name: "{{ yay_builder_user }}"
    system: true
    create_home: true
    shell: /usr/bin/nologin
    comment: "AUR build user (managed by Ansible)"

- name: Allow aur_builder to run pacman without password
  ansible.builtin.lineinfile:
    path: "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
    line: "{{ yay_builder_user }} ALL=(root) NOPASSWD: /usr/bin/pacman"
    create: true
    mode: '0440'
    owner: root
    group: root
    validate: '/usr/sbin/visudo -cf %s'
```

### setup-yay-binary.yml (переименование + 3 добавления)

**Добавление 1: Assert build user не root**
```yaml
- name: Assert yay_builder_user is not root
  ansible.builtin.assert:
    that: yay_builder_user != 'root'
    fail_msg: >-
      yay_builder_user resolved to 'root' — makepkg cannot run as root.
      Set yay_builder_user explicitly in defaults or group_vars.
```

**Добавление 2: ldd-проверка сломанного бинаря**
```yaml
- name: Check for broken yay binary (missing shared libs after Go upgrade)
  ansible.builtin.command: ldd /usr/bin/yay
  register: _yay_ldd
  failed_when: false
  changed_when: false
  when: _yay_exists.rc == 0

- name: Set fact — yay needs rebuild
  ansible.builtin.set_fact:
    _yay_needs_rebuild: "{{ 'not found' in (_yay_ldd.stdout | default('')) }}"

- name: Remove broken yay binary to trigger rebuild
  ansible.builtin.file:
    path: /usr/bin/yay
    state: absent
  when: _yay_needs_rebuild | default(false)
```

**Добавление 3: Cleanup в always: блоке**
```yaml
- name: Build and install yay
  when: _yay_exists.rc != 0 or _yay_needs_rebuild | default(false)
  block:
    - name: Clone yay from AUR
      ...
    - name: Build yay package
      ...
    - name: Install yay package
      ...
  always:
    - name: Clean up build directory
      ansible.builtin.file:
        path: "{{ _yay_build_dir.path }}"
        state: absent
      when: _yay_build_dir is defined
```

### manage-aur-packages.yml (переименование + разрыв coupling)

**Было:**
```yaml
- name: Build combined official package list
  ansible.builtin.set_fact:
    _yay_packages_all: >-
      {{ packages_base + packages_editors + packages_docker + packages_xorg
         + packages_wm + packages_filemanager + packages_network + packages_media
         + packages_desktop + packages_graphics + packages_session + packages_terminal
         + packages_fonts + packages_theming + packages_search + packages_viewers
         + (packages_distro[ansible_facts['os_family']] | default([])) }}
```

**Станет:**
```yaml
# set_fact удаляется полностью
# Переменная packages_official передаётся из group_vars/all/packages.yml

- name: Validate AUR packages don't conflict with official packages
  ansible.builtin.script:
    cmd: validate-aur-conflicts.sh
  environment:
    AUR_PACKAGES: "{{ packages_aur | join('\n') }}"
    OFFICIAL_PACKAGES: "{{ packages_official | join('\n') }}"
    CONFLICT_EXCEPTIONS: "{{ packages_aur_remove_conflicts | join('\n') }}"
```

---

## Изменения переменных

### defaults/main.yml

| Было | Станет | Изменение |
|------|--------|-----------|
| `yay_aur_url` | `yay_source_url` | переименование |
| `yay_build_user` | — | удаляется |
| `yay_build_deps` | `yay_build_deps` | без изменений |
| — | `yay_builder_user: aur_builder` | НОВАЯ |
| — | `yay_builder_sudoers_file: yay-aur-builder` | НОВАЯ |
| — | `packages_official: []` | НОВАЯ (заполняется в group_vars) |
| `packages_aur` | `packages_aur` | без изменений |
| `packages_aur_remove_conflicts` | `packages_aur_remove_conflicts` | без изменений |

### group_vars/all/packages.yml

Добавляется `packages_official` — агрегированный список всех официальных пакетов:

```yaml
packages_official: >-
  {{ packages_base + packages_editors + packages_docker + packages_xorg
     + packages_wm + packages_filemanager + packages_network + packages_media
     + packages_desktop + packages_graphics + packages_session + packages_terminal
     + packages_fonts + packages_theming + packages_search + packages_viewers
     + (packages_distro[ansible_facts['os_family']] | default([])) }}
```

---

## Molecule tests

`molecule/default/verify.yml` обновляется:

- Добавить проверку: `aur_builder` user существует и `shell == /usr/bin/nologin`
- Добавить проверку: sudoers файл `/etc/sudoers.d/yay-aur-builder` существует
- Убрать проверку: `/etc/sudoers.d/yay-pacman` (старое имя файла)
- Добавить проверку: `/tmp/yay_build_*` не существует (уже есть, оставить)
- Обновить references: `yay_build_user` → `yay_builder_user`

---

## Контракт роли (публичный интерфейс)

**Входные переменные (обязательные для manage-фазы):**
- `packages_aur: []` — список AUR-пакетов для установки
- `packages_official: []` — агрегированный список официальных пакетов (для conflict check)
- `packages_aur_remove_conflicts: []` — пакеты, которым разрешено конфликтовать

**Входные переменные (опциональные, с defaults):**
- `yay_builder_user: aur_builder`
- `yay_source_url: https://aur.archlinux.org/yay.git`
- `yay_build_deps: [base-devel, git, go]`

**Гарантии роли:**
1. yay установлен и исполняем (`yay --version` → 0)
2. `aur_builder` user существует с `shell: /usr/bin/nologin`
3. `/etc/sudoers.d/yay-aur-builder` существует, валиден, mode 0440
4. `/tmp/yay_build_*` не существует после завершения (успех или ошибка)
5. AUR-пакеты из `packages_aur` установлены
6. AUR-пакеты не конфликтуют с `packages_official`

---

## Что НЕ меняется

- `validate-aur-conflicts.sh` — логика скрипта не трогается
- `molecule/default/molecule.yml` и `converge.yml`
- `meta/main.yml`
- Зависимость от `kewlfft.aur` collection
- Логика `packages_aur_remove_conflicts`
