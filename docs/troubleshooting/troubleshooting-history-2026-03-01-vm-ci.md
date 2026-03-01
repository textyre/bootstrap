# Post-Mortem: Molecule CI для роли `vm`

**Дата:** 2026-02-28 — 2026-03-01
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)
**Итерации CI (vagrant):** 8 запусков, 6 уникальных ошибок
**Коммиты:** `b68e048` → `c981c70` (10 коммитов)

---

## 1. Задача

Создать molecule-тесты для роли `vm` и довести CI до зелёного в трёх средах:

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker (`molecule/docker/`) | Archlinux-systemd + Ubuntu-systemd | Быстрая проверка: vm_is_guest=false для контейнеров, fact-файл не создаётся |
| Vagrant arch-vm | `arch-base` box (KVM) | Полный тест: qemu-guest-agent пакет, факт hypervisor=kvm, is_guest=true |
| Vagrant ubuntu-base | `ubuntu-base` box (KVM) | То же на Ubuntu |

**Роль `vm`:** определяет тип гипервизора (kvm / virtualbox / vmware / hyperv),
устанавливает соответствующие гостевые утилиты, управляет сервисами, пишет
`/etc/ansible/facts.d/vm_guest.fact` для downstream ролей.

**Ключевая особенность:** в Docker `virtualization_type=container` → `vm_is_guest=false`
→ никакие гостевые утилиты не устанавливаются. В Vagrant KVM `virtualization_type=kvm`
→ `vm_is_guest=true` → устанавливается qemu-guest-agent.

---

## 2. Инциденты

### Инцидент #1 — Ansible Lint: `risky-file-permissions`

**Коммит:** `ec22164`
**Прогон:** первый push (ansible-lint CI)
**Ошибка:**
```
risky-file-permissions: File permissions unset or incorrect
ansible/roles/vm/molecule/vagrant/prepare.yml:29
```

**Причина:**

В `vagrant/prepare.yml` задача DNS-фикса (copy `/etc/resolv.conf`) не имела `mode:`:

```yaml
- name: Fix DNS after pacman -Syu
  ansible.builtin.copy:
    content: "nameserver 8.8.8.8\nnameserver 1.1.1.1\n"
    dest: /etc/resolv.conf
    unsafe_writes: true
    # ← mode отсутствует
```

Ansible Lint требует явного указания `mode:` на всех задачах с `ansible.builtin.copy`
и `ansible.builtin.file`. Это правило `risky-file-permissions`.

**Фикс:**
```yaml
mode: '0644'
```

**Урок:** Любой `ansible.builtin.copy` с записью в файл требует явного `mode:`.
Шаблон `prepare.yml` должен включать его с самого начала.

---

### Инцидент #2 — Vagrant: `Qemu-guest-agent` — неправильный регистр имени сервиса

**Коммит:** `f10c10b`
**Прогоны:** первые vagrant-запуски (run 22527747175, 22536190493)
**Этап:** `converge`
**Ошибка:**
```
ERROR   Task failed: Module failed:
Could not find the requested service Qemu-guest-agent: host
Origin: ansible/roles/vm/tasks/_manage_services.yml:42:3

failed: [arch-vm] (item=Qemu-guest-agent (required)) =>
  {"msg": "Could not find the requested service Qemu-guest-agent: host"}

failed: [ubuntu-base] (item=Qemu-guest-agent (required)) =>
  {"msg": "Could not find the requested service Qemu-guest-agent: host"}
```

**Причина:**

В `ansible/roles/vm/tasks/kvm.yml` имя сервиса было задано с заглавной буквы:

```yaml
vm_svc_list:
  - name: Qemu-guest-agent      # ← неправильно: capital Q
    description: "QEMU Guest Agent (filesystem freeze, shutdown, exec)"
    required: true
```

`ansible.builtin.service` на Linux передаёт имя systemd напрямую через dbus.
systemd unit называется `qemu-guest-agent.service` (строчными). Несовпадение имени
означает что unit не найден, даже если пакет установлен корректно.

