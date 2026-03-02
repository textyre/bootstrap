# Troubleshooting History — 2026-03-01

## Post-Mortem: hostctl CI v2 — три скрытых бага, один за другим

### Контекст

**PR:** https://github.com/textyre/bootstrap/pull/25 (`fix/hostctl-molecule-overhaul`)
**Задача:** обеспечить зелёный CI для роли `hostctl` — Docker и Vagrant тесты.
**Исходное состояние:** 2 failing checks из 7.
**Итог:** 4 коммита, все 7 checks зелёные.

---

## Хронология

```
Commit f670650  fix(hostctl): resolve Docker Ubuntu SSL and Vagrant Arch ACL failures
                ├─ docker/prepare.yml: apt install ca-certificates + update-ca-certificates
                └─ vagrant/molecule.yml: skip-tags: report,aur → report,aur,molecule-notest

                CI запуск 22550825224:
                └─ hostctl (test-docker)  ✓ PASS

                CI запуск 22550825205:
                └─ hostctl (test-vagrant/arch)   ✗ FAIL (box add — новый баг в workflow!)
                └─ hostctl (test-vagrant/ubuntu) ✗ FAIL (box add — тот же)
                └─ user (test-vagrant/arch)      ✗ FAIL (box add — регресс на user)
                └─ user (test-vagrant/ubuntu)    ✗ FAIL (box add — регресс на user)

Commit 891c261  fix(ci): fix vagrant box add idempotence and sync workflow to master version
                └─ molecule-vagrant.yml: id: box-cache + idempotent box add

                → не триггерит новый CI (pull_request trigger был только в старой
                  версии файла на PR ветке, GitHub смотрит HEAD PR для триггеров)

Commit 10a0d86  merge: resolve molecule-vagrant.yml conflict — keep id: box-cache fix
                └─ merge origin/master, принимаем нашу версию workflow

                CI запуск 22551058520:
                └─ hostctl (test-vagrant/arch)   ✓ PASS
                └─ hostctl (test-vagrant/ubuntu) ✓ PASS

Финальный статус: все 7 checks ✓
```

---

## Решено

- [x] **Docker Ubuntu — SSL cert error при обращении к GitHub API**
- [x] **Vagrant Arch — ACL chmod error при become_user: aur_builder**
- [x] **Workflow — vagrant box add падает на restore-key cache hit**
- [x] **Conflict — molecule-vagrant.yml конфликт между PR и master**

---

## Детальный разбор трёх root causes

---

### Root Cause 1 — Docker Ubuntu: SSL cert error

#### Симптом

```
fatal: [Ubuntu-systemd]: FAILED! => {
  "msg": "Status code was -1 and not [200]: Request failed:
  <urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed:
  unable to get local issuer certificate (_ssl.c:1000)>",
  "url": "https://api.github.com/repos/guumaster/hostctl/releases/tags/v1.1.4"
}
```

Файл: `tasks/download.yml:20` — таск "Query specific hostctl release from GitHub API".

#### Почему это происходит

Роль `hostctl` качает бинарь с GitHub Releases. Путь:
1. Сначала пробует `apt install hostctl` — пакета нет в Ubuntu репах → `failed_when: false` → OK
2. Проверяет `command -v hostctl` → rc=1 (нет бинаря)
3. Идёт в `download.yml` → делает HTTP запрос к `api.github.com`

Ubuntu systemd Docker контейнер (`ghcr.io/textyre/ubuntu-base:latest`) запускается как systemd init. В таком режиме Python SSL модуль (`urllib3`) использует системный CA bundle `/etc/ssl/certs/ca-certificates.crt`.

Проблема: ca-certificates в контейнере устарел или не обновлён при запуске. GitHub использует сертификат выданный DigiCert/Let's Encrypt — если root CA нет в bundle, SSL handshake падает.

**Почему Arch не страдает:** Arch контейнер идёт по другому пути — сначала пытается AUR (molecule-notest, т.е. пропускается), потом делает GitHub API запрос, и у него с SSL всё OK (Arch base image имеет свежий bundle).

