# Post-Mortem: CI-тесты для роли `package_manager`

**Дата:** 2026-02-24
**Статус:** Завершено — CI зелёный
**Коммиты:** `8b2f687` → `3708e9a` (5 итераций)

---

## 1. Задача

Создать CI-тесты для роли `package_manager`:
- роль была невидима для CI (отсутствовал `molecule/docker/molecule.yml`)
- не дублировать логику между localhost-сценарием (`default/`) и docker/CI
- переиспользовать verify-плейбук через `molecule/shared/` паттерн
- улучшить качество тестов: value-level проверки, permissions, idempotency

---

## 2. Архитектурные решения

### `shared/` паттерн

Принята та же структура, что уже используется в ролях `locale`, `hostname`, `ntp`:

```
molecule/
  shared/
    converge.yml   ← единый playbook для localhost + docker
    verify.yml     ← distro-блоки с value-level assertions
  default/         ← localhost (ссылается на ../shared/)
  docker/          ← CI (ссылается на ../shared/)
    prepare.yml    ← pacman -Sy перед converge
```

### Флаги условной верификации

Для функционала, недоступного в Docker (AUR, reflector — требуют интернет и не-root), введены
boolean-флаги в `host_vars`:

| Флаг | Docker | default (localhost) |
|---|---|---|
| `pm_verify_aur` | `false` (skip-tags) | `true` |
| `pm_verify_mirrors` | `false` (skip-tags) | `true` |

`default/molecule.yml` передаёт `pm_verify_aur: true` и `pm_verify_mirrors: true` через
`inventory.host_vars.localhost`. Docker-сценарий использует `skip-tags: report,aur,mirrors`.

### Улучшения качества тестов

По сравнению со старым localhost-only `verify.yml`:

| Аспект | Было | Стало |
|---|---|---|
| Проверка значений | отсутствовала | `ParallelDownloads = 5`, `-k 3`, `installonly_limit=3` |
| Permissions | отсутствовала | `mode == '0644'`, `pw_name == 'root'` |
| Ansible-marker | отсутствовала | `'Managed by Ansible' in content` |
| Idempotency | отсутствовала | шаг `idempotence` в `test_sequence` |
| Timer-проверки | `service_facts` | `systemctl is-enabled` |

---

## 3. Инциденты CI

### Инцидент #1 — ansible-lint `syntax-check[specific]` на task-файлах

**Commit:** `7ca012d`
**Ошибка:**
```
syntax-check[specific]: 'ansible.builtin.stat' is not a valid attribute for a Play
```
в файлах: `verify_arch.yml`, `verify_apt.yml`, `verify_dnf.yml`, `verify_xbps.yml`

**Причина:**

Claudette создал 4 отдельных task-файла в `molecule/shared/`, подключаемых через `include_tasks`.
ansible-lint с профилем `production` сканирует все `roles/**/*.yml`. Файлы без ключа `hosts:` он
парсит как playbook-play. Первый dict в файле (`- name: Stat /etc/pacman.conf`) трактуется как
определение Play, а `ansible.builtin.stat:` — как неизвестный атрибут Play.

```
roles/package_manager/molecule/shared/verify_arch.yml  ← нет hosts: → Play-парсинг
  - name: Stat /etc/pacman.conf             # ← трактуется как Play name
    ansible.builtin.stat:                   # ← 'not a valid attribute for a Play'
```

Файл был корректным task-файлом Ansible, но ansible-lint не делает различий — он парсит всё
с одними правилами.

**Fix:**

Удалить 4 отдельных файла. Перенести весь verify-код в единый `verify.yml`, используя
`block` + `when: ansible_facts['os_family'] == 'Archlinux'` для группировки по дистрибутиву:

```yaml
- name: Verify Arch Linux — pacman.conf
  when: ansible_facts['os_family'] == 'Archlinux'
  block:
    - name: Stat /etc/pacman.conf
      ansible.builtin.stat:
        path: /etc/pacman.conf
      register: pm_verify_pacman_stat
    # ...
```

**Урок:** Нельзя создавать отдельные task-файлы в `molecule/shared/`. ansible-lint парсит
`roles/**/*.yml` как playbook-play и падает на `syntax-check[specific]`. Единственный
`verify.yml` с `block` + `when:` — единственно корректный подход.

---

### Инцидент #2 — Handler не найден (case sensitivity)

**Commit:** `d22eb0d`
**Ошибка:**
```
The requested handler 'daemon-reload' was not found in either the main handlers
list nor in the listening handlers list
```

**Причина:**

В `handlers/main.yml` handler был назван с заглавной буквы:
```yaml
- name: Daemon-reload           # ← capital D
  ansible.builtin.systemd:
    daemon_reload: true
```

В `tasks/paccache.yml` notify использовал строчную букву:
```yaml
notify: daemon-reload           # ← lowercase d
```

Ansible case-sensitive при поиске хендлеров. На localhost-VM баг был замаскирован:
при выполнении полного playbook мог присутствовать хендлер из другой роли с именем
`daemon-reload` через `listen:` — или просто хендлер не вызывался при конкретных условиях.
В изолированном Docker-контейнере несоответствие стало явным.

**Fix:**

```yaml
- name: daemon-reload           # ← lowercase, совпадает с notify
  ansible.builtin.systemd:
    daemon_reload: true
```

**Урок:** Ansible case-sensitive при сопоставлении `notify:` и `name:` хендлера.
Стандарт проекта (MED-03): использовать `listen:` на всех хендлерах — это полностью
устраняет проблему, так как matching идёт по `listen:` строке, а не по `name:`.

