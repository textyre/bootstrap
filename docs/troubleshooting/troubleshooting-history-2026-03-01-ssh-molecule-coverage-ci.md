# Post-Mortem: Molecule CI — расширение покрытия роли `ssh`

**Дата:** 2026-03-01
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)
**Итерации CI:** 3 запуска, 3 уникальных ошибки (2 реальных + 1 self-inflicted)
**Коммиты:** `d074a6f` + `152da91` (2 фикс-коммита поверх 11 коммитов фичи), PR #50
**Скоуп:** 268 добавленных строк, 20 удалённых, 7 изменённых файлов

---

## 1. Задача

Расширить molecule-тесты роли `ssh` — покрыть директивы управления доступом,
интеграцию с Teleport CA, SFTP chroot, модули DH, а также поднять 6 Docker-платформ
вместо 1 для максимально широкого параметрического тестирования.

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker (`molecule/docker/`) — было | 1 платформа (Archlinux-systemd) | Базовый hardening конфиг |
| Docker (`molecule/docker/`) — стало | 6 платформ | Базовый hardening + access-control + features |
| Vagrant arch-vm | `arch-base` box (KVM) | Полный тест на реальном systemd |
| Vagrant ubuntu-base | `ubuntu-base` box (KVM) | То же на Ubuntu |

**Новые Docker-платформы:**

| Платформа | ОС | Цель |
|-----------|-----|------|
| `Arch-access-control` | Archlinux-systemd | AllowGroups / AllowUsers / DenyGroups / DenyUsers |
| `Ubuntu-access-control` | Ubuntu-systemd | То же на Debian-семействе |
| `Arch-features` | Archlinux-systemd | Teleport CA (`TrustedUserCAKeys`), SFTP chroot (`Match Group sftponly`), `ListenAddress` |
| `Ubuntu-features` | Ubuntu-systemd | То же на Debian-семействе |

Итог по покрытию: `verify.yml` вырос с ~120 до ~620 строк, ~70 assertions суммарно
по всем платформам.

---

## 2. Инциденты

### Инцидент #1 — Docker Ubuntu-features: `/etc/ssh` не существует до установки пакета

**Коммит фикса:** `d074a6f`
**CI-прогон:** первый (run 22547333843)
**Этап:** `prepare`
**Симптом:**

```
TASK [prepare : Create fake Teleport user CA key file (features platforms)]
fatal: [Ubuntu-features]: FAILED! =>
  {
    "msg": "Destination directory /etc/ssh does not exist"
  }
```

**Контекст:**

Для платформ `*-features` в `prepare.yml` создавался фиктивный Teleport CA-ключ:

```yaml
- name: Create fake Teleport user CA key file (features platforms)
  ansible.builtin.copy:
    content: "ssh-ed25519 AAAA... fake-teleport-ca\n"
    dest: /etc/ssh/teleport_user_ca.pub
    mode: "0644"
  when: inventory_hostname is search('features')
```

**Причина:**

На Arch-based образах (`archlinux:latest`) директория `/etc/ssh` **присутствует** в базовом
образе — openssh устанавливается как зависимость многих пакетов или присутствует в образе.

На Ubuntu-based образах (`ubuntu:22.04` / `ubuntu:24.04`) директория `/etc/ssh`
**не создаётся до установки пакета `openssh-server`**. Базовый образ Ubuntu не содержит
OpenSSH. Директория появляется только в `converge`-фазе при выполнении
`ansible.builtin.package: name: openssh-server`. Но `prepare` выполняется **до** `converge`.

Таким образом:
```
prepare (наш CA-файл) → converge (установка openssh-server) → verify
         ↑ падает                 ↑ создаёт /etc/ssh
```

Задача `copy` не создаёт parent-директории автоматически — это ответственность caller'а.

**Почему Arch-платформы прошли:** на Arch `archlinux:latest` директория `/etc/ssh` создаётся
либо файловой системой пакета openssh (если он уже в образе), либо существует как часть
системного дерева. На Ubuntu minimal-образе этого нет.

**Диагностика:**