**Почему предыдущие CI прогоны не замечали:** Это первый раз когда для Ubuntu роль добралась до шага GitHub API download.

#### Решение

В `molecule/docker/prepare.yml` добавить ДО converge:

```yaml
- name: Install ca-certificates package (Ubuntu)
  ansible.builtin.apt:
    name: ca-certificates
    state: present
    update_cache: true
  when: ansible_facts['os_family'] == 'Debian'

- name: Refresh CA certificate bundle (Ubuntu)
  ansible.builtin.command: update-ca-certificates
  changed_when: false
  when: ansible_facts['os_family'] == 'Debian'
```

`update-ca-certificates` пересобирает `/etc/ssl/certs/ca-certificates.crt` из `/usr/share/ca-certificates/`. После этого Python SSL доверяет GitHub API.

---

### Root Cause 2 — Vagrant Arch: ACL chmod error

#### Симптом

```
fatal: [arch-vm]: FAILED! => {
  "msg": "Task failed: Failed to set permissions on the temporary files Ansible
  needs to create when becoming an unprivileged user (rc: 1,
  err: chmod: invalid mode: 'A+user:aur_builder:rx:allow')"
}
Origin: ansible/roles/hostctl/tasks/install.yml:47
```

Таск: "Install hostctl via AUR (Arch Linux)".

#### Почему это должно было быть пропущено

Таск помечен тегом `molecule-notest`:

```yaml
- name: Install hostctl via AUR (Arch Linux)
  kewlfft.aur.aur:
    name: hostctl-bin
    use: yay
  become: true
  become_user: "{{ yay_build_user | default('aur_builder') }}"
  failed_when: false
  when:
    - ansible_facts['os_family'] == 'Archlinux'
  tags: ['hostctl', 'molecule-notest']  # ← должен быть пропущен
```

#### Почему molecule-notest не сработал

Молекула должна добавлять `--skip-tags molecule-notest,notest` к ansible-playbook автоматически. Но есть **критический нюанс**: это происходит только если `provisioner.options.skip-tags` НЕ задан явно.

Как только ты ставишь явный `skip-tags` в molecule.yml — молекула использует ТОЛЬКО его, и `molecule-notest` из defaults выбрасывается.

В нашем `molecule/vagrant/molecule.yml` было:

```yaml
provisioner:
  options:
    skip-tags: report,aur     # ← только эти. molecule-notest? забыт!
```

Значит `molecule-notest` НЕ в skip-list → таск запускается.

#### Почему Docker не страдал

В Docker контейнере Ansible подключается как root. Когда current user = root и нужно `become_user: aur_builder` — Ansible НЕ использует setfacl (ACL), потому что root и так может читать/писать любые файлы. ACL setup пропускается → задача запускается → `kewlfft.aur.aur` падает (yay не установлен) → но `failed_when: false` → OK.

В Vagrant контейнере Ansible подключается как пользователь `vagrant` (не root). Когда `become_user: aur_builder` от non-root — Ansible пытается использовать `setfacl`/`chmod` с ACL режимом `A+user:aur_builder:rx:allow`. В Arch vagrant box эта команда падает (файловая система или отсутствие acl пакета). И это **connection-level error**, который случается ДО запуска таска → `failed_when: false` его не перехватывает.

#### Решение

Добавить `molecule-notest` явно в skip-tags:

```yaml
provisioner:
  options:
    skip-tags: report,aur,molecule-notest     # ← теперь явно
```

#### Правило

> Если ты КОГДА-ЛИБО пишешь `provisioner.options.skip-tags` в molecule.yml — ВСЕГДА добавляй `molecule-notest` в этот список. Иначе защита от CI-неподходящих тасков ломается.

---

### Root Cause 3 — Workflow: vagrant box add падает из-за restore-key cache hit

#### Симптом (появился неожиданно после первых фиксов)

```
==> box: Adding box 'arch-base' (v0) for provider: libvirt (amd64)
The box you're attempting to add already exists. Remove it before
adding it again or add it with the `--force` flag.

Name: arch-base
Provider: ["libvirt"]
Version: 0
##[error]Process completed with exit code 1.
```

