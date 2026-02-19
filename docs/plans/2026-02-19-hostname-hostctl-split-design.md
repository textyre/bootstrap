# Design: hostname/hostctl Role Split

**Date:** 2026-02-19
**Scope:** Ansible roles `hostname` и `hostctl`
**Approach:** Чистый split — две независимые роли (Approach A)

---

## Проблема

Роль `hostname` нарушает SRP: она устанавливает имя машины, управляет `/etc/hosts` и устанавливает/конфигурирует `hostctl` — три разных ответственности. Кроме того, `hostname_name: "archbox"` — конкретный хардкод в defaults, URL GitHub жёстко прописаны в задачах.

---

## Решение

Разделить на две независимые роли:

- `hostname` — имя машины + `127.0.1.1` запись в `/etc/hosts`
- `hostctl` — новая роль: установка инструмента + управление профилями

Роли не зависят друг от друга. Оба запускаются в `workstation.yml` независимо.

---

## Роль `hostname` — изменения

### Что убирается

| Файл | Действие |
|---|---|
| `defaults/main.yml` | Удалить `hostname_hostctl_*` переменные |
| `tasks/hostctl.yml` | Удалить файл |
| `tasks/hostctl_download.yml` | Удалить файл |
| `templates/hostctl_profile.j2` | Перенести в `hostctl` роль |

### Новый `defaults/main.yml`

```yaml
hostname_name: ""    # REQUIRED — assert проверит
hostname_domain: ""  # Опционально: FQDN суффикс ("example.com")
```

### Assert в начале `tasks/main.yml`

```yaml
- name: Assert hostname_name is provided
  ansible.builtin.assert:
    that:
      - hostname_name is defined
      - hostname_name | length > 0
    fail_msg: "hostname_name is required. Set it in group_vars or playbook vars."
```

### Что остаётся без изменений

- `tasks/main.yml` — set hostname + verify + report
- `tasks/hosts.yml` — `127.0.1.1` в `/etc/hosts` + verify
- `vars/main.yml` — `_hostname_strategy` маппинг по OS family
- `molecule/` — минимальная правка (убрать hostctl vars из converge)

---

## Роль `hostctl` — новая

### Структура файлов

```
ansible/roles/hostctl/
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
├── molecule/
│   └── default/
│       ├── converge.yml
│       ├── molecule.yml
│       └── verify.yml
├── tasks/
│   ├── main.yml        ← orchestrator: assert + include install + include profiles
│   ├── install.yml     ← pkg manager (non-Arch), AUR (Arch), GitHub fallback
│   ├── download.yml    ← GitHub fallback с block/rescue/always
│   └── profiles.yml    ← deploy /etc/hostctl/*.hosts + verify
├── templates/
│   └── profile.j2      ← перенесён из hostname/templates/hostctl_profile.j2
└── vars/
    └── main.yml        ← _arch_map (x86_64→amd64, aarch64→arm64, armv7l→armv6)
```

### `defaults/main.yml` — все переменные `hostctl_*`

```yaml
hostctl_enabled: true
hostctl_version: "latest"              # "latest" или конкретная "1.1.4"
hostctl_install_dir: /usr/local/bin
hostctl_github_repo: "guumaster/hostctl"
hostctl_github_api: "https://api.github.com"
hostctl_verify_checksum: true          # fail если checksum недоступен
hostctl_profiles: {}
# Пример:
#   hostctl_profiles:
#     dev:
#       - { ip: "127.0.0.1", host: "app.local" }
#     docker:
#       - { ip: "172.17.0.1", host: "registry.local" }
```

### `tasks/install.yml` — версионная идемпотентность

```yaml
# Проверить установленную версию
- name: Get installed hostctl version
  ansible.builtin.command: hostctl --version
  register: _hostctl_installed_ver
  changed_when: false
  failed_when: false

# Пропустить установку если версия совпадает (и не "latest")
- name: Skip install if version matches
  ansible.builtin.set_fact:
    _hostctl_skip_install: >-
      {{ _hostctl_installed_ver.rc == 0
         and hostctl_version != "latest"
         and hostctl_version in _hostctl_installed_ver.stdout }}

# Установка через pkg manager → AUR → GitHub fallback
# ... (только если не _hostctl_skip_install)
```

### `tasks/download.yml` — block/rescue/always для cleanup

