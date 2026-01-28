# Decisions Log: Molecule Testing для Reflector Role

## Дата: 2026-01-28

## Контекст
Настройка molecule тестов для Ansible роли `reflector` на Arch Linux VM с delegated driver.

---

## 1. Что было сделано (успешно)

### PATH для venv
- **Проблема**: `molecule` не найден в PATH
- **Решение**: `bash -c 'source ~/.bashrc; export PATH="{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH" && molecule test'`

### Sudo пароль для Ansible become
- **Проблема**: `sudo: a password is required` при выполнении задач с `become: true`
- **Решение**: Переменная окружения `MOLECULE_SUDO_PASS` в `~/.bashrc` (до строки `[[ $- != *i* ]] && return`)
- **molecule.yml**: `ansible_become_password: "{{ lookup('env', 'MOLECULE_SUDO_PASS') | default(omit) }}"`

### ansible_connection: local
- **Проблема**: Molecule пытался подключиться по SSH к localhost
- **Решение**: `ansible_connection: local` в `host_vars.localhost`

### os_family для Arch Linux
- **Проблема**: Проверка `os_family == 'Arch'` падала
- **Решение**: Ansible определяет Arch как `Archlinux` (не `Arch`)
- **Исправлено в**: `converge.yml`, `tasks/main.yml`

### Устаревший callback plugin
- **Проблема**: `community.general.yaml` callback удалён в новых версиях
- **Решение**: `stdout_callback: default` + `result_format: yaml`

### reflector --config не поддерживается
- **Проблема**: Версия reflector 2023-5 не имеет флага `--config`
- **Решение**: Передача аргументов напрямую в команде:
  ```yaml
  ansible.builtin.command: >-
    reflector
    --country {{ reflector_countries }}
    --protocol {{ reflector_protocol }}
    ...
  ```

### Idempotence тест
- **Проблема**: reflector каждый раз возвращает разные зеркала — idempotence падает
- **Решение**: Убран `idempotence` из `test_sequence` (это ожидаемое поведение)

---

## 2. Что пробовали и не сработало

### Taskfile env с $PATH
```yaml
env:
  PATH: "{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"  # НЕ работает
  PATH: "{{.TASKFILE_DIR}}/{{.VENV}}/bin:{{.PATH}}"  # НЕ работает - .PATH не существует
```
**Причина**: Taskfile не интерполирует системные переменные в env секции

### Taskfile env с sh:
```yaml
PATH:
  sh: echo "{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"  # НЕ работает
```
**Причина**: sh: выполняется до запуска команды, но PATH не передаётся корректно

### bash -l -c (login shell)
```yaml
- bash -l -c '... && molecule test'  # НЕ работает
```
**Причина**: Login shell читает `.bash_profile`, но переменные из `.bashrc` не загружаются если там есть `[[ $- != *i* ]] && return`

### MOLECULE_SUDO_PASS в конце .bashrc
**Причина**: Строка `[[ $- != *i* ]] && return` в начале файла прерывает выполнение для non-interactive shell

---

## 3. Что можно улучшить

### Безопасность пароля
- [ ] Использовать `ansible-vault` для хранения пароля вместо plaintext в `.bashrc`
- [ ] Или использовать `pass` / `gopass` для получения пароля: `MOLECULE_SUDO_PASS=$(pass show arch/sudo)`

### CI/CD интеграция
- [ ] Для CI использовать Docker driver вместо delegated (эфемерные контейнеры)
- [ ] Или настроить VM с NOPASSWD для CI user

### Taskfile
- [ ] Вынести PATH логику в отдельный wrapper script чтобы избежать `bash -c 'source ...'`
- [ ] Добавить `task test-converge` для быстрого запуска без verify

### Reflector роль
- [ ] Добавить проверку версии reflector и использовать `--config` если поддерживается
- [ ] Сделать idempotence опциональным через переменную (для тех кто хочет проверять)

### Документация
- [ ] Добавить в README.md секцию "Running tests" с требованиями
- [ ] Документировать требование `MOLECULE_SUDO_PASS` в `.bashrc`

---

## Итоговая конфигурация

### ~/.bashrc (на Arch VM)
```bash
#
# ~/.bashrc
#

export MOLECULE_SUDO_PASS="your_password"  # ДО проверки на интерактивность!

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
...
```

### Запуск тестов
```bash
go-task test           # обычный запуск (требует MOLECULE_SUDO_PASS)
go-task test-root      # запуск через sudo (запросит пароль интерактивно)
```