Все 4 Vagrant job-а упали (в том числе `user` который раньше работал).

#### Анализ workflow

Это баг в `.github/workflows/molecule-vagrant.yml` (версия master). Логика была:

```yaml
- name: Cache Vagrant box
  # НЕТУ id: box-cache !
  uses: actions/cache@v4
  with:
    path: ~/.vagrant.d/boxes
    key: vagrant-box-${{ matrix.platform }}-${{ steps.box.outputs.tag }}
    restore-keys: vagrant-box-${{ matrix.platform }}-

- name: Add Vagrant box
  if: steps.box-cache.outputs.cache-hit != 'true'   # ← ссылается на несуществующий id
  run: |
    vagrant box add ${{ steps.box.outputs.name }} \
      ${{ steps.box.outputs.url }} --provider libvirt
```

**Баг 1:** У шага "Cache Vagrant box" нет `id: box-cache`. Значит `steps.box-cache` — undefined. `steps.box-cache.outputs.cache-hit` = пустая строка. Условие `'' != 'true'` = **true**. Шаг "Add Vagrant box" запускается **всегда**, независимо от cache.

**Баг 2 (глубже):** Даже если бы `id: box-cache` был, всё равно падало бы при restore-key hit. Вот почему:

`actions/cache` возвращает `cache-hit: 'true'` ТОЛЬКО при ТОЧНОМ совпадении primary key. При совпадении по restore-key (`vagrant-box-arch-`) — кэш восстанавливается (бокс есть в `~/.vagrant.d/boxes`), но `cache-hit = 'false'`. Исходная логика думала: "cache-hit false = box не скачан, нужно добавить". Но box уже есть! → `vagrant box add` падает.

**Почему в предыдущих CI прогонах не падало:** В старых прогонах у каждого PR был уникальный primary key, и при первом запуске кэша не было вообще (полный cache miss) → box скачивался и добавлялся нормально. Или же primary key совпадал точно и `cache-hit = 'true'` → add пропускался. Restore-key hit с несовпадением primary key возникает когда версия образа изменилась, но предыдущие образы в кэше остались.

#### Решение

Два изменения:

```yaml
- name: Cache Vagrant box
  id: box-cache     # ← добавить ID (без этого outputs недоступны)
  uses: actions/cache@v4
  with:
    path: ~/.vagrant.d/boxes
    key: vagrant-box-${{ matrix.platform }}-${{ steps.box.outputs.tag }}
    restore-keys: vagrant-box-${{ matrix.platform }}-

- name: Add Vagrant box
  # Убрать "if:" — сделать шаг идемпотентным
  run: |
    # Проверяем: бокс уже зарегистрирован? Тогда пропускаем.
    vagrant box list | grep -q "^${{ steps.box.outputs.name }}" || \
      vagrant box add ${{ steps.box.outputs.name }} \
        ${{ steps.box.outputs.url }} --provider libvirt
```

`vagrant box list | grep -q "^arch-base"` проверяет действительно ли бокс уже зарегистрирован в Vagrant — независимо от cache hit/miss. Если бокс есть → пропускаем. Если нет → добавляем. Идемпотентно.

---

### Дополнительная сложность — конфликт workflow файлов

Исправление workflow на PR ветке создало merge conflict: PR ветка имела СТАРЫЙ `molecule-vagrant.yml` (только schedule/dispatch), master добавил НОВЫЙ (с pull_request trigger). Когда мы в PR ветке записали исправленный НОВЫЙ файл — и PR ветка, и master теперь имели разные версии нового файла → conflict.

**Ещё одна ловушка:** GitHub для определения триггеров workflow при PR использует файл с HEAD PR ветки. PR ветка имела старый `molecule-vagrant.yml` без `pull_request` trigger → workflow не триггерился от пуша с исправлением, пока не сделали merge commit (который содержит изменения и PR ветки и master).

Разрешение: `git merge origin/master`, принять нашу версию файла (с fix), закоммитить.

---

## Анализ задержек

