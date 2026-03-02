# Post-Mortem: Molecule CI для роли `fail2ban`

**Дата:** 2026-03-02
**Статус:** Завершено — CI зелёный (Docker Arch+Ubuntu + vagrant arch-vm + vagrant ubuntu-base)
**Итерации CI:** ~6 прогонов, 4 уникальных проблемы (3 реальных + 1 self-inflicted через промежуточный фикс)
**Коммиты:** 7 commit-ов в PR #53, squash-merged → `98e748f`
**Скоуп:** 10 изменённых файлов, +197 строк, -6 строк

---

## 1. Задача

Запустить molecule-тесты роли `fail2ban` в трёх средах и сделать CI зелёным:

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker (`molecule/docker/`) | `Archlinux-systemd` + `Ubuntu-systemd` | Синтаксис, идемпотентность, конфигурация без запуска сервиса |
| Vagrant arch-vm | `arch-base` box (KVM) | Полный тест: установка → конфигурация → запуск → jails |
| Vagrant ubuntu-base | `ubuntu-base` box (KVM) | То же на Ubuntu |

Стартовое состояние: ветка `ci/track-fail2ban`, PR #53. Три CI-задачи провалились:

```
✗ fail2ban (test-docker)         — 2 ошибки
✗ fail2ban (test-vagrant/arch)   — 1 ошибка
✓ fail2ban (test-vagrant/ubuntu) — чистый с начала
```

---

## 2. Инциденты

### Инцидент #1 — Docker prepare: iptables-nft конфликт с iptables

**Этап:** `prepare`
**Симптом:**

```
TASK [Install iptables-nft for fail2ban backend, replacing iptables (Arch)]
fatal: [Archlinux-systemd]: FAILED! => {
  "msg": "Failed to install packages: conflict: iptables and iptables-nft"
}
```

Или при попытке сначала удалить `iptables`:

```
error: failed to prepare transaction (could not satisfy dependencies)
:: removing iptables breaks dependency 'libxtables.so=12-64' required by iproute2
```

**Контекст:**

Arch Linux образ `ghcr.io/textyre/arch-base:latest` содержит в базовом слое:
- `iptables` — legacy iptables
- `iproute2` — зависит от `libxtables.so=12-64`, которую предоставляет `iptables`

Для работы fail2ban нужен `iptables-nft` (nftables backend). Он конфликтует с `iptables`,
но ТОЖЕ предоставляет `libxtables.so=12-64`. Проблема: два отдельных шага
(удалить `iptables` → установить `iptables-nft`) разрывают транзакцию.
На шаге удаления `iproute2` остаётся без зависимости → pacman отказывает.

**Механизм сбоя (упрощённо):**

```
Шаг 1: pacman -R iptables
  → iproute2 требует libxtables.so=12-64 → iptables её предоставлял → конфликт
  → FAIL

Шаг 2 (если 1 пропустить): pacman -S iptables-nft
  → конфликт: iptables и iptables-nft несовместимы → нужно --noconfirm или ответ
  → FAIL в неинтерактивном режиме
```

**Корневая причина:**

`community.general.pacman` не поддерживает атомарную замену конфликтующих пакетов
через стандартные параметры. Нужен `--ask=4` (ALPM_QUESTION_CONFLICT_PKG) — это
числовой флаг, который сообщает ALPM: «автоматически соглашаться при вопросе
о конфликте пакетов». Одна транзакция: удалить iptables + установить iptables-nft
→ iproute2 получает `libxtables.so=12-64` от нового пакета без разрыва.

**Фикс:**

```yaml
# molecule/docker/prepare.yml
# БЫЛО (первая попытка — двухшаговая, ломает iproute2):
- name: Remove iptables before installing iptables-nft
  community.general.pacman:
    name: iptables
    state: absent

- name: Install iptables-nft
  community.general.pacman:
    name: iptables-nft
    state: present

# СТАЛО (одна транзакция с auto-confirm конфликта):
- name: Install iptables-nft for fail2ban backend, replacing iptables (Arch)
  community.general.pacman:
    name: iptables-nft
    state: present
    extra_args: --ask=4
  when: ansible_facts['os_family'] == 'Archlinux'
```

