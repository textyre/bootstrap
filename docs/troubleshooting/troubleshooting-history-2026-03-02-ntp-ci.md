# Post-Mortem: NTP CI тесты — Docker Ubuntu NTS sync + Vagrant Ubuntu idempotence

**Дата:** 2026-03-02
**Статус:** Завершено — CI зелёный (Docker + Vagrant arch + Vagrant ubuntu)
**Итерации CI (Docker):** 4 запуска, 3 уникальных ошибки (все на Ubuntu в Docker)
**Итерации CI (Vagrant):** 1 запуск — зелёный с первой попытки (после фикса mode)
**Коммиты:** `ccbe094` (WIP) → `2684fc3` (4 фикс-коммита), PR #56
**Ветка:** `ci/track-ntp`

---

## 1. Задача

Исправить два падающих CI-теста роли `ntp` (chrony с NTS):

| Среда | Платформа | Симптом |
|-------|-----------|--------|
| Docker | Ubuntu-systemd | Sync assertion fail — `chronyc -n sources` не показывает `^*` маркер |
| Vagrant | ubuntu-base (KVM) | Idempotence fail — таска "Ensure chrony directories exist" показывает `changed` на втором прогоне |

**Роль `ntp`:** деплоит chrony с NTS (Network Time Security, RFC 8915) — все 4 сервера
используют TLS-аутентифицированный NTP: `time.cloudflare.com`, `time.nist.gov`,
`ptbtime1.ptb.de`, `ptbtime2.ptb.de`. NTS требует TLS handshake перед первой
синхронизацией, что значительно медленнее обычного NTP.

---

## 2. Инциденты

### Инцидент #1 — Vagrant Ubuntu: idempotence fail на `/var/log/chrony` (mode 0755 vs 0750)

**Коммит фикса:** `5f850d6`
**Прогон:** до CI (обнаружено при анализе кода + логов предыдущего падающего прогона)
**Этап:** `idempotence` (второй converge)

**Симптом:**

```
TASK [ntp : Ensure chrony directories exist] ***
changed: [ubuntu-base] => (item={'path': '/var/log/chrony', 'mode': '0750'})
ok: [ubuntu-base] => (item={'path': '/var/lib/chrony', 'mode': '0750'})
ok: [ubuntu-base] => (item={'path': '/var/lib/chrony/nts-data', 'mode': '0700'})
```

Второй converge показывал `changed` только для `/var/log/chrony`, остальные директории —
`ok`. При этом на Arch обе итерации показывали `ok` для всех трёх.

**Расследование:**

Загружен unit-файл `chrony.service` из пакета Ubuntu (`salsa.debian.org/debian/chrony`):

```ini
[Service]
# ... sandboxing ...
LogsDirectory=chrony
LogsDirectoryMode=0750
StateDirectory=chrony
StateDirectoryMode=0750
```

Ключевое: `LogsDirectoryMode=0750`. Systemd unit-файл Ubuntu задаёт mode `0750` для
`/var/log/chrony` через директиву `LogsDirectoryMode`. При каждом (ре)старте `chrony.service`
systemd принудительно выставляет этот mode — **перезаписывая** любое значение, которое
роль установила через `ansible.builtin.file`.

**Цепочка событий при converge:**

```
1. converge #1:
   ansible.builtin.file → /var/log/chrony mode=0755          → changed ✓
   notify: restart ntp
   handler fires → systemctl restart chrony.service
   systemd: LogsDirectoryMode=0750 → mode сброшен в 0750

2. converge #2 (idempotence check):
   ansible.builtin.file → /var/log/chrony mode=0755          → changed ❌
                          (текущий 0750 ≠ желаемый 0755)
```

**Почему `/var/lib/chrony` (mode 0750) не показывал `changed`:**

`StateDirectoryMode=0750` совпадает с mode в роли (`0750`). Конфликта нет.

**Почему Arch не падал:**

`chronyd.service` на Arch (`extra/chrony` пакет) **не содержит** `LogsDirectoryMode` и
`StateDirectoryMode`. Никакого systemd override — роль единственная кто управляет mode.

```
Arch: chronyd.service — zero sandboxing, zero LogsDirectory directives
Ubuntu: chrony.service — full sandboxing + LogsDirectory + StateDirectory
```

