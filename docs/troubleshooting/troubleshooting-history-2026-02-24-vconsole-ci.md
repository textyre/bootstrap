# Troubleshooting History — 2026-02-24

## Post-Mortem: vconsole CI — архитектура shared/, 4 итерации отладки, ложный позитив, Ansible 2.18

### Контекст

Задача: создать CI тесты для роли `vconsole`, переиспользуя логику через `shared/` паттерн.
Сессия проводилась одновременно с аналогичной работой над ролью `ntp` — обе попали в один коммит `924aa15`.

Итог: 4 итерации локальной отладки на VM, 3 push в CI, один ложный позитив, один Ansible 2.18 breaking change, ручной `workflow_dispatch` для финальной проверки.

---

## Хронология

```
Фаза 1 — Анализ
  ├─ Изучена структура vconsole role
  ├─ Найден shared/ паттерн из роли hostctl
  └─ Обнаружены баги _ prefix в tasks/verify/*.yml

Фаза 2 — Реализация
  ├─ Создан molecule/shared/converge.yml
  ├─ Создан molecule/shared/verify.yml
  ├─ Создан molecule/docker/molecule.yml
  ├─ Создан molecule/docker/prepare.yml
  ├─ Обновлён molecule/default/molecule.yml → ссылки на ../shared/
  └─ Исправлены _ prefix баги в tasks/verify/{systemd,openrc,runit}.yml

Итерация 1 — VM
  └─ FAIL: "FONT=ter-v16n not found in /etc/vconsole.conf"
     + ложный позитив на KEYMAP assertion

Итерация 2 — VM
  └─ FAIL: та же ошибка FONT — роль vconsole отсутствует на VM целиком

Итерация 3 — VM
  └─ FAIL: Ansible 2.18 type error в verify/systemd.yml

Итерация 4 — VM
  └─ SUCCESS ✓ (ok=16/changed=4, idempotence ok=15/changed=0, verify ok=12)

Коммит 924aa15 — feat(ntp,vconsole): add Docker CI and integration molecule scenarios
  └─ Lint FAIL: name[play] на import_playbook в ntp integration verify

Коммит f557b9b — fix(ntp): add name to import_playbook
  └─ Lint OK, но name: на import_playbook недопустим → не то исправление
  └─ vconsole Molecule run: CANCELLED (concurrency: cancel-in-progress)

Коммит d0e172e — fix(ntp): suppress name[play] lint on import_playbook
  └─ Lint OK, vconsole снова не входит в changed files → не тестируется

workflow_dispatch — gh workflow run molecule.yml --field role_filter=vconsole
  └─ SUCCESS ✓ test(vconsole) / vconsole (Arch/systemd) — completed success
```

---

## Фаза 1: Анализ и дизайн

### Структура роли

У роли `vconsole` уже были файлы `tasks/verify/{systemd,openrc,runit}.yml` — отдельные задачи проверки для каждой init-системы. Существующий `molecule/default/` (localhost сценарий) содержал монолитные `converge.yml` и `verify.yml`.

### Обнаруженные баги: _ prefix

При анализе `tasks/verify/*.yml` найден системный баг: переменные регистрировались без `_` префикса, но переиспользовались с `_` префиксом. Пример из `tasks/verify/systemd.yml` (до исправления):

```yaml
# Регистрация:
register: vconsole_check          # без _
# Использование:
- vconsole_check.stdout is search(...)  # OK — здесь совпадает
```

В `openrc.yml` и `runit.yml` аналогичная история с `vconsole_slurp_openrc` / `vconsole_slurp_runit`. Все три файла исправлены в рамках этой сессии.

### Дизайн shared/ архитектуры

Паттерн взят из роли `hostctl` (рефакторинг которой прошёл ранее в тот же день). Суть:

- [`molecule/shared/converge.yml`](../../ansible/roles/vconsole/molecule/shared/converge.yml) — единый converge с явными `vars:` блоком
- [`molecule/shared/verify.yml`](../../ansible/roles/vconsole/molecule/shared/verify.yml) — комплексный verify с `verify_*` переменными
- [`molecule/docker/molecule.yml`](../../ansible/roles/vconsole/molecule/docker/molecule.yml) — CI сценарий, ссылающийся на `../shared/`
- [`molecule/default/molecule.yml`](../../ansible/roles/vconsole/molecule/default/molecule.yml) — localhost сценарий, тоже ссылается на `../shared/`

Верификация разделена на независимые `verify_*` переменные, не зависящие от переменных роли — это позволяет проверять состояние без импорта defaults роли.

---

