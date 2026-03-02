# Post-Mortem: Molecule CI для роли `power_management`

**Дата:** 2026-03-01
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)
**Итерации CI:** 2 прогона, 4 уникальных ошибки (3 запланированные, 1 обнаружена в CI)
**Коммиты:** `70b62a1` → `fe734bf` (3 коммита в ветке `fix/power-management-molecule-tests`)
**PR:** [#11](https://github.com/textyre/bootstrap/pull/11)

---

## 1. Задача

Довести molecule-тесты роли `power_management` до зелёного в трёх средах:

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker (`molecule/docker/`) | Archlinux-systemd + Ubuntu-systemd | Config files, audit timer, drift state, conflicting services masked |
| Vagrant arch-vm | `arch-base` box (KVM) | То же + cpupower install, udev rule, идемпотентность |
| Vagrant ubuntu-base | `ubuntu-base` box (KVM) | То же на Ubuntu + linux-tools-common |

**Роль `power_management`:** управляет CPU governor (desktop → udev rule, laptop → TLP),
systemd sleep/logind конфигами, аудит-таймером, детекцией drift. Поддерживает Arch и
Debian/Ubuntu. В тестах конвергируется в desktop-режиме (`power_management_device_type: desktop`,
`power_management_assert_strict: false`).

**Контекст:** тесты существовали давно (написаны при создании роли), но никогда не
запускались в CI. В MEMORY.md числились как "pre-existing failures". Задача: зафиксировать
и довести до зелёного.

---

## 2. Статический анализ — ожидаемые баги (до первого прогона)

Перед открытием PR проведён полный статический анализ кода. Найдены три бага.

### Баг A — `handlers/main.yml` — `Reload udev rules` без `failed_when: false`

**Файл:** `ansible/roles/power_management/handlers/main.yml:20`
```yaml
- name: Reload udev rules
  listen: "reload udev rules"
  ansible.builtin.command: udevadm control --reload-rules
  changed_when: false
  # ← нет failed_when: false !
```

В Docker-контейнерах `systemd-udevd` может не запускаться (systemd его не стартует без
реального udev-окружения). `udevadm control --reload-rules` → rc != 0 → хендлер падает →
весь converge падает.

Хендлер вызывается при каждом первом деплое `50-cpu-governor.rules` → блокирует тест.

### Баг Б — `handlers/main.yml` — `Reload systemd-logind` без `failed_when: false`

**Файл:** `ansible/roles/power_management/handlers/main.yml:11`
```yaml
- name: Reload systemd-logind
  listen: "reload systemd-logind"
  ansible.builtin.systemd:
    name: systemd-logind
    state: reloaded
  when: power_management_init | default('') == 'systemd'
  # ← нет failed_when: false !
```

В контейнерах logind может не принимать reload (нет реального seat/VT). Аналогично Багу А.

### Баг В — `molecule/vagrant/prepare.yml` — нет Arch-подготовки

**Файл:** `ansible/roles/power_management/molecule/vagrant/prepare.yml`

Оригинальный prepare.yml для vagrant:
```yaml
- name: Prepare
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Update apt cache (Ubuntu)
      ...
    - name: Load acpi-cpufreq kernel module
      ...
    - name: Load cpufreq_schedutil kernel module
      ...
```

Для Arch — **ничего**. Нет `pacman update_cache`, нет обновления keyring, нет `pacman -Syu`.
Когда роль затем выполняет `pacman -S cpupower` — база пакетов устарела → GPG-ошибки или
"package not found".

**Ориентир:** `ansible/roles/vm/molecule/vagrant/prepare.yml` — уже работающий паттерн для
vagrant Arch, подтверждённый CI.

---

## 3. Первый прогон CI — неожиданный баг #4

После открытия PR все три job упали с **одинаковой** ошибкой. Баги А, Б, В не успели
проявиться — роль падала раньше.

**Ошибка (Docker + vagrant arch-vm + vagrant ubuntu-base):**
```
TASK [power_management : Set current governor fact] ****************************
ERROR: Task failed: Finalization of task args for 'ansible.builtin.set_fact' failed:
Error while resolving value for 'power_management_current_governor':
object of type 'dict' has no attribute 'content'
```

**Файл:** `tasks/governor.yml:16`
```yaml
- name: Set current governor fact
  ansible.builtin.set_fact:
    power_management_current_governor: >-
      {{ (power_management_governor_raw.content | b64decode | trim)
         if power_management_governor_raw is succeeded else 'unknown' }}
```

### Корневая причина — изменение поведения `is succeeded` в Ansible 2.20

До Ansible 2.20:
- `failed_when: false` + slurp на несуществующий файл → `result.failed = True`
- `result is succeeded` → **False** → ternary возвращает `'unknown'` ✓

В Ansible 2.20 (используется в CI):
- `failed_when: false` + slurp на несуществующий файл → task помечается как `ok`
- `result.failed` в зарегистрированном dict = **False** (overridden by `failed_when`)
- `result is succeeded` → **True** → Jinja2 пытается вычислить `result.content`
- `content` отсутствует в dict упавшего slurp → **AttributeError/KeyError → crash**

**Затронутые файлы `/sys/...` которые не существуют в Docker и VM без cpufreq-модуля:**
- `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` (governor.yml + collect_facts.yml)
- `/sys/class/power_supply/BAT0/capacity`, `/status`, `/charge_control_*` (collect_facts.yml)
- `/var/lib/ansible-power-management/last_state.json` на первом запуске (drift_detection.yml)

**Правило:** `detect.yml` избежал краша, т.к. использует Python `and` short-circuit:
```yaml
# Работает: если is succeeded == True, но content может отсутствовать —
# и так не упадёт, потому что у Docker chassis_type СУЩЕСТВУЕТ (host DMI)
power_management_chassis_raw is succeeded and
(power_management_chassis_raw.content | b64decode | trim) in ...
```
А `governor.yml` использует Jinja2 ternary, где оба branch вычисляются до проверки
условия в некоторых контекстах (либо в версии 2.20 поведение ternary изменилось).

---

## 4. Хронология и фиксы

### Коммит 1 — `70b62a1` — Хендлеры (Баг А + Баг Б)

Два изменения в `handlers/main.yml`:
```yaml
- name: Reload systemd-logind
  ...
  failed_when: false   # ← добавлено

- name: Reload udev rules
  ...
  changed_when: false
  failed_when: false   # ← добавлено
```

Обоснование: хендлеры являются best-effort операциями. Конфиги (logind.conf, udev rule)
уже задеплоены корректно. Reload применит их немедленно, если демон запущен; если нет —
применятся при следующем старте или триггере.

### Коммит 2 — `db9771f` — Vagrant prepare.yml (Баг В)

Полная переписка `molecule/vagrant/prepare.yml` по паттерну `vm` роли:

```yaml
gather_facts: false

tasks:
  # 1. Raw Python (arch-base имеет Python, но explicit bootstrap безопасен)
  - raw: pacman -Sy --noconfirm python
    when: inventory_hostname == 'arch-vm'

  # 2. gather_facts после Python
  - ansible.builtin.setup:

  # 3. Обновление keyring (SigLevel=Never trick)
  - shell: |
      pacman -Sy --noconfirm --config <(sed 's/SigLevel.*/SigLevel = Never/' ...) archlinux-keyring
      pacman-key --populate archlinux
    when: ansible_facts['os_family'] == 'Archlinux'

  # 4. Полный upgrade
  - community.general.pacman: { upgrade: true, update_cache: true }
    when: ansible_facts['os_family'] == 'Archlinux'

  # 5. DNS fix (systemd заменяет resolv.conf на IPv6-stub после syu)
  - copy: { content: "nameserver 8.8.8.8\n...", dest: /etc/resolv.conf, unsafe_writes: true }
    when: ansible_facts['os_family'] == 'Archlinux'

  # 6. Ubuntu apt cache
  - apt: { update_cache: true }
    when: ansible_facts['os_family'] == 'Debian'

  # 7. cpufreq modules (best-effort)
  - command: modprobe acpi-cpufreq
    failed_when: false
  - command: modprobe cpufreq_schedutil
    failed_when: false
```

### Коммит 3 — `fe734bf` — Замена `is succeeded` (Баг #4 / обнаружен в CI)

**Принцип:** вместо `reg is succeeded` использовать `'content' in reg`.

Это работает независимо от версии Ansible и значения `failed_when`. `content` присутствует
в dict только когда slurp реально прочитал файл — никаких сюрпризов.

**`tasks/governor.yml`:**
```yaml
# До:
power_management_current_governor: >-
  {{ (...) if power_management_governor_raw is succeeded else 'unknown' }}

# После:
power_management_current_governor: >-
  {{ (...) if 'content' in power_management_governor_raw else 'unknown' }}
```

**`tasks/collect_facts.yml`** — 5 замен:
```yaml
# governor fact
power_management_fact_governor: >-
  {{ (...) if 'content' in power_management_fact_governor_raw else 'unknown' }}

# battery facts (capacity, status, charge_start, charge_stop)
capacity: "{{ (...) if 'content' in power_management_fact_bat0_capacity_raw else 'N/A' }}"
# ... (аналогично для остальных)
```

**`tasks/drift_detection.yml`:**
```yaml
# До:
power_management_drift_previous: >-
  {{ (...) if power_management_drift_previous_raw is succeeded else {} }}

# После:
power_management_drift_previous: >-
  {{ (...) if 'content' in power_management_drift_previous_raw else {} }}
```

**Почему остальные `is succeeded` не тронуты:**

| Файл | Переменная | Файл на хосте | Безопасно? |
|------|-----------|---------------|-----------|
| `detect.yml` | `chassis_raw` | `/sys/class/dmi/id/chassis_type` | Существует в Docker (host DMI) + используется с `and` short-circuit ✓ |
| `preflight.yml` | `swap_check` | `/proc/swaps` | Всегда существует ✓ |
| `assert.yml` | `assert_hibernate`, `assert_lid` | `/etc/systemd/sleep.conf`, `logind.conf` | Задеплоены ролью до assert.yml ✓ |
| `verify.yml` | `pm_verify_governor` | `/sys/.../scaling_governor` | Доп. guard: `when: pm_verify_cpufreq_available.stat.exists` ✓ |

---

## 5. Результат

### Прогон 1 — fail

```
test / power_management             FAIL  1m15s  (governor.yml crash)
test-vagrant / power_management / arch-vm    FAIL  2m46s  (governor.yml crash)
test-vagrant / power_management / ubuntu-base  FAIL  2m37s  (governor.yml crash)
```

### Прогон 2 — green (после добавления коммита 3)

```
YAML Lint & Syntax                           pass  23s
Ansible Lint                                 pass  1m55s
test / power_management (Arch+Ubuntu/systemd)  pass  2m18s
test-vagrant / power_management / arch-vm      pass  3m40s
test-vagrant / power_management / ubuntu-base  pass  2m55s
```

---

## 6. Уроки

### `is succeeded` с `failed_when: false` — паттерн сломан в Ansible 2.20

**Проблема:** `failed_when: false` меняет `result.failed` на `False` в зарегистрированной
переменной. `is succeeded` проверяет `not result.failed` → True. Если файл не существует,
slurp не добавляет `content` в dict. Ternary `X if succeeded else Y` пытается вычислить X
(в некоторых контекстах) → crash.

**Правило на будущее:** для slurp-результатов с `failed_when: false` всегда использовать
`'content' in result` вместо `result is succeeded`. Это явно, версионно-независимо и
корректно документирует намерение ("проверяем наличие данных, а не статус задачи").

### Vagrant prepare.yml — Arch требует полного bootstrap

Без `pacman -Syu` на `arch-base` боксе — базы пакетов устарели. Полный паттерн:

```
gather_facts: false
→ raw python
→ setup
→ keyring refresh (SigLevel=Never)
→ pacman -Syu
→ DNS fix (/etc/resolv.conf → 8.8.8.8)
→ platform tasks
```

Этот паттерн описан в MEMORY.md и используется в ролях `vm`, `gpu_drivers`, `power_management`.
Любая новая роль с vagrant Arch должна его применять.

### Handlers в Docker — всегда `failed_when: false`

`udevadm control --reload-rules` и `systemctl reload systemd-logind` — best-effort операции.
В Docker-контейнерах (даже privileged + systemd PID 1) `udevd` и `logind` могут не принять
команду. Конфиг-файл уже задеплоен. Хендлер — это "применить сейчас, если возможно".
`failed_when: false` обязателен для любого такого хендлера.