**Фикс:**

Выровнять mode роли с тем, что systemd навязывает на Ubuntu:

```yaml
# БЫЛО (ansible/roles/ntp/tasks/main.yml):
loop:
  - { path: "{{ ntp_logdir }}", mode: "0755" }

# СТАЛО:
loop:
  - { path: "{{ ntp_logdir }}", mode: "0750" }
```

И в verify:

```yaml
# БЫЛО (ansible/roles/ntp/molecule/shared/verify.yml):
- _ntp_verify_logdir.stat.mode == '0755'

# СТАЛО:
- _ntp_verify_logdir.stat.mode == '0750'
```

**0750 vs 0755 — безопасность:**

`0750` строже: группа может читать, остальные — нет. Для директории логов chrony это
правильнее (логи содержат IP-адреса серверов, стратум, смещения). Фактически Ubuntu
навязывает более безопасный дефолт, и выравнивание по нему — улучшение.

**Урок:**

Systemd `LogsDirectoryMode`/`StateDirectoryMode` перезаписывает filesystem permissions
при каждом старте сервиса. `ansible.builtin.file` не имеет приоритета — systemd выполняется
позже. Роль должна совпадать с дистрибутивным unit-файлом, иначе idempotence ломается.

При добавлении новой роли: проверить systemd unit-файл на target distro на предмет
`*DirectoryMode` директив.

---

### Инцидент #2 — Docker Ubuntu: chrony не синхронизируется (нет waitsync)

**Коммит фикса:** `5f850d6`
**Прогон:** CI run `22566852673` (первый после фиксов)
**Этап:** `converge` → `tasks/verify.yml`

**Симптом:**

```
TASK [ntp : Assert at least one source is synced (^* marker)] ***
fatal: [Ubuntu-systemd]: FAILED! =>
  "msg": "No synchronized NTP source (no '^*' marker in chronyc -n sources).
   Chrony is running but not synced — check internet connectivity."
```

**Причина:**

`tasks/verify.yml` сразу после старта chrony выполнял `chronyc -n sources` и искал `^*`
маркер. NTS требует TLS handshake перед первой синхронизацией (≈2-5s на сервер).
С 4 NTS-серверами: ~8-20 секунд на установление связи. Роль не ждала.

```yaml
# Порядок в tasks/main.yml:
- service: started          # chrony запущен
- include_tasks: verify.yml # СРАЗУ проверяем sync — chrony не успел
```

**Canonical решение:**

`chrony-wait.service` — upstream systemd unit, ожидающий синхронизации:

```ini
# /usr/lib/systemd/system/chrony-wait.service
ExecStart=/usr/bin/chronyc waitsync 30 0 0 2
```

Параметры: `waitsync <max_tries> <max_correction> <max_skew> <interval>`
- `30` попыток × `2` секунды = до 60 секунд ожидания
- `0 0` — без ограничений на коррекцию и skew

**Фикс:**

```yaml
# tasks/verify.yml — перед assertion на ^* маркер:
- name: Wait for chronyd to synchronize (up to 60s)
  ansible.builtin.command:
    cmd: chronyc waitsync 30 0 0 2
  changed_when: false
  tags: ['ntp']
```

**Почему Arch в Docker не падал:**

Arch `chronyd.service` не имеет sandboxing — chrony мог делать NTS handshake сразу.
Но даже на Arch без waitsync результат зависел от скорости сети (race condition).
waitsync устраняет race на всех платформах.