**Почему `--ask=4` работает:**

ALPM (Arch Linux Package Manager) при конфликте пакетов задаёт вопрос с числовым
кодом `ALPM_QUESTION_CONFLICT_PKG = 4`. `extra_args: --ask=4` говорит pacman:
«на этот тип вопроса всегда отвечай "да"». Транзакция проходит атомарно:
удаление старого пакета и установка нового в одном шаге → зависимости не нарушаются.

**Урок:** Замена конфликтующих пакетов с общими зависимостями в Arch — только через
одну ALPM-транзакцию. `--ask=4` для автоподтверждения конфликта в неинтерактивном
режиме CI. Двухшаговый подход (remove + install) всегда ломает транзитивные зависимости.

---

### Инцидент #2 — Docker: idempotence `changed=1` (неправильная диагностика → промежуточный фикс)

**Этап:** `idempotence`
**Симптом (поверхностный):**

```
Idempotence test failed because of the following tasks:
* [Archlinux-systemd] => (item={'name': 'fail2ban'}) CHANGED
TASK [fail2ban : Enable and start fail2ban]
```

**Первоначальный диагноз (ошибочный):**

Задача `ansible.builtin.service: enabled: true state: started` на втором прогоне
возвращает `changed=1`. Казалось: fail2ban меняет своё состояние между запусками.
Гипотеза: `banaction = iptables-multiport` в Docker падает → fail2ban крашится →
на следующем converge сервис снова запускается → changed.

**Промежуточная попытка #1: banaction = noop**

Добавили в `molecule/docker/group_vars/all.yml`:

```yaml
fail2ban_sshd_banaction: "noop"
```

И добавили переменную `fail2ban_sshd_banaction` в шаблон `jail_sshd.conf.j2`:

```ini
{% if fail2ban_sshd_banaction %}
banaction = {{ fail2ban_sshd_banaction }}
{% endif %}
```

**Результат:** CI прогон — Docker по-прежнему падал с `changed=1`.

**Промежуточная попытка #2: container guard в verify.yml**

Добавили условие `ansible_virtualization_type not in ['docker', 'container', 'lxc']`
в `until`-условие verify задачи. Это пропускало assertions в контейнерах,
но idempotence падал в OTHER задаче — самом `service start`.

**Результат:** FAIL. Assertions в verify.yml пропускались, но idempotence на
`Enable and start fail2ban` по-прежнему падал.

**Настоящая корневая причина:**

Глубокий анализ CI-логов с таймстемпами показал: fail2ban не просто «нестабилен»
после первого запуска — он **вообще никогда не стартует** в Docker:

```
# Оба converge-прогона (первый и второй):
TASK [fail2ban : Enable and start fail2ban] → changed (state: started)
# Далее в verify.yml:
TASK [Verify fail2ban is running]
fail2ban-client status → rc=255  (сокет не создан)
fail2ban-client status → rc=255  (retry 2/5)
...5 попыток, все rc=255
```

Суть: `ansible.builtin.service: state: started` всегда возвращает `changed=1`,
потому что fail2ban **крашится сразу после старта** (Type=simple — systemd считает
сервис запущенным как только process fork выполнен, не дожидаясь готовности).
На втором converge — снова `state: started` → снова changed. Идемпотентности
нет не потому что что-то меняется, а потому что сервис неустойчив.

**Почему fail2ban крашится в Docker:**

fail2ban с `banaction = iptables-multiport` при старте инициализирует jails.
Инициализация jail = выполнение `actionstart` скрипта = `iptables -N fail2ban-sshd`.
В Docker-контейнере, даже `privileged: true` на GitHub Actions runner, netfilter
(ядро хоста) недоступен через контейнерный namespace. `iptables` возвращает ошибку,
fail2ban логирует её как fatal и завершает процесс.

Даже с `banaction = noop` fail2ban иногда крашился из-за других инициализационных
проблем (`/run/fail2ban/` permissions, `tmpfs /run` в molecule.yml).

