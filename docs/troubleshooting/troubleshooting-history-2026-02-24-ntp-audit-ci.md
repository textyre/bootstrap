# Post-Mortem: CI-тесты для роли `ntp_audit`

**Дата:** 2026-02-24
**Статус:** Завершено — CI зелёный
**Коммиты:** `0a256e4` → `5719cf2` (5 итераций)

---

## 1. Задача

Создать CI-тесты для роли `ntp_audit`:
- не дублировать логику между localhost-сценарием и docker/CI
- переиспользовать `tasks/verify.yml` как единый источник истины
- добавить сценарий `disabled` (роль отключена)
- расширить проверки: exit code, permissions, logrotate syntax, JSON field types, Alloy/Loki config

---

## 2. Архитектурные решения

### `shared/` паттерн

Уже использовался в ролях `locale` и `hostname`. Принята та же структура:

```
molecule/
  shared/
    converge.yml   ← единый playbook для localhost + docker
    verify.yml     ← основные + расширенные проверки
  default/         ← localhost (ссылается на ../shared/)
  docker/          ← CI (ссылается на ../shared/)
  disabled/        ← отдельный сценарий, свой converge/verify
```

**Ключевое решение:** `tasks/verify.yml` — базовые проверки. `molecule/shared/verify.yml` включает его через `include_tasks: ../../tasks/verify.yml` и добавляет molecule-only логику поверх.

### Duality MOLECULE_PROJECT_DIRECTORY

Критическая ловушка, уже документированная в прошлых post-mortem'ах:

| Контекст | `MOLECULE_PROJECT_DIRECTORY` | `../../tasks/verify.yml` ведёт в |
|---|---|---|
| Taskfile | `ansible/` | `ansible/tasks/verify.yml` ❌ |
| CI (без override) | `ansible/roles/ntp_audit/` | `ansible/roles/ntp_audit/tasks/verify.yml` ✓ |

Решение: `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"` в `docker/molecule.yml`, и относительный путь `../../tasks/verify.yml` в shared/verify.yml (работает в CI, не ломает localhost при правильном MOLECULE_PROJECT_DIRECTORY).

---

## 3. Инциденты CI

### Инцидент #1 — `service_facts` не видит `.timer` юниты

**Commit:** `595979e`
**Ошибка:**
```
ntp-audit.timer is not enabled after deploy
```

**Причина:**
`ansible.builtin.service_facts` использует `systemctl list-units --type=service`. Timer-юниты имеют тип `timer`, а не `service`. На Arch Linux в Docker-контейнере модуль возвращал только сервисы — `.timer` юниты отсутствовали в словаре `ansible_facts.services`.

Это не баг Ansible — это намеренное поведение: модуль вызывает `systemctl list-units --type=service --all`. Для timers нужен отдельный вызов `--type=timer`.

**Fix:**
Заменить `ansible.builtin.service_facts` + assert на прямые команды:
```yaml
- ansible.builtin.command:
    cmd: systemctl is-enabled ntp-audit.timer
  register: ntp_audit_verify_timer_enabled

- ansible.builtin.command:
    cmd: systemctl is-active ntp-audit.timer
  register: ntp_audit_verify_timer_active
```

`systemctl is-enabled` возвращает exit code 0 и stdout `"enabled"` — надёжно для любого типа юнита.

**Задетые файлы:** `tasks/verify.yml`, `tasks/scheduler_assert.yml`

**Урок:** `service_facts` непригоден для проверки timer-юнитов. Использовать `systemctl is-enabled <unit>` и `systemctl is-active <unit>` напрямую.

---

### Инцидент #2 — `audit.log` пустой после первого запуска

**Commit:** `d547d2a`
**Ошибка:**
```
/var/log/ntp-audit/audit.log missing or empty — first run failed
```

**Причина — двойная:**

**2a. Chronyd socket не готов.** Converge запускал `chronyd` через `service: started`, после чего немедленно выполнял роль. `ntp-audit` обращается к `/run/chrony/chronyd.sock` сразу после старта сервиса. В Docker без реального iron systemd sock может не существовать ещё 0.5–1 сек после `started`.

**2b. Критическая ошибка в exception handler `__main__.py.j2`.** При исключении (в том числе при `FileNotFoundError` на сокете) handler делал:
```python
except Exception as exc:
    write_syslog_error(str(exc))   # может упасть — нет /dev/log в контейнере
    return 0
```
`write_syslog_error` падал внутри (нет `/dev/log` в Docker), при этом `write_log` так и не вызывался. Скрипт завершался с rc=0 без единой записи в лог. Verify видел пустой файл и падал.

**Fix:**
Добавить `wait_for` для сокета chrony перед запуском роли:
```yaml
- name: Wait for chronyd socket to be ready
  ansible.builtin.wait_for:
    path: /run/chrony/chronyd.sock
    state: present
    timeout: 30
```

Исправить exception handler — всегда записывать error record в лог, независимо от syslog:
```python
except Exception as exc:
    error_record = { ..., 'sync_status': 'error', 'ntp_conflict': 'none', ... }
    try:
        write_log(error_record)       # СНАЧАЛА лог
    except Exception:
        pass
    try:
        write_syslog_error(str(exc))  # потом syslog (не критично)
    except Exception:
        pass
    return 0
```

**Урок:** Exception handler обязан записать в файл-лог до любых сетевых/IPC операций. В Docker: `/dev/log` отсутствует — `syslog.syslog()` падает. Порядок: сначала file log, потом syslog.