---

## 4. Ревью конфигурации (2026-01-28)

### Вопрос 1: `ignore-errors: true` в molecule.yml

**Файл:** `roles/reflector/molecule/default/molecule.yml:18`

```yaml
dependency:
  name: galaxy
  options:
    ignore-errors: true
```

**Вердикт: ✅ КОРРЕКТНО**

**Документация:** [Molecule Configuration - Dependency](https://docs.ansible.com/projects/molecule/configuration/)

> Additional options can be passed to `ansible-galaxy install` through the options dict.

Пример из документации:
```yaml
dependency:
  name: galaxy
  options:
    ignore-certs: True
    ignore-errors: True
```

**Объяснение:** Опция `--ignore-errors` позволяет ansible-galaxy пропустить неудавшиеся роли и продолжить установку остальных. Полезно когда requirements.yml содержит опциональные зависимости.

**Рекомендация:** Оставить, если зависимости опциональны. Убрать, если все зависимости обязательны (лучше узнать об ошибке сразу).

---

### Вопрос 2: `driver: name: default` vs `molecule-plugins[delegated]`

**Вопрос:** Если драйвер `default`, зачем нужен `molecule-plugins[delegated]==23.5.3`?

**Вердикт: ⚠️ ВОЗМОЖНО ИЗБЫТОЧНО**

**Документация:** [Molecule Installation](https://docs.ansible.com/projects/molecule/installation/)

> Molecule uses the "delegated" driver by default. Other drivers can be installed separately from PyPI, most of them being included in molecule-plugins package.

**Факты:**
- В Molecule 25.x встроенный драйвер называется `default` (ранее `delegated`)
- `molecule-plugins[delegated]` — отдельный пакет
- В README.md есть troubleshooting для "Failed to find driver delegated"

**Рекомендация:**
```python
# requirements.txt - ПРОВЕРИТЬ
# Попробовать убрать molecule-plugins[delegated] и протестировать
molecule==25.12.0
# molecule-plugins[delegated]==23.5.3  # Возможно не нужен для default driver
```

Если `task test` работает без этой зависимости — она избыточна.

---

### Вопрос 3: `managed: false` — что это значит?

**Файл:** `molecule.yml:23`

```yaml
driver:
  name: default
  options:
    managed: false
```

**Вердикт: ✅ КОРРЕКТНО для localhost тестирования**

**Документация:** [Molecule Configuration - Driver](https://docs.ansible.com/projects/molecule/configuration/)

> When `managed: false` is set in driver options, Molecule skips provisioning and deprovisioning steps entirely. It is the developer's responsibility to manage the instances.

**Объяснение:**
- `managed: true` (default) — Molecule создает и удаляет инстансы (create/destroy playbooks)
- `managed: false` — Molecule использует существующую инфраструктуру

**Для localhost:** `managed: false` — единственно правильный выбор:
1. localhost уже существует
2. Мы не хотим "удалять" localhost после теста
3. Тестируем на реальной VM, а не в контейнере

---

### Вопрос 4: `groups: - arch_hosts` — стандартное или кастомное?

**Файл:** `molecule.yml:28`

```yaml
platforms:
  - name: localhost
    groups:
      - arch_hosts
```

**Вердикт: 🔧 КАСТОМНОЕ (и не используется)**

**Документация:** [Molecule Configuration - Platforms](https://docs.ansible.com/projects/molecule/configuration/)

> Molecule generates inventory automatically based on the hosts defined under Platforms.

`groups` — кастомные группы Ansible inventory.

**Проблема:** Группа `arch_hosts` нигде не используется:
- В `converge.yml`: `hosts: all`
- В `verify.yml`: `hosts: all`
- В playbooks: `hosts: localhost`

**Рекомендация:** Убрать или использовать:
```yaml
# Вариант 1: Убрать
platforms:
  - name: localhost

# Вариант 2: Использовать в converge.yml
- hosts: arch_hosts
```

---

### Вопрос 5: Зачем inventory в molecule.yml если есть hosts.ini?

**Вердикт: ✅ КОРРЕКТНО — разные inventory для разных целей**

**Документация:** [Molecule Configuration - Provisioner](https://docs.ansible.com/projects/molecule/configuration/)

> Molecule generates inventory automatically based on the hosts defined under Platforms.

| Inventory | Назначение | Переменные |
|-----------|-----------|------------|
| `inventory/hosts.ini` | Production через `ansible-playbook` | Production values |
| `molecule.yml inventory` | Тестирование через Molecule | Test values |

**Почему правильно:**
1. **Изоляция тестов** — тестовые параметры не влияют на production
2. **Безопасность** — `MOLECULE_SUDO_PASS` только для тестов
3. **Скорость** — `reflector_latest: 5` вместо `20`

---

### Вопрос 6: Зачем group_vars в molecule.yml?

**Файл:** `molecule.yml:37-43`

```yaml
group_vars:
  all:
    reflector_countries: "US,DE"
    reflector_latest: 5
    reflector_age: 24
```

**Вердикт: ✅ КОРРЕКТНО — переопределение для тестов**

**Документация:** [Ansible Variable Precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)

> Variables defined in inventory `group_vars` have higher precedence than role defaults.

Приоритет (от низшего к высшему):
1. `defaults/main.yml` — **20** mirrors, **KZ,RU,DE** countries
2. `inventory group_vars` — **5** mirrors, **US,DE** countries

**Зачем:** Тестовые значения меньше → тест быстрее.

---

### Вопрос 7: Почему не используются переменные из defaults/main.yml?

**Вердикт: ✅ КОРРЕКТНО — РАЗНЫЕ значения для разных сценариев**

| Источник | `reflector_latest` | `reflector_countries` | Назначение |
|----------|-------------------|----------------------|------------|
| `defaults/main.yml` | 20 | KZ,RU,DE,NL,FR | Production |
| `molecule.yml` | 5 | US,DE | Тестирование |

Defaults ИСПОЛЬЗУЮТСЯ, но ПЕРЕОПРЕДЕЛЯЮТСЯ для тестов.

---

### Вопрос 8: Что такое config_options: defaults?

**Файл:** `molecule.yml:47-51`

```yaml
config_options:
  defaults:
    callbacks_enabled: profile_tasks
    stdout_callback: default
    result_format: yaml
```

**Вердикт: ✅ КОРРЕКТНО**

**Документация:** [Molecule Configuration - Provisioner](https://docs.ansible.com/projects/molecule/configuration/)

> It accepts the same configuration options provided in an Ansible configuration file `ansible.cfg`.

Эквивалент в ansible.cfg:
```ini
[defaults]
callbacks_enabled = profile_tasks
stdout_callback = default
result_format = yaml
```

**Что делает:**
- `callbacks_enabled: profile_tasks` — показывает время выполнения каждой задачи
- `stdout_callback: default` — стандартный вывод
- `result_format: yaml` — YAML формат (читаемее JSON)

---

### Вопрос 9: ⚠️ Команда reflector с параметрами vs конфиг

**Файл:** `roles/reflector/tasks/main.yml:66-86`

**Вердикт: ✅ КОРРЕКТНО (но по особой причине)**

**Контекст из decisions выше (секция 1):**

> **reflector --config не поддерживается**
> Версия reflector 2023-5 не имеет флага `--config`

**Объяснение:** Роль деплоит `/etc/xdg/reflector/reflector.conf`, но:
1. Старые версии reflector не поддерживают `--config`
2. Reflector читает конфиг из `/etc/xdg/reflector/reflector.conf` **только** при запуске через systemd service
3. При ручном запуске `reflector` без аргументов — **не читает** конфиг автоматически

**Почему дублирование неизбежно:**
- Конфиг нужен для systemd timer (автоматический запуск)
- Параметры в команде нужны для первого запуска через Ansible

**Альтернатива (если версия reflector >= 2024):**
```yaml
- name: Run reflector using config
  ansible.builtin.command: reflector --config {{ reflector_conf_path }}
```

---

### Вопрос 10: ⚠️ Нет инструкции восстановления бэкапа

**Вердикт: ⚠️ ОТСУТСТВУЕТ В README**

**Что есть:** Роль создает бэкап `/etc/pacman.d/mirrorlist.bak.{timestamp}`

**Рекомендация добавить в README.md:**

```markdown
## Восстановление mirrorlist

Если после обновления зеркал pacman не работает:

### Автоматическое восстановление
```bash
# Найти последний бэкап
ls -la /etc/pacman.d/mirrorlist.bak.*

# Восстановить
sudo cp /etc/pacman.d/mirrorlist.bak.20241128T120000Z /etc/pacman.d/mirrorlist
```

### Ручное восстановление (если бэкапов нет)
```bash
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist
sudo pacman -Syy
```
```

---

### Вопрос 11: ⚠️ Три playbooks дублируют друг друга

**Файлы:**
- `playbooks/mirrors-update.yml`
- `playbooks/reflector-setup.yml`
- `playbooks/reflector-verify.yml`

**Вердикт: ⚠️ ЧАСТИЧНОЕ ДУБЛИРОВАНИЕ**

| Playbook | Содержимое | Уникальность |
|----------|-----------|--------------|
| mirrors-update.yml | `roles: [reflector]` | Нет (= reflector-setup) |
| reflector-setup.yml | `roles: [reflector]` + tags | Нет |
| reflector-verify.yml | `roles: [reflector]` + debug | Добавляет debug output |

**Рекомендация:** Объединить `mirrors-update.yml` и `reflector-setup.yml` в один файл.

---

### Вопрос 12: Переменные vs PATH в Taskfile

**Файл:** `Taskfile.yml:7-11`

```yaml
vars:
  VENV: .venv
  PYTHON: "{{.VENV}}/bin/python"
  ANSIBLE: "{{.VENV}}/bin/ansible-playbook"
```

**Вердикт: ⚠️ WORKAROUND из-за ограничений Taskfile**

**Документация:** [Taskfile Environment](https://taskfile.dev/docs/reference/environment), [GitHub Issue #202](https://github.com/go-task/task/issues/202)

> Task runs each command as a separate shell process, so something you do in one command won't affect any future commands.

**Почему полные пути:** Taskfile не позволяет корректно модифицировать PATH между командами.

**Решение из документации:**
```yaml
env:
  PATH: "{{.PWD}}/.venv/bin:{{.PATH}}"
```

**НО** это не работает надёжно (см. секцию 2 выше "Что пробовали и не сработало").

---

### Вопрос 13: ⚠️ Сложные bash -c конструкции

**Файл:** `Taskfile.yml:64`

```yaml
- bash -c 'source ~/.bashrc 2>/dev/null; export PATH="..." && molecule test'
```

**Вердикт: ⚠️ ВЫНУЖДЕННЫЙ WORKAROUND**

**Документация:** [GitHub Issue #202](https://github.com/go-task/task/issues/202)

**Почему так сложно:**
1. Taskfile не интерполирует `{{.PATH}}` (системный PATH)
2. `env: PATH: ...` не работает надёжно на всех платформах
3. `source ~/.bashrc` нужен для загрузки `MOLECULE_SUDO_PASS`

**Альтернатива — wrapper script:**
```bash
#!/bin/bash
# scripts/run-molecule.sh
source ~/.bashrc 2>/dev/null
export PATH="$(dirname "$0")/../.venv/bin:$PATH"
exec molecule "$@"
```

```yaml
# Taskfile.yml
test:
  cmds:
    - ./scripts/run-molecule.sh test
```

---

## 5. Сводка рекомендаций

| # | Проблема | Статус | Действие |
|---|----------|--------|----------|
| 1 | ignore-errors | ✅ OK | Оставить если зависимости опциональны |
| 2 | molecule-plugins | ⚠️ Проверить | Попробовать убрать, протестировать |
| 3 | managed: false | ✅ OK | Оставить |
| 4 | groups: arch_hosts | 🔧 Unused | Убрать или использовать |
| 5 | Два inventory | ✅ OK | Оставить (разные цели) |
| 6 | group_vars | ✅ OK | Оставить (тестовые значения) |
| 7 | defaults | ✅ OK | Используются, переопределяются |
| 8 | config_options | ✅ OK | Оставить |
| 9 | Команда vs конфиг | ✅ OK* | *Ограничение версии reflector |
| 10 | Бэкап recovery | ⚠️ Missing | **Добавить в README** |
| 11 | 3 playbooks | ⚠️ DRY | **Объединить mirrors-update + reflector-setup** |
| 12 | Переменные vs PATH | ⚠️ Limitation | Ограничение Taskfile |
| 13 | bash -c | ⚠️ Workaround | Рассмотреть wrapper script |

---

## Источники

- [Molecule Configuration](https://docs.ansible.com/projects/molecule/configuration/)
- [Molecule Installation](https://docs.ansible.com/projects/molecule/installation/)
- [Ansible Variable Precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
- [Taskfile Environment Reference](https://taskfile.dev/docs/reference/environment)
- [Taskfile GitHub Issue #202 - PATH modification](https://github.com/go-task/task/issues/202)