```bash
# Воспроизведение:
docker run --rm ubuntu:22.04 ls -la /etc/ssh
# → ls: cannot access '/etc/ssh': No such file or directory

docker run --rm archlinux bash -c "ls -la /etc/ssh 2>&1"
# → /etc/ssh существует (пустая, но есть)
```

**Фикс:**

Добавить задачу создания директории **перед** копированием файла, с той же guards-условием:

```yaml
- name: Ensure /etc/ssh exists (features platforms — Ubuntu container lacks it pre-install)
  ansible.builtin.file:
    path: /etc/ssh
    state: directory
    mode: "0755"
  when: inventory_hostname is search('features')

- name: Create fake Teleport user CA key file (features platforms)
  ansible.builtin.copy:
    content: "ssh-ed25519 AAAA... fake-teleport-ca\n"
    dest: /etc/ssh/teleport_user_ca.pub
    mode: "0644"
  when: inventory_hostname is search('features')
```

`ansible.builtin.file` с `state: directory` идемпотентен: если директория уже существует
(Arch) — no-op; если не существует (Ubuntu) — создаёт.

**Урок:** Никогда не предполагать, что Ubuntu-контейнер имеет те же директории уровня системы,
что и Arch-контейнер, если они принадлежат пакетам а не ОС. Явно создавать parent-директории
в prepare.yml перед копированием в них. Arch-first разработка скрывает Ubuntu-специфичные
пропуски.

---

### Инцидент #2 — Все платформы: `\b` в Jinja2 — backspace (ASCII 8), не word boundary

**Коммит фикса:** `152da91`
**CI-прогон:** второй (после d074a6f), тот же run 22547333843
**Этап:** `verify`
**Симптом:**

```
TASK [Assert Port 22]
fatal: [Arch-systemd]: FAILED! =>
  {
    "assertion": "_ssh_verify_sshd_content is regex('Port\\s+22\\b')",
    "msg": "Port is not set to 22"
  }

# То же самое на ALL 6 Docker-платформах + arch-vm + ubuntu-base
```

При этом соседнее утверждение, не содержащее `\b`, проходило без проблем:

```
TASK [Assert PermitRootLogin no]
ok: [Arch-systemd] => {"changed": false, "msg": "All assertions passed"}
```

**Затронутые assertions:**

```
Assert Port 22                             → regex('Port\s+22\b')
Assert AddressFamily inet                  → regex('AddressFamily\s+inet\b')
Assert AllowGroups sshusers (access-ctrl)  → regex('AllowGroups\s+sshusers\b')
Assert AllowUsers root (access-ctrl)       → regex('AllowUsers\s+root\b')
Assert DenyGroups badgroup (access-ctrl)   → regex('DenyGroups\s+badgroup\b')
Assert DenyUsers baduser (access-ctrl)     → regex('DenyUsers\s+baduser\b')
Assert ListenAddress 127.0.0.1 (features) → regex('ListenAddress\s+127\.0\.0\.1\b')
```

**Ключевое наблюдение:** `\s` работает в тех же самых строках (`Port\s+22`), а `\b` — нет.
Это указывает на различие в обработке этих escape-последовательностей.

**Корневая причина:**

Jinja2 обрабатывает строковые литералы через внутренний маппинг `_str_escapes`:

```python
# jinja2/lexer.py (упрощённо)
_str_escapes = {
    't': '\t',
    'n': '\n',
    'r': '\r',
    'b': '\x08',   # ← backspace, ASCII 8
    '\\': '\\',
}
```

