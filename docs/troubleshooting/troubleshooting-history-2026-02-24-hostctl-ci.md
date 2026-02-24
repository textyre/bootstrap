# Troubleshooting History — 2026-02-24

## Post-Mortem: hostctl CI — 10 итераций до зелёного

### Контекст

Задача: добавить CI тесты для роли `hostctl` (docker сценарий для GitHub Actions).
Итог: 10 коммитов, ~2 часа, 9 неудачных CI прогонов до успеха.

---

## Хронология инцидента

```
Коммит 1  feat(hostctl): add docker molecule scenario
          └─ FAIL: binary download — arch неверный (64bit вместо amd64)

Коммит 2  fix(hostctl): map x86_64 arch to amd64 for hostctl download URL
          └─ FAIL: stat.executable field не существует (Ansible 2.18 regression?)

Коммит 3  fix(hostctl): use access() for executable check instead of stat.executable
          └─ FAIL: verify — app.local не в /etc/hosts (entries not applied)

Коммит 4  fix(hostctl): rename docker profile to registry to avoid subcommand conflict
          └─ FAIL: entries не в /etc/hosts — hostctl sync не работает

Коммит 5  fix(hostctl): use hostctl add --from file instead of sync
          └─ FAIL: та же проблема — пустые секции в /etc/hosts

Коммит 6  fix(hostctl): remove '# hostctl' comment from profile template
          └─ FAIL: та же проблема — template format не при чём

Коммит 7  debug(hostctl): re-add diagnostics to see /etc/hosts state after template fix
          └─ FAIL + данные: /etc/hosts = ['# profile.on dev', '# end'] — секции есть, но ПУСТЫЕ

Коммит 8  debug(hostctl): add post_tasks to converge for hostctl replace diagnostic
          └─ FAIL + данные: hostctl replace rc=0, stdout=[], stderr=[] — тихий no-op

Коммит 9  debug(hostctl): test echo write, hostctl add --ip, and help text
          └─ FAIL + данные: echo >> /etc/hosts работает; hostctl add --ip = unknown flag

Коммит 10 fix(hostctl): use hostctl add domains to apply profiles  [FINAL]
           └─ SUCCESS ✓
```

---

## Решено

- [x] **hostctl CI тест** — добавлен `molecule/docker/` сценарий
- [x] **Неверный arch в URL** — `x86_64` → `amd64` в `vars/main.yml`
- [x] **stat.executable regression** — переход на `access()` задачу для проверки бинаря
- [x] **Конфликт профиля `docker`** — переименован в `registry` (hostctl трактует `docker` как субкоманду)
- [x] **Пустые секции в /etc/hosts** — root cause: `hostctl replace/add --from file` не добавляет записи; корректный API: `hostctl add domains [profile] [hosts] --ip IP`

---

## Анализ первопричин

### Root Cause 1 — hostctl add domains (PRIMARY)

Ключевое открытие: `hostctl replace --from file` и `hostctl add --from file` **тихо создают пустые секции** в `/etc/hosts`. Они возвращают `rc=0, stdout=[], stderr=[]`, и никакой ошибки нет — просто записи не добавляются.

Реальный API для добавления IP-hostname записей — субкоманда `add domains`:

```
hostctl add domains [profile] [domains] [flags]
Flags:
  --ip string   domains ip (default "127.0.0.1")
```

Обнаружено через `hostctl add domains --help` в диагностических `post_tasks` в `converge.yml`.

Финальный паттерн (идемпотентный):
```shell
hostctl remove {{ item.key }} 2>/dev/null || true
hostctl add domains {{ item.key }} {{ entry.host }} --ip {{ entry.ip }}
# (повторяется для каждой записи)
```

`remove` сначала — чтобы при повторном apply не дублировались записи.

Идемпотентность обеспечивается структурно: handler вызывается только при изменении template файла. При втором прогоне файл не меняется → handler не вызывается → `/etc/hosts` не трогается → `changed=0`.

### Root Cause 2 — Конфликт имени профиля `docker`

В `converge.yml` профиль назывался `docker`. Это не строка — hostctl трактует `docker` как субкоманду в некоторых контекстах, что вызывало неожиданное поведение.

Переименован в `registry` (семантически корректно — он описывает `registry.local`).

### Root Cause 3 — Неверный формат arch в download URL

hostctl GitHub Releases использует `amd64`, не `x86_64`. В `vars/main.yml` было:

```yaml
x86_64: "64bit"   # ← неверно
```

hostctl ожидает:

```yaml
x86_64: "amd64"   # ← правильно
```

Соответствие выяснено из реального listing GitHub Releases assets.

### Root Cause 4 — stat.executable (MINOR)

Таск `when: not stat.stat.executable` падал. Причина неизвестна — либо regression в Ansible 2.18, либо inconsistency в arch-systemd образе. Заменён на `ansible.builtin.command: test -x {{ hostctl_install_path }}` с `register` + `failed_when`.

---

## Диагностическая цепочка

Ключевой момент — в 8-й и 9-й итерациях добавлены `post_tasks` в `converge.yml` с прямыми shell командами. Они показали:

**Итерация 8:**
```yaml
- name: Test hostctl replace from file
  ansible.builtin.shell: hostctl replace dev --from /etc/hostctl/dev.hosts
  register: r
# Результат: rc=0, stdout=[], stderr=[]  ← тихий no-op
```