| Действие | Почему потребовалось | Что можно было сделать раньше |
|----------|---------------------|-------------------------------|
| 2 итерации вместо 1 | После первого фикса сразу появился новый баг в workflow | Заранее читать workflow файл перед пушем |
| Лишний коммит | Пуш fix workflow не триггернул CI из-за trigger rules | Проверять trigger rules нового файла до пуша |
| Merge conflict | Работа с устаревшей версией molecule-vagrant.yml | Fetch + merge master в начале работы |

---

## Ключевые паттерны (для будущего)

### Паттерн 1: molecule-notest + явный skip-tags

```yaml
# ПРАВИЛО: если задаёшь skip-tags явно — ВСЕГДА включай molecule-notest
provisioner:
  options:
    skip-tags: report,аур,molecule-notest    # ← molecule-notest ОБЯЗАТЕЛЕН

# ПОЧЕМУ: явный skip-tags отменяет дефолтный auto-skip molecule-notest
```

### Паттерн 2: Ubuntu Docker + внешние HTTPS запросы

```yaml
# В molecule/docker/prepare.yml ВСЕГДА для ролей что делают внешние запросы:
- name: Install ca-certificates package (Ubuntu)
  ansible.builtin.apt:
    name: ca-certificates
    state: present
    update_cache: true
  when: ansible_facts['os_family'] == 'Debian'

- name: Refresh CA certificate bundle (Ubuntu)
  ansible.builtin.command: update-ca-certificates
  changed_when: false
  when: ansible_facts['os_family'] == 'Debian'
```

### Паттерн 3: Vagrant box add — идемпотентность

```yaml
# ПЛОХО: зависит от cache-hit (ненадёжно при restore-key)
- name: Add Vagrant box
  if: steps.box-cache.outputs.cache-hit != 'true'
  run: vagrant box add NAME URL --provider libvirt

# ХОРОШО: проверяем реальное состояние
- name: Cache Vagrant box
  id: box-cache                    # ← id ОБЯЗАТЕЛЕН
  uses: actions/cache@v4
  ...

- name: Add Vagrant box
  run: |
    vagrant box list | grep -q "^NAME" || \
      vagrant box add NAME URL --provider libvirt
```

**Правило для actions/cache:** `cache-hit: 'true'` — только при ТОЧНОМ совпадении primary key. restore-key hit → `cache-hit: 'false'` даже если данные восстановлены. Никогда не полагайся на `cache-hit` для "файлы уже есть на диске" — всегда проверяй фактическое состояние.

---

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/hostctl/molecule/docker/prepare.yml` | Добавлены ca-certificates install + update для Ubuntu |
| `ansible/roles/hostctl/molecule/vagrant/molecule.yml` | `skip-tags: report,aur` → `skip-tags: report,aur,molecule-notest` |
| `.github/workflows/molecule-vagrant.yml` | Заменён старый schedule-only файл новой версией с PR trigger + fix: `id: box-cache` + idempotent box add |

---

## Итог

Все 7 CI checks зелёные:
- `Ansible Lint` ✓
- `YAML Lint & Syntax` ✓
- `hostctl (test-docker)` ✓ — Arch + Ubuntu systemd containers
- `hostctl (test-vagrant/arch)` ✓ — KVM Vagrant Arch VM
- `hostctl (test-vagrant/ubuntu)` ✓ — KVM Vagrant Ubuntu VM

Тесты честные: роль реально скачивает бинарь с GitHub, создаёт `/etc/hostctl/`, применяет профили в `/etc/hosts` через `hostctl add domains`, verify.yml проверяет каждый hostname в каждом профиле.

Ключевые уроки:
1. **molecule-notest требует явной защиты** — если пишешь `provisioner.options.skip-tags`, всегда добавляй `molecule-notest` явно
2. **Become от non-root требует ACL** — в Vagrant (non-root connection) `become_user` триггерит setfacl; в Docker (root) — нет
3. **actions/cache `cache-hit` ненадёжен для файловых проверок** — restore-key hit = данные есть, но `cache-hit = 'false'`; проверяй реальное состояние
4. **CA bundle в Docker нужно обновлять** — Ubuntu systemd containers могут иметь устаревший CA bundle; `update-ca-certificates` в prepare.yml