Когда в YAML-файле написано `regex('Port\s+22\b')`:
1. YAML plain scalar: `\s` и `\b` — два символа каждый (`\` + буква), без обработки
2. Jinja2 получает строку: `Port\s+22\b`
3. Jinja2 обрабатывает escape-последовательности в single-quoted строке:
   - `\s` → Jinja2 не знает escape `\s` → передаёт как есть: два символа `\` + `s`
   - `\b` → Jinja2 знает `\b` = backspace (`\x08`) → заменяет на один символ ASCII 8
4. Python `re.search()` получает:
   - `\s` как два символа `\s` → интерпретирует как whitespace class ✓
   - `\x08` как один символ ASCII 8 → ищет буквальный backspace в sshd_config ✗

Результат: паттерн `Port\s+22\x08` никогда не найдёт совпадение в `/etc/ssh/sshd_config`
(там нет символов backspace). `assert` всегда падает на 100% платформ.

**Почему `\s` работает "по случайности":**

В Python/Jinja2 нет `\s` escape-последовательности. Jinja2 не находит её в словаре
`_str_escapes` и оставляет без изменений — два символа `\` + `s`. Модуль `re` получает
`\s` как двухсимвольную escape-последовательность и интерпретирует её как whitespace class.
Это работает, но не по замыслу — по недосмотру отсутствия в маппинге.

**Другие escapes, которые ломаются аналогично:**

| Escape | Jinja2 результат | В regex |
|--------|-----------------|---------|
| `\b`   | `\x08` (backspace) | ищет буквальный backspace ✗ |
| `\n`   | newline          | ищет буквальный newline ✗ |
| `\t`   | tab              | ищет буквальный tab (случайно верно) |
| `\r`   | carriage return  | ищет буквальный CR ✗ |

| Escape | Jinja2 результат | В regex |
|--------|-----------------|---------|
| `\s`   | `\s` (два символа) | whitespace class ✓ |
| `\d`   | `\d` (два символа) | digit class ✓ |
| `\w`   | `\w` (два символа) | word char class ✓ |
| `\B`   | `\B` (два символа) | non-word boundary ✓ |

**Правило:** в Ansible `that:` / Jinja2 `regex()` — использовать `\\b` (два слеша в YAML),
чтобы получить `\b` в regex-движке.

**Цепочка обработки при фиксе:**

```
YAML plain scalar: \\b
        ↓ (YAML: plain scalar, без обработки)
Jinja2 получает: \\b  (два символа: обратный слеш + обратный слеш + b)
        ↓ (Jinja2 _str_escapes: '\\' → '\')
Jinja2 рендерит: \b   (два символа: обратный слеш + b)
        ↓ (Python re)
re интерпретирует \b как word boundary ✓
```

**Фикс — 7 targeted Edit-вызовов:**

```yaml
# БЫЛО (всегда ложное совпадение):
that: _ssh_verify_sshd_content is regex('Port\s+22\b')

# СТАЛО (корректное word boundary):
that: _ssh_verify_sshd_content is regex('Port\s+22\\b')
```

Аналогично для оставшихся 6 паттернов.

**Почему `\b` вообще нужен:** без него `Port\s+22` совпадёт с `Port 221` или `Port 2222`.
Word boundary гарантирует, что после числа нет цифр/букв. В данном случае это паранойя
(sshd_config не имеет таких строк), но правильная практика для надёжных regex.

---

### Инцидент #3 (self-inflicted) — sed сломал verify.yml

**Статус:** обнаружен и исправлен в той же сессии, до push
**Этап:** локальная разработка
**Симптом:**

После применения sed-команды для фикса Инцидента #2:

```bash
sed -i 's/\\b)/\\\\b)/g' verify.yml
```

Файл `verify.yml` содержал повреждённые строки:

```yaml
# Было:
- name: Assert openssh package installed (Arch)
# Стало (сломано):
- name: Assert openssh package installed (Arch\b)

# Было:
- name: Stat ed25519 host key (private)
# Стало (сломано):
- name: Stat ed25519 host key (private\b)

# Было:
fail_msg: "sshd_config content empty (missing '====' in converge)"
# Стало (сломано):
fail_msg: "sshd_config content empty (missing '====' in converge\b)"
```

Итого: 36 строк изменены вместо 7.

**Причина:**

Паттерн `\b)` (backslash + b + закрывающая скобка) встречался в файле не только в
`that:` строках с regex, но и в:
- task `name:` полях: `(Arch)` → `Arch\b)` ✓ для sed
- task `name:` полях: `(private)` → `private\b)` ✓ для sed
- `fail_msg:` строках
- комментариях

Sed не понимает структуру YAML/Ansible — он работает с текстом как с потоком строк
без учёта семантики поля. Буква `b)` присутствует во многих местах.

Дополнительная проблема: sed с `\\b` в разных реализациях (GNU sed vs BSD sed vs MSYS2 sed)
обрабатывает escape-последовательности по-разному, что делало команду труднопредсказуемой.

**Диагностика:**

```bash
git diff --stat HEAD ansible/roles/ssh/molecule/shared/verify.yml
# → 36 insertions(+), 36 deletions(-)  ← должно быть 7
```

**Фикс:**

```bash
# 1. Откат через git
git checkout HEAD -- ansible/roles/ssh/molecule/shared/verify.yml

