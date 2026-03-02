# Post-Mortem: Teleport Molecule CI — реальный binary install вместо моков

**Дата:** 2026-03-02
**Статус:** Завершено — CI зелёный (Docker Arch + Ubuntu, Vagrant Arch + Ubuntu)
**Итерации CI:** 3 запуска, 2 уникальных ошибки (обе — в Docker)
**Коммиты:** 7 коммитов (3 фичи + 2 фикса + 1 WIP + 1 комментарии), squash-merged в `5c03534`
**PRs:** #58 merged, #45 closed (superseded)
**Ветка:** `ci/track-teleport`
**Скоуп:** 196 добавленных строк, 74 удалённых, 11 изменённых файлов

---

## 1. Задача

Переработать molecule-тесты роли `teleport` — заменить mock-подход реальной установкой
бинарного Teleport с CDN (`cdn.teleport.dev`), расширить verify.yml комплексными
assertions, исправить архитектурные проблемы роли (handler, variable precedence).

### Контекст: два конкурирующих PR

| PR | Ветка | Подход | Статус |
|----|-------|--------|--------|
| #45 `fix/teleport-molecule-overhaul` | Mock-бинарники в prepare.yml | Закрыт (superseded) |
| #58 `ci/track-teleport` | Реальная установка binary с CDN | Merged ✓ |

**Почему mock-подход был отвергнут:**

PR #45 создавал фиктивные бинарники в `prepare.yml`:

```yaml
# PR #45 — mock-подход (отвергнут):
- name: Create mock teleport binary
  ansible.builtin.copy:
    content: |
      #!/bin/bash
      echo "Teleport v{{ teleport_version }}"
    dest: /usr/local/bin/teleport
    mode: "0755"
```

Проблемы mock-подхода:
1. **Тест не проверяет реальную установку** — скачивание, распаковка, placement бинарника
   не тестируются. Мок скрывает баги в `tasks/install.yml`
2. **`teleport version` возвращает фейк** — verify.yml проверяет вывод мока, а не реального
   Teleport CLI
3. **Ложное чувство безопасности** — тест зелёный, но роль может быть сломана на production

**Принятый подход:** `teleport_install_method: binary` в molecule host_vars — реальное
скачивание tarball с `cdn.teleport.dev`, распаковка в `/usr/local/bin/`, создание
systemd unit file.

### Объём изменений — до и после