**Итерация 9:**
```yaml
- name: Test echo write to /etc/hosts
  ansible.builtin.shell: echo "127.0.0.1 echotest.local" >> /etc/hosts
# Результат: rc=0 ✓ — echotest.local появился в hostctl list (default profile)

- name: Test hostctl add --ip flag
  ansible.builtin.shell: hostctl add dev --ip 127.0.0.1 app.local api.local
# Результат: rc=1, stderr="[✖] error: unknown flag: --ip"

- name: Get hostctl add domains help
  ansible.builtin.shell: hostctl add domains --help
# Результат: правильный синтаксис с --ip флагом
```

Это подтвердило: проблема не в Docker bind mounts (echo работает), а в API hostctl.

---

## Почему так долго?

| Итерация | Гипотеза | Почему неверна | Потеря времени |
|----------|----------|----------------|----------------|
| 3→4 | «Профиль `docker` конфликтует» | Частично верно, но не root cause | 1 цикл CI |
| 4→5 | «`sync` не работает, нужен `add`» | `add --from` тоже создаёт пустые секции | 1 цикл CI |
| 5→6 | «Проблема в формате файла — `# hostctl` comment» | Формат не при чём | 1 цикл CI |
| 6→7 | «Убрали comment — должно работать» | Та же проблема | 1 цикл CI |
| 7→8 | «Нужен `replace` вместо `add`» | Оба создают пустые секции | 1 цикл CI |
| 8→9 | «Нужна прямая запись» | echo работает, но правильный API другой | 1 цикл CI |
| 9→10 | «`add domains` — корректный API» | Верно ✓ | — |

**Главная причина задержки**: документация hostctl не описывает семантику `--from file`. Не было ясно, что `replace/add --from file` создаёт только маркеры секций без содержимого. Нужно было запустить диагностику значительно раньше — в идеале на итерации 4, а не 8.

---

## Что было сделано неправильно

| # | Что сделано | Лучше было бы |
|---|-------------|---------------|
| 1 | Несколько итераций меняли формат profile.j2 без данных | Добавить диагностику в первую итерацию сбоя |
| 2 | Не прочитали `hostctl --help` и `hostctl add domains --help` перед первым handler | `hostctl add domains --help` нужно было прочитать до написания handler |
| 3 | Debug вывод добавлен на 8-й итерации | Debug-first: собрать факты, потом фиксить |
| 4 | Попытки изменить template format без понимания как `--from` работает | Проверить реальное поведение: что происходит с /etc/hosts после hostctl replace |
| 5 | Конфликт `docker` profile name найден на 4-й итерации | Проверять имена профилей на конфликт с subcommand-ами hostctl заранее |

---

## Ключевые факты о hostctl v1.1.4

### Что работает

```shell
# Добавить записи в профиль
hostctl add domains <profile> <host1> <host2> --ip <ip>

# Удалить профиль целиком
hostctl remove <profile>

# Список профилей
hostctl list

# Статус конкретного профиля
hostctl status <profile>
```

### Что НЕ работает так, как ожидается

```shell
# Создаёт пустую секцию, НЕ добавляет записи из файла:
hostctl replace <profile> --from <file>   ← только маркер секции
hostctl add <profile> --from <file>       ← только маркер секции

# Флага --ip нет у hostctl add (есть только у hostctl add domains):
hostctl add <profile> --ip <ip> <host>   ← unknown flag: --ip
```

### Идемпотентный паттерн для Ansible handler

```yaml
- name: Apply hostctl profiles
  ansible.builtin.shell: |
    hostctl remove {{ item.key }} 2>/dev/null || true
    {% for entry in item.value %}
    hostctl add domains {{ item.key }} {{ entry.host }} --ip {{ entry.ip }}
    {% endfor %}
  loop: "{{ hostctl_profiles | dict2items }}"
  listen: "apply hostctl profiles"
  changed_when: true
  when: hostctl_profiles | length > 0
```

Handler вызывается только при изменении template файла → при повторном converge handler не вызывается → idempotence проходит.

### Конфликтующие имена профилей

Не использовать в качестве имён профилей subcommand-ы hostctl:

```
add, remove, list, status, sync, enable, disable, backup, restore, domains
```

---

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/hostctl/vars/main.yml` | `x86_64: "64bit"` → `x86_64: "amd64"` |
| `ansible/roles/hostctl/tasks/download.yml` | Убрана проверка `stat.executable`, заменена на `test -x` |
| `ansible/roles/hostctl/handlers/main.yml` | Переписан: `hostctl sync`/`replace` → `hostctl remove` + `hostctl add domains` |
| `ansible/roles/hostctl/templates/profile.j2` | Несколько промежуточных изменений; финальный формат: plain IP hostname |
| `ansible/roles/hostctl/molecule/docker/converge.yml` | Debug `post_tasks` добавлены, затем убраны |
| `ansible/roles/hostctl/molecule/docker/verify.yml` | Профиль `docker` → `registry`; debug таски добавлены, затем убраны |

---

## Итог

CI тесты для роли `hostctl` работают. Тест честный: роль реально скачивает бинарь, создаёт директорию `/etc/hostctl`, прописывает профили в `/etc/hosts` через `hostctl add domains`, verify проверяет наличие hostnames в `/etc/hosts`.

Ключевые уроки:
1. **Читай `--help` инструмента до написания handler** — `hostctl add domains --help` показал правильный API на первой же секунде
2. **Debug-first** — добавлять диагностические таски в первую итерацию при неожиданном поведении, не после 5-ти циклов CI
3. **`rc=0` ≠ "что-то сделано"** — hostctl `replace/add --from file` всегда возвращает rc=0, даже когда записи не добавлены
4. **Проверяй имена на конфликт** — имена профилей hostctl не должны совпадать с его subcommand-ами
