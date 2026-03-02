# Post-Mortem: Chezmoi Molecule CI — 5 root causes в 5 файлах

**Дата:** 2026-03-02
**Статус:** Завершено — CI зелёный (Docker Arch + Ubuntu, Vagrant Arch + Ubuntu)
**Итерации CI:** 1 запуск (все 7 checks зелёные с первой попытки)
**Коммиты:** 1 коммит (`feb26f2`), squash-merged в `8e8c856`
**PRs:** #52 merged, #28 closed (superseded)
**Ветка:** `ci/track-chezmoi`
**Скоуп:** 5 файлов изменено, 42 insertions, 9 deletions

---

## 1. Задача

Исправить failing molecule-тесты роли `chezmoi` — добиться зелёного CI для всех
сценариев (Docker + Vagrant, Arch + Ubuntu). Роль устанавливает chezmoi, инициализирует
из локального source directory, применяет dotfiles, деплоит wallpapers.

### Контекст: два конкурирующих PR

| PR | Ветка | Статус |
|----|-------|--------|
| #28 `fix/chezmoi-molecule-overhaul` | Molecule tests to production quality | Закрыт (superseded) |
| #52 `ci/track-chezmoi` | Fix failing molecule tests | Merged ✓ |

PR #28 содержал 3 failing CI checks. PR #52 был tracking-веткой с пустым diff.
Решение: исправить все root causes на чистой ветке от master, force-push в `ci/track-chezmoi`,
закрыть #28 как superseded.

### Объём изменений — до и после

