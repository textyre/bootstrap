# Ansible Role Patterns

> **Note:** This document covers implementation patterns. For role requirements
> and compliance checklist, see [[Role Requirements|standards/role-requirements]].
> Security control mappings: [[Security Standards|standards/security-standards]].

Чеклисты паттернов для написания ролей в этом проекте.

---

## Defaults (`defaults/main.yml`)

- [ ] Все переменные с префиксом имени роли (`base_system_*`, `docker_*`)
- [ ] Список поддерживаемых ОС: `_<role>_supported_os`
- [ ] Секции разделены комментариями `# ---- Section Name ----`
- [ ] Boolean-флаги для опциональных фич (`base_system_setup_pacman_cache: false`)
- [ ] Все переменные имеют значения по умолчанию
- [ ] Связанные настройки сгруппированы вместе

---

## Tasks (`tasks/main.yml`)

- [ ] Секции разделены `# ---- Name ----`
- [ ] Каждый таск имеет `tags: ['<role>', '<feature>']`
- [ ] OS dispatch через `include_tasks: "{{ ansible_facts['os_family'] | lower }}.yml"`
- [ ] Проверка ОС: `when: ansible_facts['os_family'] in _<role>_supported_os`
- [ ] `notify` для вызова handlers при изменении конфигурации
- [ ] Debug-таск в конце для отчёта о применённой конфигурации

---

## OS-Specific Tasks (`tasks/<os>.yml`)

- [ ] Имя файла = lowercase OS family (`archlinux.yml`, `debian.yml`)
- [ ] `block` для группировки связанных условных тасков
- [ ] `register` + `when` для зависимостей между тасками
- [ ] Сложные `when` в multiline формате (`>`)
- [ ] Таски внутри `block` наследуют `tags` и `when` от блока
- [ ] `failed_when: false` для опциональных проверок
- [ ] Заглушки для нереализованных ОС — `debug` с сообщением

---

## Handlers (`handlers/main.yml`)

- [ ] Вызываются через `notify` в тасках
- [ ] `changed_when: true` для handlers, которые всегда должны отчитываться об изменении
- [ ] Описательные имена
- [ ] Условные handlers с `when` (например, проверка `service_mgr == 'systemd'`)

---

## Molecule тесты

### `molecule.yml`

- [ ] `driver: default` + `managed: false` (локальное тестирование)
- [ ] `ansible_connection: local`
- [ ] Vault: `vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh`
- [ ] `ANSIBLE_ROLES_PATH` через `env`
- [ ] Последовательность: `syntax → converge → verify`

### `converge.yml`

- [ ] `become: true`
- [ ] `gather_facts: true`
- [ ] Загрузка vault через `vars_files` + `lookup('env', 'MOLECULE_PROJECT_DIRECTORY')`
- [ ] `pre_tasks` с `assert` для проверки среды
- [ ] Одна роль в `roles`

### `verify.yml`

- [ ] `check_mode: true` + `failed_when: is changed` — проверка идемпотентности
- [ ] `changed_when: false` для информационных команд
- [ ] Регистрация: `_<role>_verify_<check>`
- [ ] Debug в конце показывает результаты

---

## Именование переменных

- [ ] `<role>_<setting>` — конфигурационные переменные (`base_system_locale`)
- [ ] `_<role>_<purpose>` — внутренние register-переменные (`_base_system_alpm_user`)
- [ ] `<role>_<feature>` — флаги включения фич (`docker_enable_service`)
- [ ] `_<role>_supported_os` — списки поддерживаемых значений

---

## Теги

- [ ] Формат: `tags: ['<role>', '<feature>']`
- [ ] Примеры: `['system', 'timezone']`, `['docker', 'configure']`
- [ ] Использование:
  ```bash
  ansible-playbook playbook.yml --tags system
  ansible-playbook playbook.yml --tags docker,configure
  ansible-playbook playbook.yml --skip-tags pacman
  ```

---

## Права доступа

- [ ] Директории: `mode: '0755'`
- [ ] Конфигурационные файлы: `mode: '0644'`
- [ ] Чувствительные файлы: `mode: '0600'`
- [ ] Групповые директории: `mode: '2775'` (setgid)
- [ ] Системные файлы: `owner: root`, `group: root`
- [ ] Все файловые операции имеют явные `owner/group/mode`

---

## Условные паттерны

- [ ] Feature flag: `when: docker_add_user_to_group`
- [ ] OS check: `when: ansible_facts['os_family'] in _<role>_supported_os`
- [ ] Service manager: `when: ansible_facts['service_mgr'] == 'systemd'`
- [ ] Сложные условия — multiline `>`
- [ ] `block` для группировки условных фич — `when` и `tags` на уровне блока

---

## Архитектурные решения

### Vault (sudo пароль)

- [ ] Зашифрованный файл: `inventory/group_vars/all/vault.yml`
- [ ] Каскадный скрипт `vault-pass.sh`: `pass` → `~/.vault-pass` → ошибка
- [ ] Molecule: `config_options.defaults.vault_password_file`
- [ ] AES-256 шифрование, безопасен для git

### Централизация пакетов

- [ ] Все пакеты в `inventory/group_vars/all/packages.yml` (data layer)
- [ ] Precedence уровень 4: выше role defaults, ниже host_vars
- [ ] Per-host override: `inventory/host_vars/<hostname>/packages.yml`

### Модульные роли

- [ ] Каждая роль — одна ответственность
- [ ] Molecule тесты для каждой роли
- [ ] Порядок:
  ```
  base_system → vm → reflector → yay → packages → user → ssh →
  git → shell → docker → firewall → xorg → lightdm → chezmoi
  ```

### Мульти-дистро

- [ ] OS dispatch: `include_tasks: "{{ ansible_facts['os_family'] | lower }}.yml"`
- [ ] 5 поддерживаемых дистро: Arch, Ubuntu (Debian), Fedora (RedHat), Void, Gentoo
- [ ] `vars/<os_family>.yml` — маппинг пакетов и путей per-distro
- [ ] `_<role>_supported_os` в defaults с preflight assert
- [ ] Init-agnostic: `ansible.builtin.service` вместо `ansible.builtin.systemd`
- [ ] Init dispatch: `with_first_found: "service_{{ ansible_facts['service_mgr'] }}.yml"`
- [ ] 5 supported inits: systemd, runit, openrc, s6, dinit

### Reflector

- [ ] Без `--config` флага — параметры напрямую в команде
- [ ] Конфиг только для systemd timer через `@file` синтаксис

### Taskfile venv PATH

- [ ] PREFIX переменная: `env PATH="{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"`
- [ ] Все ansible-команды через `{{.PREFIX}}`

---

## Безопасность

- [ ] Обновление пакетов: полное (`-Syu`), никогда частичное (`-Sy`)
- [ ] Файлы с секретами: `mode: '0600'`, `no_log: true` в тасках
- [ ] Сетевые сервисы: default deny, явные allow-правила
- [ ] SSH hardening настройки вынесены в переменные (`defaults/main.yml`), не захардкожены
- [ ] Vault для любых паролей/токенов — никогда plaintext в коде

---

## Переиспользование (DRY)

- [ ] Общие переменные (`target_user`, `dotfiles_base_dir`) — в `system.yml`, не дублировать в ролях
- [ ] Пакеты — в `packages.yml` (data layer), роли только читают списки
- [ ] Per-host override — через `host_vars/<hostname>/`, не через условия в ролях
- [ ] Зависимости (Galaxy collections) — в одном `requirements.yml`
- [ ] Новая роль не дублирует логику существующей — проверить `roles/` перед созданием

Назад к [[Ansible-Overview]] | [[Home]]
