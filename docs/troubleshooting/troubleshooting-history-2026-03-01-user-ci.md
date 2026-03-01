# Post-Mortem: Molecule CI для роли `user`

**Дата:** 2026-03-01
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)

**PR #10** — первичный фикс тестов:
- Итерации CI: 2 запуска, 1 уникальная ошибка
- Коммиты: `919d1df` → `8a7b5dc` (5 коммитов)
- [fix(user): fix molecule tests for Docker + Vagrant](https://github.com/textyre/bootstrap/pull/10)

**PR #13** — полное покрытие тестов (вторая сессия):
- Итерации CI: 3 запуска, 3 уникальные ошибки
- Коммиты: `03bab57` → `2562f73` (7 коммитов)
- [test(user): full molecule coverage — shadow lock, aging, sudo:true, absent user, logrotate](https://github.com/textyre/bootstrap/pull/13)

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

## 3. Инциденты — PR #13 (полное покрытие)

После PR #10 была проведена аудит-сессия: тесты проверяли только часть того, что роль
реально делает. PR #13 закрыл все пробелы.

### Инцидент #4 — `regex_search()` возвращает строку, не bool (все среды)

**Коммит:** `ca4127b`
**Прогон:** первый CI в PR #13 (run `22538183040`)
**Этап:** verify (Docker), converge (Vagrant ubuntu-base)
**Ошибки:**

Docker — `verify.yml:56`:
```
fatal: [Archlinux-systemd]: FAILED! => {"msg": "Task failed: Conditional result (True)
was derived from value of type 'str' at '.../verify.yml:56:13'.
Conditionals must have a boolean result."}
```

Vagrant ubuntu-base — `security.yml:16` (роль, converge):
```
fatal: [ubuntu-base]: FAILED! => {"msg": "Task failed: Conditional result (True)
was derived from value of type 'str' at '.../tasks/security.yml:16:9'.
Conditionals must have a boolean result."}
```

**Анализ:**

Jinja2 фильтр `regex_search()` возвращает matched substring (строку) при совпадении
или `None` при несовпадении — но НЕ boolean. В `ansible.builtin.assert that:` Ansible
2.15+ требует строго boolean результат:

```yaml
# ПЛОХО — возвращает '!' (str) при совпадении
- _user_verify_owner_shadow.ansible_facts.getent_shadow['testuser_owner'][0] | regex_search('^[!*]')

# ХОРОШО — Jinja2 test 'is regex()' возвращает True/False
- _user_verify_owner_shadow.ansible_facts.getent_shadow['testuser_owner'][0] is regex('^[!*]')
```

Проблема была в двух местах одновременно:
1. `ansible/roles/user/tasks/security.yml:16` — проверка root shadow (роль)
2. `ansible/roles/user/molecule/shared/verify.yml:56,159` — проверки shadow в verify

В Docker `security.yml` не запускался (`user_verify_root_lock: false`), поэтому Docker
упал только на `verify.yml`. В Vagrant `user_verify_root_lock: true`, поэтому Vagrant
упал на `security.yml` в converge ещё до verify.

**Фикс:** заменить `| regex_search('^pattern')` на `is regex('^pattern')` везде в
`assert that:` условиях. Применимо к любым assertion в role tasks и verify.yml.

**Урок:** `regex_search()` — фильтр для извлечения данных (возвращает строку).
`is regex()` — тест для проверки совпадения (возвращает bool). В `assert that:` всегда
использовать тест, не фильтр.

---

### Инцидент #5 — arch-base box не блокирует root (vagrant arch-vm только)

**Коммит:** `2562f73`
**Прогон:** третий CI в PR #13 (run `22538351517`)
**Этап:** converge (arch-vm only; ubuntu-base прошла)
**Ошибка:**

```json
{
  "assertion": "user_root_shadow.ansible_facts.getent_shadow['root'][0] is regex('^[!*]')",
  "evaluated_to": false,
  "msg": "CIS 5.4.3 FAIL: root account has a usable password."
}
```

**Анализ:**

`user_verify_root_lock: true` в `vagrant/converge.yml` заставляет роль вызывать
`security.yml`, который проверяет что root shadow field начинается с `!` или `*`.

Наш `arch-base` Vagrant box поставляется без заблокированного root (shadow field не
начинается с `!` или `*`). `ubuntu-base` box поставляется с root `*` в shadow
(locked by default).

Это поведение коробки (box), не роли. Роль только ПРОВЕРЯЕТ что root заблокирован —
она его не блокирует (это задача для отдельной hardening роли).

**Фикс:** добавить `passwd -l root` в `vagrant/prepare.yml` для Arch перед converge:

```yaml
- name: Lock root account (Arch — box ships without locked root)
  ansible.builtin.command:
    cmd: passwd -l root
  changed_when: true
  when: ansible_facts['os_family'] == 'Archlinux'
```

`passwd -l` устанавливает shadow password field в `!<hash>` — начинается с `!`,
`is regex('^[!*]')` → True.

**Урок:** Тестовое окружение (box) должно соответствовать production-контракту который
проверяет роль. Если роль проверяет `user_verify_root_lock`, prepare.yml обязан
гарантировать заблокированный root на платформах, где box его не блокирует.

---

### Инцидент #6 — vars_files переопределяет molecule group_vars (потенциальная проблема)

**Коммит:** `685a963` (превентивный фикс)
**Этап:** проектирование, не CI-ошибка

**Проблема:**

`shared/verify.yml` загружает `vars_files: - "../../defaults/main.yml"`. В defaults:
`user_manage_password_aging: true`. Это play-level vars — приоритет выше чем у
inventory `group_vars` в molecule. Если бы Docker использовал `provisioner.inventory.
group_vars.all.user_manage_password_aging: false` — это НЕ переопределило бы значение
из vars_files в verify.yml.

**Решение:** использовать `provisioner.options.extra-vars:` вместо `group_vars`:

```yaml
# docker/molecule.yml
provisioner:
  name: ansible
  options:
    skip-tags: report
    extra-vars: "user_manage_password_aging=false"
```

`extra-vars` имеют наивысший приоритет в Ansible (выше play vars_files) и применяются
ко всем playbook'ам сценария (prepare, converge, verify).

Это позволяет: Docker — `false` через extra-vars; Vagrant — `true` через converge vars
+ `true` в defaults для verify.yml.

**Урок:** Для переопределения переменных в `shared/verify.yml` который загружает
defaults через `vars_files` — только `extra-vars`, не `group_vars`.

---

## 4. Временная шкала

```
── Сессия 1 (2026-03-01) — PR #10 ──────────────────────────────────────────────

[Статический анализ роли и molecule файлов]
  → Выявлены: video group, logrotate Ubuntu, update_cache Arch
  → pre-CI фиксы подготовлены

919d1df  fix(user/molecule): ensure video group exists in docker prepare
47fad4a  fix(user/molecule): fix vagrant prepare — logrotate for Ubuntu, video group, update_cache
f295602  fix(user/molecule): add vagrant-specific converge.yml
775c6b5  fix(user/molecule): point vagrant scenario to local converge.yml
         ↓ PR #10 открыт

         ↓ Run 22537661748 (первый):
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

         ↓ Run 22537756596 (второй):
         ↓   Ansible Lint:                          PASS ✓
         ↓   YAML Lint:                             PASS ✓
         ↓   Docker (Arch+Ubuntu systemd):          PASS ✓
         ↓   Vagrant arch-vm:                       PASS ✓  (3m10s)
         ↓   Vagrant ubuntu-base:                   PASS ✓  (2m50s)

         ↓ PR #10 merged (squash) → master
         ↓ Worktree .claude/worktrees/fix-user-molecule удалён

── Сессия 2 (2026-03-01) — PR #13 ──────────────────────────────────────────────

[Аудит покрытия: анализ role tasks vs verify.yml]
  → Выявлены 7 пробелов: shadow lock, password aging, root lock,
    sudo:true user, state:absent user, logrotate directives,
    password_warn_age dead variable

03bab57  docs(user): document password_expire_warn ansible-core 2.17 limitation
685a963  test(user): update shared/converge.yml — add testuser_with_sudo, aging fields
         test(user): update vagrant/converge.yml — enable password_aging:true, root_lock:true
         test(user): add extra-vars to docker/molecule.yml for user_manage_password_aging=false
         test(user): add testuser_toberemoved to prepare files (docker + vagrant)
         test(user): rewrite shared/verify.yml — full coverage
         ↓ PR #13 открыт

         ↓ Run 22538183040 (первый):
         ↓   Ansible Lint:                          PASS ✓
         ↓   YAML Lint:                             PASS ✓
         ↓   Docker (Arch+Ubuntu systemd):          FAIL ✗
         ↓     verify.yml:56 — regex_search() returns str not bool (Инцидент #4)
         ↓   Vagrant ubuntu-base:                   FAIL ✗
         ↓     security.yml:16 — same: regex_search() in assert (Инцидент #4)
         ↓   Vagrant arch-vm:                       FAIL ✗
         ↓     security.yml:16 — same (Инцидент #4)

[Диагностика: | regex_search() → str; is regex() → bool]
  → заменить везде в assert that: условиях

ca4127b  fix(user): replace regex_search() with is regex() test in assert conditions
         ↓ PR #13 обновлён

         ↓ Run 22538351517 (второй):
         ↓   Ansible Lint:                          PASS ✓
         ↓   YAML Lint:                             PASS ✓
         ↓   Docker (Arch+Ubuntu systemd):          PASS ✓
         ↓   Vagrant ubuntu-base:                   PASS ✓
         ↓   Vagrant arch-vm:                       FAIL ✗
         ↓     verify:  root[0] is regex('^[!*]') → false (Инцидент #5)

[Диагностика: arch-base box поставляется без заблокированного root]
  → passwd -l root в prepare.yml для Arch

2562f73  fix(user/molecule): lock root in Arch vagrant prepare (box ships unlocked)
         ↓ PR #13 обновлён

         ↓ Run 22538431092 (третий):
         ↓   Ansible Lint:                          PASS ✓
         ↓   YAML Lint:                             PASS ✓
         ↓   Docker (Arch+Ubuntu systemd):          PASS ✓
         ↓   Vagrant arch-vm:                       PASS ✓  (4m22s)
         ↓   Vagrant ubuntu-base:                   PASS ✓  (3m51s)

         ↓ PR #13 merged (squash) → master
         ↓ Worktree .worktrees/fix/user-molecule-coverage удалён
```

---

## 5. Финальная структура

```
ansible/roles/user/molecule/
├── shared/
│   ├── converge.yml     ← role: user; testuser_owner, testuser_extra (aging fields),
│   │                       testuser_with_sudo; accounts (testuser_toberemoved absent);
│   │                       user_manage_password_aging: false (Docker override via extra-vars)
│   └── verify.yml       ← полное покрытие: owner/extra/sudo-user assertions;
│                           shadow lock (is regex); password aging (when: user_manage_password_aging);
│                           root lock (when: user_verify_root_lock); absent user; sudoers; logrotate
├── docker/
│   ├── molecule.yml     ← Archlinux-systemd + Ubuntu-systemd, privileged, cgroupns
│   │                       extra-vars: "user_manage_password_aging=false"
│   └── prepare.yml      ← update_cache (Arch/Ubuntu); video group; logrotate pkg;
│                           testuser_toberemoved (создаётся, роль удалит)
└── vagrant/
    ├── molecule.yml     ← arch-vm (arch-base box) + ubuntu-base (ubuntu-base box)
    │                       converge: converge.yml  ← local, не ../shared/
    ├── prepare.yml      ← update_cache (Arch/Ubuntu); video group; logrotate pkg;
    │                       zz-molecule-vagrant-nopasswd (Arch only);
    │                       testuser_toberemoved; passwd -l root (Arch only)
    └── converge.yml     ← vagrant-specific vars: user_manage_password_aging: true;
                            user_verify_root_lock: true; testuser_extra с aging;
                            testuser_with_sudo; accounts с absent user
```

**Ключевые изменения относительно исходного состояния:**

| Файл | PR #10 | PR #13 |
|------|--------|--------|
| `docker/prepare.yml` | добавлено `ansible.builtin.group: video` | добавлен `testuser_toberemoved` |
| `docker/molecule.yml` | без изменений | добавлен `extra-vars: user_manage_password_aging=false` |
| `vagrant/prepare.yml` | исправлены logrotate/update_cache/video; guard для vagrant sudo | добавлены `testuser_toberemoved`, `passwd -l root` (Arch) |
| `vagrant/converge.yml` | создан (изоляция от Docker vars) | расширен: aging/root_lock/with_sudo/absent user |
| `vagrant/molecule.yml` | `converge: converge.yml` (local) | без изменений |
| `shared/converge.yml` | baseline | добавлены testuser_with_sudo, aging fields, accounts |
| `shared/verify.yml` | базовые проверки owner/sudoers/logrotate | полное покрытие (shadow lock, aging, root lock, sudo:true, absent user, все logrotate directives) |

---

## 6. Ключевые паттерны

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

# 4. Фикс окружения для соответствия production-контракту
- name: Lock root account (Arch — box ships without locked root)
  ansible.builtin.command:
    cmd: passwd -l root
  changed_when: true
  when: ansible_facts['os_family'] == 'Archlinux'

# 5. CI-специфичные гарантии (sudoers guards, etc.)
- name: CI workarounds
  when: relevant condition

# 6. Предварительное состояние для тестов (absent users, etc.)
- name: Create user that role must remove
  ansible.builtin.user:
    name: testuser_toberemoved
    state: present
    create_home: false
```

### is regex() vs regex_search() в assert that:

Для boolean-проверок в `ansible.builtin.assert that:` всегда использовать Jinja2 тест,
не фильтр:

```yaml
# ПЛОХО — regex_search() возвращает строку (или None), не bool:
assert:
  that:
    - shadow_field | regex_search('^[!*]')   # → str '!' при совпадении → FAIL в assert

# ХОРОШО — is regex() возвращает True/False:
assert:
  that:
    - shadow_field is regex('^[!*]')          # → bool → OK в assert
```

**Правило:** `regex_search()` — для извлечения данных (→ str/None). `is regex()` — для
проверки совпадения в условиях (→ bool). В `assert that:` и `when:` использовать только
Jinja2 tests (`is`/`is not`), не фильтры.

### extra-vars для переопределения vars_files в shared/verify.yml

Если `shared/verify.yml` загружает `vars_files: ["../../defaults/main.yml"]`, только
`extra-vars` гарантированно переопределит значения (highest Ansible precedence):

```yaml
# docker/molecule.yml — ПРАВИЛЬНО:
provisioner:
  name: ansible
  options:
    extra-vars: "user_manage_password_aging=false"

# НЕ РАБОТАЕТ для переопределения vars_files:
provisioner:
  inventory:
    group_vars:
      all:
        user_manage_password_aging: false   # group_vars < play vars_files → игнорируется
```

### Условная проверка в verify.yml для Docker vs Vagrant

Когда одна переменная меняет поведение проверок между средами:

```yaml
# В verify.yml:
- name: Assert password aging configured
  ansible.builtin.assert:
    that:
      - shadow['testuser_owner'][3] | int == 365
  when: user_manage_password_aging | bool

- name: Assert root is locked
  ansible.builtin.assert:
    that:
      - root_shadow[0] is regex('^[!*]')
  when: user_verify_root_lock | bool
```

Docker передаёт `extra-vars: "user_manage_password_aging=false"` → проверки пропускаются.
Vagrant задаёт `user_manage_password_aging: true` в converge.yml → проверки выполняются.

### Безопасная проверка absent users

`ansible.builtin.getent` падает с ошибкой если ключ не найден. Используем `ignore_errors`
+ отдельный `assert` вместо `failed_when`:

```yaml
# ПРАВИЛЬНО — явное разделение:
- name: Try to get absent user from passwd
  ansible.builtin.getent:
    database: passwd
    key: testuser_toberemoved
  register: result
  ignore_errors: true

- name: Assert absent user not found
  ansible.builtin.assert:
    that:
      - result is failed   # True если getent вернул ошибку = пользователь не существует

# ПЛОХО — self-referential:
- name: Get user
  ansible.builtin.getent:
    database: passwd
    key: testuser_toberemoved
  register: result
  failed_when: result is not failed   # противоречиво; getent считает успех успехом
```

---

## 7. Сравнение инцидентов с историей проекта

| Дата | Роль | PR | Ошибка | Класс |
|------|------|----|--------|-------|
| 2026-02-28 | pam_hardening | — | pacman task без when → crash на Ubuntu | missing platform guard |
| 2026-03-01 | gpu_drivers | — | logrotate не установлен в prepare | missing prepare dependency |
| 2026-03-01 | **user** | #10 | video group не создана в prepare | missing prepare dependency |
| 2026-03-01 | **user** | #10 | logrotate только для Arch в vagrant | incomplete cross-platform prepare |
| 2026-03-01 | **user** | #10 | sudoers hardening ломает become (Arch) | role side-effect on test runner |
| 2026-03-01 | **user** | #13 | `regex_search()` → str в assert (все среды) | wrong jinja2 construct type |
| 2026-03-01 | **user** | #13 | arch-base box не блокирует root (arch-vm only) | box state ≠ production contract |
| 2026-03-01 | **user** | #13 | `group_vars` не переопределяет `vars_files` | ansible variable precedence |

Инцидент #3 (PR #10) — принципиально новый класс: роль ломает механизм выполнения
собственных тестов. Инцидент #4 (PR #13) — типичная путаница filter vs test в Jinja2.
Инцидент #5 — бокс не отражает production-контракт (нужен explicit prepare-шаг).

Полный реестр классов проблем в molecule:
- `missing platform guard` — задача без `when:` для платформо-специфичного действия
- `missing prepare dependency` — converge зависит от чего-то чего нет в образе
- `incomplete cross-platform prepare` — зависимость установлена только для одной платформы
- `role side-effect on test runner` — роль меняет механизм `become`/SSH/сеть
- `wrong jinja2 construct type` — фильтр там где нужен тест (или наоборот)
- `box state ≠ production contract` — box не соответствует ожидаемому baseline

Роли, требующие особого внимания CI self-consistency:
- Роли с `/etc/sudoers` или `/etc/sudoers.d/`
- Роли с `/etc/pam.d/` (может заблокировать PAM auth)
- Роли с `/etc/ssh/sshd_config` (может разорвать SSH-соединение Ansible)
- Роли с network configuration (может потерять connectivity)

---

## 8. Ретроспективные выводы

| # | Урок | PR | Применимость |
|---|------|-----|-------------|
| 1 | Роли, изменяющие sudoers, потенциально ломают become для последующих задач в том же play. Docker это не показывает (нет sudo). | #10 | Любая роль с sudoers/PAM задачами |
| 2 | sudoers last-match-wins + alphabetical read order = порядок имён файлов важен. `wheel` (`w`) > `vagrant` (`v`) → breaking. `sudo` (`s`) < `vagrant` (`v`) → safe. | #10 | Vagrant тесты ролей с `/etc/sudoers.d/` |
| 3 | Asymmetric failure (Ubuntu pass, Arch fail) при одинаковой роли почти всегда означает разницу в box-специфичных defaults, а не в самой роли. | #10 | CI debugging heuristics |
| 4 | prepare.yml должен явно создавать все группы и предварительные состояния, которые нужны для converge. Полагаться на "скорее всего присутствует" — implicit dependency. | #10/#13 | Все molecule сценарии |
| 5 | Порядок в prepare.yml: update_cache → create groups → install packages → box state fixes → CI guards → pre-state for tests. | #10/#13 | Все prepare.yml |
| 6 | `validate: "/usr/sbin/visudo -cf %s"` обязательна для любого файла в `/etc/sudoers.d/`. Невалидный sudoers = система без sudo = недоступная VM. | #10 | Все задачи с sudoers |
| 7 | Vagrant-specific converge.yml изолирует docker и vagrant конфигурации. При появлении divergence (password aging, root lock) отдельные файлы — правильный выбор. | #10/#13 | Любая роль с Docker+Vagrant |
| 8 | `regex_search()` (filter) → str/None; `is regex()` (test) → bool. В `assert that:` и `when:` всегда использовать тест, не фильтр. | #13 | Все verify.yml и role tasks с assert |
| 9 | Box baseline ≠ production-контракт. Если роль проверяет состояние (root locked) — prepare.yml должен это состояние гарантировать, а не полагаться на box. | #13 | Все Vagrant сценарии с state assertions |
| 10 | Только `extra-vars` переопределяет `vars_files` в shared/verify.yml. `group_vars` имеет более низкий приоритет, чем play `vars_files`. | #13 | Все сценарии с shared/verify.yml загружающим defaults |
| 11 | Аудит покрытия после первой итерации — стандартный шаг. "Тесты зелёные" ≠ "тесты полные". После первого CI pass — сравнить role tasks с verify assertions. | #13 | Все molecule сценарии |

---

## 9. Known gaps

### Закрытые в PR #13 (были открыты после PR #10)

- ~~**password aging не тестируется**~~ — **ЗАКРЫТО:** Vagrant тестирует `chage`
  через shadow-поля (max/min days). Docker пропускает через `user_manage_password_aging=false`
  extra-var. Условная проверка в verify.yml.

- ~~**root lock не тестируется**~~ — **ЗАКРЫТО:** Vagrant тестирует. arch-base box
  теперь блокируется в prepare.yml (`passwd -l root`). Docker пропускает через
  `user_verify_root_lock: false`.

- ~~**shadow lock не проверяется**~~ — **ЗАКРЫТО:** `is regex('^[!*]')` в verify.yml
  для locked users.

- ~~**sudo: true user путь не тестируется**~~ — **ЗАКРЫТО:** `testuser_with_sudo`
  в converge; verify проверяет членство в sudo-группе.

- ~~**state: absent не тестируется**~~ — **ЗАКРЫТО:** `testuser_toberemoved` создаётся
  в prepare; роль удаляет; verify проверяет отсутствие в passwd.

- ~~**logrotate directives (delaycompress, missingok, notifempty, create 0640) не тестируются**~~
  — **ЗАКРЫТО:** все четыре директивы проверяются в verify.yml.

### Открытые gaps

- **`password_warn_age` не применяется:** Переменная `password_warn_age: 7` в
  defaults/main.yml. Модуль `ansible.builtin.user.password_expire_warn` требует
  ansible-core ≥ 2.17. Проект использует 2.15. Значение задокументировано в
  defaults как "для будущего использования". Тест будет возможен после апгрейда.

- **Idempotence с umask-файлами:** Molecule запускает `idempotence` шаг автоматически.
  Если `ansible.builtin.template` не сохраняет trailing newline или меняет encoding —
  может быть flaky. Не наблюдалось, но стоит проверить при изменении шаблонов umask.
