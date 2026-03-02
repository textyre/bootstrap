# Post-Mortem: Vaultwarden Molecule CI — полная переработка тестовой инфраструктуры

**Дата:** 2026-03-02
**Статус:** Завершено — CI зелёный (Docker Arch, Vagrant Arch + Ubuntu)
**Итерации CI:** 4 запуска, 4 уникальных ошибки (каждый запуск раскрывал новый слой)
**Коммиты:** 4 коммита, squash-merged в `e49c968`
**PRs:** #35 merged, #59 closed (superseded)
**Ветка:** `fix/vaultwarden-molecule-overhaul`
**Скоуп:** ~140 добавленных строк, ~10 удалённых, 7 изменённых файлов (1 новый)

---

## 1. Задача

Довести molecule-тесты роли `vaultwarden` до зелёного CI на всех 3 workflow:
- **Molecule (Docker)** — Archlinux-systemd контейнер
- **Molecule Vagrant** — arch-vm (KVM) + ubuntu-base (KVM)
- **Ansible Lint & Syntax Check**

### Контекст: два конкурирующих PR

| PR | Ветка | Подход | Статус |
|----|-------|--------|--------|
| #35 `fix/vaultwarden-molecule-overhaul` | Полная переработка molecule инфраструктуры | Merged ✓ |
| #59 `ci/track-vaultwarden` | WIP tracking PR (1 коммит, описание ошибок) | Закрыт (superseded) |

PR #59 был создан как трекер проблем с описанием 3 оригинальных CI-ошибок. Все ошибки
исправлены в PR #35. PR #59 закрыт с комментарием ссылки на #35.

### Архитектура роли vaultwarden

```
vaultwarden/
├── meta/main.yml          ← dependencies: [docker, caddy]
├── tasks/main.yml         ← directories, admin token, docker-compose, caddy config, backup
├── handlers/main.yml      ← Restart vaultwarden (docker compose), Reload caddy (docker exec)
├── templates/
│   ├── docker-compose.yml.j2
│   ├── vault.caddy.j2
│   └── vaultwarden-backup.sh.j2
├── defaults/main.yml      ← vaultwarden_enabled, domain, ports, backup config
└── molecule/
    ├── docker/            ← Docker-specific converge (include_role)
    ├── vagrant/           ← Vagrant-specific prepare, group_vars
    └── shared/            ← Общие converge.yml, verify.yml
```

**Ключевая особенность:** Роль имеет meta dependencies (`docker`, `caddy`), которые
автоматически запускаются через `roles:` directive. Это создаёт каскад проблем в CI:
- Docker role пытается настроить daemon.json и перезапустить Docker service
- Caddy role пытается стартовать контейнеры
- Handlers vaultwarden пытаются взаимодействовать с несуществующими контейнерами

---

## 2. Исходные ошибки (до начала работы)

PR #35 имел 3 CI-ошибки при первоначальном push (до текущей сессии):

| # | Workflow | Ошибка | Этап |
|---|----------|--------|------|
| 1 | Docker (Arch) | Handler `Restart docker` fails — docker.service не существует в контейнере | converge |
| 2 | Vagrant (arch) | `community.docker` collection не установлена на runner | syntax |
| 3 | Vagrant (ubuntu) | Платформа `ubuntu-base` отсутствует в molecule.yml | syntax |

---

## 3. Инциденты

### Инцидент #1 — Docker: meta dependencies запускают docker/caddy роли внутри контейнера

**Коммит фикса:** `af35929` (rebase from master) + `b97e7b3`
**CI-прогон:** базовый (до текущей сессии)
**Этап:** converge
**Платформа:** Archlinux-systemd (Docker)

**Симптом:**

```
TASK [docker : Enable and start docker service] ********************************
fatal: [Archlinux-systemd]: FAILED! => {
    "msg": "Unable to restart service docker: ..."
}
```

Shared `converge.yml` использовал `roles:` directive:

```yaml
# molecule/shared/converge.yml (ДО):
roles:
  - role: vaultwarden
```

`roles:` directive обрабатывает `meta/main.yml` dependencies — docker и caddy роли
выполняются автоматически. Внутри Docker контейнера docker.service не существует (только
socket mount), и `systemctl start docker` падает.