# 2. Семь точечных Edit-вызовов — по одному на каждую that: строку
#    (Edit tool требует уникального контекста — гарантирует одно совпадение)
```

Каждый Edit-вызов был строго ограничен одной строкой с known-контекстом:

```
old: that: _ssh_verify_sshd_content is regex('Port\s+22\b')
new: that: _ssh_verify_sshd_content is regex('Port\s+22\\b')
```

Итоговый diff — ровно 7 строк, только в `that:` fields.

**Урок:** для точечных изменений в структурированных файлах (YAML, JSON, Python) —
использовать Edit tool с уникальным контекстом, не sed. sed оперирует текстом без
семантики: строка `(Arch)` и строка `regex('...\b')` неразличимы для sed по паттерну `\b)`.
Если sed необходим — использовать `grep -n` для поиска кандидатов и убеждаться, что
паттерн уникален до применения.

---

## 3. Временная шкала

```
── Сессия 1 (предыдущая) ─────────────────────────────────────────────────────────

[Создан worktree]  /d/projects/bootstrap-ssh-coverage
                   branch: fix/ssh-molecule-coverage

[11 коммитов фичи]:
  refactor: move converge vars to molecule host_vars
  style: document ansible_user injection
  feat: add access-control docker platforms (2 платформы)
  fix: guard banner/AllowGroups-absent assertions by platform
  feat: add features docker platforms (2 платформы)
  fix: structurally valid ed25519 key blob for fake Teleport CA
  test: add Port/AddressFamily checks and moduli cleanup verification
  test: add access-control assertions (AllowGroups/AllowUsers/Deny*)
  test: add features assertions (Teleport CA, SFTP chroot, ListenAddress)
  fix: ANSIBLE_ROLES_PATH and host_vars for default scenario
  docs: update README — 6 docker platforms, 70 assertions