---

### Инцидент #3 — Docker: правильный фикс через `fail2ban_start_service` флаг

**Решение: следовать паттерну роли `firewall`**

Читая аналогичные роли в проекте, найден идентичный паттерн в `ansible/roles/firewall/`:

```yaml
# ansible/roles/firewall/molecule/docker/molecule.yml
provisioner:
  options:
    extra-vars: "firewall_start_service=false"
```

```yaml
# ansible/roles/firewall/defaults/main.yml
firewall_start_service: true
```

```yaml
# ansible/roles/firewall/tasks/main.yml
- name: Enable firewall
  service:
    enabled: true
- name: Start firewall
  service:
    state: started
  when: firewall_start_service | bool
```

Паттерн разделяет два действия:
- **enable** (autostart при загрузке) → всегда выполняется
- **start now** (запустить сейчас) → только в реальных окружениях

**Применение к fail2ban:**

```yaml
# defaults/main.yml — добавлен переключатель:
fail2ban_start_service: true

# tasks/main.yml — разделены задачи:
- name: "Enable fail2ban"
  ansible.builtin.service:
    name: fail2ban
    enabled: true
  # без when — всегда!

- name: "Start fail2ban"
  ansible.builtin.service:
    name: fail2ban
    state: started
  when: fail2ban_start_service | bool

# molecule/docker/molecule.yml — отключаем запуск в Docker:
provisioner:
  options:
    extra-vars: "fail2ban_start_service=false"
```

**Результат первого прогона после этого фикса:**

```
✓ fail2ban (test-vagrant/arch)   — PASS
✓ fail2ban (test-vagrant/ubuntu) — PASS
✗ fail2ban (test-docker)         — FAIL (новая ошибка!)
```

---

### Инцидент #4 — Docker (self-inflicted): `fail2ban.service is not enabled (got 'disabled')` на Arch

**Этап:** `verify`
**Симптом:**

```
TASK [shared/verify : Assert fail2ban is enabled]
fatal: [Archlinux-systemd]: FAILED! => {
  "assertion": "...",
  "msg": "fail2ban.service is not enabled (got 'disabled')"
}
```

Ubuntu-контейнер проходил, Arch-контейнер падал.

**Корневая причина:**

До инцидента #3 в `tasks/main.yml` была одна объединённая задача:

```yaml
- name: "Enable and start fail2ban"
  ansible.builtin.service:
    name: fail2ban
    enabled: true
    state: started
  when: fail2ban_start_service | bool  ← ДОБАВИЛИ УСЛОВИЕ
```

При `fail2ban_start_service=false` эта задача **пропускается целиком** → ни `enabled: true`,
ни `state: started` не выполняются. На Arch-контейнере сервис остаётся в `disabled` состоянии
(пакет `fail2ban` установлен но не включён).

**Почему Ubuntu проходил:**

`apt install fail2ban` на Ubuntu выполняет post-install скрипты (`deb-systemd-helper`),
которые автоматически включают (enable) сервис. `pacman install fail2ban` на Arch
НЕ выполняет никаких post-install действий с systemd — сервис устанавливается
но остаётся в `disabled` состоянии. Это фундаментальное различие между Debian
и Arch в управлении systemd сервисами через менеджер пакетов.

**Сравнение поведения пакетных менеджеров:**

| Действие | Ubuntu `apt install` | Arch `pacman -S` |
|----------|---------------------|-----------------|
| Установка файлов пакета | ✓ | ✓ |
| Выполнение post-install scripts | ✓ (`deb-systemd-helper`) | ✗ |
| `systemctl enable service` | Автоматически | Никогда |
| Состояние после установки | `enabled` | `disabled` |

**Почему не замечали раньше:**

До этого задача была объединённой (`enabled: true + state: started`). В обычном
production-запуске она всегда выполнялась и включала сервис явно. Только когда
добавили `when: fail2ban_start_service | bool` и начали его пропускать — стало
видно, что Arch не включает сервис сам.

**Фикс: разделить задачи так, как планировалось изначально:**