**Расследование:**

Варианты решения meta dependency проблемы:

| Подход | Плюсы | Минусы |
|--------|-------|--------|
| `include_role` в converge | Пропускает meta deps | Нужен отдельный converge.yml |
| `docker_enable_service: false` | Минимальные изменения | Не решает caddy + все deps |
| Extra vars `--skip-tags` | Гибко | Handlers не скипаются tags |

**Фикс — docker-specific converge.yml:**

```yaml
# molecule/docker/converge.yml (НОВЫЙ файл):
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  pre_tasks:
    - name: Set test admin token (no vault needed in molecule)
      ansible.builtin.set_fact:
        vault_vaultwarden_admin_token: "molecule-test-token-not-for-production"

  tasks:
    - name: Include vaultwarden role (without meta dependencies)
      ansible.builtin.include_role:
        name: vaultwarden
```

`include_role` (dynamic inclusion) **не обрабатывает** `meta/main.yml` dependencies —
docker и caddy роли не запускаются. Это фундаментальное отличие от `roles:` (static
inclusion).

**Дополнительный guard на handlers:**

```yaml
# handlers/main.yml — добавлен Docker guard:
when: ansible_facts['virtualization_type'] | default('') != 'docker'
```

В Docker контейнере `virtualization_type == 'docker'` → handlers не срабатывают.
Vagrant VM имеет `virtualization_type == 'kvm'` → handlers срабатывают (если не
заблокированы другим условием).

**Паттерн `include_role` vs `roles:` для molecule:**

```
roles:           → static import → обрабатывает meta/main.yml deps → deps выполняются
include_role:    → dynamic import → НЕ обрабатывает meta deps → только указанная роль
```

Это повторяет паттерн из teleport CI, где `include_role` был использован для изоляции
роли от зависимостей в Docker-среде.

---

### Инцидент #2 — Vagrant syntax: отсутствие community.docker collection

**Коммит фикса:** `b97e7b3`
**CI-прогон:** первый в текущей сессии
**Этап:** syntax check
**Платформа:** Vagrant (обе)

**Симптом:**

```
ERROR! couldn't resolve module/action 'community.docker.docker_network'.
This often indicates a misspelling, missing collection, or incorrect module path.
```

Vagrant scenario использует `roles:` (shared converge.yml), что обрабатывает meta
dependencies. Caddy роль содержит task:

```yaml
# caddy/tasks/main.yml:
- name: Create Docker network for proxy
  community.docker.docker_network:
    name: proxy
```

Даже с `caddy_enabled: false`, Ansible syntax check **парсит все tasks** в роли,
включая те, что будут skipped. Module `community.docker.docker_network` не найден
потому что collection `community.docker` не была в `requirements.yml`.

**Фикс:**

```yaml
# ansible/requirements.yml — добавлено:
- name: community.docker
  version: ">=3.0.0"
```

**Урок:**

Ansible `--syntax-check` парсит **все** tasks во всех ролях, включая условно
пропускаемые (`when: false`). Если task использует module из collection, collection
должна быть установлена даже если task никогда не выполнится.

---

### Инцидент #3 — Vagrant: отсутствие ubuntu-base платформы

**Коммит фикса:** `b97e7b3`
**CI-прогон:** первый в текущей сессии
**Этап:** create
**Платформа:** Vagrant ubuntu

**Симптом:**

```
CRITICAL Molecule failed to validate the schema.
Platform 'ubuntu-base' not found in molecule.yml platforms list.
```

Vagrant molecule.yml содержал только `arch-vm` платформу. CI workflow
`molecule-vagrant.yml` запускает тесты для обеих платформ (`arch`, `ubuntu`),
но ubuntu-base не была определена.

**Фикс:**

Добавлена ubuntu-base платформа в vagrant molecule.yml + OS-conditional prepare tasks:

```yaml
# molecule/vagrant/molecule.yml:
platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
    memory: 2048
    cpus: 2
  - name: ubuntu-base            # ← НОВОЕ
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
    memory: 2048
    cpus: 2
```