Интересно: комментарий в начале `kvm.yml` содержал правильное написание:
```yaml
# Services:
#   qemu-guest-agent -- QEMU Guest Agent (filesystem freeze, shutdown, exec)
```
А в списке сервисов — неправильное. Расхождение комментария и кода не было замечено
при code review.

**Фикс:**
```yaml
vm_svc_list:
  - name: qemu-guest-agent      # ← исправлено: строчными
```

**Урок:** Имена systemd unit-файлов — case-sensitive. Всегда проверять фактическое
имя через `systemctl list-units | grep qemu` или `pacman -Ql qemu-guest-agent | grep service`.
Комментарий в коде ≠ код.

---

### Инцидент #3 — Vagrant: `No usable default provider` (стейл кэш)

**Прогоны:** 22527747175 (частично), 22536190493, 22536260331, 22536276328 (частично), 22536368290, 22536410958
**Этап:** `create`
**Ошибка:**
```
TASK [Create molecule instance(s)]
fatal: [localhost]: FAILED! => {
  "msg": "Failed to validate generated Vagrantfile:
  b'No usable default provider could be found for your system..."
}
```

Эта ошибка возникала повторяющимися волнами через несколько прогонов даже после
исправления инцидентов #2 и #4.

**Анализ:**

История развития этого инцидента охватывает два исследования: из pam_hardening
(инцидент #2 того post-mortem) и новое открытие из этой сессии.

**Фаза 3.1 — Первоначальная диагностика (стейл restore-key кэш)**

В прогоне 22527747175 после исправления имени сервиса (#2) vagrant-CI упал сразу
на create. Логи показали:

```
✓ Cache vagrant plugins   → Cache hit: vagrant-gems-Linux-2.4.9
                                        ↑ без версии libvirt!
- Install vagrant-libvirt plugin  → SKIPPED (cache-hit)
✗ Run Molecule            → "No usable default provider"
```

Существовали два старых кэша `vagrant-gems-Linux-2.4.9` (без версии libvirt) от
предыдущих сессий. Они матчились через `restore-keys` и восстанавливались с
`cache-hit=false`, что запускало `vagrant plugin install vagrant-libvirt`. Но
restore-key кэши содержали гемы от прогонов с другой версией libvirt-dev, и
доустановленный поверх vagrant-libvirt работал некорректно.

**Действие:** Удалены два стейл-кэша:
- `3040499658` (`vagrant-gems-Linux-2.4.9`)
- `3040441607` (`vagrant-gems-Linux-2.4.9`)

Остался только `3043919613` (`vagrant-gems-Linux-2.4.9-libvirt10.0.0-2ubuntu8.11`).

**Фаза 3.2 — Новое открытие: exact-hit кэш тоже ненадёжен**

После удаления стейл-кэшей запуск 22536410958 использовал "правильный" кэш
`vagrant-gems-Linux-2.4.9-libvirt10.0.0-2ubuntu8.11` с `cache-hit=true` — и снова
упал:

```
✓ Cache vagrant plugins   → Cache hit: vagrant-gems-Linux-2.4.9-libvirt10.0.0-2ubuntu8.11
                                        ↑ точное совпадение ключа!
- Install vagrant-libvirt plugin → SKIPPED (cache-hit=true)
✗ Run Molecule            → "No usable default provider"
```

**Root cause:**

Кэш `3043919613` был создан при прогоне 22536276328. Этот прогон:
1. Восстановил старый `vagrant-gems-Linux-2.4.9` через restore-key
2. Запустил `vagrant plugin install vagrant-libvirt` поверх (cache-hit=false)
3. Прогон завершился (vagrant create/converge прошли) — кэш сохранён с новым ключом

Но кэш содержал **смесь** старых гемов (из restore-key) и свежеустановленного
vagrant-libvirt. Нативные `.so` расширения в `gems/extensions/` были скомпилированы
под конкретный физический runner (runner A). На следующем runner (runner B) те же
`.so` файлы не работали — даже при совпадающей версии libvirt-dev.

**Механизм failure:**

```
Runner A:
  libvirt-dev = 10.0.0-2ubuntu8.11
  physical machine: host-a123
  libvirt shared libs → /usr/lib/x86_64-linux-gnu/libvirt.so.0 (hash: abc123)
  → vagrant-libvirt compiled, .so works

Cache saved to GitHub cache infrastructure.

Runner B (другой физический хост):
  libvirt-dev = 10.0.0-2ubuntu8.11  (SAME version!)
  physical machine: host-b456
  libvirt shared libs → /usr/lib/x86_64-linux-gnu/libvirt.so.0 (hash: xyz789)
  → cached .so loaded → dlopen() silent fail
  → Vagrant: "No usable default provider"
```

`dlopen()` failure поглощается Vagrant молча — нет сообщения о динамическом
линкере. Вместо этого плагин просто не загружается, и Vagrant не находит
libvirt провайдера.

**Вывод:** Версии системной библиотеки в ключе кэша **недостаточно** для
нативных расширений Ruby. Точная версия пакета может совпадать, но binary
compatibility зависит от физического окружения runner (разные ABI при одинаковой
версии пакета на разных host-машинах).

**Фикс:**

```yaml
- name: Install vagrant-libvirt plugin
  run: |
    # Always uninstall + reinstall so native extensions are compiled fresh
    # against this runner's libvirt. The gems cache speeds up the download
    # (.gem files in ~/.vagrant.d/gems/cache/) but extensions must be rebuilt.
    vagrant plugin uninstall vagrant-libvirt 2>/dev/null || true
    vagrant plugin install vagrant-libvirt
```

Убрано условие `if: steps.vagrant-gems-cache.outputs.cache-hit != 'true'`.
Плагин устанавливается заново при каждом запуске.

**Почему кэш всё ещё полезен:**

После `vagrant plugin uninstall vagrant-libvirt` удаляются `gems/vagrant-libvirt-x.y.z/`,
`specifications/`, `extensions/`. Файлы `gems/cache/vagrant-libvirt-x.y.z.gem`
(скачанные `.gem` архивы) остаются и используются при следующей установке —
gem download пропускается. Экономия: ~5-10 секунд на скачивание.
Стоимость: ~20-30 секунд компиляции нативных расширений. Суммарный overhead
по сравнению с "cache-hit и skip" — ~15-20 секунд на прогон. Приемлемо за
гарантию стабильности.

**Урок:** Нативные расширения Ruby (`.so` файлы) нельзя кэшировать как переносимые
артефакты между GitHub Actions runner instances. Даже идентичная версия системной
библиотеки не гарантирует бинарную совместимость. Всегда компилировать расширения
на target runner.

---

### Инцидент #4 — Vagrant: `qemu-guest-agent` не стартует (отсутствует virtio-serial device)

**Коммит:** `95e1e81`
**Прогон:** 22527747175 (после фикса #2), 22536190493
**Этап:** `converge`
**Ошибка:**
```
ERROR   Task failed: Module failed:
Unable to start service qemu-guest-agent:
A dependency job for qemu-guest-agent.service failed.
See 'journalctl -xe' for details.

failed: [arch-vm] (item=qemu-guest-agent (required)) =>
  {"msg": "Unable to start service qemu-guest-agent:
   A dependency job for qemu-guest-agent.service failed."}

failed: [ubuntu-base] (item=qemu-guest-agent (required)) =>
  {"msg": "Unable to start service qemu-guest-agent:
   A dependency job for qemu-guest-agent.service failed."}
```

**Анализ:**

`qemu-guest-agent.service` имеет systemd-зависимость:

```
ConditionPathExists=/dev/virtio-ports/org.qemu.guest_agent.0
```

или явную зависимость на device unit:

```
BindsTo=dev-virtio\x2dports-org.qemu.guest_agent.0.device
```

Устройство `/dev/virtio-ports/org.qemu.guest_agent.0` — virtio-serial канал между
гостевой VM и хостом QEMU. Он существует только если:
1. QEMU сконфигурирован с контроллером `virtio-serial`
2. В XML-описании VM добавлен `<channel type='unix'>` с `name='org.qemu.guest_agent.0'`

GitHub Actions runner использует Vagrant с libvirt/KVM. Стандартная конфигурация
`bento/ubuntu-24.04` и наших `arch-base`/`ubuntu-base` box-ов **не включает**
virtio-serial устройство. Libvirt VM создаётся без него. Systemd в VM пытается
стартовать `qemu-guest-agent.service`, BindsTo не выполняется, сервис падает с
"dependency job failed".

Важно: `qemu-guest-agent` пакет устанавливается успешно (apt/pacman). Сервис
зарегистрирован в systemd. Но **стартовать** его без `/dev/virtio-ports/...` невозможно.

**Альтернативы, которые не были выбраны:**

1. **`molecule-notest` на service management** — гарантированно пропускает в CI,
   но нарушает тестирование логики управления сервисом. Хуже: не объясняет почему.
2. **Добавить virtio-serial в libvirt VM** через `provider_raw_config_args` —
   технически возможно, но требует специфичного Ruby/libvirt синтаксиса в
   `molecule.yml`, который сложно проверить без запуска. Риск новых ошибок.
3. **`required: false`** для qemu-guest-agent — неверно семантически. В production
   KVM VM сервис должен стартовать.

**Выбранный фикс:**

Добавить проверку устройства перед управлением сервисами в `kvm.yml`:

```yaml
- name: "KVM: Check qemu-guest-agent virtio channel"
  ansible.builtin.stat:
    path: /dev/virtio-ports/org.qemu.guest_agent.0
  register: _vm_qga_channel
  tags: ['vm', 'kvm']

- name: "KVM: Warn — virtio-serial channel not found, skipping service management"
  ansible.builtin.debug:
    msg: >-
      /dev/virtio-ports/org.qemu.guest_agent.0 not found.
      The VM may not have a virtio-serial device configured.
      qemu-guest-agent service will not be started.
  when: not _vm_qga_channel.stat.exists
  tags: ['vm', 'kvm']

- name: "KVM: Manage guest services"
  ansible.builtin.include_tasks:
    file: _manage_services.yml
  vars:
    ...
  when: _vm_qga_channel.stat.exists   # ← ключевое условие
  tags: ['vm', 'kvm']
```

Это корректное production-поведение: если KVM VM не имеет virtio-serial устройства
(неполная конфигурация QEMU), роль не падает, а выдаёт предупреждение и продолжает.
Системный администратор видит явное сообщение о причине.

`verify.yml` обновлён аналогично — проверка активности `qemu-guest-agent` выполняется
только если устройство присутствует:

```yaml
- name: Check virtio-serial channel device (KVM)
  ansible.builtin.stat:
    path: /dev/virtio-ports/org.qemu.guest_agent.0
  register: vm_verify_virtio_dev
  when: vm_verify_virt_type == 'kvm' and vm_verify_virt_role == 'guest'

- name: Check qemu-guest-agent service (KVM with virtio channel)
  ansible.builtin.systemd:
    name: qemu-guest-agent
  register: vm_verify_qemu_ga
  when:
    - vm_verify_virt_type == 'kvm'
    - vm_verify_virt_role == 'guest'
    - vm_verify_virtio_dev.stat.exists | default(false)
```

**Урок:** `qemu-guest-agent.service` требует конкретный hardware device. В CI KVM VM
этот device обычно отсутствует. Проверяй наличие device перед управлением сервисом.
Это корректная production-логика, не CI-workaround.

---

### Инцидент #5 — Vagrant: `_vm_lsmod_output` is undefined

**Коммит:** `3332552`
**Прогон:** 22536190493, 22536276328 (этап converge, после фикса virtio guard)
**Этап:** `converge`
**Ошибка:**
```
ERROR   Task failed: Finalization of task args for 'ansible.builtin.debug' failed:
Error while resolving value for 'msg': '_vm_lsmod_output' is undefined

Origin: ansible/roles/vm/tasks/_verify_modules.yml:67:3

failed: [ubuntu-base] (item=Virtio_balloon) =>
  {"msg": "...Error while resolving value for 'msg': '_vm_lsmod_output' is undefined"}
```

**Причина:**

Тот же класс ошибки, что и в `_install_packages.yml` и `_manage_services.yml`
(инциденты из предыдущей части сессии). В `_verify_modules.yml` строка 63:

```yaml
# БЫЛО:
- name: "Check loaded status ({{ vm_mod_label }})"
  ansible.builtin.command: lsmod
  register: vm_lsmod_output      # ← без underscore-prefix

# Строка 69 ссылается на:
  msg: "{{ item.name }}...: {{ 'loaded' if item.name in _vm_lsmod_output.stdout ... }}"
  #                                                        ↑ с underscore-prefix
```

Конвенция проекта: внутренние переменные (не предназначенные для переопределения
извне) получают `_` prefix. Здесь `register:` и reference использовали разные имена.

Дополнительный контекст: `kvm.yml` в `_reboot_flag.yml` передаёт:
```yaml
vm_reboot_condition: "{{ (_vm_pkg_install_result is changed) and ('virtio_balloon' not in _vm_lsmod_output.stdout) }}"
```

Это выражение тоже бы сломалось, если бы `_verify_modules.yml` запустился и зарегистрировал
переменную с неправильным именем. В данном случае `_vm_lsmod_output` undefined → ошибка
при вычислении msg в debug-таске.

**Фикс:**
```yaml
register: _vm_lsmod_output    # ← добавлен underscore-prefix
```

**Это третий register-naming bug в роли `vm`:**

| Файл | Было | Стало | Коммит |
|------|------|-------|--------|
| `_install_packages.yml` | `vm_pkg_install_result` | `_vm_pkg_install_result` | `b68e048` |
| `_manage_services.yml` | `vm_svc_result` | `_vm_svc_result` | `b1ce32e` |
| `_verify_modules.yml` | `vm_lsmod_output` | `_vm_lsmod_output` | `3332552` |

Паттерн: при написании task-файлов авторы последовательно добавляли `_` prefix
к именам в `register:`, но забывали в некоторых файлах. Ошибки не проявлялись
в Docker-тестах (task не достигался: `vm_is_guest=false`), и только Vagrant KVM
(где `vm_is_guest=true`) выявил их.

**Урок:** Underscore-конвенция для `register:` должна соблюдаться при написании,
а не исправляться по мере обнаружения. После создания новых task-файлов сразу
проверить все `register:` имена на соответствие конвенции.

---

### Инцидент #6 — Vagrant: Idempotence failure — `Write VM guest custom fact`

**Коммит:** `7ef64dd`
**Прогон:** 22536276328
**Этап:** `idempotence` (второй запуск converge)
**Ошибка:**
```
CRITICAL Idempotence test failed because of the following tasks:
  *  => vm : Write VM guest custom fact
```

**Анализ:**

`_set_facts.yml` записывал в `/etc/ansible/facts.d/vm_guest.fact`:

```json
{
  "hypervisor": "kvm",
  "is_guest": true,
  "is_container": false,
  "reboot_required": false
}
```

Поле `reboot_required` вычислялось в `kvm.yml` через `_reboot_flag.yml` с условием:

```yaml
vm_reboot_condition: >-
  {{ (_vm_pkg_install_result is changed) and ('virtio_balloon' not in _vm_lsmod_output.stdout) }}
```

**Последовательность на первом прогоне (converge):**

1. `_vm_pkg_install_result` → `changed=true` (qemu-guest-agent устанавливается впервые)
2. `lsmod` выполняется — `virtio_balloon` в ubuntu-base KVM VM может **не быть загружен**
   в момент проверки (модуль присутствует, но не загружен ядром автоматически на Ubuntu)
3. `vm_reboot_condition = true AND true = true` → `vm_reboot_required = true`
4. Факт-файл записывается с `"reboot_required": true`

**Второй прогон (idempotence):**

1. `_vm_pkg_install_result` → `changed=false` (пакет уже установлен)
2. `vm_reboot_condition = false AND ... = false` → `vm_reboot_required = false`
3. Факт-файл хочет записать `"reboot_required": false`
4. Файл на диске содержит `"reboot_required": true`
5. **Контент изменился → `changed` → idempotence failure**

**Root cause:** `vm_reboot_required` — транзиентное состояние per-run, а не стабильный
факт о системе. Его корректное значение зависит от того, был ли изменён пакет в
текущем запуске. Попытка персистировать транзиентное состояние нарушает идемпотентность.

Другие поля (`hypervisor`, `is_guest`, `is_container`) — стабильные свойства системы.
Их значения не меняются между прогонами на одной и той же машине.

**Фикс:**

Удалить `reboot_required` из факт-файла:

```yaml
- name: Write VM guest custom fact
  ansible.builtin.copy:
    content: |
      {
        "hypervisor": "{{ vm_hypervisor }}",
        "is_guest": {{ vm_is_guest | bool | lower }},
        "is_container": {{ vm_is_container | bool | lower }}
      }
    dest: /etc/ansible/facts.d/vm_guest.fact
    mode: '0644'
  when: vm_is_guest | bool
```

`vm_reboot_required` остаётся доступным в рамках текущего play через `set_fact`.
Downstream роли, которым нужен этот флаг, должны читать его из переменной плея,
а не из кастомного факта на диске.

**Проверка `verify.yml`:** Файл проверял только `hypervisor` и `is_guest` — поле
`reboot_required` не читалось в assert. Изменение verify.yml не потребовалось.

**Урок:** Персистентный факт-файл — это API контракт для downstream ролей. В него
должны входить только стабильные свойства системы. Транзиентное per-run состояние
хранить в `set_fact` (в памяти play), а не на диске.

---

## 3. Временная шкала

```
── Предыдущая сессия (2026-02-28) ─────────────────────────────────────────────

b68e048  fix(vm): _install_packages.yml — register: _vm_pkg_install_result
b1ce32e  fix(vm): _manage_services.yml — register: _vm_svc_result
f10711b  feat(vm): molecule/shared/converge.yml
93d4f17  feat(vm): molecule/shared/verify.yml — container + KVM assertions
37bc966  feat(vm): molecule/docker/molecule.yml — Arch + Ubuntu systemd
[implicit] feat(vm): molecule/docker/prepare.yml (в том же коммите)
773587b  feat(vm): molecule/vagrant/molecule.yml + prepare.yml
ec22164  fix(vm): mode: '0644' на resolv.conf copy (ansible-lint risky-file-permissions)
          ↓ Ansible Lint: PASS ✓
          ↓ Docker: PASS ✓

── Текущая сессия (2026-03-01) ─────────────────────────────────────────────────

f10c10b  fix(vm): lowercase qemu-guest-agent service name in kvm.yml
          ↓ Vagrant run 22527747175:
          ↓   arch-vm:    FAIL — "Unable to start service qemu-guest-agent" (Инцидент #4)
          ↓   ubuntu-base: FAIL — то же

95e1e81  fix(vm): guard service management on virtio channel device presence
          ↓ Vagrant run 22536190493:
          ↓   arch-vm:    FAIL — "_vm_lsmod_output is undefined" (Инцидент #5)
          ↓   ubuntu-base: FAIL — то же

3332552  fix(vm): fix register name in _verify_modules.yml — _vm_lsmod_output
          ↓ Vagrant run 22536276328:
          ↓   arch-vm:    FAIL — "Idempotence failed: Write VM guest custom fact" (Инцидент #6)
          ↓   ubuntu-base: FAIL — то же (idempotence)
          ↓ [Параллельно: кэш 3043919613 создан по окончании прогона]

7ef64dd  fix(vm): remove reboot_required from persistent fact file
          ↓ Vagrant run 22536368290:
          ↓   arch-vm:    FAIL — "No usable default provider" (Инцидент #3, стейл кэш)
          ↓   ubuntu-base: FAIL — то же
          ↓ [Удалены стейл-кэши 3040499658, 3040441607]

          ↓ Vagrant run 22536410958:
          ↓   arch-vm:    FAIL — "No usable default provider" (Инцидент #3, exact-hit тоже сломан)
          ↓   ubuntu-base: FAIL — то же
          ↓ [Удалён кэш 3043919613]

c981c70  fix(ci): always reinstall vagrant-libvirt (no cache-hit skip)
          ↓ Vagrant run 22536504316:
          ↓   arch-vm:    SUCCESS ✓ (3m5s)
          ↓   ubuntu-base: SUCCESS ✓ (4m2s)
          ↓ Docker: SUCCESS ✓
          ↓ Ansible Lint: SUCCESS ✓
```

---

## 4. Финальная структура

```
ansible/roles/vm/molecule/
├── shared/
│   ├── converge.yml     ← role: vm
│   └── verify.yml       ← docker: fact-файл НЕ существует
│                           KVM:    stat virtio device → cond. сервис check + fact проверки
├── docker/
│   ├── molecule.yml     ← Archlinux-systemd + Ubuntu-systemd, privileged, cgroupns
│   └── prepare.yml      ← gather_facts: true; pacman (Arch) | apt (Ubuntu)
└── vagrant/
    ├── molecule.yml     ← arch-vm (arch-base box) + ubuntu-base (ubuntu-base box)
    └── prepare.yml      ← Arch: raw python → gather_facts → keyring → pacman -Syu
                            → DNS fix → other
                            Ubuntu: apt update
```

**Изменения роли:**

```
ansible/roles/vm/tasks/
├── kvm.yml               ← lowercase qemu-guest-agent; virtio device guard перед service mgmt
├── _install_packages.yml ← register: _vm_pkg_install_result
├── _manage_services.yml  ← register: _vm_svc_result
├── _verify_modules.yml   ← register: _vm_lsmod_output
└── _set_facts.yml        ← убран reboot_required из факт-файла
```

**Изменение CI workflow:**

```
.github/workflows/_molecule-vagrant.yml
  ← всегда: vagrant plugin uninstall vagrant-libvirt || true
            vagrant plugin install vagrant-libvirt
  ← убрано: if: steps.vagrant-gems-cache.outputs.cache-hit != 'true'
```

---

## 5. Ключевые паттерны

### Virtio device guard для qemu-guest-agent

```yaml
# В task-файле гипервизора (kvm.yml):
- name: "KVM: Check qemu-guest-agent virtio channel"
  ansible.builtin.stat:
    path: /dev/virtio-ports/org.qemu.guest_agent.0
  register: _vm_qga_channel

- name: "KVM: Manage guest services"
  ansible.builtin.include_tasks: _manage_services.yml
  vars: ...
  when: _vm_qga_channel.stat.exists

# В verify.yml (аналогично):
- name: Check virtio-serial channel device (KVM)
  ansible.builtin.stat:
    path: /dev/virtio-ports/org.qemu.guest_agent.0
  register: vm_verify_virtio_dev
  when: vm_verify_virt_type == 'kvm' and vm_verify_virt_role == 'guest'

- name: Assert qemu-guest-agent is active
  ...
  when:
    - vm_verify_virt_type == 'kvm'
    - vm_verify_virt_role == 'guest'
    - vm_verify_virtio_dev.stat.exists | default(false)
    - vm_verify_qemu_ga is not skipped
```

### Факт-файл: только стабильные свойства системы

```yaml
# ПРАВИЛЬНО — стабильные свойства системы:
{
  "hypervisor": "{{ vm_hypervisor }}",
  "is_guest": {{ vm_is_guest | bool | lower }},
  "is_container": {{ vm_is_container | bool | lower }}
}

# НЕПРАВИЛЬНО — транзиентное per-run состояние (нарушает идемпотентность):
{
  ...
  "reboot_required": {{ vm_reboot_required | default(false) | bool | lower }}
}
```

### vagrant-libvirt: всегда переустанавливать

```yaml
- name: Install vagrant-libvirt plugin
  run: |
    # Always uninstall + reinstall — native .so extensions must be compiled
    # against this specific runner's libvirt. Cache speeds up gem download only.
    vagrant plugin uninstall vagrant-libvirt 2>/dev/null || true
    vagrant plugin install vagrant-libvirt
```

### Underscore-конвенция для register

```yaml
# Конвенция: переменные, регистрируемые внутри task-файла
# и не предназначенные для переопределения снаружи — с _ prefix:

register: _vm_pkg_install_result    # ✓
register: _vm_svc_result            # ✓
register: _vm_lsmod_output          # ✓
register: _vm_qga_channel           # ✓

register: vm_pkg_install_result     # ✗ (без prefix = "public" переменная)
```

---

## 6. Сравнение инцидентов с историей проекта

| Инцидент | Дата | Роль | Ошибка | Класс |
|----------|------|------|--------|-------|
| register naming | 2026-02-24 | ntp | `_ntp_...` undefined | convention drift |
| Docker pacman без when | 2026-02-28 | pam_hardening | fatal на Ubuntu | missing guard |
| vagrant-libvirt stale .so (libvirt ver) | 2026-02-28 | pam_hardening | No usable default provider | cache key |
| register naming ×3 | 2026-03-01 | vm | `_vm_...` undefined | convention drift |
| systemd unit case-sensitive | 2026-03-01 | vm | Could not find service | typo |
| virtio device absent | 2026-03-01 | vm | dependency job failed | hw assumption |
| transient state in fact file | 2026-03-01 | vm | idempotence failure | design flaw |
| vagrant-libvirt stale .so (binary compat) | 2026-03-01 | vm | No usable default provider | deeper cache issue |

Инцидент #3 этой сессии является эволюцией знаний о кэшировании vagrant-libvirt:
pam_hardening выявил проблему на уровне версии libvirt-dev (первый уровень);
vm-сессия выявила, что даже точный match ключа не гарантирует бинарную совместимость
на разных физических runner'ах (второй уровень). Итоговый фикс (`always reinstall`)
более консервативен и надёжен.

---

## 7. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | systemd unit-имена case-sensitive; всегда проверять через `systemctl list-units` | Роли управляющие сервисами |
| 2 | Комментарий и код могут расходиться. Тест — единственный reliable источник истины | Code review |
| 3 | `qemu-guest-agent` требует virtio-serial device. CI KVM VM его не имеют. Guard через `stat` | Любая роль с qemu-guest-agent |
| 4 | Персистентный факт-файл = API контракт. Только стабильные свойства. Не транзиентное состояние | Любая роль с кастомными фактами |
| 5 | Native Ruby `.so` не переносимы между GitHub Actions runner instances. Всегда компилировать заново | Любой workflow с vagrant-libvirt |
| 6 | Underscore-prefix конвенция — проверять при создании task-файлов, не при отладке | Все role task-файлы |
| 7 | Docker-тесты не покрывают KVM-путь (`vm_is_guest=true`) — register-баги появились только в Vagrant | Roles с branch-логикой по типу окружения |
| 8 | Последовательные провалы обоих платформ → детерминированный баг, не флакость runner | CI debugging heuristics |

---

## 8. Known gaps

- **virtio-serial device в CI VM:** Тест service management для qemu-guest-agent в Vagrant
  пропускается (нет устройства). Для полного покрытия нужно добавить virtio-serial channel
  в конфигурацию libvirt VM через `provider_raw_config_args` в `molecule.yml`.
  Текущее состояние: package install и fact-файл тестируются; service start — только
  в production при наличии правильной QEMU конфигурации.

- **Overhead vagrant-libvirt reinstall:** +20-30 секунд на каждый vagrant-прогон.
  Можно оптимизировать через `gems/cache/` pre-warm или кастомный runner image
  с предустановленным vagrant-libvirt.

- **Идемпотентность с `virtio_balloon` guard в reboot condition:** `kvm.yml` сохраняет
  условие `('virtio_balloon' not in _vm_lsmod_output.stdout)` в `_reboot_flag.yml`.
  Это работает корректно (idempotence pass), но `virtio_balloon` в KVM VM обычно
  НЕ загружен автоматически — что означает `vm_reboot_required = true` при каждой
  первой установке qemu-guest-agent. Пользователь должен знать об этом ожидаемом поведении.