| Аспект | До (master) | После (PR #52) |
|--------|-------------|-----------------|
| verify.yml | `vars_files` загрузка defaults | `set_fact` с guard (`when: var is not defined`) |
| Источник для verify | Hardcoded `~/.local/share/chezmoi` | Динамический `chezmoi_source_dir` ∥ default path |
| Vagrant prepare.yml | `/opt/dotfiles` owned by root | `owner: vagrant`, `group: vagrant` |
| Vagrant molecule.yml | Без `chezmoi_user` | `chezmoi_user: vagrant` для обеих платформ |
| Docker molecule.yml | `chezmoi_install_method: apt` | `chezmoi_install_method: script` |
| tasks/main.yml | `find` по hardcoded path | `find {{ chezmoi_source_dir }}` |

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker | Archlinux-systemd, Ubuntu-systemd | Install + init --apply + verify config/binary |
| Vagrant | arch-vm (KVM), ubuntu-base (KVM) | Полный цикл с fixture dotfiles |

---

## 2. Инциденты

### Инцидент #1 — `vars_files` precedence: verify.yml перебивал inventory host_vars

**Файл:** `molecule/shared/verify.yml`
**Этап:** `verify`
**Платформы:** Все

**Симптом:**

verify.yml выполнялся от имени неправильного пользователя. Переменная `chezmoi_user`
из molecule host_vars (`testuser` / `vagrant`) игнорировалась, вместо неё использовалось
значение из `defaults/main.yml`:

```yaml
# defaults/main.yml:
chezmoi_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
```

Verify-плейбук загружал defaults через `vars_files`:

```yaml
# verify.yml (до фикса):
- name: Verify chezmoi
  hosts: all
  vars_files:
    - ../../defaults/main.yml    # ← ОШИБКА
```

**Расследование — Ansible Variable Precedence:**

```
Priority  1: role defaults/main.yml (через include_role)
Priority  4: inventory host_vars (файловые)
Priority  9: play vars_files
Priority 10: play host_vars (molecule provisioner.inventory.host_vars)
```

`vars_files` (priority 9) **перезаписывал** molecule host_vars из provisioner.inventory
(priority 10 для play vars, но molecule host_vars генерируются как **inventory** host_vars,
priority 4). На практике:

```
molecule.yml host_vars:
  Ubuntu-systemd:
    chezmoi_user: testuser           ← inventory host_vars (priority 4)

verify.yml vars_files:
  chezmoi_user: "{{ SUDO_USER }}"   ← play vars_files (priority 9) → ПОБЕЖДАЕТ
```

**Ключевая тонкость:**

`defaults/main.yml` (priority 1) при подключении через `include_role` имеет самый низкий
приоритет — это безопасно. Но тот же файл, подключённый через `vars_files` в standalone
плейбуке, получает priority 9 — и перебивает inventory host_vars.

Lazy Jinja2 template `"{{ ansible_facts['env']['SUDO_USER'] }}"` в vars_files
вычисляется в runtime, но с приоритетом vars_files — поэтому перебивает явное
`chezmoi_user: testuser` из host_vars.

**Фикс — `set_fact` с guard:**

```yaml
# verify.yml (после фикса):
- name: Verify chezmoi
  hosts: all
  # NOTE: Do NOT use vars_files to load ../../defaults/main.yml here.
  # vars_files (precedence 9) overrides inventory host_vars (precedence 4),
  # which breaks chezmoi_user set by molecule scenarios.
  tasks:
    - name: Set chezmoi_user default if not provided by inventory
      ansible.builtin.set_fact:
        chezmoi_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
      when: chezmoi_user is not defined
```

`set_fact` с `when: chezmoi_user is not defined` — условный default: устанавливает
значение только если molecule host_vars (или другой источник) его не задал.
Priority `set_fact` = 19, но guard `when` предотвращает перезапись.

**Урок:**

Standalone verify/converge плейбуки **не должны** использовать `vars_files` для
подключения role defaults. Правильные подходы:

| Подход | Как | Когда |
|--------|-----|-------|
| `set_fact` с guard | `when: var is not defined` | Для 1-3 переменных |
| `group_vars.all` в molecule.yml | `provisioner.inventory.group_vars.all:` | Для bulk defaults |
| Без defaults вообще | Molecule host_vars задают всё явно | Когда набор переменных мал |

**Таблица приоритетов (для принятия решения):**

| Механизм | Priority | Molecule host_vars override? |
|----------|----------|------------------------------|
| `defaults/main.yml` (через include_role) | 1 | ✓ Да |
| `group_vars.all` в molecule.yml | ~8 | ✓ Да (ниже host_vars) |
| `vars_files` в play | 9 | ✗ **Перебивает** inventory host_vars (4) |
| `set_fact` с guard | 19 (но guard) | ✓ Да (guard предотвращает) |
| `include_vars` в tasks/ | 18 | ✗ **Перебивает** всё |

---

### Инцидент #2 — Hardcoded source dir path в verify.yml

**Файл:** `molecule/shared/verify.yml`
**Этап:** `verify`
**Платформы:** Vagrant (fixture scenarios)

**Симптом:**

Verify проверял наличие source directory по hardcoded пути `~/.local/share/chezmoi`,
но Vagrant fixture scenarios используют `/opt/dotfiles` (заданный через
`chezmoi_source_dir` в host_vars).

```yaml
# verify.yml (до фикса):
- name: Check chezmoi source directory exists
  ansible.builtin.stat:
    path: "{{ _chezmoi_verify_home }}/.local/share/chezmoi"
```

**Причина:**

`chezmoi init --source /opt/dotfiles` использует указанный путь как source directory
и **не создаёт** `~/.local/share/chezmoi`. Это задокументировано в chezmoi docs:
`--source` flag полностью заменяет default source path.

Verify.yml не учитывал наличие `chezmoi_source_dir` — всегда проверял default path,
который при fixture scenario не существует.

**Фикс — динамический path:**

```yaml
# verify.yml (после фикса):
- name: Set expected source directory path
  ansible.builtin.set_fact:
    _chezmoi_verify_expected_source: >-
      {{ chezmoi_source_dir
         if chezmoi_source_dir is defined
         else _chezmoi_verify_home ~ '/.local/share/chezmoi' }}
  when: chezmoi_verify_has_dotfiles | default(false)

- name: Check chezmoi source directory exists
  ansible.builtin.stat:
    path: "{{ _chezmoi_verify_expected_source }}"
```

**Аналогичный фикс в tasks/main.yml:**

Guard от nested `.chezmoidata` тоже использовал hardcoded path:

```yaml
# tasks/main.yml (до фикса):
cmd: find {{ chezmoi_user_home }}/.local/share/chezmoi -mindepth 2 ...

# tasks/main.yml (после фикса):
cmd: find {{ chezmoi_source_dir }} -mindepth 2 ...
```

**Урок:**

Когда роль поддерживает custom source dir через переменную, **все** ссылки на source
dir — в tasks, verify, prepare — должны использовать эту переменную (с fallback на
default path). Hardcoded paths маскируют ошибку: тест проходит для default scenario,
но падает для любого custom scenario.

---

### Инцидент #3 — Vagrant: `/opt/dotfiles` owned by root

**Файл:** `molecule/vagrant/prepare.yml`
**Этап:** `converge` (prepare создавал fixture с неправильными permissions)
**Платформы:** Vagrant (arch-vm, ubuntu-base)

**Симптом:**

`chezmoi init --source /opt/dotfiles` (выполняемый как `vagrant` user через `become_user`)
падал с permission denied. Причина — `chezmoi init` создаёт `.git` внутри source directory,
а `/opt/dotfiles` принадлежал `root:root`.

```yaml
# prepare.yml (до фикса):
- name: Create dotfiles fixture directory
  ansible.builtin.file:
    path: /opt/dotfiles
    state: directory
    mode: '0755'
    # owner/group НЕ УКАЗАНЫ → default root:root
```

**Цепочка событий:**

1. `prepare.yml` создаёт `/opt/dotfiles` как root (default owner)
2. Файлы fixture (`.chezmoi.toml.tmpl`, `dot_chezmoi_test_marker`) создаются как root
3. `tasks/main.yml` выполняет `chezmoi init --source /opt/dotfiles` как `become_user: vagrant`
4. `chezmoi init` пытается создать `.git/` внутри `/opt/dotfiles`
5. Permission denied — vagrant не может писать в root-owned directory

**Фикс:**

```yaml
# prepare.yml (после фикса):
- name: Create dotfiles fixture directory
  ansible.builtin.file:
    path: /opt/dotfiles
    state: directory
    mode: '0755'
    owner: vagrant
    group: vagrant

- name: Create chezmoi config template (fixture)
  ansible.builtin.copy:
    # ...
    owner: vagrant
    group: vagrant
```

**Урок:**

Fixture directories в prepare.yml **должны** принадлежать целевому пользователю роли
(`chezmoi_user`), а не root. `chezmoi init` создаёт subdirectories (`.git/`, `.chezmoistate.boltdb`)
внутри source dir — write permissions обязательны для user, от имени которого запускается chezmoi.

---

### Инцидент #4 — Vagrant: отсутствие `chezmoi_user` в host_vars

**Файл:** `molecule/vagrant/molecule.yml`
**Этап:** `converge`
**Платформы:** Vagrant (arch-vm, ubuntu-base)

**Симптом:**

Роль определяет `chezmoi_user` в defaults как:

```yaml
chezmoi_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
```

На Vagrant VM, при `become: true`, `SUDO_USER` зависит от контекста SSH-сессии.
Molecule Vagrant SSH sessions могут иметь `SUDO_USER=vagrant` или undefined
(в зависимости от stage). Без явного `chezmoi_user` в host_vars, поведение
непредсказуемо.

**Фикс:**

```yaml
# molecule/vagrant/molecule.yml (после фикса):
provisioner:
  inventory:
    host_vars:
      arch-vm:
        chezmoi_user: vagrant           # ← добавлено
        chezmoi_install_method: pacman
        chezmoi_source_dir: /opt/dotfiles
        chezmoi_verify_has_dotfiles: true
        chezmoi_verify_fixture: true
      ubuntu-base:
        chezmoi_user: vagrant           # ← добавлено
        chezmoi_install_method: script
        chezmoi_source_dir: /opt/dotfiles
        chezmoi_verify_has_dotfiles: true
        chezmoi_verify_fixture: true
```

**Урок:**

Molecule host_vars должны **явно** задавать все ключевые переменные роли.
Полагаться на computed defaults из `defaults/main.yml` в molecule — антипаттерн:
контекст выполнения molecule (SSH, become, env) отличается от production.

---

### Инцидент #5 — Docker Ubuntu: несуществующий install method `apt`

**Файл:** `molecule/docker/molecule.yml`
**Этап:** `converge`
**Платформа:** Ubuntu-systemd (Docker)

**Симптом:**

Docker molecule.yml задавал `chezmoi_install_method: apt` для Ubuntu, но роль
поддерживает только два метода: `pacman` и `script`.

```yaml
# tasks/main.yml — install dispatch:
- name: Install chezmoi (OS-specific)
  ansible.builtin.include_tasks: "install-{{ ansible_facts['os_family'] | lower }}.yml"

- name: Install chezmoi via official script
  # ...
  when: chezmoi_install_method == 'script'
```

`install-debian.yml` содержит package-based install (если файл существует),
но `chezmoi_install_method: apt` не соответствует ни одной ветке — ни `pacman`,
ни `script`. Chezmoi **не в Debian/Ubuntu репозиториях** — нет пакета `chezmoi`
для apt.

**Фикс:**

```yaml
# molecule/docker/molecule.yml (после фикса):
Ubuntu-systemd:
  # chezmoi is not in Debian/Ubuntu repos; install via official script.
  # Binary lands at ~/.local/bin/chezmoi.
  chezmoi_install_method: script
```

**Урок:**

Install method в molecule host_vars должен соответствовать реально поддерживаемым
методам роли. Комментарий в molecule.yml объясняет **почему** `script`, а не package —
это документация для будущих разработчиков.

---

## 3. Архитектурные улучшения

### 3.1. `set_fact` guard pattern — стандарт для standalone плейбуков

**Проблема:** standalone verify/converge плейбуки не имеют доступа к role defaults
через стандартный механизм (include_role). `vars_files` — ловушка precedence.

**Решение:**

```yaml
# Паттерн для standalone плейбуков:
tasks:
  - name: Set <variable> default if not provided by inventory
    ansible.builtin.set_fact:
      <variable>: "{{ <default_expression> }}"
    when: <variable> is not defined
```

Применимость: все roles с molecule verify.yml, использующие role defaults.

### 3.2. Динамические пути вместо hardcoded defaults

**Проблема:** роли с configurable paths (source dir, install dir, config dir)
часто имеют hardcoded default path в verify.yml и tasks.

**Решение:**

```yaml
# Паттерн:
- name: Resolve effective path
  ansible.builtin.set_fact:
    _effective_path: >-
      {{ custom_var
         if custom_var is defined
         else default_path }}
```

### 3.3. Fixture ownership contract

**Проблема:** prepare.yml создаёт fixture files/dirs без explicit ownership →
default root → permission denied при become_user.

**Правило:** каждый `file`/`copy`/`template` в prepare.yml, создающий fixture data,
**обязан** иметь `owner` и `group` равные целевому пользователю роли.

---

## 4. Timeline

| Время | Действие |
|-------|----------|
| T+0 | Исследование PR #52 и #28 — анализ CI failures |
| T+10m | Root cause analysis: идентифицированы 5 причин |
| T+15m | Решение: fix PR #52 (ci/track-chezmoi), close #28 |
| T+20m | Создание worktree от origin/master |
| T+25m | LFS conflict — fresh worktree вместо rebase существующей ветки |
| T+30m | Фикс verify.yml: убран vars_files, добавлен set_fact guard |
| T+35m | Фикс verify.yml: динамический source dir path |
| T+40m | Фикс prepare.yml: owner/group vagrant + git package для Ubuntu |
| T+45m | Фикс vagrant molecule.yml: chezmoi_user + verify variables |
| T+48m | Фикс docker molecule.yml: `apt` → `script` |
| T+50m | Фикс tasks/main.yml: find path → chezmoi_source_dir |
| T+55m | Коммит, force-push в ci/track-chezmoi |
| T+60m | CI запущен (run 22573895401) |
| T+75m | Все 7 checks зелёные |
| T+80m | PR #52 squash-merged, PR #28 closed |

**CI-прогоны:**

| Run | Commit | Checks | Результат |
|-----|--------|--------|-----------|
| 22573895401 | `feb26f2` | YAML Lint & Syntax ✓, Detect changed roles (x2) ✓, Ansible Lint ✓, chezmoi test-docker ✓, chezmoi test-vagrant/arch ✓, chezmoi test-vagrant/ubuntu ✓ | **7/7 SUCCESS** |

**Squash merge:** `8e8c856` в master

---

## 5. Файлы изменённые

| Файл | Что сделано | Root cause |
|------|-------------|------------|
| `ansible/roles/chezmoi/molecule/shared/verify.yml` | Убран `vars_files`, добавлен `set_fact` guard; динамический source dir path | #1, #2 |
| `ansible/roles/chezmoi/molecule/docker/molecule.yml` | `chezmoi_install_method: apt` → `script` | #5 |
| `ansible/roles/chezmoi/molecule/vagrant/molecule.yml` | Добавлен `chezmoi_user: vagrant`, verify flags | #4 |
| `ansible/roles/chezmoi/molecule/vagrant/prepare.yml` | `owner: vagrant`, `group: vagrant`; добавлен `git` в Ubuntu packages | #3 |
| `ansible/roles/chezmoi/tasks/main.yml` | `find` path → `{{ chezmoi_source_dir }}` | #2 |

---

## 6. Ключевые паттерны

### 6.1. Ansible Variable Precedence — `vars_files` ловушка

Это **самый частый** source of bugs в molecule тестах bootstrap-проекта.
Встречен минимум в двух ролях:

| Роль | Механизм | Инцидент |
|------|----------|----------|
| chezmoi | `vars_files: ../../defaults/main.yml` в verify.yml | Этот post-mortem, инцидент #1 |
| teleport | `include_vars: {{ os_family }}.yml` в tasks/main.yml | Teleport post-mortem, инцидент #1 |

**Правило:** переменные, которые molecule должен переопределять, **не должны** быть
в механизмах с priority > 10:

```
БЕЗОПАСНО (molecule host_vars побеждает):
  Priority  1: defaults/main.yml (через include_role)
  Priority  2: role defaults (direct)
  Priority  4: inventory file host_vars
  Priority  8: group_vars.all в molecule.yml

ОПАСНО (перебивает molecule host_vars):
  Priority  9: play vars_files          ← ЛОВУШКА в verify.yml
  Priority 18: include_vars             ← ЛОВУШКА в tasks/main.yml
  Priority 19: set_fact (без guard)     ← ЛОВУШКА если без when
```

### 6.2. chezmoi init --source поведение

```
chezmoi init --source /opt/dotfiles:
  1. Использует /opt/dotfiles как source dir
  2. НЕ создаёт ~/.local/share/chezmoi
  3. Создаёт .git/ ВНУТРИ /opt/dotfiles
  4. Требует write permissions на /opt/dotfiles для target user
```

### 6.3. Fixture scenario contract

Molecule fixture scenarios (Vagrant с /opt/dotfiles) требуют:

1. **Directory ownership** = target user (не root)
2. **File ownership** = target user (не root)
3. **Git package** installed (chezmoi init нуждается в git)
4. **Minimal fixture**: `.chezmoi.toml.tmpl` + маркер-файл достаточно для verify
5. **verify.yml**: динамический path через `chezmoi_source_dir`

---

## 7. Сравнение с аналогичными инцидентами

### Teleport CI post-mortem (2026-03-02)

| Аспект | Teleport | Chezmoi |
|--------|----------|---------|
| Root causes | 2 (precedence + 404 version) | 5 (precedence + path + ownership + user + method) |
| CI итерации | 3 (2 ошибки) | 1 (все зелёные с первой попытки) |
| Precedence bug | `include_vars` (priority 18) перебивал host_vars | `vars_files` (priority 9) перебивал host_vars |
| Фикс precedence | Перенос из `vars/` в `defaults/` | Замена `vars_files` на `set_fact` guard |
| Общий паттерн | **Да — variable precedence как #1 root cause** | **Да — тот же class ошибки** |

**Вывод:** variable precedence bugs — системная проблема проекта. Каждая роль с molecule
тестами потенциально подвержена. Рекомендация: audit всех ролей на использование
`vars_files` в molecule плейбуках и `include_vars` для переменных, которые molecule
должен переопределять.

---

## 8. Ретроспективные уроки

### Что сработало хорошо

1. **Root cause analysis до кода.** Все 5 причин идентифицированы до написания
   первой строки фикса. Результат — 1 CI итерация, 0 failures.

2. **Предыдущий post-mortem как knowledge base.** Teleport post-mortem (того же дня)
   содержал детальное описание variable precedence bug. Опыт сразу применён к chezmoi.

3. **Worktree workflow.** Fresh worktree от master вместо rebase существующей ветки
   избежал LFS conflicts и гарантировал чистый diff.

4. **Комментарии в molecule.yml.** Inline comments объясняют **почему** выбран
   конкретный install method или значение — документация для будущих разработчиков.

### Что можно улучшить

1. **Нет автоматического audit.** Variable precedence bugs обнаруживаются только
   при failing CI. Нужен lint-правило или pre-commit hook, которое предупреждает
   о `vars_files` в molecule verify/converge плейбуках.

2. **PR #28 прожил долго.** Failing PR существовал без анализа root causes.
   Своевременный root cause analysis мог бы предотвратить параллельный PR.

3. **Memory не содержал паттерн `vars_files`.** Хотя инцидент #1 (precedence)
   уже встречался в другом контексте, memory file не содержал конкретного
   предупреждения о `vars_files` в molecule плейбуках. Исправлено.

---

## 9. Процессные наблюдения

### Один коммит, пять root causes

Все 5 фиксов отправлены одним коммитом. Это сработало потому что:

1. Все root causes были идентифицированы **до** написания кода
2. Фиксы в разных файлах не конфликтовали
3. CI прогон один — минимальная обратная связь

**Когда это НЕ работает:** если root causes взаимозависимы (фикс одного
открывает другой), разумнее отправлять по одному коммиту на root cause —
для точной диагностики при failure.

### Force-push vs new branch

Использован force-push в `ci/track-chezmoi` (tracking branch с пустым diff).
Безопасно потому что:
- Ветка не содержала чужих коммитов
- PR #52 не имел review comments, привязанных к конкретным коммитам
- Squash merge в master — финальный коммит всё равно один

### LFS на Windows + worktrees

`dotfiles/wallpapers/military 1.png` (LFS-tracked) показывался как modified
в worktree. Git LFS pointer vs actual file mismatch — типичная проблема
Windows + LFS + worktrees. Обход: fresh worktree вместо rebase.

---

## 10. Известные пробелы

### Verify.yml не покрывает 100% роли

Текущий verify.yml проверяет:
- [x] Binary exists and is executable
- [x] Source directory exists
- [x] Config file exists
- [x] Fixture marker file deployed (fixture scenarios)
- [x] chezmoi managed paths present

Не проверяет:
- [ ] Wallpapers deployment (conditional block)
- [ ] Nested `.chezmoidata` guard effectiveness
- [ ] `chezmoi doctor` выход (comprehensive health check)
- [ ] `chezmoi verify` (drift detection)
- [ ] Theme application correctness (promptChoice)

### `install-debian.yml` неясный статус

Роль содержит `install-{{ os_family }}.yml` dispatch. Файл `install-debian.yml`
может не существовать или быть stub. Script install method обходит этот файл,
но если кто-то добавит `chezmoi_install_method: package` для Ubuntu — поведение
непредсказуемо.

### Idempotency не тестируется

`test_sequence` в обоих scenarios не содержит `idempotence`:

```yaml
test_sequence:
  - syntax
  - create
  - prepare
  - converge
  # ← нет idempotence
  - verify
  - destroy
```

Комментарий в molecule.yml: `chezmoi init --apply always reports changed`.
Это верно (chezmoi init —idempotent только по результату, не по `changed` status).
Но остальные таски роли (install, validate source, wallpapers) могут и должны
быть idempotent — стоит рассмотреть selective idempotence test с `--skip-tags`.