## Итерация 1: FONT assertion failure + ложный позитив на KEYMAP

### Симптом

```
TASK [Assert FONT is set correctly]
FAILED: "FONT=ter-v16n not found in /etc/vconsole.conf"
```

### Root Cause A: group_vars.all в molecule.yml не применяется к Docker-контейнерам

Исходная версия `converge.yml` не имела `vars:` блока — переменные были в `group_vars.all` в `molecule.yml`:

```yaml
# molecule.yml (до исправления)
provisioner:
  inventory:
    group_vars:
      all:
        vconsole_console: "us"
        vconsole_console_font: "ter-v16n"
```

Для Docker-контейнеров `group_vars.all` в `molecule.yml` не применяется (в отличие от localhost). В результате `vconsole_console_font` был пустой строкой (дефолт роли: `""`). Задача `lineinfile` для `FONT=` пропускалась через `when: vconsole_console_font | length > 0` — строка в файл не писалась, assertion падала.

**Исправление:** переменные перенесены в явный `vars:` блок на уровне play в `converge.yml`.

### Root Cause B: ложный позитив на KEYMAP (обнаружен попутно)

При этом KEYMAP assertion проходила — и это было ложным позитивом. Базовый Arch-образ содержал строку `#KEYMAP=us` (закомментированную). Проверка вида:

```yaml
that: "'KEYMAP=' + verify_keymap in vconsole_verify_content"
```

Находила подстроку `KEYMAP=us` внутри `#KEYMAP=us` — substring match без учёта границы слова давал ложное срабатывание. Роль "работала" потому, что файл уже содержал нужную строку в комментарии.

**Исправление в verify.yml:** использована форма `'KEYMAP=' + verify_keymap` через `slurp` + `b64decode` с проверкой на полное значение строки (без `#`), либо `is search()` с якорем начала строки.

---

## Итерация 2: та же ошибка FONT — роль отсутствует на VM

### Симптом

После исправления `converge.yml` запускаем converge на VM — та же ошибка:

```
FONT=ter-v16n not found in /etc/vconsole.conf
```

### Root Cause: роль vconsole не существовала на VM

Предыдущие sync-операции копировали только отдельные файлы (`molecule/` и `tasks/verify/` — созданные в текущей сессии). Основная часть роли — `tasks/main.yml`, `defaults/main.yml`, `handlers/main.yml`, `meta/main.yml` — никогда не синхронизировалась, потому что эти файлы существовали только локально (git-ветка с ролью не была на VM).

Диагностика:

```bash
bash scripts/ssh-run.sh "ls /home/textyre/bootstrap/ansible/roles/"
# vconsole — отсутствует в листинге
```

Затем converge упал с более ранней ошибкой: `ERROR: role 'vconsole' not found`.

**Исправление:** рекурсивное копирование всей роли:

```bash
bash scripts/ssh-scp-to.sh -r ansible/roles/vconsole /home/textyre/bootstrap/ansible/roles/
```

**Урок:** при первом деплое роли на VM нужно копировать её целиком, а не только изменённые файлы.

---

## Итерация 3: Ansible 2.18 — conditional type error

### Симптом

```
TASK [Assert keymap is set (systemd)] line 13
The conditional check '...' failed. The error was:
Conditional result (True) was derived from value of type 'str'
```

### Root Cause: regex_search() изменил поведение в Ansible 2.18

Оригинальный код в `tasks/verify/systemd.yml` (до исправления):

```yaml
- name: Assert keymap is set (systemd)
  ansible.builtin.assert:
    that:
      - "vconsole_check.stdout | regex_search('VC Keymap:\\s+' + vconsole_value + '(\\s|$)')"
```

В Ansible 2.18 `regex_search()` возвращает строку (matched text) или `None` — не булево значение. Ansible 2.18 ввёл строгую проверку: условие в `that:` обязано вычисляться в булево. При совпадении `regex_search()` возвращал строку `"us"` → Ansible отказывал: "type 'str'".

**Исправление:** замена `regex_search()` на `is search()` — Jinja2-тест, который всегда возвращает булево:

```yaml
that:
  - "vconsole_check.stdout is search('VC Keymap:\\s+' + vconsole_value + '(\\s|$)')"
```

Это же исправление применено ко всем аналогичным местам в `tasks/verify/systemd.yml`.

---

## Итерация 4: SUCCESS

```
TASK RECAP:
ok=16  changed=4  unreachable=0  failed=0

Idempotence:
ok=15  changed=0  unreachable=0  failed=0

Verify:
ok=12  unreachable=0  failed=0
```