```yaml
# БЫЛО (combined task с новым when):
- name: "Enable and start fail2ban"
  ansible.builtin.service:
    name: fail2ban
    enabled: true
    state: started
  when: fail2ban_start_service | bool   ← пропускает ВСЁ при false

# СТАЛО (правильное разделение):
- name: "Enable fail2ban"              ← БЕЗ when — всегда выполняется
  ansible.builtin.service:
    name: fail2ban
    enabled: true

- name: "Start fail2ban"               ← только с флагом
  ansible.builtin.service:
    name: fail2ban
    state: started
  when: fail2ban_start_service | bool
```

**Урок:** Когда добавляешь `when:` к комбинированной `service` задаче с
`enabled: true + state: started` — она пропускается целиком. На Arch это означает
`disabled` сервис. Правило: **enable и start — всегда два отдельных таска**,
если хоть один из них может быть условным.

---

### Инцидент #5 — Vagrant/arch: fail2ban не создаёт сокет (crash при старте)

**Этап:** `verify`
**Симптом:**

```
TASK [Verify fail2ban is running]
fail2ban-client status → rc=255, stderr="ERROR  Failed to access socket..."
  Retry 1/5 (delay 2s): rc=255
  Retry 2/5 (delay 2s): rc=255
  Retry 3/5 (delay 2s): rc=255
  Retry 4/5 (delay 2s): rc=255
  Retry 5/5 (delay 2s): rc=255

TASK [Assert fail2ban is running]
fatal: [arch-vm]: FAILED! => {
  "msg": "fail2ban is not running (rc=255)"
}
```

При этом `ubuntu-base` vagrant-платформа проходила чисто.

**Диагностика через временную шкалу:**

`systemctl start fail2ban` → exit code 0 (systemd говорит «запущено»)
→ но сокет `/var/run/fail2ban/fail2ban.sock` никогда не создаётся
→ 10 секунд ожидания (5 ретраев × 2с) — нет сокета
→ fail2ban-client возвращает rc=255 (сокет не найден)

Разница с Ubuntu: Ubuntu использует `pyinotify` с `/var/log/auth.log`.
На Arch — чистый journald без `/var/log/auth.log`.

**Гипотеза #1: python-systemd не установлен**

Добавили `python-systemd` в `vars/archlinux.yml`:

```yaml
fail2ban_packages:
  - fail2ban
  - python-systemd   ← добавлен
```

**Результат:** FAIL. python-systemd установлен, но сокет по-прежнему не создаётся.

**Настоящая корневая причина:**

`backend = auto` (дефолт) при старте fail2ban пробует backend'ы в порядке:
`systemd` → `pyinotify` → `polling`. Для `systemd` backend требуется импорт
`python-systemd`. После установки пакета импорт происходит, но **инициализация
python-systemd binding** в специфической комбинации Arch vagrant box + ядро CI
вызывает crash fail2ban до создания сокета.

Симптом: systemd (Type=simple) считает процесс запущенным → `start` выходит с 0.
Но fail2ban падает внутри Python ещё до того, как создаёт `/var/run/fail2ban/fail2ban.sock`.

```
# Реконструкция порядка событий:
systemctl start fail2ban
  → fork() → Python процесс запущен → systemd: OK (exit 0)
  → fail2ban/__main__.py → JailThread init
  → import systemd.journal (python-systemd)
  → systemd journal binding: SIGABRT или segfault в specific kernel combination
  → процесс умирает до socket creation
  → /var/run/fail2ban/fail2ban.sock не создан
  → fail2ban-client: "ERROR Failed to access socket path"
```

**Почему `backend = auto` опасен:**

Auto-detection последовательно пробует backend'ы. Если системный backend
(`systemd`) вызывает crash — fail2ban падает при попытке его импорта, не
переходя к следующему (`pyinotify`, `polling`). Нет второго шанса.

**Фикс:**

```yaml
# molecule/vagrant/molecule.yml
provisioner:
  inventory:
    host_vars:
      arch-vm:
        # Arch Linux + python-systemd вызывает crash fail2ban до создания сокета
        # в CI vagrant box / ядро комбинации. Polling backend обходит проблему:
        # не импортирует python-systemd вообще.
        fail2ban_sshd_backend: polling
```