| Аспект | До (master) | После (PR #58) |
|--------|-------------|-----------------|
| verify.yml | 106 строк, 14 assertions | 309 строк, ~30 assertions |
| install.yml (binary block) | 3 таски (download, extract) | 6 тасок (stat check, versioned filename, download, extract, systemd unit, daemon-reload) |
| handler | Без tags, без listen | `tags: [teleport, service]` + `listen: "restart teleport"` |
| teleport_install_method | В `vars/{os}.yml` (priority 18) | В `defaults/main.yml` (priority 2) |
| teleport_version | `17.0.0` (не существует на CDN) | `17.4.10` (актуальная patch-версия) |
| Docker prepare | pacman cache + apt cache | + `ca-certificates` (Ubuntu) |
| Vagrant molecule.yml | `arch-vm: binary` (только Arch) | + `ubuntu-base: binary` |

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker | Archlinux-systemd, Ubuntu-systemd | Реальный binary install + config + systemd unit |
| Vagrant | arch-vm (KVM), ubuntu-base (KVM) | То же на полноценных VM с idempotence |

---

## 2. Инциденты

### Инцидент #1 — Docker Arch: `pacman --upgrade teleport-bin` вместо binary install

**Коммит фикса:** `c848719`
**CI-прогон:** первый (run 22568321463, commit `14484a5`)
**Этап:** `converge`
**Платформа:** Archlinux-systemd (Docker)

**Симптом:**

```
TASK [teleport : Install Teleport via package manager] *************************
fatal: [Archlinux-systemd]: FAILED! => {
  "changed": false,
  "cmd": ["/usr/bin/pacman", "--upgrade", "--print-format", "%n", "teleport-bin"],
  "msg": "Failed to list package teleport-bin",
  "rc": 1,
  "stderr": "error: 'teleport-bin': could not find or read package\n"
}
```

Molecule host_vars задавали `teleport_install_method: binary`, но роль выполняла
`ansible.builtin.package: teleport-bin` (ветка `package`, не `binary`). Переменная
`teleport_install_method` из host_vars **игнорировалась**.

**Расследование — Ansible Variable Precedence:**

Роль использовала `include_vars` в `tasks/main.yml` для загрузки OS-специфичных переменных:

```yaml
# tasks/main.yml:
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
```

Файл `vars/archlinux.yml` содержал:

```yaml
teleport_install_method: package
teleport_packages:
  - teleport-bin
```

**Ansible variable precedence** (из документации, от низшего к высшему):

```
Priority  2: role defaults/main.yml
Priority  8: inventory host_vars (файловые)
Priority 10: play host_vars (molecule provisioner.inventory.host_vars)
Priority 18: include_vars (задача в tasks/)
```

`include_vars` (priority 18) **безусловно перезаписывал** molecule host_vars (priority 10).
Значение `teleport_install_method: package` из `vars/archlinux.yml` побеждало
`teleport_install_method: binary` из molecule.yml, **независимо от того, что написано
в molecule host_vars**.

```
molecule.yml host_vars:
  Archlinux-systemd:
    teleport_install_method: binary    ← priority 10

include_vars: archlinux.yml
  teleport_install_method: package     ← priority 18 → ПОБЕЖДАЕТ
```

**Аналогичная ситуация на Ubuntu:**

`vars/debian.yml` не содержал `teleport_install_method` до PR #58, но содержал бы
если бы был добавлен — та же ошибка проявилась бы.

**Почему ранее не замечалось:**

На master molecule host_vars Arch задавали `teleport_install_method: binary`, но
`include_vars: archlinux.yml` перезаписывал на `package`. Тест проходил потому что
`package` path (`pacman -S teleport-bin`) не выполнялся — на Docker Arch AUR-пакеты
недоступны, и **тест падал на другом шаге** (или mock маскировал проблему).

**Фикс — архитектурное решение:**

Перенести `teleport_install_method` из `vars/{os}.yml` (priority 18) в `defaults/main.yml`
(priority 2) с computed default:

```yaml
# defaults/main.yml (priority 2):
teleport_install_method: >-
  {{ {'Archlinux': 'package', 'Debian': 'repo', 'RedHat': 'repo'}[ansible_facts['os_family']]
     | default('binary') }}
```

Удалить `teleport_install_method` из всех `vars/{os}.yml` файлов:

```
vars/archlinux.yml  ← удалена строка teleport_install_method: package
vars/debian.yml     ← удалена строка teleport_install_method: repo
vars/redhat.yml     ← удалена строка teleport_install_method: repo
vars/void.yml       ← не содержал (binary — default)
vars/gentoo.yml     ← не содержал (binary — default)
```

**Новая цепочка приоритетов:**

```
defaults/main.yml:
  teleport_install_method: {{ computed }}    ← priority 2

molecule host_vars:
  teleport_install_method: binary            ← priority 10 → ПОБЕЖДАЕТ

include_vars: archlinux.yml
  (не содержит teleport_install_method)      ← ничего не перезаписывает
```

**Computed default работает через Jinja2 lazy evaluation:**

На production (без molecule host_vars override):
- Arch: `{'Archlinux': 'package'}['Archlinux']` → `package`
- Debian: `{'Debian': 'repo'}['Debian']` → `repo`
- Void: `default('binary')` → `binary`

В molecule (с host_vars override):
- Любая ОС: `teleport_install_method: binary` из host_vars (priority 10) побеждает
  defaults (priority 2)

**Урок:**

Переменные, которые molecule должен переопределять через host_vars, **не должны** быть
в `vars/` (priority 18, через `include_vars`). Единственное безопасное место — `defaults/`
(priority 2). Это фундаментальное ограничение Ansible variable precedence.

**Быстрая таблица для принятия решения:**

| Переменная | molecule может менять? | Место |
|------------|----------------------|-------|
| `teleport_packages` | Нет (OS-fixed) | `vars/{os}.yml` ✓ |
| `teleport_service_name` | Нет (OS-fixed) | `vars/{os}.yml` ✓ |
| `teleport_install_method` | Да (binary в CI) | `defaults/main.yml` ✓ |
| `teleport_version` | Да (тестовая версия) | `defaults/main.yml` ✓ |

---

### Инцидент #2 — Docker Arch + Ubuntu: HTTP 404 для `teleport-v17.0.0`

**Коммит фикса:** `bc833ef`
**CI-прогон:** второй (run 22568492123, commit `c848719`)
**Этап:** `converge` → `install.yml` → binary download
**Платформа:** Обе (Archlinux-systemd + Ubuntu-systemd)

**Симптом:**

```
TASK [teleport : Download Teleport binary] *************************************
fatal: [Ubuntu-systemd]: FAILED! => {
  "changed": false,
  "dest": "/tmp/teleport-17.0.0-amd64.tar.gz",
  "elapsed": 0,
  "msg": "Request failed",
  "response": "HTTP Error 404: Not Found",
  "status_code": 404,
  "url": "https://cdn.teleport.dev/teleport-v17.0.0-linux-amd64-bin.tar.gz"
}

fatal: [Archlinux-systemd]: FAILED! => {
  "changed": false,
  "dest": "/tmp/teleport-17.0.0-amd64.tar.gz",
  "elapsed": 0,
  "msg": "Request failed",
  "response": "HTTP Error 404: Not Found",
  "status_code": 404,
  "url": "https://cdn.teleport.dev/teleport-v17.0.0-linux-amd64-bin.tar.gz"
}
```

**Причина:**

`defaults/main.yml` содержал `teleport_version: "17.0.0"`. Версия v17.0.0 **не
существует** на Teleport CDN как downloadable binary tarball. Teleport использует
semver, и первый релиз серии v17 был **v17.0.1** или позже.

Инцидент #1 маскировал эту ошибку: на master роль не доходила до binary download
(Arch использовал `package` path, Ubuntu — `repo` path). Binary path тестировался
только если host_vars override работал — а он не работал (инцидент #1).

**Расследование:**

Проверка доступности версий на CDN:

```bash
# 17.0.0 — не существует:
curl -sI https://cdn.teleport.dev/teleport-v17.0.0-linux-amd64-bin.tar.gz
# → HTTP 404

# 17.4.10 — существует (актуальный patch):
curl -sI https://cdn.teleport.dev/teleport-v17.4.10-linux-amd64-bin.tar.gz
# → HTTP 200, Content-Length: ~150MB
```

**Почему 17.0.0:**

Вероятно, при первоначальном создании роли была указана "плановая" версия v17.0.0
без проверки её доступности на CDN. Teleport releases на GitHub начинаются с v17.0.1
или v17.1.0 (точный первый release зависит от ветки).

**Фикс:**

```yaml
# defaults/main.yml:
# БЫЛО:
teleport_version: "17.0.0"
# СТАЛО:
teleport_version: "17.4.10"
```

v17.4.10 — последний patch-релиз серии v17 на момент фикса (март 2026).

**Урок:**

При указании версии ПО в defaults — всегда проверять доступность tarball на CDN/GitHub
Releases. Версия `X.0.0` часто не существует как downloadable artifact: CI/CD pipelines
некоторых проектов (включая Teleport) не собирают binary tarballs для "нулевых" релизов
или начинают с X.0.1.

**Второй урок — маскирование ошибок:**

Инцидент #1 (variable precedence) маскировал инцидент #2 (несуществующая версия). Пока
binary path не выполнялся, 404 не мог проявиться. Только после исправления precedence
binary path стал достижим, и скрытая ошибка всплыла.

Это повторяет паттерн "многослойных багов" из post-mortem NTP CI (2026-03-02): каждый
следующий слой виден только после фикса предыдущего.

---

## 3. Архитектурные улучшения (не инциденты)

### 3.1 Handler — tags и listen directive

**Файл:** `handlers/main.yml`

**До:**

```yaml
- name: "Restart teleport"
  ansible.builtin.service:
    name: "{{ teleport_service_name[...] }}"
    state: restarted
```

**После:**

```yaml
- name: "Restart teleport"
  ansible.builtin.service:
    name: "{{ teleport_service_name[...] }}"
    state: restarted
  tags: [teleport, service]
  listen: "restart teleport"
```

**Зачем `tags: [teleport, service]`:**

Molecule provisioner задаёт `skip-tags: report,service`. Без тега `service` на handler'е
Ansible 2.17+ может запустить handler даже при `skip-tags: service` — handler вызывается
через `notify`, и skip-tags на задачах не распространяется автоматически на handler'ы.
Добавление `tags: [service]` на handler гарантирует его пропуск при `skip-tags: service`.

В molecule тестах teleport service не может стартовать — нет auth cluster. Попытка
`systemctl restart teleport` всегда завершится ошибкой. Тег `service` предотвращает
этот крах.

**Зачем `listen: "restart teleport"`:**

Проектное соглашение (см. NTP, SSH, fail2ban роли). `listen:` позволяет другим ролям
нотифицировать handler по каноническому имени `"restart teleport"` без hard-coupling
к имени handler'а. Паттерн: `name:` с заглавной (Restart), `listen:` со строчной
(restart) — для совместимости с обоими стилями notify.

### 3.2 install.yml — binary install path

**До (3 таски):**

```yaml
- name: "Download Teleport binary"
  ansible.builtin.get_url:
    url: "https://cdn.teleport.dev/teleport-v{{ teleport_version }}-linux-..."
    dest: "/tmp/teleport.tar.gz"       # ← неверсированное имя
    mode: "0644"

- name: "Extract Teleport binary"
  ansible.builtin.unarchive:
    src: "/tmp/teleport.tar.gz"
    dest: /usr/local/bin/
    remote_src: true
    extra_opts: [--strip-components=1]
  # ← нет stat check: скачивает КАЖДЫЙ раз
  # ← нет systemd unit: service не может стартовать
```

**После (6 тасок):**

```yaml
- name: "Set architecture mapping for Teleport download"
  # x86_64 → amd64, aarch64 → arm64

- name: "Check if teleport binary already installed"
  ansible.builtin.stat:
    path: /usr/local/bin/teleport
  register: _teleport_binary_stat
  # ← stat check: пропускает download/extract если бинарник уже есть

- name: "Download Teleport binary"
  ansible.builtin.get_url:
    dest: "/tmp/teleport-{{ teleport_version }}-{{ teleport_arch }}.tar.gz"
    # ← версированное имя: не перезаписывает при upgrade
  when: not _teleport_binary_stat.stat.exists

- name: "Extract Teleport binary"
  when: not _teleport_binary_stat.stat.exists

- name: "Deploy teleport systemd unit for binary install"
  ansible.builtin.copy:
    content: |
      [Unit]
      Description=Teleport SSH Access Platform
      After=network.target
      [Service]
      Type=simple
      ExecStart=/usr/local/bin/teleport start --config=/etc/teleport.yaml
      Restart=on-failure
      RestartSec=5
      [Install]
      WantedBy=multi-user.target
    dest: /etc/systemd/system/teleport.service
    mode: "0644"
  when: ansible_facts['service_mgr'] == 'systemd'
  register: _teleport_unit_result

- name: "Reload systemd daemon after unit file change"
  ansible.builtin.systemd:
    daemon_reload: true
  when:
    - ansible_facts['service_mgr'] == 'systemd'
    - _teleport_unit_result is changed
```

**Улучшения:**

1. **Stat check** — идемпотентность: не скачивает 150MB tarball при каждом converge
2. **Версированное имя файла** — `/tmp/teleport-17.4.10-amd64.tar.gz` вместо
   `/tmp/teleport.tar.gz`. Предотвращает конфликты при upgrade
3. **Systemd unit file** — без него `systemctl start teleport` невозможен. Ранее
   binary path не создавал unit (только `package` и `repo` path устанавливают его
   через пакетный менеджер)
4. **daemon-reload** — только при изменении unit file (idempotent)

### 3.3 Docker prepare — ca-certificates для Ubuntu

**До:**

```yaml
- name: Update pacman package cache (Arch)
- name: Update apt cache (Ubuntu)
```

**После:**

```yaml
- name: Update pacman package cache (Arch)
- name: Update apt cache (Ubuntu)
- name: Install ca-certificates (Ubuntu)    # ← НОВОЕ
```

**Зачем:**

`get_url` для скачивания tarball с `cdn.teleport.dev` использует HTTPS. Минимальные
Ubuntu Docker-образы (`ghcr.io/textyre/ubuntu-base:latest`) **не содержат**
`ca-certificates`. Без них SSL verification падает:

```
SSL: CERTIFICATE_VERIFY_FAILED
```

Аналогичная проблема была в NTP CI (инцидент #5) — chrony NTS TLS handshake требовал
CA certificates. Это рекуррентный паттерн для Ubuntu Docker-образов.

**Почему в prepare, а не в роли:**

Роль `teleport` не должна устанавливать CA certificates — это ответственность базового
образа или роли `base_system`. В Docker prepare компенсируем минимальность образа.

### 3.4 verify.yml — комплексная переработка

**До (14 assertions, 106 строк):**

```
1. Binary: which teleport, teleport version
2. Config: exists, owner/mode, content (substring matches)
3. Data dir: exists, owner/mode
4. Service enabled (non-Docker)
5. Diagnostic notes
```

**После (~30 assertions, 309 строк):**

```
1. Binary:
   - command -v teleport (POSIX, не which)
   - Assert path = /usr/local/bin/teleport (binary install specific)
   - teleport version → rc 0 + содержит "Teleport"

2. Config existence + permissions:
   - stat → exists + owner root + group root + mode 0600

3. Config content (anchored regex, не substring):
   - Ansible managed header (regex)
   - version: v3 (anchored: ^version:\s+v3$)
   - nodename: molecule-test (anchored)
   - data_dir: /var/lib/teleport (anchored)
   - auth_token: non-empty (regex \S+)
   - auth_server: localhost:3025 (anchored)
   - ssh_service: + enabled: true
   - proxy_service:
   - auth_service:
   - session recording mode: node (anchored)

4. Data directory:
   - exists + isdir + owner root + group root + mode 0750

5. Systemd unit file (binary install):
   - exists + isreg + mode 0644
   - [Unit] section
   - Description=Teleport
   - ExecStart=/usr/local/bin/teleport start --config=/etc/teleport.yaml
   - [Install] + WantedBy=multi-user.target

6. Diagnostic notes:
   - Service start skipped (no auth cluster)
   - CA export not tested (requires tctl)
```

**Ключевые отличия:**

| Аспект | До | После |
|--------|-----|-------|
| Binary path assertion | Нет | `/usr/local/bin/teleport` |
| `which` vs `command -v` | `which` (не POSIX) | `command -v` (POSIX, shell builtin) |
| Config content matching | Substring (`'version: v3' in content`) | Anchored regex (`(?m)^version:\s+v3\s*$`) |
| Systemd unit verification | Нет | Полная: structure + ExecStart path + WantedBy |
| Assertions count | ~14 | ~30 |

**Почему `command -v` вместо `which`:**

`which` — внешняя команда, не POSIX-стандарт. На некоторых minimal-образах отсутствует
(Ubuntu minimal не имеет `which` по умолчанию, только `command -v` как shell builtin).
`command -v` — POSIX builtin, работает везде. Требует `executable: /bin/bash` в task
(shell module, не command).

**Почему anchored regex вместо substring:**

Substring match `'version: v3' in content` совпадёт с `# old version: v3.1` в комментарии
или `my_version: v3` в другом контексте. Anchored regex `(?m)^version:\s+v3\s*$`
гарантирует совпадение только с начала строки, с whitespace-гибкостью, до конца строки.

---

## 4. Временная шкала

```
── Сессия (2026-03-02) ────────────────────────────────────────────────────────

[Создан worktree]  .worktrees/teleport-fix на ветке ci/track-teleport
                   (ветка уже существовала от WIP-коммита ccbe094)

3e1f634      fix(teleport): tag handler with [service], add listen directive
             ↓ handler: tags: [teleport, service] + listen: "restart teleport"
             ↓ 1 файл: handlers/main.yml

5ccb03c      fix(teleport): add stat check, versioned filename, systemd unit for binary install
             ↓ install.yml: stat check + versioned tarball + systemd unit + daemon-reload
             ↓ 1 файл: tasks/install.yml (+40 строк)

32c78c7      fix(teleport): add ca-certificates to Docker prepare, binary install for vagrant ubuntu
             ↓ Docker prepare: ca-certificates для Ubuntu
             ↓ Vagrant molecule.yml: ubuntu-base: teleport_install_method: binary
             ↓ 2 файла: molecule/docker/prepare.yml, molecule/vagrant/molecule.yml

ceb7c3a      test(teleport): rewrite verify.yml with comprehensive artifact assertions
             ↓ Полная переработка verify.yml: ~30 assertions, 6 секций
             ↓ 1 файл: molecule/shared/verify.yml (+207, -74)

14484a5      chore(teleport): add binary-install-only comments to verify.yml
             ↓ Комментарии: NOTE о binary install path
             ↓ 1 файл: molecule/shared/verify.yml

── CI run #1 (run 22568321463, commit 14484a5) ────────────────────────────────

  Ansible Lint:        SUCCESS ✓
  Molecule Docker:     FAIL ✗ — Arch: pacman --upgrade teleport-bin (Инцидент #1)
  Molecule Vagrant:    FAIL ✗ (аналогичная ошибка на arch-vm)

  Анализ: include_vars priority 18 > host_vars priority 10.
  teleport_install_method из vars/archlinux.yml перезаписывает molecule host_vars.

c848719      fix(teleport): move install_method from vars/ to defaults/ (variable precedence fix)
             ↓ defaults/main.yml: computed teleport_install_method (priority 2)
             ↓ Удалено из: vars/archlinux.yml, vars/debian.yml, vars/redhat.yml,
             ↓              vars/void.yml, vars/gentoo.yml
             ↓ 6 файлов изменено

── CI run #2 (run 22568492123, commit c848719) ────────────────────────────────

  Ansible Lint:        SUCCESS ✓
  Molecule Docker:     FAIL ✗ — обе платформы: HTTP 404 cdn.teleport.dev/v17.0.0
  Molecule Vagrant:    CANCELLED (Arch pass, Ubuntu — cancelled из-за Docker fail)

  Анализ: teleport_version: "17.0.0" — версия не существует на CDN.
  Проверка: curl -sI → 404 для 17.0.0, 200 для 17.4.10.

bc833ef      fix(teleport): update version to 17.4.10 (17.0.0 does not exist on CDN)
             ↓ defaults/main.yml: teleport_version: "17.4.10"
             ↓ 1 файл

── CI run #3 (run 22568595890/916/891, commit bc833ef) ────────────────────────

  Ansible Lint:        SUCCESS ✓ (2m10s)
  YAML Lint & Syntax:  SUCCESS ✓ (23s)
  Detect changed roles: SUCCESS ✓ (6s)
  Detect vagrant roles: SUCCESS ✓ (5s)
  Molecule Docker:     SUCCESS ✓ (1m50s)
  Vagrant arch:        SUCCESS ✓ (4m23s)
  Vagrant ubuntu:      SUCCESS ✓ (3m41s)

  ALL 7/7 CHECKS GREEN ✓

── Завершение ──────────────────────────────────────────────────────────────────

  PR #45: closed (superseded by #58)
  PR #58: squash-merged → master 5c03534
  Remote branch ci/track-teleport: deleted
  Worktree .worktrees/teleport-fix: removed
  master: fast-forward pull to 5c03534
```

---

## 5. Финальная структура изменений

**Файлы изменённые (11):**

```
ansible/roles/teleport/
├── defaults/main.yml           ← + computed teleport_install_method (priority 2)
│                                  + teleport_version 17.0.0→17.4.10
├── handlers/main.yml           ← + tags: [teleport, service]
│                                  + listen: "restart teleport"
├── tasks/install.yml           ← binary block: +stat check, versioned filename,
│                                  systemd unit, daemon-reload (+40 строк)
├── vars/
│   ├── archlinux.yml           ← − teleport_install_method: package
│   ├── debian.yml              ← − teleport_install_method: repo
│   ├── redhat.yml              ← − teleport_install_method: repo
│   ├── void.yml                ← − (не содержал, но gentoo содержал)
│   └── gentoo.yml              ← − teleport_install_method: binary
└── molecule/
    ├── docker/
    │   └── prepare.yml         ← + ca-certificates (Ubuntu)
    ├── vagrant/
    │   └── molecule.yml        ← + ubuntu-base: teleport_install_method: binary
    └── shared/
        └── verify.yml          ← полная переработка: 106→309 строк, 14→30 assertions
```

**Файлы НЕ изменённые:**

```
tasks/main.yml                  ← без изменений (include_vars, config deploy)
templates/teleport.yaml.j2      ← шаблон конфига — без изменений
molecule/docker/molecule.yml    ← host_vars уже содержали binary (не менялись)
molecule/shared/converge.yml    ← роль vars (auth_server, token) — без изменений
molecule/vagrant/prepare.yml    ← apt cache only — без изменений
```

---

## 6. Ключевые паттерны

### Ansible Variable Precedence и Molecule

```yaml
# ПРАВИЛО: переменные, которые molecule должен переопределять,
# ДОЛЖНЫ быть в defaults/ (priority 2), НЕ в vars/ (priority 18)

# НЕПРАВИЛЬНО — vars/{os}.yml:
# include_vars (priority 18) > host_vars (priority 10)
# molecule host_vars ИГНОРИРУЮТСЯ
teleport_install_method: package    # в vars/archlinux.yml → priority 18

# ПРАВИЛЬНО — defaults/main.yml:
# defaults (priority 2) < host_vars (priority 10)
# molecule host_vars ПОБЕЖДАЮТ
teleport_install_method: >-         # в defaults/main.yml → priority 2
  {{ {'Archlinux': 'package', ...}[ansible_facts['os_family']]
     | default('binary') }}
```

**Таблица приоритетов (полная):**

| Priority | Source | Кто задаёт |
|----------|--------|------------|
| 2 | `defaults/main.yml` | Автор роли |
| 8-10 | Inventory / play host_vars | Molecule provisioner |
| 14 | Role vars (`vars/main.yml`) | Автор роли |
| 18 | `include_vars` task | Автор роли (runtime) |
| 22 | Extra vars (`-e`) | CLI / pipeline |

### CDN version verification

```bash
# ВСЕГДА проверять доступность tarball перед указанием версии:
curl -sI "https://cdn.teleport.dev/teleport-v${VERSION}-linux-amd64-bin.tar.gz" | head -1

# HTTP/2 200 → версия существует
# HTTP/2 404 → версия НЕ существует — не указывать в defaults
```

### Stat check для binary install idempotence

```yaml
# ПАТТЕРН: stat → download when not exists → extract when not exists

- name: Check if binary already installed
  ansible.builtin.stat:
    path: /usr/local/bin/teleport
  register: _binary_stat

- name: Download
  ansible.builtin.get_url:
    url: "..."
    dest: "/tmp/teleport-{{ version }}-{{ arch }}.tar.gz"   # версированное имя!
  when: not _binary_stat.stat.exists

- name: Extract
  ansible.builtin.unarchive:
    src: "/tmp/teleport-{{ version }}-{{ arch }}.tar.gz"
    dest: /usr/local/bin/
  when: not _binary_stat.stat.exists
```

**Версированное имя файла** (`teleport-17.4.10-amd64.tar.gz` вместо `teleport.tar.gz`)
предотвращает перезапись при upgrade — старый tarball остаётся для rollback.

### `command -v` вместо `which` для проверки бинарников

```yaml
# НЕПРАВИЛЬНО (не POSIX, может отсутствовать):
- ansible.builtin.command: which teleport

# ПРАВИЛЬНО (POSIX shell builtin, работает везде):
- ansible.builtin.shell:
    cmd: command -v teleport
    executable: /bin/bash
```

### ca-certificates для HTTPS в минимальных Docker-образах

```yaml
# ПАТТЕРН для Docker prepare.yml любой роли, скачивающей по HTTPS:
- name: Install ca-certificates (Debian — required for HTTPS downloads)
  ansible.builtin.apt:
    name: ca-certificates
    state: present
  when: ansible_facts['os_family'] == 'Debian'
```

---

## 7. Сравнение с историей проекта

| Инцидент | Дата | Роль | Ошибка | Класс |
|----------|------|------|--------|-------|
| Docker hostname EPERM | 2026-02-24 | hostname | hostnamectl в контейнере | container restriction |
| Docker sysctl EPERM | 2026-03-01 | sysctl | handler sysctl --system | container restriction |
| Docker chrony sandboxing | 2026-03-02 | ntp | Ubuntu ProtectSystem=strict | container restriction |
| NTS без CA certs | 2026-03-02 | ntp | TLS handshake silent fail | missing dependency |
| Handler before verify | 2026-03-02 | ntp | handler fires end-of-play | execution order |
| **include_vars vs host_vars** | **2026-03-02** | **teleport** | **priority 18 > 10** | **variable precedence** |
| **CDN 404 — версия не существует** | **2026-03-02** | **teleport** | **teleport-v17.0.0 отсутствует** | **phantom version** |
| **Ubuntu Docker без ca-certificates** | **2026-03-02** | **teleport** | **HTTPS download fails** | **missing dependency** |

**Новый класс ошибок: "variable precedence"** — `include_vars` (priority 18) перебивает
molecule host_vars (priority 10). Ранее не встречался в проекте. Потенциально затрагивает
любую роль, использующую `include_vars` для OS-специфичных переменных, если molecule
пытается переопределить эти переменные через host_vars.

**Новый класс ошибок: "phantom version"** — указание несуществующей версии ПО в defaults.
Ошибка была скрыта, потому что binary path никогда не выполнялся (variable precedence
маскировала его).

**Рекуррентный класс: "missing dependency"** — третий инцидент с `ca-certificates` в
Ubuntu Docker (после NTP и теперь teleport). Паттерн предсказуем: любая роль,
скачивающая по HTTPS или использующая TLS в Ubuntu Docker, нуждается в `ca-certificates`
в prepare.

### Многослойная маскировка

```
Слой 1: Variable precedence — binary path не выполняется (package path вместо binary)
         ↓ фикс: defaults/ вместо vars/
         ↓ раскрыл →

Слой 2: Phantom version — CDN 404 для v17.0.0
         ↓ фикс: 17.0.0 → 17.4.10
         ↓ РЕШЕНО ✓
```

Двухслойная маскировка, аналогичная четырёхслойной в NTP CI (waitsync → sandboxing →
handler order → CA certs). Общий принцип: каждый следующий слой виден только после
фикса предыдущего.

---

## 8. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `include_vars` (priority 18) безусловно перебивает molecule host_vars (priority 10). Переменные для molecule override — только в `defaults/` (priority 2) | Все роли с `include_vars` + molecule |
| 2 | Computed defaults через Jinja2 (`{{ dict[key] \| default('fallback') }}`) безопасны в defaults/ — lazy evaluation, вычисляется при каждом обращении | Pattern для OS-specific defaults |
| 3 | Версия ПО в defaults должна быть проверена на CDN перед фиксацией. `X.0.0` часто не существует | Любая роль с binary download path |
| 4 | Многослойные баги маскируют друг друга — precedence скрывала phantom version | Debugging methodology |
| 5 | Mock-бинарники в molecule — антипаттерн. Реальная установка проверяет download, extract, placement, permissions | Molecule testing strategy |
| 6 | Stat check перед download — idempotence без лишнего трафика (150MB tarball) | Binary install roles |
| 7 | Systemd unit file необходим для binary install path — пакетный менеджер создаёт его автоматически, binary — нет | Any binary-install role |
| 8 | `command -v` (POSIX builtin) надёжнее `which` (может отсутствовать) | Verify playbooks |
| 9 | Handler tags `[service]` предотвращают крах handler при `skip-tags: service` | Roles tested without service start |
| 10 | `listen:` directive на handler'ах — проектное соглашение для cross-role notify | All roles with handlers |
| 11 | `ca-certificates` обязателен для HTTPS в Ubuntu Docker-образах (рекуррентный паттерн) | Docker prepare for any HTTPS/TLS role |
| 12 | Версированное имя tarball (`teleport-17.4.10-amd64.tar.gz`) предотвращает конфликты при upgrade | Binary download tasks |

---

## 9. Процессные наблюдения

### Что прошло хорошо

- **2 CI-итерации до зелёного** — каждая ошибка уникальная, фикс точечный (1 коммит
  на ошибку)
- **Переработка verify.yml** — с 14 до 30 assertions, anchored regex вместо substring
  match, полное покрытие systemd unit file
- **Архитектурное решение по precedence** — computed default в `defaults/` вместо
  хака с extra vars или другим workaround
- **Параллельная работа** — Ansible Lint, Docker, Vagrant workflows запускались
  одновременно; Vagrant прошёл с первого раза
- **Superseding PR #45** — решение закрыть mock-подход и сделать заново с реальной
  установкой оказалось правильным

### Что можно улучшить

- **Не была проверена версия 17.0.0 на CDN до первого push** — один `curl -sI` мог
  сэкономить целую CI-итерацию (~3 минуты ожидания)
- **Variable precedence не была проанализирована заранее** — при создании molecule
  host_vars можно было проверить, что `include_vars` не перезаписывает значение.
  Команда `ansible-config dump` или чтение `vars/` файлов показала бы конфликт

### Предложенный checklist для новых ролей с binary install

```
□ Проверить версию ПО на CDN/GitHub Releases (curl -sI URL)
□ Переменные для molecule override — в defaults/ (не vars/)
□ include_vars файлы — не содержат переменных, переопределяемых molecule
□ Stat check перед download (idempotence)
□ Версированное имя tarball (не /tmp/tool.tar.gz)
□ Systemd unit file для binary install
□ ca-certificates в Docker prepare (Ubuntu)
□ command -v вместо which в verify
□ Handler: tags + listen directive
□ Anchored regex в config assertions (не substring)
```

---

## 10. Known gaps (после фикса)

- **Stat check по существованию, не по версии** — `stat /usr/local/bin/teleport` проверяет
  наличие бинарника, но не его версию. При upgrade с 17.4.10 на 18.x.x бинарник уже
  существует → download пропускается. Для production нужен `teleport version | grep`
  с сравнением версий. Оставлено для отдельного PR (scope creep).

- **Hardcoded binary path** — `/usr/local/bin/teleport` прописан в install.yml, verify.yml,
  и systemd unit. Для переносимости нужна переменная `teleport_binary_path`. Текущее
  значение canonical для CDN tarball → `extra_opts: [--strip-components=1]` экстрактит
  прямо в `/usr/local/bin/`.

- **Systemd unit file — minimal** — unit содержит минимальный набор (`Type=simple`,
  `Restart=on-failure`, `RestartSec=5`). Production unit может нуждаться в sandboxing
  (`ProtectSystem=strict`, etc.), `LimitNOFILE`, `TimeoutStartSec`. Текущий unit
  достаточен для molecule тестов и базового production.

- **Vagrant ubuntu-base: apt repo path не тестируется** — Vagrant ubuntu-base использует
  `teleport_install_method: binary`, не `repo`. APT repo path (`repo`) тестируется
  неявно через `defaults/main.yml` computed default, но фактически не выполняется ни
  в одном molecule сценарии. Для покрытия `repo` path нужен отдельный Vagrant scenario
  или Docker платформа без host_vars override.