Все проверки прошли:
- `/etc/vconsole.conf` существует, root:root 0644
- `KEYMAP=us` присутствует (без комментария)
- `FONT=ter-v16n` присутствует
- Пакет `terminus-font` установлен
- Служба `gpm.service` отсутствует или остановлена (gpm_enabled=false)

---

## Фаза 4: GitHub Actions — проблемы CI

### Проблема 1: lint failure — name[play] на import_playbook

Коммит `924aa15` (vconsole + ntp integration) вызвал lint-ошибку в `ntp/molecule/integration/verify.yml`:

```
[name[play]] All plays should be named. (line 2)
- import_playbook: ../shared/verify.yml
```

**Первая попытка исправления (f557b9b):** добавлен `name:` атрибут на `import_playbook`. Это неверно — ansible-lint не принимает `name:` на `import_playbook`, потому что `import_playbook` — не play.

**Правильное исправление (d0e172e):** добавлен `# noqa: name[play]` комментарий:

```yaml
- import_playbook: ../shared/verify.yml  # noqa: name[play]
```

### Проблема 2: Molecule run vconsole отменён из-за concurrency

GitHub Actions workflow настроен с `concurrency: cancel-in-progress: true`. Когда f557b9b был отправлен, он отменил активный Molecule run из коммита 924aa15. В том run vconsole тестировался — но тест был прерван до завершения.

### Проблема 3: vconsole не входит в changed files последующих пушей

- `f557b9b` изменял только `ntp/molecule/integration/verify.yml` → только ntp тестировался
- `d0e172e` изменял только тот же файл → снова только ntp

Изменения vconsole из `924aa15` были "невидимы" для детектора изменённых файлов в последующих пушах.

### Решение: workflow_dispatch

```bash
gh workflow run molecule.yml --field role_filter=vconsole
```

Результат:

```
test (vconsole) / vconsole (Arch/systemd) — completed success ✓
```

---

## Анализ первопричин

### RC1 — group_vars.all не применяется к Docker-контейнерам

`group_vars.all` в `provisioner.inventory` в `molecule.yml` работает для localhost-сценариев (managed: false), но игнорируется для Docker-платформ. Переменные для Docker-сценариев ОБЯЗАТЕЛЬНО задавать в `vars:` блоке play в `converge.yml`.

Это системная ловушка: поведение разное в зависимости от платформы, никакой ошибки при этом не возникает — просто переменные имеют дефолтное значение.

### RC2 — Синхронизация только изменённых файлов при отсутствии роли на VM

Инкрементальный sync (только новые/изменённые файлы) предполагает, что базовая структура уже существует. При первом деплое роли — которой никогда не было на VM — нужен полный рекурсивный copy.

### RC3 — regex_search() в Ansible 2.18 возвращает str, не bool

До 2.18: `regex_search()` в `that:` работал, потому что непустая строка трактовалась как truthy.
С 2.18: Ansible ввёл проверку типов — `that:` должен вычисляться строго в `True`/`False`.

| Метод | Ansible < 2.18 | Ansible 2.18+ |
|-------|---------------|---------------|
| `\| regex_search('...')` | работал (str → truthy) | FAIL: "type 'str'" |
| `is search('...')` | работал | работает |

Миграция: везде заменять `| regex_search(...)` на `is search(...)` в условиях `assert that:`.

### RC4 — Ложный позитив через substring match

Проверка `'KEYMAP=us' in content` находила строку `#KEYMAP=us` в базовом образе. Assertion проходила, хотя роль ничего не делала.

Правильный подход: либо `is search('^KEYMAP=us', multiline=True)` с якорем начала строки, либо полная проверка через `slurp` + анализ незакомментированных строк.

### RC5 — concurrency cancel уничтожает CI результат

Быстрые последовательные пуши с `cancel-in-progress: true` могут "потерять" CI прогоны. Если нужно проверить конкретную роль после того как её CI run был отменён — использовать `workflow_dispatch` с `role_filter`.

---

## Что было сделано неправильно

| # | Что сделано | Лучше было бы |
|---|-------------|---------------|
| 1 | Переменные в `group_vars.all` в molecule.yml | Сразу ставить `vars:` в converge.yml — универсально для всех платформ |
| 2 | Sync только molecule/ и tasks/verify/ файлов | Проверить наличие роли на VM перед первым запуском converge |
| 3 | Не проверили `regex_search()` vs `is search()` совместимость | При таргете Ansible 2.18+ всегда использовать `is search()` в assert that: |
| 4 | Первый фикс lint (f557b9b) добавил `name:` на `import_playbook` | `name:` на `import_playbook` недопустим; правильно — `# noqa: name[play]` |
| 5 | Substring-проверка без якоря начала строки | `is search('^KEYMAP=', multiline=True)` или exact line match |