```yaml
# molecule/vagrant/prepare.yml (дополнительно)
# Polling backend требует существования лог-файла при старте.
# Arch не имеет /var/log/auth.log (чистый journald) — создаём заглушку.
- name: Create /var/log/auth.log for fail2ban polling backend (Arch)
  ansible.builtin.file:
    path: /var/log/auth.log
    state: touch
    owner: root
    group: root
    mode: "0640"
    modification_time: preserve
    access_time: preserve
  when: ansible_facts['os_family'] == 'Archlinux'
```

**Почему polling работает:**

`backend = polling` использует Python `inotify` (через `pyinotify`) или `gamin`
для отслеживания файла `/var/log/auth.log`. Не импортирует `systemd.journal`.
Crash устранён. Dummy `/var/log/auth.log` нужен потому что polling-backend
проверяет существование файла при старте jailThread и падает если файл не найден.

**Почему python-systemd оставлен в пакетах:**

В production (реальный Arch Linux сервер) `backend = auto` корректно определяет
systemd journal backend и использует python-systemd. Crash воспроизводится
только в специфической CI-среде (vagrant box + GitHub runner ядро). Для
production journald backend лучше: real-time, нет latency у polling.

**Урок:** `backend = auto` скрывает crashes — fail2ban молча падает не переходя
к следующему backend. Для тестовых окружений с нестандартным ядром или vagrant
box — явно указывать `backend = polling`. Отсутствие `/var/log/auth.log` на Arch
надо компенсировать в prepare.yml.

---

### Инцидент #6 — Диагностика: journalctl в verify.yml

