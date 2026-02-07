# Ansible Role Patterns

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

## Meta (`meta/main.yml`)

- [ ] `role_name` совпадает с именем директории
- [ ] `license: MIT`
- [ ] `min_ansible_version: "2.15"`
- [ ] `platforms` — список поддерживаемых ОС
- [ ] `galaxy_tags` — lowercase
- [ ] `dependencies: []` — явно, даже если пусто

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

Назад к [[Ansible-Overview]] | [[Home]]
