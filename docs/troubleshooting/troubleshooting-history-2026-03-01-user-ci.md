# Post-Mortem: Molecule CI для роли `user`

**Дата:** 2026-03-01
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)
**Итерации CI (vagrant):** 2 запуска, 1 уникальная ошибка
**Коммиты:** `919d1df` → `8a7b5dc` (5 коммитов)
**PR:** [#10 fix(user): fix molecule tests for Docker + Vagrant](https://github.com/textyre/bootstrap/pull/10)

---

## 1. Задача

Довести molecule-тесты роли `user` до зелёного во всех трёх CI-средах:

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker (`molecule/docker/`) | Archlinux-systemd + Ubuntu-systemd | Создание owner + extra user, umask-профиль, sudoers политика, logrotate конфиг |
| Vagrant arch-vm | `arch-base` box (KVM) | То же на реальной VM, Arch |
| Vagrant ubuntu-base | `ubuntu-base` box (KVM) | То же на реальной VM, Ubuntu 24.04 |

**Роль `user`:** создаёт primary owner (с группой wheel/sudo, umask), дополнительных
пользователей, деплоит hardened sudoers файл (`/etc/sudoers.d/wheel` или `sudo`),
настраивает logrotate для `/var/log/sudo.log`.

**Ключевая особенность:** роль изменяет sudoers — это затрагивает механизм `become`
в тех же Ansible-прогонах. Паттерн редкий и заранее был не очевиден.

---

## 2. Инциденты

### Инцидент #1 — Статический анализ: `video` группа не гарантирована (pre-CI fix)

**Коммит:** `919d1df`
**Этап:** code review перед первым push
**Проблема:**

`shared/converge.yml` создаёт `testuser_extra` с `groups: [video]`:

```yaml
user_additional_users:
  - name: testuser_extra
    groups:
      - video
```

`ansible.builtin.user` с `groups: [video]` завершается с ошибкой если группа `video`
не существует в системе. В Docker-контейнерах (и потенциально в Vagrant boxes) `video`
группа создаётся `udev`/systemd при полном запуске, но не гарантируется в минимальных
образах.

**Анализ:**

В обоих `prepare.yml` (docker и vagrant) группа `video` не создавалась перед converge.
Риск не проявился в Docker-прогонах (наши образы с полным systemd включают `video`),
но это неявная зависимость на содержимое образа, не на prepare-шаг.

`ansible.builtin.group` с `state: present` идемпотентен — если группа уже существует,
ничего не делает.

**Фикс:** добавить явное создание группы в оба prepare.yml без `when:` guard
(кросс-платформенный модуль):

```yaml
- name: Ensure video group exists (required by testuser_extra)
  ansible.builtin.group:
    name: video
    state: present
```

**Урок:** Если converge зависит от существования группы/пользователя/файла —
создать его в prepare, явно, не полагаясь на то что он "скорее всего есть в образе".

---

### Инцидент #2 — Статический анализ: vagrant Ubuntu не устанавливал logrotate (pre-CI fix)

**Коммит:** `47fad4a`
**Этап:** code review перед первым push
**Проблема:**

`molecule/vagrant/prepare.yml` до фикса:

```yaml
- name: Ensure logrotate is installed (Arch)
  ansible.builtin.package:
    name: logrotate
    state: present
  when: ansible_facts['os_family'] == 'Archlinux'

- name: Update apt cache (Ubuntu)
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
  when: ansible_facts['os_family'] == 'Debian'
```

Три проблемы в одном файле:
1. `logrotate` устанавливается только для Arch — Ubuntu полностью пропущена
2. Нет `update_cache: true` для Arch перед установкой пакета — установка может
   упасть если кэш устарел
3. Порядок задач: обновление кэша Ubuntu идёт ПОСЛЕ установки пакета для Arch,
   что создаёт логическую путаницу

В Ubuntu logrotate обычно предустановлен (зависимость многих базовых пакетов),
но это implicit dependency. `verify.yml` проверяет содержимое `/etc/logrotate.d/sudo`
— если logrotate не установлен, эта проверка пройдёт, но сам logrotate не будет
функционировать. Explicit is better than implicit.

**Фикс:** переписать prepare.yml с правильным порядком:

```yaml
# 1. Сначала обновить кэш (обе платформы)
- name: Update pacman package cache (Arch)
  community.general.pacman:
    update_cache: true
  when: ansible_facts['os_family'] == 'Archlinux'

- name: Update apt cache (Ubuntu)
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
  when: ansible_facts['os_family'] == 'Debian'

# 2. Потом устанавливать зависимости (обе платформы)
- name: Ensure logrotate is installed (Arch)
  community.general.pacman:
    name: logrotate
    state: present
  when: ansible_facts['os_family'] == 'Archlinux'

- name: Ensure logrotate is installed (Ubuntu)
  ansible.builtin.apt:
    name: logrotate
    state: present
  when: ansible_facts['os_family'] == 'Debian'
```

Используем платформо-специфичные модули (`pacman`, `apt`) вместо generic `package` —
на свежих vagrant boxes package manager может ещё не иметь полного кэша, и generic
модуль может неверно определить менеджер.

**Урок:** Структура prepare.yml: сначала все обновления кэша, потом все установки.
Всегда явно устанавливать зависимости для обеих платформ. `logrotate` может быть
предустановлен в Ubuntu, но это совпадение, не контракт.

---

### Инцидент #3 — Vagrant arch-vm: sudoers hardening ломает become для последующих задач

**Коммит:** `8a7b5dc`
**Прогон:** первый CI (run `22537661748`)
**Этап:** `converge` (arch-vm only; ubuntu-base прошла)
**Ошибка:**

```
TASK [user : CIS 5.3.4/5.3.5/5.3.7 | Deploy sudoers hardening]
ok: [arch-vm]   ← sudoers файл задеплоен

TASK [user : Configure logrotate for sudo.log]
fatal: [arch-vm]: FAILED! => {"changed": false, "msg": "Task failed: Missing sudo password"}

PLAY RECAP *****
arch-vm : ok=13  changed=5  unreachable=0  failed=1  skipped=2
```

```
ERROR  Ansible return code was 2, command was: ansible-playbook
       --skip-tags report .../molecule/vagrant/converge.yml
```

**Анализ:**

Задача `Configure logrotate for sudo.log` — первая задача после `Deploy sudoers
hardening`. Все предыдущие become-задачи прошли успешно. Сломалось именно первое
`become: true` после деплоя sudoers файла.

Диаграмма механизма:

```
Arch vagrant box:
  /etc/sudoers (read first):
    vagrant ALL=(ALL) NOPASSWD: ALL   ← passwordless

  [нет /etc/sudoers.d/wheel изначально]

Converge deploys:
  /etc/sudoers.d/wheel:
    %wheel ALL=(ALL:ALL) ALL           ← requires password

sudoers alphabetical order: 'v' < 'w'
  Чтение: /etc/sudoers → /etc/sudoers.d/wheel
  Last-match wins: %wheel ALL=(ALL:ALL) ALL ПОБЕЖДАЕТ

vagrant user in wheel group → match %wheel rule → password required
Next become task → "Missing sudo password"
```

**Почему Ubuntu прошла:**

```
Ubuntu vagrant box:
  /etc/sudoers (read first):
    %sudo ALL=(ALL:ALL) ALL           ← default Ubuntu sudoers
  /etc/sudoers.d/vagrant:
    vagrant ALL=(ALL) NOPASSWD: ALL   ← passwordless

Converge deploys:
  /etc/sudoers.d/sudo:
    %sudo ALL=(ALL:ALL) ALL           ← same as default!

Alphabetical order: 'sudo' < 'vagrant'
  Чтение: ... → /etc/sudoers.d/sudo → /etc/sudoers.d/vagrant
  Last-match: vagrant ALL=(ALL) NOPASSWD: ALL ПОБЕДЖАЕТ ✓

vagrant user → NOPASSWD → become works
```

На Ubuntu наш файл `/etc/sudoers.d/sudo` сортируется ДО `/etc/sudoers.d/vagrant`
(`s` < `v`), поэтому vagrant's NOPASSWD rule выигрывает. На Arch наш файл
`/etc/sudoers.d/wheel` сортируется ПОСЛЕ vagrant's rule (`w` > `v`), и role's
password-required rule выигрывает — breaking become.

**Детали sudoers last-match semantics:**

В sudoers правило last-match-wins означает: если пользователь совпадает с несколькими
строками, применяется последняя по порядку чтения. Файлы в `/etc/sudoers.d/`
читаются в лексикографическом ASCII-порядке. В нашем случае:

- Arch: vagrant rule в `/etc/sudoers` (первый) → перекрывается `/etc/sudoers.d/wheel` (позже)
- Ubuntu: `/etc/sudoers.d/sudo` (раньше) → перекрывается `/etc/sudoers.d/vagrant` (позже)

**Альтернативы, которые не были выбраны:**

1. **Переименовать group в converge** — использовать тестовую группу `ci-sudo` вместо
   реального `wheel`. Тогда role деплоит `/etc/sudoers.d/ci-sudo`, не затрагивая wheel.
   Проблема: `verify.yml` проверяет `%wheel` в sudoers для Arch-specific assert —
   пришлось бы менять verify или усложнять конфигурацию.

2. **`Defaults !authenticate` для vagrant user** — добавить в sudoers hardening template
   исключение для CI. Проблема: меняет production template ради CI workaround.

3. **`ANSIBLE_BECOME_PASS`** — передать пароль через env. Проблема: в vagrant boxes
   нет стандартного sudo пароля; нужно сначала его установить, что усложняет prepare.

4. **`molecule-notest` на задачи после sudoers** — пропускать logrotate deploy в CI.
   Проблема: нарушает смысл тестирования — именно logrotate deploy нужно проверить.

**Выбранный фикс:** добавить в `vagrant/prepare.yml` для Arch файл sudoers с `zz-`
префиксом, который сортируется ПОСЛЕ `wheel` (`z` > `w`), и содержит vagrant NOPASSWD
правило с highest priority:

```yaml
- name: Preserve passwordless sudo for vagrant user (Arch CI workaround)
  ansible.builtin.copy:
    content: "vagrant ALL=(ALL) NOPASSWD: ALL\n"
    dest: /etc/sudoers.d/zz-molecule-vagrant-nopasswd
    owner: root
    group: root
    mode: "0440"
    validate: "/usr/sbin/visudo -cf %s"
  when: ansible_facts['os_family'] == 'Archlinux'
```

Алфавитный порядок чтения:
```
/etc/sudoers.d/wheel                      (w — наш файл)
/etc/sudoers.d/zz-molecule-vagrant-nopasswd (z — наш guard)

last-match: vagrant ALL=(ALL) NOPASSWD: ALL ✓
```

`validate: "/usr/sbin/visudo -cf %s"` — синтаксическая проверка файла перед записью,
исключает деплой невалидного sudoers.

Имя файла намеренно описательное: `molecule-vagrant` указывает на CI-контекст,
`nopasswd` — на назначение. Если кто-то откроет VM вручную, он поймёт откуда файл.

**Урок:** Роли, изменяющие sudoers, должны тестироваться с учётом того что они сами
ломают become механизм для последующих задач. Паттерн не очевиден: role succeeds,
но следующая задача после неё в том же play уже использует изменённые правила.
В Docker это не проявляется (Ansible работает как root напрямую, без sudo).

---

## 3. Временная шкала

```
── Сессия (2026-03-01) ──────────────────────────────────────────────────────────

[Статический анализ роли и molecule файлов]
  → Выявлены: video group, logrotate Ubuntu, update_cache Arch
  → pre-CI фиксы подготовлены

919d1df  fix(user/molecule): ensure video group exists in docker prepare
47fad4a  fix(user/molecule): fix vagrant prepare — logrotate for Ubuntu, video group, update_cache
f295602  fix(user/molecule): add vagrant-specific converge.yml
775c6b5  fix(user/molecule): point vagrant scenario to local converge.yml
         ↓ PR #10 открыт

         ↓ Vagrant run 22537661748 (первый):
         ↓   Ansible Lint:                          PASS ✓
         ↓   YAML Lint:                             PASS ✓
         ↓   Docker (Arch+Ubuntu systemd):          PASS ✓
         ↓   Vagrant ubuntu-base:                   PASS ✓
         ↓   Vagrant arch-vm:                       FAIL ✗
         ↓     "Missing sudo password" на logrotate (Инцидент #3)

[Диагностика: sudoers last-match механизм + alphabetical ordering]
  → /etc/sudoers.d/wheel (w) > vagrant rule (v) → breaks become

8a7b5dc  fix(user/molecule): preserve vagrant NOPASSWD sudo on Arch after sudoers hardening
         ↓ PR #10 обновлён

         ↓ Vagrant run 22537756596 (второй):
         ↓   Ansible Lint:                          PASS ✓
         ↓   YAML Lint:                             PASS ✓
         ↓   Docker (Arch+Ubuntu systemd):          PASS ✓
         ↓   Vagrant arch-vm:                       PASS ✓  (3m10s)
         ↓   Vagrant ubuntu-base:                   PASS ✓  (2m50s)

         ↓ PR #10 merged (squash) → master
         ↓ Worktree .claude/worktrees/fix-user-molecule удалён
```

---

## 4. Финальная структура

```
ansible/roles/user/molecule/
├── shared/
│   ├── converge.yml     ← role: user; test users; managed_password_aging: false
│   └── verify.yml       ← owner/extra user assertions; sudoers; logrotate; sudo pkg
├── docker/
│   ├── molecule.yml     ← Archlinux-systemd + Ubuntu-systemd, privileged, cgroupns
│   └── prepare.yml      ← update_cache (Arch/Ubuntu); video group; logrotate pkg
└── vagrant/
    ├── molecule.yml     ← arch-vm (arch-base box) + ubuntu-base (ubuntu-base box)
    │                       converge: converge.yml  ← local, не ../shared/
    ├── prepare.yml      ← update_cache (Arch/Ubuntu); video group; logrotate pkg;
    │                       zz-molecule-vagrant-nopasswd (Arch only)
    └── converge.yml     ← vagrant-specific vars (копия shared, изолирована от Docker)
```

**Ключевые изменения относительно исходного состояния:**

| Файл | До | После |
|------|----|-------|
| `docker/prepare.yml` | нет video group | добавлено `ansible.builtin.group: video` |
| `vagrant/prepare.yml` | logrotate только Arch; нет update_cache для Arch; нет video group | исправлено всё + guard для vagrant sudo |
| `vagrant/converge.yml` | не существовал | создан (isolates vagrant от docker vars) |
| `vagrant/molecule.yml` | `converge: ../shared/converge.yml` | `converge: converge.yml` |

---

## 5. Ключевые паттерны

### Sudoers-safe prepare для ролей с sudoers hardening

Если роль деплоит файл в `/etc/sudoers.d/`, vagrant become может сломаться
если имя файла сортируется после файла с vagrant NOPASSWD правилом.

Защита для Arch (wheel group):

```yaml
# В vagrant/prepare.yml — ПЕРЕД converge:
- name: Preserve passwordless sudo for vagrant user (Arch CI workaround)
  ansible.builtin.copy:
    content: "vagrant ALL=(ALL) NOPASSWD: ALL\n"
    dest: /etc/sudoers.d/zz-molecule-vagrant-nopasswd
    owner: root
    group: root
    mode: "0440"
    validate: "/usr/sbin/visudo -cf %s"
  when: ansible_facts['os_family'] == 'Archlinux'
```

Правило: `zz-` prefix гарантирует что файл сортируется ПОСЛЕ любого разумного имени
sudoers файла (все строчные буквы < `z`). Vagrant user's NOPASSWD правило побеждает.

На Ubuntu защита не требуется: наш файл `/etc/sudoers.d/sudo` сортируется ДО
стандартного vagrant файла `vagrant` или `vagrant-etc-sudoers`, поэтому vagrant
NOPASSWD правило сохраняет приоритет.

### Правило диагностики: asymmetric platform failure → different file ordering

Если одна платформа проходит, а другая падает с `Missing sudo password` именно
после задачи, которая пишет в `/etc/sudoers.d/` — это почти наверняка проблема
алфавитного порядка sudoers файлов.

Алгоритм проверки:
```
1. Узнать имя sudoers файла, который деплоит роль: /etc/sudoers.d/<X>
2. Узнать где vagrant NOPASSWD правило на каждой box:
   sudo grep -r NOPASSWD /etc/sudoers /etc/sudoers.d/
3. Сравнить алфавитный порядок имён:
   [X] < [vagrant file] → vagrant rule wins → become works ✓
   [X] > [vagrant file] → role rule wins → become broken ✗
4. Фикс: добавить zz-<guard> с vagrant NOPASSWD (всегда последний)
```

### Структура prepare.yml: порядок задач

```yaml
# 1. Обновление кэшей — всегда первым
- name: Update pacman/apt cache
  when: os_family == X

# 2. Создание необходимых групп
- name: Ensure required groups exist
  ansible.builtin.group: ...

# 3. Установка пакетов-зависимостей
- name: Install required packages
  when: os_family == X

# 4. CI-специфичные гарантии (sudoers guards, etc.)
- name: CI workarounds
  when: relevant condition
```

---

## 6. Сравнение инцидентов с историей проекта

| Дата | Роль | Ошибка | Класс |
|------|------|--------|-------|
| 2026-02-28 | pam_hardening | pacman task без when → crash на Ubuntu | missing platform guard |
| 2026-03-01 | gpu_drivers | logrotate не установлен в prepare | missing prepare dependency |
| 2026-03-01 | **user** | video group не создана в prepare | missing prepare dependency |
| 2026-03-01 | **user** | logrotate только для Arch в vagrant | incomplete cross-platform prepare |
| 2026-03-01 | **user** | sudoers hardening ломает become (Arch) | role side-effect on test runner |

Инцидент #3 этой сессии — принципиально новый класс проблем для проекта. Все
предыдущие molecule-проблемы были связаны с отсутствием зависимостей или неправильными
platform guards. Здесь впервые тестируемая роль изменяет системное поведение таким
образом, что это влияет на механизм выполнения самих тестов (become через sudo).

Это возможно только для ролей, которые изменяют:
- `/etc/sudoers` или `/etc/sudoers.d/`
- `/etc/pam.d/` (может заблокировать PAM auth)
- `/etc/ssh/sshd_config` (может разорвать SSH-соединение Ansible)
- Network configuration (может потерять connectivity)

Такие роли требуют отдельного анализа prepare-шага на предмет CI self-consistency.

---

## 7. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | Роли, изменяющие sudoers, потенциально ломают become для последующих задач в том же play. Docker это не показывает (нет sudo). | Любая роль с sudoers/PAM задачами |
| 2 | sudoers last-match-wins + alphabetical read order = порядок имён файлов важен. `wheel` (`w`) > `vagrant` (`v`) → breaking. `sudo` (`s`) < `vagrant` (`v`) → safe. | Vagrant тесты ролей с `/etc/sudoers.d/` |
| 3 | Asymmetric failure (Ubuntu pass, Arch fail) при одинаковой роли почти всегда означает разницу в box-специфичных defaults, а не в самой роли. | CI debugging heuristics |
| 4 | prepare.yml должен явно создавать все группы, которые нужны для converge. Полагаться на "скорее всего присутствует в образе" — implicit dependency. | Все molecule сценарии |
| 5 | Порядок в prepare.yml: update_cache → create groups → install packages → CI guards. Нарушение порядка (установка пакета до update_cache) работает случайно, не надёжно. | Все prepare.yml |
| 6 | `validate: "/usr/sbin/visudo -cf %s"` обязательна для любого файла в `/etc/sudoers.d/`. Невалидный sudoers = система без sudo = недоступная VM. | Все задачи с sudoers |
| 7 | Vagrant-specific converge.yml изолирует docker и vagrant конфигурации. Shared converge удобен, но при появлении divergence (password aging, root lock) лучше иметь отдельные файлы сразу. | Любая роль с Docker+Vagrant |

---

## 8. Known gaps

- **password aging не тестируется:** `user_manage_password_aging: false` в обоих
  converge (docker + vagrant). В Docker это правильно (chage в контейнерах
  ненадёжен). В Vagrant VMs password aging должен работать, но требует проверки
  что `chage` корректно устанавливает shadow-поля. Деферировано.

- **root lock не тестируется:** `user_verify_root_lock: false` в обоих converge.
  На реальной системе (production) root должен быть заблокирован. В vagrant boxes
  root обычно не заблокирован. Для полного покрытия нужен отдельный тест или
  prepare-шаг, который блокирует root и потом проверяет assert.

- **Idempotence с umask-файлами:** `verify.yml` не проверяет идемпотентность
  отдельно — это делает molecule. Если `ansible.builtin.template` не сохраняет
  trailing newline или меняет encoding — может быть flaky idempotence. Не наблюдалось,
  но стоит иметь в виду при изменении шаблонов.