---

### Инцидент #3 — `ModuleNotFoundError: No module named 'molecule.command.idempotency'`

**Commit:** `6a79745`
**Ошибка:**
```
ModuleNotFoundError: No module named 'molecule.command.idempotency'
```

**Причина:**
Опечатка в `molecule/docker/molecule.yml`:
```yaml
test_sequence:
  - idempotency   # ❌ — не существует
```

Правильное имя команды: `idempotence`. В более ранних версиях Molecule команда называлась `idempotency`, затем переименована. Все остальные роли в проекте уже используют `idempotence`:
```
hostname/molecule/docker/molecule.yml:    - idempotence  ✓
locale/molecule/docker/molecule.yml:      - idempotence  ✓
ntp/molecule/docker/molecule.yml:         - idempotence  ✓
```

**Fix:** `idempotency` → `idempotence`

**Урок:** При создании нового `molecule.yml` — копировать `test_sequence` из существующего соседнего файла, не писать с нуля. Converge при этом прошёл успешно (ok=47, changed=18), ошибка проявилась только при попытке запустить следующий шаг.

---

### Инцидент #4 — `type_debug in ['bool', 'AnsibleUnsafeText']` не проходит

**Commit:** `5719cf2`
**Ошибка:**
```
"assertion": "ntp_audit_molecule_log_json.ntp_conflict | type_debug in ['bool', 'AnsibleUnsafeText']"
"evaluated_to": false
"msg": "JSON field type validation failed. ntp_conflict=none"
```

**Причина:**
Assertion предполагал, что Ansible представляет строки как `AnsibleUnsafeText`. Но после `{{ value | from_json }}` Ansible возвращает нативные Python-типы:

| JSON тип | Python тип | `type_debug` |
|---|---|---|
| `"string"` | `str` | `"str"` |
| `true`/`false` | `bool` | `"bool"` |
| `123` | `int` | `"int"` |
| `null` | `NoneType` | `"NoneType"` |

`AnsibleUnsafeText` — специальный тип Ansible для строк, пришедших из переменных через шаблонизатор Jinja2. Результат `from_json` — нативный Python, не AnsibleUnsafeText.

`check_conflicts()` возвращает `str` (аннотация `-> str`), значит `ntp_conflict` — всегда строка. Исходная assertion содержала ошибку в предположении о типе.

**Fix:**
```yaml
- ntp_audit_molecule_log_json.ntp_conflict | type_debug in ['bool', 'str', 'AnsibleUnsafeText']
```

**Урок:** При использовании `type_debug` с `from_json` всегда включать `'str'` для строковых полей. `AnsibleUnsafeText` появляется только при интерполяции переменных через Jinja2, не при парсинге JSON.

---

## 4. Финальная структура

```
molecule/
  shared/
    converge.yml    ← pre_tasks: chrony install + start + wait_for socket
    verify.yml      ← include_tasks ../../tasks/verify.yml + exit code + permissions
                       + logrotate syntax + JSON field types + Alloy content check
  default/
    molecule.yml    ← playbooks: converge/verify → ../shared/
  docker/
    molecule.yml    ← ANSIBLE_ROLES_PATH: ${MOLECULE_PROJECT_DIRECTORY}/../
                       test_sequence: syntax/create/converge/idempotence/verify/destroy
  disabled/
    converge.yml    ← vars: ntp_audit_enabled: false
    molecule.yml    ← localhost scenario
    verify.yml      ← assert: no zipapp, no log dir, no timer
```

```
tasks/
  verify.yml           ← единый источник истины: stat/assert для zipapp, logdir,
                          logfile, JSON keys, systemctl timer, logrotate, src, alloy, loki
  scheduler_assert.yml ← systemctl is-enabled/is-active (не service_facts)

templates/ntp-audit/
  __main__.py.j2       ← exception handler: write_log FIRST, syslog after
```

---

## 5. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `service_facts` не возвращает `.timer` юниты — использовать `systemctl is-enabled`/`is-active` | Все роли с timer |
| 2 | Exception handler обязан писать в файл-лог до syslog — `/dev/log` нет в Docker | Все Python-скрипты |
| 3 | `wait_for` нужен для сокетов, которые открываются асинхронно после `service: started` | Chrony, любой socket-based daemon |
| 4 | `from_json` возвращает нативные Python-типы; `AnsibleUnsafeText` только из Jinja2 | Все type_debug assertions |
| 5 | `test_sequence` копировать из соседней роли, не писать вручную | docker/molecule.yml |
| 6 | В CI `MOLECULE_PROJECT_DIRECTORY` = директория роли, не `ansible/` | Все shared verify |
| 7 | Vault `vars_files` нельзя в shared playbooks — CI без vault | Все shared converge/verify |

---

## 6. Known gaps (за рамками задачи)

- **`disabled` сценарий не покрывает переход `enabled` → `disabled`** — нет теста миграции (снос таймера, удаление бинаря). Отдельная задача.
- **`logrotate syntax check` пропускается если `logrotate` не установлен** — в Docker-образе он может отсутствовать. Явно помечено `when: logrotate_binary.rc == 0`, что корректно, но снижает покрытие.
- **Нет теста на `chrony_error` JSON поле в error-path** — verify всегда запускается после успешного converge (chrony работает), поэтому error record не тестируется.