**Это не решило Docker Ubuntu полностью** — потребовались ещё 3 итерации (инциденты #3-#5).

---

### Инцидент #3 — Docker Ubuntu: systemd sandboxing блокирует сеть chrony

**Коммит фикса:** `f50d698`
**Прогон:** CI run `22566852673` (первый после фиксов — waitsync не помог)
**Этап:** `converge` → `tasks/verify.yml` → `waitsync` timeout

**Симптом:**

```
TASK [ntp : Wait for chronyd to synchronize (up to 60s)] ***
fatal: [Ubuntu-systemd]: FAILED! =>
  "rc": 1, "stdout": "No suitable source for synchronisation."
```

`chronyc tracking` показывал:

```
Reference ID    : 00000000 ()
Stratum         : 0
...
Leap status     : Not synchronised
```

`refid 00000000` после 60 секунд ожидания — chrony вообще не получал ответов от серверов.

**Расследование:**

Ubuntu `chrony.service` содержит полный набор systemd sandboxing:

```ini
[Service]
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectHostname=yes
ProtectProc=invisible
PrivateTmp=yes
MemoryDenyWriteExecute=yes
RestrictNamespaces=~user pid net uts mnt
RestrictSUIDSGID=yes
LockPersonality=yes
ProcSubset=pid
```

На реальной VM (bare-metal, KVM) эти ограничения работают корректно — systemd создаёт
изолированные namespace'ы для каждого ограничения. Chrony получает доступ к сети, но
не может писать в `/home`, `/boot`, и т.д.

**В Docker контейнере** namespace'ы хоста и контейнера уже разделены Docker runtime.
Systemd sandboxing пытается создать вложенные namespace'ы поверх Docker'овских — это
либо не поддерживается (EPERM), либо создаёт дополнительную изоляцию, которая блокирует
**сетевые** подключения chrony. Результат: chrony запускается (`active (running)`), но не
может установить ни одного NTP/NTS соединения.

**Ключевое отличие Arch:**

```
Arch: chronyd.service — ZERO sandboxing → работает в Docker без проблем
Ubuntu: chrony.service — FULL sandboxing → ProtectSystem=strict ломает Docker
```

**Фикс:**

Systemd drop-in override в Docker prepare.yml — обнуляет все sandbox-директивы:

```yaml
# ansible/roles/ntp/molecule/docker/prepare.yml:
- name: Create chrony.service.d directory (Debian — Docker workaround)
  ansible.builtin.file:
    path: /etc/systemd/system/chrony.service.d
    state: directory
    mode: "0755"
  when: ansible_facts['os_family'] == 'Debian'

- name: Disable chrony sandboxing for Docker (Debian)
  ansible.builtin.copy:
    dest: /etc/systemd/system/chrony.service.d/docker.conf
    mode: "0644"
    content: |
      # Relax systemd sandboxing — incompatible with Docker
      [Service]
      ProtectSystem=
      ProtectHome=
      ProtectKernelTunables=
      ProtectKernelModules=
      ProtectKernelLogs=
      ProtectControlGroups=
      ProtectHostname=
      ProtectProc=
      PrivateTmp=
      MemoryDenyWriteExecute=
      RestrictNamespaces=
      RestrictSUIDSGID=
      LockPersonality=
      ProcSubset=
  when: ansible_facts['os_family'] == 'Debian'
```

Пустое значение (`ProtectSystem=`) отменяет директиву из base unit-файла.
Drop-in создаётся **только в Docker prepare.yml** — не влияет на production.

**Почему это правильно:**

Drop-in — в `molecule/docker/prepare.yml`, не в роли. Роль не знает про Docker.
Docker prepare готовит среду так, чтобы роль работала в нестандартном окружении.
Аналогия: `Vagrant prepare.yml` останавливает `systemd-timesyncd` — тоже подготовка
среды, не часть роли.

**Это не решило Docker Ubuntu полностью** — потребовались ещё 2 итерации (инциденты #4-#5).

---

### Инцидент #4 — Docker Ubuntu: handler fires AFTER verify (порядок flush)

**Коммит фикса:** `8560588`
**Прогон:** CI run `22567108925` (второй, после sandboxing drop-in — всё ещё `refid 00000000`)
**Этап:** `converge` → `tasks/verify.yml` → `waitsync` timeout

**Симптом:**

Идентичный инциденту #3: `refid 00000000`, chrony не синхронизируется после 60 секунд.
Но на этот раз sandboxing снят. Почему?

**Расследование:**

Анализ порядка выполнения в `tasks/main.yml`:

```yaml
# tasks/main.yml — порядок выполнения:
- name: Install NTP daemon (chrony)         # 1. Установка
  ansible.builtin.package: ...

- name: Deploy chrony configuration          # 2. Конфиг → notify: restart ntp
  ansible.builtin.template: ...
  notify: restart ntp                        # handler ЗАРЕГИСТРИРОВАН, но не выполнен

- name: Enable and start chronyd             # 3. Запуск с ДЕФОЛТНЫМ конфигом
  ansible.builtin.service:
    state: started                           # chrony стартует с /etc/chrony/chrony.conf (Ubuntu default)

- name: Verify NTP                           # 4. Проверка — chrony работает с ДЕФОЛТНЫМ конфигом!
  ansible.builtin.include_tasks: verify.yml  # waitsync 60s → timeout, потому что дефолтные серверы

# --- КОНЕЦ PLAY ---
# ТОЛЬКО СЕЙЧАС handler 'restart ntp' выполняется → chrony перезапускается с НАШИМ конфигом
```

**Корень проблемы:**

Ansible handlers выполняются **в конце play**, не после каждой таски. `notify: restart ntp`
на таске `Deploy chrony configuration` регистрирует handler, но не запускает его.
`verify.yml` выполняется ДО handler'а. Chrony в момент verify использует **пакетный
дефолтный конфиг** Ubuntu, а не наш NTS-enabled шаблон.

Дефолтный Ubuntu chrony.conf:

```conf
pool ntp.ubuntu.com        iburst maxsources 4
pool 0.ubuntu.pool.ntp.org iburst maxsources 1
pool 1.ubuntu.pool.ntp.org iburst maxsources 1
pool 2.ubuntu.pool.ntp.org iburst maxsources 2
```

Без NTS — обычный NTP. Но в Docker CI runner (GitHub Actions) эти пулы могут быть
недоступны или медленны. На Arch дефолтный `pool.ntp.org` отвечал быстрее, маскируя
проблему.

**Почему Arch проходил:**

1. Arch `chronyd.service` без sandboxing → нет проблемы из инцидента #3
2. Arch дефолтный `/etc/chrony.conf` использует `pool.ntp.org` — более доступный в CI
3. Arch может успевать синхронизироваться с дефолтными серверами за 60 секунд

Но это ненадёжно — порядок handler/verify неправильный на всех платформах.

**Фикс:**

```yaml
# tasks/main.yml — добавить flush_handlers ПЕРЕД verify:
- name: Flush handlers to apply new chrony config before verification
  ansible.builtin.meta: flush_handlers
  tags: ['ntp']

- name: Verify NTP
  ansible.builtin.include_tasks: verify.yml
  tags: ['ntp']
```

`meta: flush_handlers` принудительно выполняет все зарегистрированные handlers прямо
сейчас. После этого chrony перезапущен с НАШИМ NTS-конфигом, и verify проверяет
правильную конфигурацию.

**Новый порядок:**

```
1. Install chrony
2. Deploy chrony config → notify: restart ntp (зарегистрирован)
3. Enable and start chronyd (дефолтный конфиг)
4. meta: flush_handlers → handler 'restart ntp' → chrony перезапущен с НАШИМ конфигом
5. verify.yml → waitsync → проверяет NTS-серверы → sync ✓
```

**Урок:**

`meta: flush_handlers` — обязательный шаг перед любой верификацией, зависящей от
конфигурации, которая деплоится с `notify`. Без flush handler выполнится ПОСЛЕ verify,
и verify проверяет не ту конфигурацию. Паттерн:

```yaml
# ПРАВИЛЬНО:
- template: ... notify: restart X
- meta: flush_handlers        # X перезапущен с новым конфигом
- include_tasks: verify.yml   # проверяет новый конфиг

# НЕПРАВИЛЬНО:
- template: ... notify: restart X
- include_tasks: verify.yml   # проверяет СТАРЫЙ конфиг
# --- end of play ---
# handler fires here — слишком поздно для verify
```

**Это не решило Docker Ubuntu полностью** — потребовалась ещё 1 итерация (инцидент #5).

---

### Инцидент #5 — Docker Ubuntu: NTS TLS fail из-за отсутствия CA certificates

**Коммит фикса:** `2684fc3`
**Прогон:** CI run `22567358621` (третий — flush_handlers работает, chrony с нашим конфигом,
но всё ещё `refid 00000000`)
**Этап:** `converge` → `tasks/verify.yml` → `waitsync` timeout

**Симптом:**

Теперь подтверждено: flush_handlers работает, chrony перезапускается с нашим NTS-конфигом.
Но `chronyc sources` показывает 0 источников. `chronyc tracking` — `refid 00000000`.

**Расследование:**

NTS = Network Time Security (RFC 8915). Протокол:

```
1. NTS-KE (Key Establishment) — TLS 1.3 handshake с NTP-сервером (порт 4460)
2. Сервер выдаёт cookies + AEAD ключ
3. Дальнейший NTP обмен идёт по UDP/123 с аутентификацией через cookies
```

Шаг 1 требует **TLS** — chrony должен верифицировать сертификат NTP-сервера.
Для этого нужна CA certificate bundle в системе (`/etc/ssl/certs/ca-certificates.crt`
на Debian/Ubuntu).

Минимальные Docker-образы (включая `ghcr.io/textyre/ubuntu-systemd:latest`) **не содержат**
`ca-certificates` пакет. Размер образа минимизируется, TLS-зависимости не включаются.

**Без CA certificates:**

```
chrony → NTS-KE TLS handshake → certificate verification FAIL → silent failure
       → chrony логирует ошибку в syslog (но не в файл) → 0 sources → refid 00000000
```

Chrony **молча** отбрасывает серверы, чьи NTS-KE сессии не удались. Нет assertion failure,
нет crash — просто 0 рабочих источников.

**Почему Arch не падал:**

Arch Docker-образ (`ghcr.io/textyre/archlinux-systemd:latest`) включает `ca-certificates`
как зависимость базовых пакетов. `pacman -S chrony` не тянет `ca-certificates` явно, но
они уже установлены.

**Почему Vagrant не падал:**

Vagrant boxes (`arch-base`, `ubuntu-base`) — полноценные VM с pre-installed `ca-certificates`.

**Фикс:**

```yaml
# ansible/roles/ntp/molecule/docker/prepare.yml:
- name: Ensure CA certificates are installed (Debian — required for NTS)
  ansible.builtin.apt:
    name: ca-certificates
    state: present
  when: ansible_facts['os_family'] == 'Debian'
```

**Почему в prepare, а не в роли:**

Роль `ntp` не должна устанавливать `ca-certificates` — это ответственность базового
образа или роли `base_system`. В Docker prepare мы компенсируем минимальность образа.
Аналогия: Vagrant prepare устанавливает `systemd-timesyncd` stop — тоже подготовка среды.

**Урок:**

NTS требует CA certificates для TLS. При тестировании NTS-enabled chrony в минимальных
контейнерах: проверить наличие `ca-certificates`. Ошибка молчаливая — chrony не crash'ится,
просто работает с 0 источниками.

Общий паттерн: когда демон использует TLS (NTS, HTTPS, mTLS) — Docker prepare должен
обеспечить CA bundle. Иначе TLS handshake тихо падает.

---

## 3. Многослойная природа проблемы Docker Ubuntu

Инциденты #2-#5 — это **одна проблема** (`chrony не синхронизируется в Docker Ubuntu`),
проявившаяся как цепочка из 4 слоёв:

```
Слой 1: Race condition — verify до sync
         ↓ фикс: waitsync 60s
         ↓ раскрыл →

Слой 2: Sandboxing — chrony не может делать сетевые запросы
         ↓ фикс: systemd drop-in
         ↓ раскрыл →

Слой 3: Handler ordering — chrony работает с дефолтным конфигом
         ↓ фикс: meta: flush_handlers
         ↓ раскрыл →

Слой 4: Missing CA certs — NTS TLS handshake невозможен
         ↓ фикс: ca-certificates в prepare
         ↓ РЕШЕНО ✓
```

Каждый фикс был необходимым, но недостаточным. Только все 4 вместе решили проблему.

**Почему нельзя было найти все 4 слоя сразу:**

Каждый следующий слой маскировался предыдущим. Пока sandboxing блокировал сеть (слой 2),
невозможно было увидеть что handler не применяет конфиг (слой 3). Пока handler не применял
конфиг, невозможно было увидеть что NTS fail из-за CA certs (слой 4).

**Почему Arch проходил без всех 4 фиксов:**

| Слой | Arch | Ubuntu |
|------|------|--------|
| 1. waitsync | Иногда sync за <5s | NTS handshake 8-20s |
| 2. sandboxing | chronyd.service: 0 директив | chrony.service: 14 директив |
| 3. handler order | pool.ntp.org доступен в CI | ntp.ubuntu.com менее доступен |
| 4. CA certs | Установлены в базовом образе | Не установлены в образе |

Arch маскировал все 4 проблемы благодаря простоте своего unit-файла и составу образа.
Это подтверждает важность cross-platform CI: баг на одной платформе может скрывать
фундаментальные проблемы в порядке выполнения.

---

## 4. Временная шкала

```
── Начало сессии (2026-03-02) ──────────────────────────────────────────────────

[Анализ]     Исследование CI логов, Ubuntu chrony.service (salsa.debian.org),
             upstream chrony-wait.service, чтение tasks/main.yml и verify.yml

ccbe094      ci(ntp): track CI failures [WIP]
             ↓ Начальный трекинг-коммит, без фиксов

5f850d6      fix(ntp): resolve Docker sync failure and Ubuntu idempotence issue
             ↓ waitsync 30 0 0 2 перед sync assertion
             ↓ logdir mode 0755→0750 (Ubuntu LogsDirectoryMode=0750)
             ↓ verify.yml: expected mode 0755→0750
             ↓ 3 файла: tasks/verify.yml, tasks/main.yml, molecule/shared/verify.yml

             CI run 22566852673:
             ↓ Lint:          SUCCESS ✓
             ↓ Docker:        FAIL — Ubuntu waitsync timeout (refid 00000000)
             ↓ Vagrant arch:  SUCCESS ✓ (4m22s)
             ↓ Vagrant ubuntu: SUCCESS ✓ (3m58s)    ← idempotence ИСПРАВЛЕНА

f50d698      fix(ntp): disable chrony sandboxing in Docker prepare (Ubuntu)
             ↓ Systemd drop-in /etc/systemd/system/chrony.service.d/docker.conf
             ↓ 14 директив обнулены
             ↓ 1 файл: molecule/docker/prepare.yml (+34 строк)

             CI run 22567108925:
             ↓ Lint:          SUCCESS ✓
             ↓ Docker:        FAIL — Ubuntu waitsync timeout (refid 00000000)
             ↓ Vagrant:       SUCCESS ✓ (оба)

8560588      fix(ntp): flush handlers before verify to apply chrony config
             ↓ meta: flush_handlers перед include_tasks: verify.yml
             ↓ 1 файл: tasks/main.yml (+4 строки)

             CI run 22567358621:
             ↓ Lint:          SUCCESS ✓
             ↓ Docker:        FAIL — Ubuntu waitsync timeout (refid 00000000)
             ↓ Vagrant:       SUCCESS ✓ (оба)

2684fc3      fix(ntp): ensure CA certificates for NTS in Docker Ubuntu
             ↓ apt: ca-certificates в Docker prepare.yml
             ↓ 1 файл: molecule/docker/prepare.yml (+8 строк)

             CI run 22567510842-22567510845:
             ↓ Lint:          SUCCESS ✓ (2m17s)
             ↓ Docker:        SUCCESS ✓ (2m21s)    ← DOCKER ИСПРАВЛЕН
             ↓ Vagrant arch:  SUCCESS ✓ (3m56s)
             ↓ Vagrant ubuntu: SUCCESS ✓ (3m55s)

             PR #56 merged → master b6daa1d
```

**Время от первого коммита до зелёного CI:** ~25 минут (08:04 → 08:29)

---

## 5. Финальная структура изменений

**Файлы роли (влияют на production):**

```
ansible/roles/ntp/
├── tasks/
│   ├── main.yml               ← logdir mode 0755→0750
│   │                             + meta: flush_handlers перед verify.yml
│   └── verify.yml             ← + chronyc waitsync 30 0 0 2
│                                  + улучшено fail_msg ("after 60s")
└── molecule/
    ├── shared/
    │   └── verify.yml         ← expected logdir mode 0755→0750
    └── docker/
        └── prepare.yml        ← + ca-certificates (Debian)
                                  + chrony.service.d/docker.conf drop-in (Debian)
```

**Файлы НЕ изменённые:**

```
defaults/main.yml             ← ntp_servers, ntp_logdir — без изменений
vars/main.yml                 ← ntp_package, ntp_service_name — без изменений
handlers/main.yml             ← handler 'restart ntp' — без изменений
templates/chrony.conf.j2      ← шаблон — без изменений
molecule/vagrant/prepare.yml  ← Vagrant prepare — без изменений
molecule/docker/molecule.yml  ← Docker scenario config — без изменений
```

---

## 6. Ключевые паттерны

### flush_handlers перед verify

```yaml
# ОБЯЗАТЕЛЬНЫЙ паттерн для ролей с notify + verify:
- name: Deploy config
  ansible.builtin.template: ...
  notify: restart service

- name: Enable and start service
  ansible.builtin.service:
    state: started

- name: Flush handlers to apply config before verification
  ansible.builtin.meta: flush_handlers    # ← КРИТИЧНО

- name: Verify service
  ansible.builtin.include_tasks: verify.yml
```

Без `flush_handlers` verify проверяет СТАРЫЙ конфиг. Handler выполнится после verify
в конце play — слишком поздно.

### Systemd LogsDirectoryMode vs Ansible file mode

```yaml
# Ansible роль ДОЛЖНА совпадать с systemd *DirectoryMode:
# Ubuntu chrony.service: LogsDirectoryMode=0750
# → роль:
- { path: "{{ ntp_logdir }}", mode: "0750" }   # ← совпадает с systemd

# Если не совпадает: idempotence fail на каждом restart
# (systemd сбрасывает mode → Ansible видит changed)
```

### Docker prepare для TLS-сервисов

```yaml
# Любой сервис с TLS (NTS, HTTPS, mTLS) в минимальном Docker-образе:
- name: Ensure CA certificates are installed (Debian)
  ansible.builtin.apt:
    name: ca-certificates
    state: present
  when: ansible_facts['os_family'] == 'Debian'
```

### Systemd sandboxing drop-in для Docker

```yaml
# Создаётся ТОЛЬКО в molecule/docker/prepare.yml, не в роли.
# Формат: пустое значение директивы = отмена base unit.
# ProtectSystem= (без значения) → отменяет ProtectSystem=strict
```

---

## 7. Сравнение с историей проекта

| Инцидент | Дата | Роль | Ошибка | Класс |
|----------|------|------|--------|-------|
| Docker hostname EPERM | 2026-02-24 | hostname | hostnamectl EBUSY | container restriction |
| Docker /etc/hosts EBUSY | 2026-02-24 | hostname | lineinfile atomic rename | bind-mount restriction |
| Docker sysctl EPERM | 2026-03-01 | sysctl | handler sysctl --system | container restriction |
| {% raise %} parse error | 2026-03-01 | sysctl | Jinja2 unknown tag | template syntax |
| Ubuntu sysctl.d ordering | 2026-03-01 | sysctl | --system перекрыт 99-sysctl.conf | OS-specific gap |
| **Docker chrony sandboxing** | **2026-03-02** | **ntp** | **Ubuntu ProtectSystem=strict** | **container restriction** |
| **Ubuntu LogsDirectoryMode** | **2026-03-02** | **ntp** | **systemd сбрасывает mode** | **OS-specific gap** |
| **Handler before verify** | **2026-03-02** | **ntp** | **handler fires end-of-play** | **execution order** |
| **NTS без CA certs** | **2026-03-02** | **ntp** | **TLS handshake silent fail** | **missing dependency** |

**Новый класс ошибок: "execution order"** — handler fires at end of play, verify runs
before handler. Ранее не встречался. Потенциально затрагивает все роли с `notify` + verify.

**Рекуррентный класс: "container restriction"** — третий инцидент с Docker sandboxing
(после hostname EBUSY и sysctl EPERM). Ubuntu unit-файлы значительно более sandboxed
чем Arch. Паттерн предсказуем: любая роль, деплоящая systemd-сервис на Ubuntu в Docker,
рискует столкнуться с sandboxing-конфликтами.

---

## 8. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `meta: flush_handlers` обязателен перед verify, зависящим от notify-конфига | Все роли с template → notify → verify |
| 2 | Systemd `LogsDirectoryMode`/`StateDirectoryMode` перезаписывает filesystem mode при каждом старте. Роль должна совпадать | Все роли, создающие dirs для systemd-сервисов |
| 3 | Ubuntu systemd unit-файлы содержат sandboxing, Arch — нет. В Docker sandboxing ломает сеть/файлы. Drop-in в prepare | Все роли с systemd-сервисами в Docker CI |
| 4 | NTS (и любой TLS) требует CA certificates. Минимальные Docker-образы не содержат `ca-certificates`. Ошибка молчаливая | Любая роль с TLS/NTS/HTTPS в Docker |
| 5 | `chronyc waitsync 30 0 0 2` — upstream canonical способ ожидания sync. Не retry loop, не sleep | NTP verification |
| 6 | Многослойные баги маскируют друг друга — каждый следующий слой виден только после фикса предыдущего | Debugging methodology |
| 7 | Arch в Docker маскирует проблемы благодаря минимальным unit-файлам и полному составу образа. Cross-platform CI обязателен | CI testing strategy |
| 8 | При расследовании Docker failures — проверять unit-файл target дистрибутива на наличие sandboxing директив | Docker + systemd debugging |

---

## 9. Процессные наблюдения

### Что прошло хорошо

- **Vagrant исправлен с первого CI-прогона** — root cause (LogsDirectoryMode) найден
  через чтение upstream unit-файла до push
- **Каждый Docker-фикс был минимальным** — один коммит = одно изменение, легко отследить
  какой слой что решил
- **Commit messages информативны** — каждый объясняет WHY, не только WHAT
- **waitsync** взят из upstream `chrony-wait.service` — не самодел, а проверенное решение

### Что можно улучшить

- **4 CI-итерации на Docker** — каждая итерация ~8 минут (push → CI → анализ).
  Итого ~30 минут CI-ожидания. Альтернатива: добавить диагностику в первом коммите
  (`chronyc -n sources -v`, `journalctl -u chrony.service`, `openssl s_client -connect
  time.cloudflare.com:4460`) чтобы увидеть все слои сразу

- **Не был проверен Ubuntu chrony.service заранее** — sandboxing директивы можно было
  обнаружить до push (как была обнаружена LogsDirectoryMode для Vagrant). Один дополнительный
  шаг расследования мог сэкономить 2 итерации

- **CA certificates — предсказуемая проблема** — для NTS-enabled конфига TLS-зависимость
  очевидна. Checklist при добавлении Docker prepare для TLS-сервисов:
  1. CA certificates (`ca-certificates` на Debian, предустановлен на Arch)
  2. Systemd sandboxing drop-in (если unit-файл содержит `Protect*`)
  3. `meta: flush_handlers` перед verify

### Предложенный checklist для будущих ролей

При добавлении Docker CI для роли с systemd-сервисом:

```
□ Скачать unit-файл target дистрибутива (salsa.debian.org, Arch PKGBUILD)
□ Проверить Protect*, Restrict*, MemoryDenyWriteExecute — нужен ли drop-in?
□ Проверить LogsDirectoryMode, StateDirectoryMode — совпадает ли с ролью?
□ Сервис использует TLS? → ca-certificates в prepare
□ Роль использует notify? → meta: flush_handlers перед verify
```

---

## 10. Known gaps

- **`chronyc waitsync` в tasks/verify.yml влияет на production** — при первом деплое на
  медленной сети waitsync может задержать playbook на 60 секунд. Допустимо: chrony-wait.service
  делает то же самое на production системах с `After=chrony-wait.service`.

- **Drop-in в Docker prepare не daemon-reload** — systemd видит drop-in только после
  `systemctl daemon-reload`. В текущей конфигурации drop-in создаётся в prepare (до
  converge). Chrony ещё не установлен → при установке через `apt install chrony` systemd
  автоматически делает daemon-reload. Если порядок изменится — может потребоваться явный
  daemon-reload.

- **Arch Docker-образ может потерять ca-certificates** — если upstream образ минимизируется
  и перестанет включать `ca-certificates`, NTP Docker-тест на Arch тоже упадёт. Пока не
  актуально: Arch base включает `ca-certificates` как зависимость `pacman`.