```yaml
# molecule/vagrant/prepare.yml — OS-conditional tasks:

# Arch:
- name: Install Docker and prerequisites (Arch)
  community.general.pacman:
    name: [docker, docker-compose, openssl, cronie, sqlite3]
  when: ansible_facts['os_family'] == 'Archlinux'

# Ubuntu:
- name: Install Docker and prerequisites (Debian)
  ansible.builtin.apt:
    name: [docker.io, docker-compose-v2, openssl, cron, sqlite3]
  when: ansible_facts['os_family'] == 'Debian'
```

---

### Инцидент #4 — Vagrant: Docker daemon не перезапускается (CIS hardened defaults)

**Коммит фикса:** `fdceff6`
**CI-прогон:** второй (run после commit `b97e7b3`)
**Этап:** converge → docker role → handler `Restart docker`
**Платформа:** Обе (arch-vm + ubuntu-base)

**Симптом:**

```
RUNNING HANDLER [docker : Restart docker] **************************************
fatal: [arch-vm]: FAILED! => {
    "msg": "Unable to restart service docker: Job for docker.service
    failed because the control process exited with error code."
}
```

Docker role's handler перезапускает Docker daemon после deploy daemon.json. Но
daemon.json содержит CIS-hardened defaults, несовместимые с Vagrant CI VMs:

```json
{
  "userns-remap": "default",
  "icc": false,
  "live-restore": true,
  "no-new-privileges": true,
  "log-driver": "journald",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
```

**Три проблемы в daemon.json:**

| Параметр | Значение | Проблема в CI VM |
|----------|----------|-----------------|
| `userns-remap: "default"` | CIS Docker Benchmark | User namespaces не настроены в VM |
| `icc: false` | Межконтейнерная изоляция | Требует специфичной network config |
| `log-driver: "journald"` + `max-size/max-file` | CIS defaults | `max-size`/`max-file` — log-opts для `json-file`, **невалидны для `journald`** |

**Расследование — ход анализа:**