```yaml
- name: Install hostctl from GitHub releases
  block:
    - name: Query GitHub API for release
      ansible.builtin.uri: ...
    - name: Download hostctl archive
      ansible.builtin.get_url: ...
    - name: Verify archive exists
      ansible.builtin.stat:
        path: /tmp/hostctl.tar.gz
      register: _hostctl_archive_stat
    - name: Assert archive downloaded
      ansible.builtin.assert:
        that: _hostctl_archive_stat.stat.exists
    - name: Create temp extraction dir
      ansible.builtin.tempfile: ...
    - name: Extract archive
      ansible.builtin.unarchive: ...
    - name: Assert binary extracted
      ansible.builtin.stat:
        path: "{{ _hostctl_tmpdir.path }}/hostctl"
      register: _hostctl_bin_stat
    - name: Assert binary exists and executable
      ansible.builtin.assert:
        that:
          - _hostctl_bin_stat.stat.exists
          - _hostctl_bin_stat.stat.executable
    - name: Install binary
      ansible.builtin.copy: ...
    - name: Verify installation
      ansible.builtin.command: "{{ hostctl_install_dir }}/hostctl --version"
      register: _hostctl_verify
      failed_when: _hostctl_verify.rc != 0
  always:
    - name: Cleanup tmp files
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /tmp/hostctl.tar.gz
        - "{{ _hostctl_tmpdir.path | default('') }}"
      when: item | length > 0
```

### `tasks/profiles.yml` — deploy + verify

```yaml
- name: Create /etc/hostctl directory
  ansible.builtin.file:
    path: /etc/hostctl
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Deploy hostctl profile files
  ansible.builtin.template:
    src: profile.j2
    dest: "/etc/hostctl/{{ item.key }}.hosts"
    owner: root
    group: root
    mode: '0644'
  loop: "{{ hostctl_profiles | dict2items }}"
  notify: apply hostctl profiles

- name: Verify profile files deployed
  ansible.builtin.stat:
    path: "/etc/hostctl/{{ item.key }}.hosts"
  register: _hostctl_profile_stat
  loop: "{{ hostctl_profiles | dict2items }}"

- name: Assert all profiles exist
  ansible.builtin.assert:
    that: item.stat.exists
    fail_msg: "Profile file missing: {{ item.item.key }}.hosts"
  loop: "{{ _hostctl_profile_stat.results }}"
```

### `handlers/main.yml` — с `listen:` по проектным конвенциям

```yaml
- name: Apply hostctl profiles
  ansible.builtin.command:
    cmd: "hostctl replace {{ item.key }} --from /etc/hostctl/{{ item.key }}.hosts"
  loop: "{{ hostctl_profiles | dict2items }}"
  listen: "apply hostctl profiles"
  changed_when: true
```

> **Важно:** использовать `hostctl replace`, НЕ `hostctl restore`.
> `hostctl restore` восстанавливает из бэкапа, который создаётся при первой инициализации
> — до того как hostname роль добавила `127.0.1.1`. Вызов `restore` сотрёт эту запись.
> `hostctl replace <profile>` меняет только именованную секцию между маркерами,
> не трогая базовые записи выше маркера.

### `hostctl_verify_checksum` логика

```yaml
- name: Fail if checksum required but unavailable
  ansible.builtin.fail:
    msg: "hostctl_verify_checksum is true but no checksum file found in release assets"
  when:
    - hostctl_verify_checksum
    - _hostctl_checksums_url | length == 0
```

### Molecule тесты

`converge.yml` — устанавливает hostctl с одним тестовым профилем.
`verify.yml` — проверяет:
- `hostctl --version` возвращает rc=0
- `/etc/hostctl/test.hosts` существует
- `hostctl list` показывает профиль

---

## Интеграция

### `workstation.yml`

```yaml
- role: hostname
  tags: [system, hostname]

- role: hostctl
  tags: [system, hostctl]
```

### Taskfile — добавить запись для hostctl

По аналогии с существующими ролями (проверить конвенцию в Taskfile).

### `inventory/group_vars/`

- Убрать `hostname_hostctl_*` переменные
- Добавить `hostctl_*` переменные где нужны профили

---

## Порядок реализации

1. Scaffold `hostctl` роль через `/ansible-role-creator`
2. Перенести код из `hostname` → `hostctl` (tasks, template)
3. Параметризовать URL и пути в `hostctl/defaults/main.yml`
4. Добавить версионную идемпотентность в `install.yml`
5. Обернуть download в `block/rescue/always`
6. Добавить `hostctl_verify_checksum` логику
7. Добавить handler с `listen:`
8. Написать Molecule для `hostctl`
9. Рефакторить `hostname`: убрать hostctl-код, добавить assert
10. Обновить `hostname` Molecule (убрать hostctl vars)
11. Обновить `workstation.yml` и Taskfile
12. Синтаксис-чек обеих ролей

---

## Не делаем (YAGNI)

- Зависимость через meta (выбран clean split)
- `hostctl` не вызывает `hostname` и не знает о нём
- Логирование через `common/report_phase.yml` остаётся в `hostctl` если уже есть (не удалять)