---

### Инцидент #3 — Undefined variable в verify playbook

**Commit:** `da39d0e`
**Ошибка:**
```
AnsibleUndefinedVariable: 'package_manager_pacman_parallel_downloads' is undefined
```

**Причина:**

`defaults/main.yml` роли загружается только при выполнении роли через `roles:` или
`include_role:`. Standalone-плейбук `molecule/shared/verify.yml` выполняется отдельно
(Molecule запускает verify как независимый шаг после converge). Переменные роли в нём
недоступны.

Ошибка проявлялась не в assert-условии (`that:`), а в `fail_msg:` — шаблон
`{{ package_manager_pacman_parallel_downloads }}` вычислялся даже если assert прошёл.

**Fix:**

Добавить явную загрузку defaults в verify playbook:
```yaml
- name: Verify package_manager role
  hosts: all
  vars_files:
    - "../../defaults/main.yml"   # molecule/shared/ → роль/defaults/
```

**Урок:** `defaults/main.yml` роли НЕ загружается автоматически в verify playbook.
Всегда добавлять явный `vars_files: - "../../defaults/main.yml"` в `molecule/shared/verify.yml`.
Путь `../../` — от `molecule/shared/` до корня роли.

---

### Инцидент #4 — `service_facts` не видит `.timer` юниты

**Commit:** `3708e9a`
**Ошибка:**
```
"assertion": "'paccache.timer' in ansible_facts.services"
"evaluated_to": false
```

**Причина:**

`ansible.builtin.service_facts` вызывает `systemctl list-units --type=service --all`.
Ключ `--type=service` исключает timer-юниты из результата. Модуль возвращает только
`.service` юниты в `ansible_facts.services`.

Это известное поведение Ansible — открытый issue #51362 с 2018 года. Не баг, а
намеренное ограничение: модуль назван `service_facts`, не `unit_facts`.

```
ansible_facts.services:
  'paccache.service': {...}   ← есть
  'paccache.timer': ???       ← отсутствует
```

**Fix:**

Заменить `service_facts` + assert на прямые команды:
```yaml
- name: Check paccache.timer is enabled  # noqa: command-instead-of-module
  ansible.builtin.command:
    cmd: systemctl is-enabled paccache.timer
  register: pm_verify_paccache_timer
  changed_when: false
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Assert paccache.timer is enabled (systemd)
  ansible.builtin.assert:
    that: pm_verify_paccache_timer.stdout | trim == 'enabled'
  when: ansible_facts['service_mgr'] == 'systemd'
```

`systemctl is-enabled` возвращает exit code 0 и stdout `"enabled"` для любого типа юнита.
Применено также к `reflector.timer`.

**Урок:** `service_facts` непригоден для проверки timer-юнитов. Использовать
`systemctl is-enabled <unit>.timer` напрямую. (Тот же урок, что Инцидент #1 в ntp_audit
post-mortem — подтверждён повторно.)

---

## 4. Финальная структура

```
molecule/
  shared/
    converge.yml    ← hosts: all; roles: [package_manager]
    verify.yml      ← vars_files: ../../defaults/main.yml
                       Arch block: pacman.conf + paccache + makepkg + yay + reflector
                       Debian block: apt parallel + dpkg options
                       RedHat block: dnf.conf
                       Void block: xbps.conf + cron
  default/
    molecule.yml    ← localhost; pm_verify_aur: true, pm_verify_mirrors: true
                       playbooks: converge/verify → ../shared/
                       test_sequence: syntax, converge, idempotency, verify
  docker/
    molecule.yml    ← arch-systemd image; skip-tags: report,aur,mirrors
                       ANSIBLE_ROLES_PATH: ${MOLECULE_PROJECT_DIRECTORY}/../
                       test_sequence: syntax, create, prepare, converge, idempotence, verify, destroy
    prepare.yml     ← community.general.pacman: update_cache: true
```

```
handlers/
  main.yml          ← daemon-reload (lowercase — совпадает с notify)
```

---

## 5. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | Отдельные task-файлы в `molecule/shared/` → `syntax-check[specific]`; только `block` + `when:` в едином `verify.yml` | Все роли |
| 2 | `defaults/main.yml` не загружается в standalone verify — добавлять `vars_files: ../../defaults/main.yml` | Все shared verify |
| 3 | `service_facts` не возвращает `.timer` юниты — использовать `systemctl is-enabled <unit>` | Все роли с timer |
| 4 | Ansible case-sensitive: `notify: daemon-reload` ≠ `name: Daemon-reload`; стандарт проекта — `listen:` на всех хендлерах | Все роли |
| 5 | Изолированный Docker-контейнер обнажает баги, которые маскирует полный playbook-контекст на VM | Все роли |
| 6 | `pm_verify_aur` / `pm_verify_mirrors` — паттерн флагов для условного пропуска неверифицируемого функционала в CI | Роли с внешними зависимостями |

---

## 6. Known gaps (за рамками задачи)

- **Debian/Ubuntu сценарий отсутствует** — verify.yml содержит apt-блок, но Docker-образ только Arch.
  Потребует отдельного образа и второй платформы в `docker/molecule.yml`.
- **Fedora/Void не тестируются** — dnf и xbps блоки написаны, но нет соответствующих Docker-образов.
- **yay и reflector тестируются только на localhost** — в CI пропускаются через флаги.
  Возможный подход: отдельный интеграционный сценарий с self-hosted runner.
- **Нет теста на pacman.conf drift** — если файл изменён вручную, idempotence шаг поймает changed,
  но не покажет что именно изменилось.