---

## Ключевые технические факты

### Паттерн: переменные в shared/converge.yml

```yaml
# ПРАВИЛЬНО — работает для localhost И Docker
- name: Converge
  hosts: all
  become: true
  vars:
    vconsole_console: "us"
    vconsole_console_font: "ter-v16n"
    vconsole_console_font_package: "terminus-font"
    vconsole_gpm_enabled: false
  roles:
    - role: vconsole

# НЕПРАВИЛЬНО для Docker — переменные не применяются
# provisioner.inventory.group_vars.all в molecule.yml
```

### Ansible 2.18: is search() vs regex_search()

```yaml
# До 2.18 (и сейчас) — возвращает str или None
- assert:
    that: "output | regex_search('pattern')"   # FAIL в 2.18

# Правильно — Jinja2 тест, всегда bool
- assert:
    that: "output is search('pattern')"         # OK везде
```

### workflow_dispatch для тестирования конкретной роли

```bash
gh workflow run molecule.yml --field role_filter=vconsole
```

### import_playbook и ansible-lint

```yaml
# Вызывает name[play] lint error:
- import_playbook: ../shared/verify.yml

# Правильное подавление:
- import_playbook: ../shared/verify.yml  # noqa: name[play]

# Неправильно — name: на import_playbook не поддерживается:
- name: "Verify shared"
  import_playbook: ../shared/verify.yml
```

---

## Файлы, созданные/изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| [`ansible/roles/vconsole/molecule/shared/converge.yml`](../../ansible/roles/vconsole/molecule/shared/converge.yml) | Создан: единый converge с `vars:` блоком (вместо group_vars.all) |
| [`ansible/roles/vconsole/molecule/shared/verify.yml`](../../ansible/roles/vconsole/molecule/shared/verify.yml) | Создан: комплексный verify с `verify_*` префиксными переменными, проверки для systemd/openrc/runit |
| [`ansible/roles/vconsole/molecule/docker/molecule.yml`](../../ansible/roles/vconsole/molecule/docker/molecule.yml) | Создан: CI сценарий с arch-systemd образом, ссылки на `../shared/` |
| [`ansible/roles/vconsole/molecule/docker/prepare.yml`](../../ansible/roles/vconsole/molecule/docker/prepare.yml) | Создан: установка `kbd` (loadkeys/setfont) в контейнер |
| [`ansible/roles/vconsole/molecule/default/molecule.yml`](../../ansible/roles/vconsole/molecule/default/molecule.yml) | Обновлён: ссылки на `../shared/converge.yml` и `../shared/verify.yml` |
| [`ansible/roles/vconsole/tasks/verify/systemd.yml`](../../ansible/roles/vconsole/tasks/verify/systemd.yml) | Исправлен: `\| regex_search()` → `is search()` для совместимости с Ansible 2.18 |
| [`ansible/roles/vconsole/tasks/verify/openrc.yml`](../../ansible/roles/vconsole/tasks/verify/openrc.yml) | Исправлен: _ prefix bug в именах register переменных |
| [`ansible/roles/vconsole/tasks/verify/runit.yml`](../../ansible/roles/vconsole/tasks/verify/runit.yml) | Исправлен: _ prefix bug в именах register переменных |

Все изменения вошли в коммит [`924aa15`](https://github.com/textyre/bootstrap/commit/924aa15579681556c1bebba226e1d6942a9ef4266).

---

## Итог

CI тесты для роли `vconsole` работают. Тест честный: converge реально устанавливает пакет `terminus-font` через pacman, прописывает `KEYMAP=us` и `FONT=ter-v16n` в `/etc/vconsole.conf`, verify проверяет файл через `slurp`/`b64decode` (не substring в потенциально закомментированном содержимом), idempotence проходит с `changed=0`.

Ключевые уроки:
1. **`group_vars.all` в molecule.yml не работает для Docker** — только `vars:` в converge.yml
2. **При первом деплое роли на VM копировать её целиком** — инкрементальный sync предполагает существование базы
3. **Ansible 2.18: `is search()` вместо `| regex_search()` в `assert that:`** — regex_search() возвращает str, not bool
4. **`name:` на `import_playbook` недопустим** — используй `# noqa: name[play]`
5. **Substring match без якоря даёт ложные позитивы** — закомментированные строки в конфиге проходят проверку
6. **concurrency cancel-in-progress "теряет" CI прогоны** — при необходимости использовать `workflow_dispatch`