── CI run #1 (run 22547283158 / 22547333822) ─────────────────────────────────────

  Ansible Lint:  SUCCESS ✓
  Molecule Docker+Vagrant: FAILURE ✗

  Ошибка: Ubuntu-features — /etc/ssh не существует (Инцидент #1)

  d074a6f  fix(ssh/molecule): create /etc/ssh dir before CA key copy on Ubuntu containers
           ↓ Добавляет task: file path=/etc/ssh state=directory before copy
           ↓ Оба task guarded: when: inventory_hostname is search('features')

── CI run #2 (run 22547333843) ───────────────────────────────────────────────────

  Ошибка: Port is not set to 22 — ВСЕ 6 Docker + arch-vm + ubuntu-base (Инцидент #2)

  [Анализ]: \b в Jinja2 = backspace ASCII 8, не word boundary
  [Попытка фикса через sed]: sed -i 's/\\b)/\\\\b)/g' → сломал 36 строк (Инцидент #3)
  [Откат]: git checkout HEAD -- verify.yml
  [Точечный фикс]: 7 Edit-вызовов по одному на каждую that: строку

  152da91  fix(ssh/molecule): escape \b word-boundary in Jinja2 regex patterns
           ↓ 7 строк: \b → \\b только в that: regex() expressions
           ↓ Не затронуто: task names, fail_msg, comments

── CI run #3 (run 22547804286) ───────────────────────────────────────────────────

  Ansible Lint:     SUCCESS ✓
  Detect changed roles: SUCCESS ✓ (9s)
  test (ssh) / ssh (Arch+Ubuntu/systemd): SUCCESS ✓ (3m42s)
  test-vagrant (ssh, arch-vm):            SUCCESS ✓ (3m28s)
  test-vagrant (ssh, ubuntu-base):        SUCCESS ✓ (3m19s)

  PR #50 squash-merged → master ae65fd4
  Worktree удалён: git worktree remove --force /d/projects/bootstrap-ssh-coverage
  Локальная ветка удалена: git branch -d fix/ssh-molecule-coverage
```

---

## 4. Финальная структура изменений

```
ansible/roles/ssh/
├── README.md                              ← 6 платформ, 70 assertions
├── molecule/
│   ├── default/
│   │   └── molecule.yml                   ← фикс vault_password_file + host_vars path
│   ├── docker/
│   │   ├── molecule.yml                   ← РАСШИРЕН: 1 → 6 платформ; host_vars per-platform
│   │   └── prepare.yml                    ← РАСШИРЕН: /etc/ssh mkdir + CA key + sftponly group
│   ├── shared/
│   │   ├── converge.yml                   ← упрощён: vars перенесены в host_vars
│   │   └── verify.yml                     ← РАСШИРЕН: +99 строк; \b → \\b в 7 assertions
│   └── vagrant/
│       └── molecule.yml                   ← добавлены vagrant host_vars
```

**Docker платформы — итог:**

| Платформа | Группа переменных | Ключевые overrides |
|-----------|------------------|--------------------|
| `Arch-systemd` | базовые defaults | — |
| `Ubuntu-systemd` | базовые defaults | — |
| `Arch-access-control` | access-control | `ssh_allow_groups: [sshusers]`, `ssh_allow_users: [root]`, `ssh_deny_groups: [badgroup]`, `ssh_deny_users: [baduser]` |
| `Ubuntu-access-control` | access-control | то же |
| `Arch-features` | features | `ssh_teleport_integration: true`, `ssh_sftp_chroot_enabled: true`, `ssh_listen_addresses: [127.0.0.1]` |
| `Ubuntu-features` | features | то же |

---

## 5. Ключевые паттерны

### Jinja2 escapes в Ansible regex assertions

```yaml
# НЕПРАВИЛЬНО — \b Jinja2 интерпретирует как backspace (ASCII 8):
that: _content is regex('Port\s+22\b')
#                              ↑ backspace ≠ word boundary → всегда false

# ПРАВИЛЬНО — \\b: YAML plain scalar даёт \\, Jinja2 даёт \, re видит \b:
that: _content is regex('Port\s+22\\b')
#                              ↑ word boundary ✓
```

**Быстрая таблица для Ansible regex паттернов:**

| Нужно в regex | Писать в YAML | Почему |
|---------------|---------------|--------|
| `\b` (word boundary) | `\\b` | Jinja2 знает `\b` = backspace |
| `\s` (whitespace) | `\s` | Jinja2 не знает `\s`, передаёт as-is ✓ |
| `\d` (digit) | `\d` | Аналогично `\s` ✓ |
| `\w` (word char) | `\w` | Аналогично ✓ |
| `\n` (newline в regex) | `\\n` | Jinja2 знает `\n` = newline |
| `\t` (tab) | `\\t` | Jinja2 знает `\t` = tab |
| literal `\.` (в URL/IP) | `\\.` | Экранировать точку от regex |

### Prepare.yml для Ubuntu-контейнеров: явно создавать директории

```yaml
# Arch-контейнер: /etc/ssh существует в образе
# Ubuntu-контейнер: /etc/ssh появляется только при установке openssh-server (в converge)
# prepare выполняется ДО converge → нужно создать явно

- name: Ensure /etc/ssh exists (Ubuntu container lacks it pre-install)
  ansible.builtin.file:
    path: /etc/ssh
    state: directory
    mode: "0755"
  when: ansible_os_family == 'Debian'   # или по inventory_hostname

- name: Copy CA key
  ansible.builtin.copy:
    dest: /etc/ssh/teleport_user_ca.pub
    ...
```

### Edit tool вместо sed для точечных YAML-изменений

```bash
# НЕ ДЕЛАТЬ — sed не понимает YAML-семантику:
sed -i 's/\\b)/\\\\b)/g' verify.yml
# → меняет \b) везде: в task names, fail_msg, comments

# ДЕЛАТЬ — Edit tool с уникальным контекстом:
# old: that: _ssh_verify_sshd_content is regex('Port\s+22\b')
# new: that: _ssh_verify_sshd_content is regex('Port\s+22\\b')
# Гарантия: одно совпадение → одно изменение
```

---

## 6. Сравнение с историей проекта

| Инцидент | Дата | Роль | Ошибка | Класс |
|----------|------|------|--------|-------|
| Docker hostname EPERM | 2026-02-24 | hostname | hostnamectl в контейнере | container restriction |
| Docker /etc/hosts bind-mount | 2026-02-24 | hostname | lineinfile atomic rename | container restriction |
| `/etc/sudoers.d` создание | 2026-03-01 | user | директория не существует | missing parent dir |
| **Ubuntu /etc/ssh отсутствует** | **2026-03-01** | **ssh** | **prepare до converge** | **missing parent dir** |
| `{% raise %}` parse error | 2026-03-01 | sysctl | Jinja2 unknown tag | template syntax |
| **`\b` backspace в regex** | **2026-03-01** | **ssh** | **Jinja2 _str_escapes** | **escape processing** |
| sysctl --system конфликт Ubuntu | 2026-03-01 | sysctl | 99-sysctl.conf перекрывает | OS-specific ordering |

Паттерн "отсутствующая директория" возникает уже второй раз: user-роль `/etc/sudoers.d` и
теперь ssh-роль `/etc/ssh`. Общий вывод: Ubuntu minimal-образы не имеют директорий
принадлежащих пакетам — всегда создавать через `ansible.builtin.file state: directory`
в prepare.yml.

---

## 7. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `\b` в Jinja2 = backspace ASCII 8. Для regex word boundary — писать `\\b` в YAML | Любой `is regex()` в Ansible assertions |
| 2 | `\s`, `\d`, `\w`, `\B` работают "случайно" — Jinja2 их не знает, re получает as-is | Документировать, не полагаться на случайность |
| 3 | Ubuntu minimal docker-образ не имеет `/etc/ssh` до установки openssh. Создавать явно в prepare | Любая prepare-задача копирующая в system dirs |
| 4 | `prepare` выполняется до `converge` — пакеты ещё не установлены, system dirs могут отсутствовать | Все prepare.yml задачи с system paths |
| 5 | sed без семантики YAML меняет паттерн везде — в task names, fail_msg, comments | Точечные изменения в YAML → Edit tool |
| 6 | git checkout + Edit tool надёжнее sed для хирургических правок в структурированных файлах | Любые правки в YAML/JSON/Python |
| 7 | Arch-first разработка скрывает Ubuntu-специфичные пропуски. Arch проходит там, где Ubuntu падает | Всегда тестировать обе платформы параллельно |
| 8 | Ansible-lint не ловит ошибки рендеринга шаблонов и некорректные escape в строках | Regex-паттерны требуют ручной проверки или unit-тестов |

---

## 8. Known gaps (после фикса)

- **Arch-access-control verify**: `AllowGroups sshusers` assertion использует `\\b` для
  предотвращения ложных совпадений с `sshusers-something`. Значение single-word,
  поэтому практически не критично, но паттерн правильный.

- **Features + access-control пересечение**: платформы `*-features` и `*-access-control`
  не тестируют одновременную активацию обеих функций. Если кто-то захочет Teleport + SFTP
  chroot + AllowGroups — нужна отдельная платформа. Текущий скоуп этого не требует.

- **Vagrant features/access-control**: vagrant-платформы (`arch-vm`, `ubuntu-base`) тестируют
  только базовый hardening (без access-control и features). Расширение возможно добавлением
  `vagrant-features` box — оставлено для отдельного PR.
