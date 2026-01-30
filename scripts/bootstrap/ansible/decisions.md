# Decisions Log

## Дата: 2026-01-28 — 2026-01-29

---

## 1. PATH для venv в Taskfile

**Задача:** Команды из `.venv/bin/` (ansible-playbook, molecule) должны быть доступны в Taskfile.

**Сделали:** Используем PREFIX переменную с `env PATH=...`:
```yaml
vars:
  PREFIX: 'env PATH="{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"'

tasks:
  check:
    cmds:
      - '{{.PREFIX}} ansible-playbook ...'
```

**Пробовали:**
```yaml
# Глобальный env - не работает
env:
  PATH: "{{.TASKFILE_DIR}}/.venv/bin:{{.PATH}}"  # {{.PATH}} не существует

# sh: - не работает
PATH:
  sh: echo "{{.TASKFILE_DIR}}/.venv/bin:$PATH"

# bash -c wrapper - работает, но громоздко
- bash -c 'export PATH="..." && molecule test'
```

**Не получилось:** `{{.PATH}}` не является встроенной переменной Taskfile. OS env vars имеют приоритет над Taskfile env.

**Ресурсы:**
- [GitHub Issue #482 - Changing PATH env var doesn't seem to work](https://github.com/go-task/task/issues/482)
- [GitHub Issue #202 - PATH modification](https://github.com/go-task/task/issues/202)
- [GitHub Issue #2034 - Variables Megathread](https://github.com/go-task/task/issues/2034)

---

## 2. Sudo пароль для Ansible (Ansible Vault)

**Задача:** Ansible требует sudo пароль для задач с `become: true`. Нужно безопасное решение, работающее через SSH сессии.

**Сделали:** Ansible Vault — пароль зашифрован (AES-256), безопасен для git.

1. `inventory/group_vars/all/vault.yml` — зашифрованный файл с `ansible_become_password`
2. `vault-pass.sh` — каскадный скрипт для vault пароля: `pass` → `~/.vault-pass` → ошибка
3. `ansible.cfg` → `vault_password_file = ./vault-pass.sh`
4. Molecule: `config_options.defaults.vault_password_file` + `vars_files` в converge/verify

```bash
# Первоначальная настройка (один раз):
echo 'vault_password' > ~/.vault-pass && chmod 600 ~/.vault-pass
ansible-vault create inventory/group_vars/all/vault.yml
# Содержимое: ansible_become_password: "your_sudo_password"

# Запуск тестов — пароль не нужен:
task test

# После bootstrap: vault пароль можно перенести в pass
pass insert ansible/vault-password
```

**Пробовали:**
1. `MOLECULE_SUDO_PASS` в `~/.bashrc` — не работает через SSH (non-interactive shell), небезопасно
2. `sudo -v` + keep-alive — не сохраняется между SSH сессиями
3. Environment variable — не персистентна, требует `.bashrc` хаки

**Почему Ansible Vault:**
- Шифрование AES-256, безопасен для git
- Работает через SSH (файл на диске, не в памяти)
- Разделение паролей (vault пароль ≠ sudo пароль)
- CI/CD: `ANSIBLE_VAULT_PASSWORD_FILE` env var
- Enterprise стандарт (Red Hat, AWS)

**Ресурсы:**
- [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [Ansible become password](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html)

---

## 3. Molecule драйвер для localhost

**Задача:** Тестировать роль на локальной Arch Linux VM.

**Сделали:**
```yaml
driver:
  name: default
  options:
    managed: false  # Не управлять инфраструктурой

platforms:
  - name: localhost

provisioner:
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
```

**Пробовали:** `molecule-plugins[delegated]` в requirements.txt

**Не получилось:** Избыточно — в Molecule 25.x драйвер `default` встроен.

**Ресурсы:**
- [Molecule Configuration - Driver](https://docs.ansible.com/projects/molecule/configuration/)
- `managed: false` — Molecule не создаёт/удаляет инстансы

---

## 4. os_family для Arch Linux

**Задача:** Проверка что роль запускается только на Arch.

**Сделали:**
```yaml
- ansible_facts['os_family'] == 'Archlinux'  # НЕ 'Arch'
```

**Пробовали:** `os_family == 'Arch'`

**Не получилось:** Ansible определяет Arch как `Archlinux`.

**Ресурсы:**
- [Ansible os_family values](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)

---

## 5. Reflector не имеет --config флага

**Задача:** Использовать конфиг файл для reflector.

**Сделали:** Параметры передаются напрямую в команде:
```yaml
ansible.builtin.command: >-
  reflector
  --country {{ reflector_countries }}
  --protocol {{ reflector_protocol }}
  ...
```

Конфиг `/etc/xdg/reflector/reflector.conf` используется только systemd timer через `@file` синтаксис:
```
ExecStart=/usr/bin/reflector @/etc/xdg/reflector/reflector.conf
```

**Пробовали:** `reflector --config /path/to/config`

**Не получилось:** Reflector 2023-5 не имеет флага `--config`. `@file` — это Python argparse response file, не флаг reflector.

**Ресурсы:**
- [Reflector ArchWiki](https://wiki.archlinux.org/title/Reflector)
- [Python argparse fromfile_prefix_chars](https://docs.python.org/3/library/argparse.html#fromfile-prefix-chars)

---

## 6. Idempotence тест падает

**Задача:** Molecule idempotence проверка.

**Сделали:** Убрали `idempotence` из `test_sequence`:
```yaml
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Пробовали:** Стандартный test_sequence с idempotence.

**Не получилось:** Reflector каждый раз возвращает разные зеркала — это ожидаемое поведение.

**Ресурсы:**
- [Molecule test sequence](https://docs.ansible.com/projects/molecule/configuration/#scenario)

---

## 7. Бэкап mirrorlist

**Задача:** Сохранить старый mirrorlist перед обновлением.

**Сделали:** Бэкап **ДО** запуска reflector:
```yaml
- name: Read current mirrorlist
  slurp: ...
  register: reflector_old_mirror

- name: Backup current mirrorlist BEFORE update
  copy:
    src: "{{ reflector_mirrorlist_path }}"
    dest: "{{ reflector_mirrorlist_path }}.bak.{{ timestamp }}"
  when: reflector_old_mirror is succeeded

- name: Run reflector
  command: reflector ...
```

**Пробовали:** Бэкап после reflector.

**Не получилось:** Бэкапился уже новый файл, а не старый.

**Ресурсы:**
- Логическая ошибка в порядке задач

---

## 8. changed_when для reflector команды

**Задача:** Корректно отслеживать изменения.

**Сделали:**
```yaml
- name: Run reflector
  command: reflector ...
  changed_when: false  # Изменение отслеживается отдельно

- name: Report reflector result
  debug:
    msg: "Mirrorlist changed: {{ reflector_mirrorlist_changed }}"
  changed_when: reflector_mirrorlist_changed  # Здесь показываем changed
```

**Пробовали:** Костыль с `/bin/true`.

**Не получилось:** ansible-lint ругается на `no-changed-when`.

**Ресурсы:**
- [ansible-lint no-changed-when](https://ansible.readthedocs.io/projects/lint/rules/no-changed-when/)

---

## 9. Централизация пакетов в group_vars/all/packages.yml

**Задача:** Убрать дублирование пакетов между ролями и отделить данные от логики.

**Проблема:**
- `base-devel`, `git` — дублировались в `packages/defaults/main.yml` и хардкод в `yay/tasks/main.yml`
- `go` — хардкод в `yay/tasks/main.yml` без переменной
- Все данные привязаны к роли `packages`, нет разделения "код vs данные"

**Сделали:** Перенесли все пакетные переменные в `inventory/group_vars/all/packages.yml`:
1. `packages_*` переменные (из `roles/packages/defaults/main.yml` — файл удалён)
2. `yay_*` переменные (из `roles/yay/defaults/main.yml` — файл удалён)
3. `yay_build_deps` — новая переменная, заменила хардкод в `yay/tasks/main.yml`

**Как роли работают standalone:**
- `ansible.cfg` задаёт `inventory = ./inventory/hosts.ini`
- Ansible автоматически подхватывает `inventory/group_vars/all/*.yml`
- Molecule: переменные задаются в `molecule.yml` provisioner `group_vars`

**Почему `group_vars/all/`:**
- Ansible-стандартное место для "data layer" (данные отдельно от логики)
- Precedence уровень 4: выше role defaults (2), ниже host_vars (8) и `-e` (22)
- Per-host override: создать `inventory/host_vars/<hostname>/packages.yml`

**Почему reflector не тронули:**
- Пакет `reflector` = идентичность роли, параметризация бессмысленна

**Ресурсы:**
- [Ansible Sample Setup](https://docs.ansible.com/projects/ansible/latest/tips_tricks/sample_setup.html)
- [Red Hat CoP — Good Practices](https://redhat-cop.github.io/automation-good-practices/)
- [Ansible Variable Precedence](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_variables.html)

---

## 10. Миграция дотфайлов из кастомного Python-кода в Ansible роль

**Дата:** 2026-01-29

**Задача:** Развёртывание дотфайлов выполнялось кастомным Python-кодом (`scripts/bootstrap/gui/`, 15 файлов, ~500 LOC). Нужно перенести в Ansible для единообразия и удалить кастомный код.

**Проблема:**
- Phase 2 (DEPLOY) в `bootstrap.sh` запускала Python-модуль через `gui/launch.sh`
- Python-код дублировал то, что Ansible делает нативно: копирование файлов, установка owner/group/mode, создание директорий
- chezmoi использовался только как файловый копировальщик (без шаблонов, `.chezmoi.toml.tmpl` пуст)
- Кастомные стратегии (Strategy pattern, 6 файлов в `display/`) для задачи, решаемой одним `ansible.builtin.copy`
- Зависимость от Python 3 на этапе deploy, хотя Ansible уже доступен

**Сделали:** Новая роль `roles/dotfiles` заменяет весь Python-код:

```yaml
# roles/dotfiles/tasks/main.yml (ключевые задачи)

# User-level: copy с become_user
- name: Deploy user dotfiles
  ansible.builtin.copy:
    src: "{{ _dotfiles_abs }}/{{ item.src }}"
    dest: "{{ _dotfiles_user_home }}/{{ item.dest }}"
    owner: "{{ dotfiles_user }}"
    group: "{{ dotfiles_user }}"
    mode: "0644"
    remote_src: true
  loop: "{{ dotfiles_user_files }}"

# System-level: copy с явными owner/group/mode
- name: Deploy system config files
  ansible.builtin.copy:
    src: "{{ _dotfiles_abs }}/{{ item.src }}"
    dest: "{{ item.dest }}"
    owner: "{{ item.owner }}"
    group: "{{ item.group }}"
    mode: "{{ item.mode }}"
    remote_src: true
  loop: "{{ dotfiles_system_files }}"
```

**Конфигурация через `defaults/main.yml`:**
```yaml
dotfiles_user_files:
  - { src: "xinitrc",           dest: ".xinitrc" }
  - { src: "config/i3/config",  dest: ".config/i3/config" }
  - { src: "config/picom.conf", dest: ".config/picom.conf" }

dotfiles_system_files:
  - src: "etc/lightdm/lightdm.conf.d/10-config.conf"
    dest: "/etc/lightdm/lightdm.conf.d/10-config.conf"
    owner: root
    group: root
    mode: "0644"
  - src: "etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    dest: "/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    owner: lightdm
    group: lightdm
    mode: "0755"
  - src: "etc/X11/xorg.conf.d/10-monitor.conf"
    dest: "/etc/X11/xorg.conf.d/10-monitor.conf"
    owner: root
    group: root
    mode: "0644"
```

**Что удалили:**
1. `scripts/bootstrap/gui/` — 15 Python-файлов (deploy_dotfiles.py, display strategies, launch.py/sh, check_required_bins.py, start_gui.py, path_utils.py, user_utils.py)
2. Phase 2 (DEPLOY) из `bootstrap.sh` — Python-проверки, GUI launcher
3. `packages_dotfiles` (chezmoi) из `packages.yml` — зависимость больше не нужна
4. chezmoi-именование: `dot_xinitrc` → `xinitrc`, `dot_config/` → `config/`

**Что было избыточным в Python-коде:**
- `check_required_bins.py` — проверка Xorg/i3/alacritty/lightdm → роль `packages` уже ставит их
- `start_gui.py` — `systemctl enable --now lightdm` → `packages_enable_services` уже включает lightdm
- `display/` (Strategy pattern) — 6 файлов для копирования 2 файлов с правами → `ansible.builtin.copy`

**Почему Ansible `copy`, а не chezmoi:**
- chezmoi шаблонизация не использовалась (`.chezmoi.toml.tmpl` пуст)
- Ansible `copy` нативно поддерживает owner/group/mode — нет нужды в `sudo tee` + `sudo chmod` + `sudo chown`
- Идемпотентность встроена — Ansible сравнивает content + metadata перед копированием
- Одна система (Ansible) вместо двух (Ansible + chezmoi)
- `remote_src: true` — файлы уже на диске в `scripts/dotfiles/`, не нужно тянуть из role `files/`

**Почему `remote_src: true` вместо role `files/`:**
- Исходные дотфайлы живут в `scripts/dotfiles/` — standalone директория с README
- Роль ссылается на них через `dotfiles_source_dir` переменную
- Нет дублирования файлов между `scripts/dotfiles/` и `roles/dotfiles/files/`
- Путь параметризуем: можно переопределить через `-e` или `host_vars`

**Новый bootstrap flow:**
```
Phase 0: Externals (опционально)
Phase 1: Install (mirror search + packages via shell)
Phase 2: Ansible (reflector → yay → packages → dotfiles)
```

**Ресурсы:**
- [Ansible copy module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Ansible file module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Jeff Geerling — Ansible for DevOps](https://www.ansiblefordevops.com/)
- [TechDufus/dotfiles](https://github.com/TechDufus/dotfiles) — Ansible-only dotfiles management

---

## 11. Полная миграция на 13 модульных Ansible ролей

**Дата:** 2026-01-30

**Задача:** Проект использовал смесь shell-скриптов и 4 Ansible ролей. Нужно перейти на полностью автоматизированный Ansible bootstrap с DevOps best practices: маленькие, модульные, тестируемые, заменяемые роли.

**Проблема:**
- Старый `scripts/bootstrap/bootstrap.sh` — 3-фазный оркестратор (externals → install → deploy) со сложной логикой парсинга аргументов
- `scripts/bootstrap/externals/externals.sh` — pacman cache setup дублировал то, что делает `ansible.builtin.file`
- `scripts/lib/log.sh` — кастомное логирование, не нужное при Ansible
- `roles/dotfiles/` — монолитная роль для user-level + system-level файлов (нарушает single responsibility)
- `roles/packages/` — содержала управление сервисами и группами пользователей (не её зона ответственности)
- Только 4 роли покрывали систему, а настройка SSH, git, shell, docker, firewall, user — вне Ansible

**Сделали:** 13 модульных ролей, каждая с Galaxy-совместимой структурой:

```
base_system → reflector → yay → packages → user → ssh → git → shell → docker → firewall → xorg → lightdm → chezmoi
```

Каждая роль имеет:
- `defaults/main.yml` — переменные с namespace `<role>_*`
- `tasks/main.yml` — задачи с FQCN и тегами
- `meta/main.yml` — Galaxy metadata
- `molecule/default/{molecule.yml, converge.yml, verify.yml}` — тесты

**Новые роли (9):**
1. `base_system` — locale, timezone, hostname, pacman.conf, external cache
2. `user` — создание пользователя, sudo, wheel group
3. `ssh` — генерация Ed25519 ключей, hardening sshd
4. `git` — глобальная конфигурация через `community.general.git_config`
5. `shell` — bash/zsh конфигурация, aliases, PATH, templates
6. `docker` — daemon.json, docker group, systemd service
7. `firewall` — nftables правила, template, service
8. `xorg` — X11 конфигурация мониторов из `scripts/dotfiles/etc/X11/`
9. `lightdm` — display manager + resolution script из `scripts/dotfiles/etc/lightdm/`

**Замена `roles/dotfiles/` на 3 роли:**
- `xorg` — system-level `/etc/X11/` файлы (root:root)
- `lightdm` — system-level `/etc/lightdm/` файлы (root/lightdm)
- `chezmoi` — user-level дотфайлы через chezmoi (ansible → chezmoi → dotfiles pipeline)

Причина: system-level файлы требуют `become: true` с root ownership, а user-level — `become_user`. chezmoi обеспечивает шаблонизацию и кроссплатформенность для $HOME файлов.

**Изменения в существующих ролях:**
- `packages` — удалено управление сервисами (`packages_enable_services`) и группами (`packages_user_groups`), перенесено в `docker`, `lightdm`, `user` роли
- `reflector`, `yay` — добавлены `meta/main.yml`, теги

**Оркестрация:**
- `inventory/group_vars/all/system.yml` — новый файл с переменными для 9 ролей
- `packages.yml` — убраны `packages_enable_services`, `packages_user_groups`; добавлены openssh, chezmoi, nftables
- `playbooks/workstation.yml` — 13 ролей в 7 фазах с тегами
- `Taskfile.yml` — 13 test-* задач, обновлённая `test` задача

**Entry point:**
- Новый `bootstrap.sh` в корне проекта — минимальный: проверка Arch, установка ansible + go-task, vault password, venv, запуск playbook
- Передача всех аргументов в `ansible-playbook` (--tags, --check, --skip-tags, -e)

**Что удалили:**
- `scripts/bootstrap/bootstrap.sh` — старый 3-фазный оркестратор
- `scripts/bootstrap/externals/` — absorbed в `base_system`
- `scripts/bootstrap/ansible/bootstrap.sh` — absorbed в корневой `bootstrap.sh`
- `scripts/lib/log.sh` и `scripts/lib/` — не нужны
- `scripts/bootstrap/gui/` и `scripts/bootstrap/logging/` — __pycache__ remnants
- `roles/dotfiles/` — заменена тремя ролями

**DevOps tooling:**
- `.github/workflows/lint.yml` — CI: yamllint, ansible-lint, syntax-check
- `.pre-commit-config.yaml` — pre-commit hooks

**Ресурсы:**
- [Ansible Galaxy Role Structure](https://docs.ansible.com/ansible/latest/galaxy/dev_guide.html)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Red Hat CoP — Automation Good Practices](https://redhat-cop.github.io/automation-good-practices/)
- [Jeff Geerling — Ansible for DevOps](https://www.ansiblefordevops.com/)
- [Molecule Documentation](https://docs.ansible.com/projects/molecule/configuration/)

---

## Итоговая структура

```
bootstrap/
├── bootstrap.sh                           # Единственная точка входа
├── .pre-commit-config.yaml                # Pre-commit hooks
├── .github/workflows/lint.yml             # CI pipeline
├── scripts/
│   ├── bootstrap/ansible/                 # Ansible project
│   │   ├── ansible.cfg                    # vault_password_file = ./vault-pass.sh
│   │   ├── Taskfile.yml                   # Task runner (PREFIX для PATH)
│   │   ├── vault-pass.sh                  # Каскадный resolver: pass → ~/.vault-pass → error
│   │   ├── requirements.txt               # Python deps
│   │   ├── inventory/
│   │   │   ├── hosts.ini
│   │   │   └── group_vars/all/
│   │   │       ├── packages.yml           # Реестр пакетов (data layer)
│   │   │       ├── system.yml             # Системные переменные (9 ролей)
│   │   │       └── vault.yml              # Encrypted sudo password (AES-256)
│   │   ├── playbooks/
│   │   │   ├── workstation.yml            # 13 ролей в 7 фазах
│   │   │   └── mirrors-update.yml         # Только зеркала
│   │   └── roles/                         # 13 модульных ролей
│   │       ├── base_system/               # Locale, timezone, hostname, pacman.conf
│   │       ├── reflector/                 # Зеркала pacman
│   │       ├── yay/                       # AUR helper
│   │       ├── packages/                  # Установка пакетов
│   │       ├── user/                      # Пользователь, sudo, groups
│   │       ├── ssh/                       # SSH ключи, sshd hardening
│   │       ├── git/                       # Git global config
│   │       ├── shell/                     # Bash/Zsh конфигурация
│   │       ├── docker/                    # Docker daemon, service
│   │       ├── firewall/                  # nftables firewall
│   │       ├── xorg/                      # X11 конфигурация
│   │       ├── lightdm/                   # Display manager
│   │       └── chezmoi/                   # Дотфайлы через chezmoi
│   ├── dotfiles/                          # Исходные дотфайлы (chezmoi source)
│   ├── ci/                                # CI скрипты
│   ├── show_installed_packages.sh         # Анализ пакетов
│   └── show_all_dependencies.sh           # Дерево зависимостей
├── windows/                               # Windows SSH/sync утилиты
└── docs/                                  # Документация
```