1. Первая гипотеза: CIS features (`userns-remap`, `icc`) несовместимы с VM.
   Добавлены overrides — **не помогло** (CI run #3).

2. Вторая гипотеза: `log-driver: journald` с `max-size`/`max-file` — невалидная
   комбинация. Docker daemon отказывается стартовать с invalid log-opts.
   Добавлен `docker_log_driver: "json-file"` — **не помогло** (CI run #4).

3. Финальная диагностика (CI run #4 logs): ошибка оказалась **НЕ** в docker role,
   а **НИЖЕ** — docker role проходит полностью. Ошибка сместилась к handlers vaultwarden
   (инцидент #5).

**Фикс — CI-safe docker overrides в vagrant molecule group_vars:**

```yaml
# molecule/vagrant/molecule.yml — group_vars:
docker_log_driver: "json-file"
docker_userns_remap: ""
docker_icc: true
docker_live_restore: false
docker_no_new_privileges: false
docker_storage_driver: ""
```

**Ansible variable precedence:**

```
docker/defaults/main.yml:
  docker_userns_remap: "default"     ← priority 2

molecule group_vars/all:
  docker_userns_remap: ""            ← priority 4 (inventory group_vars) → ПОБЕЖДАЕТ
```

Group_vars из molecule inventory имеют priority 4, что выше role defaults (priority 2).
Overrides успешно перезаписывают CIS defaults.

**Урок:**

Docker CIS Benchmark defaults (`userns-remap`, `icc`, `no-new-privileges`) предполагают
production-ready Linux host с настроенными user namespaces. CI VMs (Vagrant on GitHub
Actions) не имеют этой настройки. Molecule group_vars — правильное место для CI-safe
overrides. Аналогичный паттерн уже используется в docker role's own molecule tests.

**Log-driver incompatibility:**

```
journald + {"max-size": "10m", "max-file": "3"}  ← INVALID
json-file + {"max-size": "10m", "max-file": "3"} ← VALID
journald + {}                                     ← VALID
```

`max-size` и `max-file` — log-opts, специфичные для `json-file` log driver. При
`log-driver: journald` Docker daemon не валидирует log-opts при записи daemon.json,
но **падает при перезапуске**. Ошибка silent: daemon.json записывается успешно
(JSON-валиден), но `systemctl restart docker` фейлит с "control process exited
with error code" без пояснения о невалидных log-opts.

---

### Инцидент #5 — Vagrant: handlers vaultwarden срабатывают без запущенных контейнеров

**Коммит фикса:** `13ac60f`
**CI-прогон:** четвёртый (run 22574485705, после commit `fdceff6`)
**Этап:** converge → handlers (end of play)
**Платформа:** arch-vm: `Reload caddy`; ubuntu-base: `Restart vaultwarden`

**Симптомы (два разных handler failures):**

**Arch-VM:**

```
RUNNING HANDLER [vaultwarden : Reload caddy] ***********************************
fatal: [arch-vm]: FAILED! => {
    "cmd": ["docker", "exec", "caddy", "caddy", "reload", "--config",
            "/etc/caddy/Caddyfile"],
    "stderr": "Error response from daemon: No such container: caddy"
}
```

Handler `Reload caddy` пытается `docker exec caddy` — но caddy контейнер не существует
(caddy_enabled: false).

**Ubuntu-base:**

```
RUNNING HANDLER [vaultwarden : Restart vaultwarden] ****************************
fatal: [ubuntu-base]: FAILED! => {
    "cmd": ["docker", "compose", "-f",
            "/opt/vaultwarden/docker-compose.yml", "restart"],
    "rc": 125,
    "stderr": "unknown shorthand flag: 'f' in -f\n\nUsage: docker [OPTIONS] COMMAND"
}
```

Handler `Restart vaultwarden` пытается `docker compose -f ...` — но `docker compose`
subcommand не установлен. Пакет `docker.io` на Ubuntu **не включает** Docker Compose V2
plugin.

**Расследование — почему handlers срабатывают:**

```
1. Task "Deploy Vaultwarden docker-compose.yml" (tasks/main.yml:89-98)
   → шаблон изменён (первый прогон) → notify: Restart vaultwarden

2. Task "Deploy Vaultwarden Caddy site config" (tasks/main.yml:102-111)
   → шаблон изменён (первый прогон) → notify: Reload caddy

3. Task "Start Vaultwarden containers" (tasks/main.yml:115-120)
   → tags: ['molecule-notest'] → SKIPPED (skip-tags: molecule-notest)

4. End of play → Ansible fires notified handlers
   → Restart vaultwarden: docker compose restart → FAILS
   → Reload caddy: docker exec caddy → FAILS
```

**Ключевая проблема:** Handlers в Ansible **не подчиняются `--skip-tags`**. Даже если
handler имеет тег `molecule-notest`, `--skip-tags: molecule-notest` **не предотвращает**
его запуск, если handler был notified.

Из Ansible documentation:

> "Handlers are executed based on notification. If a handler is notified,
> it will run regardless of its tags."

Это фундаментальное ограничение Ansible: `--skip-tags` фильтрует **tasks**, но **не
handlers**. Handler вызывается, если задача, которая его notified, выполнилась.

**Фикс — условные guards на handlers:**

```yaml
# handlers/main.yml (ПОСЛЕ):
- name: Restart vaultwarden
  ansible.builtin.command:
    cmd: docker compose -f {{ vaultwarden_base_dir }}/docker-compose.yml restart
  changed_when: true
  listen: Restart vaultwarden
  when:
    - ansible_facts['virtualization_type'] | default('') != 'docker'
    - vaultwarden_compose_manage | default(true)

- name: Reload caddy
  ansible.builtin.command:
    cmd: docker exec caddy caddy reload --config /etc/caddy/Caddyfile
  changed_when: true
  listen: Reload caddy
  when:
    - ansible_facts['virtualization_type'] | default('') != 'docker'
    - caddy_enabled | default(true)
```

**Два разных guard-механизма:**

| Handler | Guard | Источник переменной |
|---------|-------|-------------------|
| `Restart vaultwarden` | `vaultwarden_compose_manage \| default(true)` | Новая переменная, false в molecule group_vars |
| `Reload caddy` | `caddy_enabled \| default(true)` | Существующая переменная, уже false в molecule |

`caddy_enabled` уже установлена в `false` в molecule group_vars для обоих сценариев
(Docker и Vagrant). Дополнительных изменений для Reload caddy не нужно — достаточно
добавить условие в handler.

`vaultwarden_compose_manage` — новая переменная, аналогичная `docker_enable_service`
из docker роли. Паттерн проекта: handlers контролируются переменными, которые molecule
устанавливает в group_vars.

**Molecule group_vars (vagrant):**

```yaml
# molecule/vagrant/molecule.yml:
group_vars:
  all:
    caddy_enabled: false                    # Reload caddy → skipped
    vaultwarden_compose_manage: false       # Restart vaultwarden → skipped
```

**Ubuntu compose fix:**

Дополнительно добавлен `docker-compose-v2` в prepare.yml для Ubuntu:

```yaml
- name: Install Docker and prerequisites (Debian)
  ansible.builtin.apt:
    name:
      - docker.io
      - docker-compose-v2    # ← ДОБАВЛЕНО: docker.io не включает compose v2
```

Даже с guard'ом на handler, наличие `docker compose` subcommand необходимо для
полноценного тестирования роли в будущем (когда compose_manage будет true).

**Почему `docker.io` не включает compose:**

Ubuntu 24.04 предоставляет Docker через два канала:
- `docker.io` (universe) — Docker Engine CLI + daemon, **без** compose plugin
- `docker-compose-v2` (universe) — Docker Compose V2 CLI plugin

Arch Linux иначе:
- `docker` — Docker Engine
- `docker-compose` — включает compose plugin в `/usr/lib/docker/cli-plugins/`

Compose V2 устанавливается как CLI plugin в `/usr/lib/docker/cli-plugins/docker-compose`
и добавляет subcommand `docker compose` (без дефиса). Старый `docker-compose` (V1,
Python) — отдельная команда, deprecated.

---

## 4. Многослойная маскировка ошибок

```
Слой 1: Docker — meta deps запускают docker/caddy роли в контейнере
         ↓ фикс: include_role + virtualization_type guard
         ↓ раскрыл →

Слой 2: Vagrant syntax — community.docker collection отсутствует
         ↓ фикс: requirements.yml
         ↓ раскрыл →

Слой 3: Vagrant converge — Docker daemon не стартует (CIS defaults)
         ↓ фикс: CI-safe docker overrides в group_vars
         ↓ раскрыл →

Слой 4: Vagrant converge — handlers fire без запущенных контейнеров
         ↓ фикс: conditional guards + docker-compose-v2
         ↓ РЕШЕНО ✓
```

Четырёхслойная каскадная маскировка — каждый фикс раскрывал следующий слой ошибки.
Аналогичная структура наблюдалась в NTP CI (waitsync → sandboxing → handler order →
CA certs). Паттерн предсказуем для ролей с meta dependencies и сложной CI-средой.

**Временна́я шкала маскировки:**

| CI Run | Видимая ошибка | Скрытая за ней |
|--------|---------------|----------------|
| #1 | Docker: `Restart docker` in container | Vagrant syntax: community.docker |
| #2 | Vagrant: CIS daemon.json breaks Docker | Vagrant: handlers without containers |
| #3 | Vagrant: handlers fire (compose, caddy) | — (финальный слой) |
| #4 | ВСЁ ЗЕЛЁНОЕ ✓ | — |

---

## 5. Временная шкала

```
── Сессия (2026-03-02) ────────────────────────────────────────────────────────

[Начало]  Ветка fix/vaultwarden-molecule-overhaul (rebase на master)
          3 исходных коммита → rebase оставил 1 (af35929)

── Итерация 1: Базовые CI-фиксы ──────────────────────────────────────────────

b97e7b3  fix(vaultwarden): resolve 3 CI failures in molecule tests
         ↓ Docker: include_role в docker-specific converge.yml
         ↓ Vagrant: community.docker в requirements.yml
         ↓ Vagrant: ubuntu-base платформа + OS-conditional prepare
         ↓ Handlers: virtualization_type != 'docker' guard
         ↓ Verify: graceful container check skip
         ↓ 6 файлов (1 новый)

── CI run #1 (Docker ✓, Lint ✓, Vagrant ✗) ────────────────────────────────────

  Docker:    SUCCESS ✓
  Lint:      SUCCESS ✓
  Vagrant:   FAIL ✗ — обе платформы: "Unable to restart service docker"

  Анализ: CIS-hardened Docker defaults несовместимы с CI VM.

── Итерация 2: Docker daemon overrides ────────────────────────────────────────

fdceff6  fix(vaultwarden): add CI-safe docker overrides for vagrant tests
         ↓ group_vars: userns_remap, icc, live_restore, no_new_privileges
         ↓ group_vars: docker_log_driver: "json-file" (journald + max-size invalid)
         ↓ group_vars: docker_storage_driver: ""
         ↓ 1 файл: molecule/vagrant/molecule.yml

── CI run #2 (Docker ✓, Lint ✓, Vagrant ✗) ────────────────────────────────────

  Docker:    SUCCESS ✓
  Lint:      SUCCESS ✓
  Vagrant:   FAIL ✗ — arch: Reload caddy (no container)
                      ubuntu: Restart vaultwarden (compose not found)

  Анализ: Docker role проходит! Ошибка сместилась к vaultwarden handlers.
  Root cause: handlers не подчиняются --skip-tags.

── Итерация 3: Handler guards ─────────────────────────────────────────────────

13ac60f  fix(vaultwarden): guard handlers for molecule compatibility
         ↓ Restart vaultwarden: + vaultwarden_compose_manage | default(true)
         ↓ Reload caddy: + caddy_enabled | default(true)
         ↓ prepare.yml: + docker-compose-v2 (Ubuntu)
         ↓ molecule.yml: + vaultwarden_compose_manage: false
         ↓ 3 файла

── CI run #3 (ALL GREEN ✓) ────────────────────────────────────────────────────

  Docker:    SUCCESS ✓
  Lint:      SUCCESS ✓
  Vagrant:   SUCCESS ✓ (arch-vm + ubuntu-base)

── Завершение ─────────────────────────────────────────────────────────────────

  PR #35: squash-merged → master e49c968
  PR #59: closed (superseded by #35)
  Remote branch fix/vaultwarden-molecule-overhaul: deleted
  master: fast-forward pull
```

---

## 6. Финальная структура изменений

**Файлы изменённые (7, из них 1 новый):**

```
ansible/
├── requirements.yml                        ← + community.docker >= 3.0.0
└── roles/vaultwarden/
    ├── handlers/main.yml                   ← + vaultwarden_compose_manage guard
    │                                          + caddy_enabled guard
    ├── molecule/
    │   ├── docker/
    │   │   ├── converge.yml                ← НОВЫЙ: include_role (skip meta deps)
    │   │   └── molecule.yml                ← converge: converge.yml (не shared)
    │   ├── vagrant/
    │   │   ├── molecule.yml                ← + ubuntu-base platform
    │   │   │                                  + group_vars: CI-safe docker overrides
    │   │   │                                  + group_vars: compose_manage, caddy_enabled
    │   │   │                                  + skip-tags: report,molecule-notest
    │   │   └── prepare.yml                 ← + OS-conditional tasks (Arch + Debian)
    │   │                                      + docker-compose-v2 (Ubuntu)
    │   │                                      + caddy directory stubs
    │   │                                      + Docker proxy network
    │   └── shared/
    │       └── verify.yml                  ← + graceful container check skip
    └── (tasks/, defaults/, templates/ — без изменений)
```

**Файлы НЕ изменённые:**

```
tasks/main.yml              ← без изменений (tags molecule-notest сохранены)
defaults/main.yml           ← без изменений (vaultwarden_compose_manage не в defaults)
templates/*.j2              ← без изменений
meta/main.yml               ← без изменений (dependencies: docker, caddy)
molecule/docker/prepare.yml ← без изменений
molecule/shared/converge.yml ← без изменений (используется vagrant'ом)
```

---

## 7. Ключевые паттерны

### Handlers НЕ подчиняются `--skip-tags`

```
ПРАВИЛО: Ansible handlers выполняются если notified, НЕЗАВИСИМО от tags.

--skip-tags: molecule-notest

Task "Deploy docker-compose.yml"     → НЕТ тега molecule-notest → ВЫПОЛНЯЕТСЯ
                                     → notify: Restart vaultwarden
Task "Start Vaultwarden containers"  → ТЕГ molecule-notest → SKIPPED

Handler "Restart vaultwarden"        → NOTIFIED → ВЫПОЛНЯЕТСЯ (skip-tags не работает!)

РЕШЕНИЕ: условный guard через переменную на handler:
  when: vaultwarden_compose_manage | default(true)
```

Это фундаментальное ограничение Ansible. Единственный способ предотвратить выполнение
notified handler — условие `when:` на самом handler. Tags, skip-tags, и `--tags` на
handlers работают только для фильтрации include, не для skip.

### `include_role` vs `roles:` для meta dependency isolation

```yaml
# roles: → STATIC → обрабатывает meta/main.yml dependencies
roles:
  - role: vaultwarden    # → docker, caddy тоже выполнятся

# include_role → DYNAMIC → НЕ обрабатывает meta dependencies
tasks:
  - ansible.builtin.include_role:
      name: vaultwarden  # → ТОЛЬКО vaultwarden, без docker/caddy
```

Использовать `include_role` в Docker molecule scenario, `roles:` в Vagrant (где
зависимости могут реально выполняться).

### Docker log-driver + log-opts совместимость

```
json-file + {"max-size": "10m", "max-file": "3"}    ← VALID
journald  + {"max-size": "10m", "max-file": "3"}    ← INVALID (daemon won't start!)
journald  + {}                                       ← VALID
syslog    + {"max-size": "10m"}                      ← INVALID

ПРАВИЛО: max-size и max-file — log-opts ТОЛЬКО для json-file и local driver.
Docker daemon валидирует log-opts при СТАРТЕ, не при записи daemon.json.
```

### Проектный паттерн: handler guards через переменные

```yaml
# Паттерн из docker role (существующий):
- name: Restart docker
  listen: Restart docker
  when: docker_enable_service | default(true)

# Новый паттерн для vaultwarden:
- name: Restart vaultwarden
  listen: Restart vaultwarden
  when: vaultwarden_compose_manage | default(true)

# Caddy — использует существующую переменную:
- name: Reload caddy
  listen: Reload caddy
  when: caddy_enabled | default(true)
```

Molecule group_vars устанавливает guard-переменные в `false`, handler становится no-op.
Production не задаёт эти переменные → `default(true)` → handler выполняется.

### Ubuntu docker.io vs docker-compose-v2

```
ПАКЕТ                    ЧТО ДАЁТ                          COMPOSE SUBCOMMAND
docker.io (Ubuntu)       Docker Engine CLI + daemon          НЕТ
docker-compose-v2        Compose V2 CLI plugin               docker compose ✓
docker (Arch)            Docker Engine                       НЕТ
docker-compose (Arch)    Compose V2 binary + CLI plugin      docker compose ✓

ПРАВИЛО: На Ubuntu ВСЕГДА устанавливать docker-compose-v2 вместе с docker.io.
Arch docker-compose покрывает оба.
```

---

## 8. Сравнение с историей проекта

| Инцидент | Дата | Роль | Ошибка | Класс |
|----------|------|------|--------|-------|
| Docker hostname EPERM | 2026-02-24 | hostname | hostnamectl в контейнере | container restriction |
| Docker sysctl EPERM | 2026-03-01 | sysctl | handler sysctl --system | container restriction |
| NTP handler before verify | 2026-03-02 | ntp | handler fires end-of-play | handler timing |
| Teleport include_vars | 2026-03-02 | teleport | priority 18 > host_vars 10 | variable precedence |
| **Meta deps in Docker** | **2026-03-02** | **vaultwarden** | **roles: triggers docker/caddy** | **dependency isolation** |
| **CIS defaults break CI** | **2026-03-02** | **vaultwarden** | **daemon.json incompatible** | **config incompatibility** |
| **Handlers ignore skip-tags** | **2026-03-02** | **vaultwarden** | **notified = always fires** | **handler control** |
| **journald + max-size** | **2026-03-02** | **vaultwarden** | **invalid log-opts combo** | **config validation** |

**Новые классы ошибок:**

1. **dependency isolation** — meta deps запускают несовместимые роли в CI-среде.
   Решение: `include_role` вместо `roles:` в Docker scenario.

2. **handler control** — handlers не подчиняются `--skip-tags`, единственный способ
   контроля — `when:` condition на handler с guard-переменной.

3. **config validation** — Docker daemon.json принимает JSON с невалидными log-opts
   при записи, но daemon не стартует. Silent failure without clear error message.

**Рекуррентные классы:**

- **container restriction** (3-й случай) — действия, невозможные в Docker контейнере
- **config incompatibility** — production defaults несовместимы с CI среда

---

## 9. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | Handlers не подчиняются `--skip-tags`. Guard через `when:` + переменная — единственный способ | Все роли с handlers в molecule |
| 2 | `include_role` пропускает meta dependencies, `roles:` — нет. Docker molecule ДОЛЖЕН использовать `include_role` для ролей с meta deps | Роли с meta/main.yml dependencies |
| 3 | Docker CIS defaults (userns-remap, icc, no-new-privileges) несовместимы с CI VMs без настроенных user namespaces | Vagrant tests для ролей с docker dependency |
| 4 | `journald` log-driver не поддерживает `max-size`/`max-file` log-opts. Docker daemon молча принимает невалидный JSON, но не стартует | daemon.json configuration |
| 5 | Ubuntu `docker.io` не включает Docker Compose V2. Нужен отдельный пакет `docker-compose-v2` | Ubuntu-based molecule tests |
| 6 | `--syntax-check` парсит ВСЕ tasks включая условно пропускаемые. Collections должны быть установлены даже для skipped tasks | requirements.yml completeness |
| 7 | Каскадная маскировка — каждый слой ошибки виден только после фикса предыдущего. 4 слоя в этом инциденте | Debugging methodology |
| 8 | Guard-переменные для handlers (`compose_manage`, `enable_service`) — проектный паттерн. `default(true)` обеспечивает backward compatibility | Handler design pattern |
| 9 | Molecule group_vars (priority 4) > role defaults (priority 2). Безопасное место для CI overrides | Molecule variable management |
| 10 | OS-conditional prepare tasks (Arch pacman / Debian apt) — обязательный паттерн для multi-platform vagrant tests | Vagrant prepare.yml |

### Предложенный checklist для ролей с meta dependencies

```
□ Docker molecule: include_role (не roles:) в converge.yml
□ Vagrant molecule: roles: с group_vars overrides для CI-safe defaults
□ Handlers: when guard с переменной + caddy_enabled / service_manage
□ Docker overrides в group_vars: log-driver, userns-remap, icc, live-restore
□ Ubuntu prepare: docker-compose-v2 вместе с docker.io
□ requirements.yml: все collections используемые в dependency roles
□ OS-conditional prepare tasks для каждой платформы
□ Stub directories для disabled dependencies (caddy sites, etc.)
```

---

## 10. Known gaps (после фикса)

- **`vaultwarden_compose_manage` не в defaults/main.yml** — переменная используется
  только через `default(true)` в handler. Для документации и discoverability стоит
  добавить её в defaults с комментарием. Текущее поведение корректно.

- **Verify не тестирует actual container runtime** — контейнеры vaultwarden не
  запускаются в molecule (tagged molecule-notest). Verify проверяет конфигурацию
  (файлы, шаблоны, permissions), но не runtime (container health, HTTP endpoint).
  Для полного покрытия нужен отдельный integration test scenario.

- **Caddy config deployed but never validated** — task "Deploy Vaultwarden Caddy site
  config" создаёт файл, но caddy не запущен → файл не валидируется Caddy. Синтаксическая
  ошибка в `vault.caddy.j2` не будет поймана molecule.

- **Docker role handler guard не унифицирован** — docker role использует
  `docker_enable_service`, vaultwarden — `vaultwarden_compose_manage`, caddy —
  `caddy_enabled`. Три разных паттерна для одной задачи (skip handler in molecule).
  Можно унифицировать, но текущее состояние работает.