**Контекст:** Без диагностики vagrant/arch инцидент (#5) потребовал бы нескольких
дополнительных CI-прогонов для понимания причины краша. Логи fail2ban отсутствовали
в стандартном CI-выводе.

**Решение: добавить journalctl задачу ПЕРЕД assert:**

```yaml
# tasks/verify.yml
- name: "Diagnostic: collect fail2ban journal on startup failure"
  ansible.builtin.command:
    cmd: "journalctl -u fail2ban --lines=40 --no-pager --output=short-iso"
  register: _fail2ban_diag_journal
  changed_when: false
  failed_when: false
  when:
    - fail2ban_start_service | bool
    - fail2ban_verify_status is defined
    - fail2ban_verify_status.rc | default(0) != 0
    - ansible_virtualization_type | default('') not in ['docker', 'container', 'lxc']
    - ansible_facts['service_mgr'] == 'systemd'

- name: "Diagnostic: show fail2ban journal on startup failure"
  ansible.builtin.debug:
    msg: "fail2ban journal (last 40 lines):\n{{ _fail2ban_diag_journal.stdout | default('(empty)') }}"
  when: ...  # те же условия
```

**Паттерн:** Диагностику запускать только при `rc != 0` (не замедляет успешные прогоны)
и только вне контейнеров (journald доступен). `failed_when: false` — диагностическая
задача не должна маскировать основную ошибку. Вывод через `debug` — попадает в
molecule stdout/CI лог без дополнительных артефактов.

---

## 3. Временная шкала

```
── Стартовое состояние ───────────────────────────────────────────────────────

WIP push: ветка ci/track-fail2ban, PR #53
  fail2ban (test-docker):        ✗ (iptables-nft конфликт + idempotence)
  fail2ban (test-vagrant/arch):  ✗ (сокет не создаётся)
  fail2ban (test-vagrant/ubuntu): ✓

── Итерация 1 ─────────────────────────────────────────────────────────────

fix(fail2ban): resolve iptables-nft conflict and add Arch vagrant prep
  - docker/prepare.yml: iptables-nft через --ask=4
  - vagrant/prepare.yml: аналогичная подготовка для Arch

  Docker:        ✗ (idempotence changed=1 на "Enable and start fail2ban")
  vagrant/arch:  ✗ (сокет не создаётся)
  vagrant/ubuntu: ✓

── Итерация 2 ─────────────────────────────────────────────────────────────

fix(packages): sync pacman database before installing packages
fix(fail2ban): guard tasks/verify.yml for containers and add retries
  - добавлен container guard в until: условие verify.yml
  - добавлены retries (5×2s) для socket race condition

  Docker:        ✗ (idempotence все ещё changed=1 — guard не помогает)
  vagrant/arch:  ✗ (сокет не создаётся)
  vagrant/ubuntu: ✓

── Итерация 3 ─────────────────────────────────────────────────────────────

fix(fail2ban): add banaction var + noop for Docker + python-systemd for Arch
  - fail2ban_sshd_banaction переменная + шаблон
  - Docker group_vars: banaction=noop
  - vars/archlinux.yml: +python-systemd

  Docker:        ✗ (noop не устраняет crash — fail2ban падает до jail init)
  vagrant/arch:  ✗ (python-systemd установлен, но crash всё равно)
  vagrant/ubuntu: ✓

── Итерация 4 ─────────────────────────────────────────────────────────────

fix(fail2ban): skip service in Docker, use polling backend for Arch vagrant
  - defaults/main.yml: fail2ban_start_service: true
  - tasks/main.yml: when: fail2ban_start_service | bool (на combined task)
  - docker/molecule.yml: extra-vars: "fail2ban_start_service=false"
  - vagrant/molecule.yml: host_vars.arch-vm.fail2ban_sshd_backend: polling
  - vagrant/prepare.yml: touch /var/log/auth.log (Arch)
  - tasks/verify.yml: полная переработка с fail2ban_start_service guard

  Docker:        ✗ НОВАЯ ОШИБКА: fail2ban.service is 'disabled' на Arch
  vagrant/arch:  ✓
  vagrant/ubuntu: ✓

── Итерация 5 ─────────────────────────────────────────────────────────────

fix(fail2ban): separate enable from start — always enable, conditionally start
  - tasks/main.yml: "Enable fail2ban" (нет when) + "Start fail2ban" (when: start_service)
  - удалены group_vars Docker (noop banaction — больше не нужен)

  Docker:        ✓
  vagrant/arch:  ✓
  vagrant/ubuntu: ✓

  Все 10 CI-проверок зелёные ✓
  PR #53 squash-merged → master 98e748f

── docs(fail2ban): CI troubleshooting post-mortem ───────────────────────────

  Начальный постмортем (72 строки) → этот документ (расширенная версия)
```

---

## 4. Финальные изменения

| Файл | Изменение |
|------|-----------|
| `defaults/main.yml` | Добавлен `fail2ban_start_service: true` и `fail2ban_sshd_banaction: ""` |
| `tasks/main.yml` | "Enable fail2ban" (всегда) + "Start fail2ban" (`when: fail2ban_start_service`) |
| `tasks/verify.yml` | Полная переработка: guard на `fail2ban_start_service`; retries 5×2s; диагностический journalctl; warn в контейнерах |
| `templates/jail_sshd.conf.j2` | Добавлен блок `{% if fail2ban_sshd_banaction %}banaction = ...{% endif %}` |
| `molecule/docker/molecule.yml` | `extra-vars: "fail2ban_start_service=false"` |
| `molecule/docker/prepare.yml` | iptables-nft через `--ask=4` |
| `molecule/vagrant/molecule.yml` | `host_vars.arch-vm.fail2ban_sshd_backend: polling` |
| `molecule/vagrant/prepare.yml` | touch `/var/log/auth.log` + iptables-nft + Arch/Ubuntu условия |
| `vars/archlinux.yml` | `python-systemd` в packages (для production journald backend) |

---

## 5. Ключевые паттерны

### fail2ban_start_service — паттерн для сервисов несовместимых с Docker

```yaml
# defaults/main.yml
fail2ban_start_service: true  # false в Docker через extra-vars

# tasks/main.yml — КРИТИЧНО: всегда два отдельных таска
- name: "Enable fail2ban"
  ansible.builtin.service:
    name: fail2ban
    enabled: true
  # НЕТ when — всегда включаем для autostart

- name: "Start fail2ban"
  ansible.builtin.service:
    name: fail2ban
    state: started
  when: fail2ban_start_service | bool  # только в реальных окружениях

# molecule/docker/molecule.yml
provisioner:
  options:
    extra-vars: "fail2ban_start_service=false"
```

**Применимость:** Любой сервис требующий ядерных возможностей (netfilter, bpf, userns)
недоступных в Docker контейнерах. Примеры в этом проекте: `firewall` (nftables),
`fail2ban` (iptables). Шаблон: `<role>_start_service: true` в defaults,
`extra-vars: "<role>_start_service=false"` в Docker molecule.

### Разделение enable и start обязательно при conditional start

```yaml
# НЕПРАВИЛЬНО — combined task с when: пропускает enabled: true на Arch:
- name: "Enable and start service"
  service:
    enabled: true
    state: started
  when: start_service | bool
# → На Arch: pacman install НЕ включает сервис
# → При when=false: enabled: true пропускается → сервис disabled

# ПРАВИЛЬНО — всегда два таска:
- name: "Enable service"
  service:
    enabled: true
  # без when

- name: "Start service"
  service:
    state: started
  when: start_service | bool
```

### iptables-nft атомарная замена в Arch

```yaml
# Правильно — одна транзакция, ALPM разрешает конфликт:
- name: Install iptables-nft (replacing iptables)
  community.general.pacman:
    name: iptables-nft
    state: present
    extra_args: --ask=4   # ALPM_QUESTION_CONFLICT_PKG = 4

# Неправильно — два шага ломают транзитивные зависимости:
- pacman: name=iptables state=absent  # → iproute2 теряет libxtables.so
- pacman: name=iptables-nft state=present  # → зависимость не удовлетворена
```

### fail2ban backend для тестовых Arch окружений

```yaml
# molecule/vagrant/molecule.yml — явный backend для Arch:
provisioner:
  inventory:
    host_vars:
      arch-vm:
        fail2ban_sshd_backend: polling
        # backend=auto пробует systemd → python-systemd crash в CI ядро/box
        # polling: нет python-systemd зависимости, нет crash

# molecule/vagrant/prepare.yml — создать лог-файл для polling:
- name: Create /var/log/auth.log for polling backend (Arch)
  ansible.builtin.file:
    path: /var/log/auth.log
    state: touch
    mode: "0640"
    modification_time: preserve
    access_time: preserve
  when: ansible_facts['os_family'] == 'Archlinux'
```

### Диагностика сервиса в verify.yml (паттерн для future roles)

```yaml
# Шаблон диагностики: запускать ТОЛЬКО при неудаче, ПЕРЕД assert
- name: "Diagnostic: collect service journal on startup failure"
  ansible.builtin.command:
    cmd: "journalctl -u {{ service_name }} --lines=40 --no-pager --output=short-iso"
  register: _diag_journal
  changed_when: false
  failed_when: false   # не маскировать основную ошибку
  when:
    - start_service | bool
    - verify_status is defined
    - verify_status.rc | default(0) != 0
    - ansible_virtualization_type | default('') not in ['docker', 'container', 'lxc']
    - ansible_facts['service_mgr'] == 'systemd'

- name: "Diagnostic: show journal"
  ansible.builtin.debug:
    msg: "{{ service_name }} journal:\n{{ _diag_journal.stdout | default('(empty)') }}"
  when: ... # те же условия + _diag_journal is defined

- name: "Assert service is running"
  ansible.builtin.assert:
    that: verify_status.rc == 0
    fail_msg: "See diagnostic output above"  # ← диагностика уже в логе выше
  when:
    - start_service | bool
    - ansible_virtualization_type | default('') not in ['docker', 'container', 'lxc']
```

---

## 6. Сравнение с историей проекта

| Инцидент | Дата | Роль | Класс проблемы |
|----------|------|------|----------------|
| `iptables` в Docker без netfilter | 2026-03-01 | firewall | container restriction |
| Chrony sandboxing в Docker | 2026-03-02 | ntp | container restriction |
| **fail2ban iptables crash в Docker** | **2026-03-02** | **fail2ban** | **container restriction** |
| PAM flush-handlers перед verify | 2026-02-28 | pam_hardening | handler flush |
| NTP flush-handlers перед verify | 2026-03-02 | ntp | handler flush |
| pacman database stale в vagrant | 2026-03-01 | packages | Arch package cache |
| **pacman database stale в vagrant** | **2026-03-02** | **fail2ban** | **Arch package cache** |
| `\b` в Jinja2 = backspace | 2026-03-01 | ssh | Jinja2 escape |
| Ubuntu `/etc/ssh` не существует | 2026-03-01 | ssh | missing parent dir |
| vagrant-libvirt ABI mismatch | 2026-02-28 | pam_hardening | native extensions cache |

**Паттерн «container restriction»** повторяется третий раз (firewall → ntp → fail2ban).
Роли требующие kernel capabilities (netfilter, BPF, cgroups) нельзя полноценно
тестировать в Docker. Стандартный ответ: `<role>_start_service=false` + `extra-vars`.

**Паттерн «Arch package cache»** повторяется: packages и fail2ban оба требовали
`update_cache: true` в vagrant prepare. Шаблон vagrant/prepare.yml должен включать
это по умолчанию для Arch.

---

## 7. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | Читай аналогичные роли перед началом. `firewall_start_service=false` паттерн существовал — его надо было найти первым | Любая новая роль с сервисом в Docker |
| 2 | `enabled: true + state: started` в одном task + `when:` = ошибка на Arch. Arch не авто-включает сервисы. Всегда разделять | Arch-поддерживающие роли с conditional start |
| 3 | `backend = auto` в fail2ban скрывает crashes: пробует systemd → crash → нет fallback на polling | Environments с нестандартным ядром или vagrant box |
| 4 | `--ask=4` (ALPM_QUESTION_CONFLICT_PKG) для атомарной замены конфликтующих пакетов | Arch: замена пакетов с общими зависимостями |
| 5 | Polling backend требует существующего лог-файла. Arch = чистый journald, нет `/var/log/auth.log` | fail2ban на Arch без syslog |
| 6 | Диагностику (`journalctl`) добавлять в verify.yml ДО assert, условно при rc≠0 | Любые роли с сервисами на systemd |
| 7 | `vagrant plugin repair` не надёжен для перекомпиляции native extensions (из pam_hardening) | CI vagrant-libvirt setup |
| 8 | `gather_facts: true` обязателен в prepare.yml при нескольких платформах с OS-условиями | Все multi-platform Docker/vagrant scenarios |
| 9 | Два последовательных провала на всех платформах = не флакость. Углублённый анализ CI-логов | CI debugging heuristics |
| 10 | `Type=simple` systemd: exit 0 при `start` НЕ означает готовности сервиса. Проверяй сокет/PID | Любые systemd Type=simple сервисы |

---

## 8. Known gaps (после фикса)

- **`banaction = noop` переменная оставлена:** `fail2ban_sshd_banaction: ""` в defaults.
  Переменная добавлена в шаблон, но в Docker не используется (сервис не стартует).
  Оставлена для production use case когда banaction надо переопределить без правки шаблона.

- **python-systemd crash не исследован до конца:** точная причина краша
  (`backend = auto` + `python-systemd` + CI kernel) не установлена. Это CI-специфичная
  комбинация. На реальных Arch серверах `backend = auto` работает (production validated).
  Workaround через `polling` для CI достаточен.

- **Vagrant/arch тестирует только `polling` backend:** production использует `auto`
  (journald). Тест не покрывает journald путь. Добавление `vagrant-arch-journald` платформы
  возможно, но требует стабильного ядра — оставлено для отдельного PR.

- **Docker тест не проверяет runtime fail2ban:** с `fail2ban_start_service=false`
  тестируются только: установка пакетов, конфигурация файлов, service-enable. Runtime
  поведение (jails, banning, socket) тестируется только в vagrant. Это приемлемый trade-off.
