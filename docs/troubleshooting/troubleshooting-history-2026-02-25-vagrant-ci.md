# Post-Mortem: Molecule Vagrant (KVM) CI для роли `package_manager`

**Дата:** 2026-02-25
**Статус:** Завершено — CI зелёный (arch-vm + ubuntu-noble)
**Коммиты:** `891be50` → `1a77a14` (12 итераций)

---

## 1. Задача

Реализовать интеграционные тесты роли `package_manager` на реальных VM (не Docker):

- GitHub Actions + KVM (доступен на `ubuntu-latest` с апреля 2024)
- Vagrant + libvirt провайдер
- Матрица: Arch Linux + Ubuntu 24.04 параллельно
- Без дублирования: переиспользовать `molecule/shared/converge.yml` и `verify.yml`

**Мотивация:** Docker-сценарий не покрывает сетевые операции (reflector, AUR, pacman signature check).
Vagrant на KVM даёт полноценную VM с интернетом, systemd, пространством имён пользователей.

---

## 2. Архитектурные решения

### Воркфлоу

```
.github/workflows/molecule-vagrant.yml
├── Enable KVM (udev rule для /dev/kvm)
├── Install libvirt + vagrant (HashiCorp apt repo — не в Ubuntu 24.04 стандартных репах)
├── actions/setup-python@v5 (Python 3.12)
├── pip install ansible-core molecule molecule-plugins[vagrant]
├── ansible-galaxy collection install
└── molecule test -s vagrant --platform-name ${{ matrix.platform }}
```

### Матрица и платформы

```yaml
strategy:
  matrix:
    platform: [arch-vm, ubuntu-noble]
  fail-fast: false      # оба бегут независимо
```

| Платформа   | Vagrant box       | Провайдер |
|-------------|-------------------|-----------|
| arch-vm     | `generic/arch`    | libvirt   |
| ubuntu-noble| `bento/ubuntu-24.04` | libvirt |

### Переиспользование shared/

Vagrant-сценарий ссылается на те же плейбуки что и Docker:

```yaml
provisioner:
  playbooks:
    prepare: prepare.yml        # ← свой (VM-специфичный bootstrap)
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
```

### Skip-tags стратегия

AUR и reflector не тестируются в vagrant-сценарии (как и в docker):

```yaml
provisioner:
  options:
    skip-tags: report,aur,mirrors
```

Роль также помечает соответствующие `import_role` тегом `molecule-notest` — Molecule всегда
добавляет `--skip-tags molecule-notest,notest` к `ansible-playbook`.

---

## 3. Инциденты

### Инцидент #1 — python-vagrant не найден Ansible-модулем (venv isolation)

**Коммиты:** `d429c77` → `6b266a4`
**Ошибка:**
```
ERROR: Driver missing, install python-vagrant.
```

**Причина:**

Vagrant Ansible-модуль (`molecule_plugins/vagrant/modules/vagrant.py`) запускается в subprocess
с Python, который Ansible auto-discover для `localhost`. На GitHub Actions Ansible обнаруживает
Python из toolcache (`/opt/hostedtoolcache/Python/3.12.x/x64/bin/python3`), а не из venv.

Попытки установить python-vagrant в другие места:
- venv (`pip install` внутри activated venv) → toolcache Python его не видит
- `pip3 install --user` → устанавливает в `~/.local`, но toolcache Python ищет в своём prefix
- `sudo pip install --break-system-packages` → устанавливает в `/usr/local/lib/python3.12`,
  но sudo сбрасывает PATH и использует `/usr/bin/python3` (system), а не toolcache

**Диагностика:**

```bash
# В workflow было добавлено:
python -c "import vagrant; print('python-vagrant OK:', vagrant.__file__)"
# Выводило путь из toolcache только ПОСЛЕ правильного фикса
```

**Фикс:**

Отказ от venv в пользу `actions/setup-python@v5` + прямой `pip install`:

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.12'
- run: pip install ansible-core molecule molecule-plugins[vagrant]
  # python3 в PATH = toolcache Python = тот, который Ansible discover для localhost
```

**Урок:** При использовании `actions/setup-python`, Ansible auto-discovers именно toolcache Python.
Все зависимости модулей (`import vagrant`, `import jmespath`) должны быть в том же Python.
Никаких venv — только прямой `pip install` после `setup-python`.

---

### Инцидент #2 — ANSIBLE_LIBRARY указывал на неправильный путь

**Коммит:** `a120fbb` → `6b266a4`
**Ошибка:**
```
couldn't resolve module/action 'vagrant'
```

**Причина:**

`molecule-plugins[vagrant]` устанавливает Ansible-модуль по пути:
```
molecule_plugins/vagrant/modules/vagrant.py
```

Но первоначально `ANSIBLE_LIBRARY` указывал на `molecule_plugins/vagrant/` (Python package dir),
а не на `molecule_plugins/vagrant/modules/` (где лежит `vagrant.py`).

**Фикс:**

```bash
VAGRANT_MODULES=$(python3 -c \
  "import os, molecule_plugins.vagrant; \
   print(os.path.join(os.path.dirname(molecule_plugins.vagrant.__file__), 'modules'))")
export ANSIBLE_LIBRARY="$VAGRANT_MODULES"
```

**Урок:** `molecule_plugins.vagrant.__file__` указывает на `__init__.py` в пакете.
Модуль `vagrant.py` находится в `modules/` subdirectory. Нельзя угадать путь — вычислять
динамически из import.

---

### Инцидент #3 — `archlinux/archlinux` box не поддерживает libvirt

**Коммит:** `fe109a5`
**Ошибка:**
```
The box you're attempting to add doesn't support the provider you requested.
Name: archlinux/archlinux
Requested provider: libvirt
```

**Причина:**

Официальный `archlinux/archlinux` box поддерживает только VirtualBox.

**Фикс:**

Поиск через Vagrant Cloud API:
```bash
curl -s "https://vagrantcloud.com/api/v2/vagrant/generic/arch" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); ..."
# → generic/arch providers: {libvirt, virtualbox, qemu, ...}
```

| Замена | Обоснование |
|--------|-------------|
| `archlinux/archlinux` → `generic/arch` | roboxes.org box, поддерживает libvirt |
| `generic/ubuntu2404` → `bento/ubuntu-24.04` | `generic/ubuntu2404` возвращает 404 |

**Урок:** Всегда проверять наличие `libvirt` провайдера через API до коммита.
Namespace `generic/` (roboxes.org) и `bento/` надёжно поддерживают libvirt.

---

### Инцидент #4 — `idempotency` вместо `idempotence`

**Коммит:** `8ebec19`
**Ошибка:**
```
ModuleNotFoundError: No module named 'molecule.command.idempotency'
```

**Причина:**

В `molecule.yml` был указан неверный шаг `test_sequence`:

```yaml
- idempotency   # ← неверно
```

В Molecule 25.x правильное имя:

```yaml
- idempotence   # ← верно
```

**Урок:** Правильный `test_sequence` для vagrant-сценария:
```yaml
scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence   # не idempotency
    - verify
    - destroy
```

---

### Инцидент #5 — `generic/arch` не имеет Python

**Коммит:** `8ebec19`
**Ошибка:**
```
fatal: [arch-vm]: FAILED! => {
  "msg": "The module interpreter '/usr/bin/python3' was not found.",
  "module_stdout": "/bin/sh: line 1: /usr/bin/python3: No such file or directory"
}
```

**Причина:**

`generic/arch` — минимальный Arch Linux box. Python не установлен по умолчанию.
`gather_facts: true` в `prepare.yml` пытается запустить setup-модуль через Python —
падает ещё до первого task.

**Фикс:**

```yaml
- name: Prepare
  gather_facts: false    # ← отключаем auto-gather

  tasks:
    - name: Bootstrap Python (raw — не требует Python)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts     # ← теперь Python есть
      ansible.builtin.gather_facts:
```

**Урок:** Шаблон prepare.yml для minimal Arch Vagrant box:
`gather_facts: false` → `raw bootstrap Python` → `gather_facts:` модуль → остальные таски.

---

### Инцидент #6 — Устаревший keyring в `generic/arch` (PGP signature failure)

**Коммит:** `49e8ea5`
**Ошибка:**
```
error: pacman-contrib: signature from "Daniel M. Capella <polyzen@archlinux.org>" is unknown trust
error: failed to commit transaction (invalid or corrupted package (PGP signature))
```

**Причина:**

`generic/arch` box обновлялся редко. Keyring устарел — новые ключи мейнтейнеров
(в т.ч. `Daniel M. Capella`) не доверенные. При попытке установить любой пакет,
подписанный этим ключом, pacman отказывает.

**Фикс:**

Стандартный workaround для stale Arch box — временно отключить SigLevel, обновить
keyring, восстановить SigLevel:

```yaml
- name: Refresh pacman keyring
  ansible.builtin.shell: |
    sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
    pacman -Sy --noconfirm archlinux-keyring
    sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
    pacman-key --populate archlinux
  when: ansible_facts['os_family'] == 'Archlinux'
```

**Урок:** `generic/arch` всегда имеет устаревший keyring в CI. Этот шаг обязателен
в prepare.yml для любого vagrant-сценария на Arch.

---

### Инцидент #7 — SSL не работает (`unknown url type: https`)

**Коммит:** `ad9e0db`
**Ошибка:**
```
error: failed to retrieve mirrorstatus data: URLError: <urlopen error unknown url type: https>
```

**Причина:**

После обновления keyring (инцидент #6) reflector всё равно не мог получить данные
по HTTPS. Ошибка `unknown url type: https` в Python urllib означает: SSL handler не
зарегистрирован, т.е. `import ssl` упал при инициализации.

Причина: OpenSSL в stale box не совместим с версией Python (ABI mismatch). После
`pacman-key --populate archlinux`, пакеты устанавливаются из обновлённой БД, но
сам OpenSSL и Python ещё старые — несоответствие версий разделяемых библиотек.

**Фикс:**

Полное обновление системы перед converge:

```yaml
- name: Full system upgrade (ensures openssl/ssl compatibility)
  community.general.pacman:
    update_cache: true
    upgrade: true
  when: ansible_facts['os_family'] == 'Archlinux'
```

`pacman -Syu` обновляет openssl, python, и все зависимости до консистентных версий.

**Время:** ~5-7 минут дополнительного времени на upgrade в CI.

**Урок:** После keyring fix, `generic/arch` нужен полный `pacman -Syu` для восстановления
ABI-консистентности пакетов. Нельзя доверять частичному обновлению stale box.

---

### Инцидент #8 — Баг в роли `reflector`: `_reflector_backups is undefined`

**Коммит:** `c0acedf`
**Ошибка:**
```
[ERROR]: Task failed: '_reflector_backups' is undefined
Origin: ansible/roles/reflector/tasks/update.yml:87:13
```

**Причина:**

Опечатка в `roles/reflector/tasks/update.yml` — несоответствие имён переменных:

```yaml
# Строка 78 — регистрируется БЕЗ underscore:
register: reflector_backups

# Строки 87, 91 — используется С underscore:
loop: "{{ (_reflector_backups.files | ...) }}"
when: _reflector_backups.matched > ...
```

Аналогичная ошибка на строке 96 (`_reflector_old_mirror` вместо `reflector_old_mirror`).

**Почему не обнаружили раньше:**
- Docker CI: задача пропускается через `skip-tags: mirrors`
- localhost VM: reflector отрабатывал, но backup rotation мог не срабатывать (если
  бэкапов мало, `when: matched > keep` не выполнялось)
- Vagrant CI: первый прогон с включённым reflector в реальной VM — баг обнажился

**Важно:** Reflector к этому моменту уже УСПЕШНО обновил mirrorlist. Rescue-блок
сработал не из-за ошибки reflector, а из-за `_reflector_backups undefined` в блоке
ротации бэкапов. Restored mirrorlist был валидным.

**Фикс:**

```yaml
register: _reflector_backups   # было: reflector_backups
```

```yaml
# Строка 96:
{{ (reflector_old_mirror.content | default('')) != (reflector_new_mirror.content | default('')) }}
# было: _reflector_old_mirror / _reflector_new_mirror
```

**Урок:** Баги в rescue-путях не обнаруживаются в happy path тестах.
Docker-сценарий со skip-tags полностью маскировал этот код. Vagrant-тест на реальной
VM впервые прошёл полный путь, включая ротацию бэкапов.

---

## 4. Финальная структура

### Файлы

```
.github/workflows/molecule-vagrant.yml   ← workflow: KVM + matrix

ansible/roles/package_manager/molecule/
  vagrant/
    molecule.yml    ← driver: libvirt; generic/arch + bento/ubuntu-24.04
                       skip-tags: report,aur,mirrors
                       test_sequence: ..., idempotence, ...
    prepare.yml     ← Arch: raw python → gather_facts → keyring refresh
                       → pacman -Syu → update cache
                       Ubuntu: apt update_cache

ansible/roles/reflector/tasks/update.yml  ← баг-фикс: _reflector_backups naming
```

### prepare.yml (финальный)

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Bootstrap Python on Arch (raw)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts
      ansible.builtin.gather_facts:

    - name: Refresh pacman keyring (generic/arch has stale keys)
      ansible.builtin.shell: |
        sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
        pacman -Sy --noconfirm archlinux-keyring
        sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
        pacman-key --populate archlinux
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade (ensures openssl/ssl compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

---

## 5. Ключевые паттерны

### Python discovery в GitHub Actions

```
actions/setup-python → toolcache Python → /opt/hostedtoolcache/Python/3.12.x/x64/
     ↓
pip install ansible-core molecule-plugins[vagrant]  # в toolcache Python
     ↓
Ansible auto-discovers toolcache Python для localhost modules
     ↓
vagrant.py module: import vagrant → OK (установлен в тот же Python)
```

НЕ использовать venv. Всё в одном Python-окружении.

### ANSIBLE_LIBRARY resolution

```bash
python3 -c "import os, molecule_plugins.vagrant; \
  print(os.path.join(os.path.dirname(molecule_plugins.vagrant.__file__), 'modules'))"
# → /opt/hostedtoolcache/.../molecule_plugins/vagrant/modules
```

### generic/arch bootstrap sequence

```
raw: pacman -Sy python
    ↓
gather_facts
    ↓
SigLevel=Never → pacman -Sy archlinux-keyring → SigLevel=Required
    ↓
pacman-key --populate archlinux
    ↓
pacman -Syu (обновляет openssl, python, всё)
    ↓
обычные prepare-таски
```

---

## 6. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `actions/setup-python` + прямой pip install — единственная надёжная схема для Ansible на GH Actions | Все GH Actions workflows |
| 2 | ANSIBLE_LIBRARY → `modules/` subdir, не package dir | Все vagrant-сценарии |
| 3 | Проверять libvirt support через Vagrant Cloud API перед выбором box | Все vagrant-сценарии |
| 4 | `idempotence`, не `idempotency` в `test_sequence` | Все vagrant/docker сценарии |
| 5 | `generic/arch` требует: raw Python → keyring refresh (SigLevel=Never) → pacman -Syu | Все Arch vagrant-сценарии |
| 6 | Rescue-пути в ролях не покрываются Docker CI со skip-tags — нужны реальные VM-тесты | Роли с rescue-блоками |
| 7 | Баги в variable naming (`_var` vs `var`) не обнаруживаются если код пропускается через skip-tags | Все роли с rescue |
| 8 | Читать постмортемы перед началом отладки — экономит минимум 2-3 итерации | Все сессии отладки CI |

---

## 7. Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `.github/workflows/molecule-vagrant.yml` | Создан с нуля; 6 итераций фиксов |
| `ansible/roles/package_manager/molecule/vagrant/molecule.yml` | Создан; box fixes; idempotence; skip-tags |
| `ansible/roles/package_manager/molecule/vagrant/prepare.yml` | Создан; 3 итерации: python bootstrap → keyring → syu |
| `ansible/roles/reflector/tasks/update.yml` | Фикс `_reflector_backups` naming bug |
| `ansible/roles/package_manager/molecule/shared/converge.yml` | molecule-notest теги на reflector+yay |

---

## 8. Known gaps

- **AUR (yay) не тестируется на VM** — требует пользователя без root и доступ к AUR.
  В текущем vagrant-сценарии пропускается через `molecule-notest`. Потребует отдельный
  сценарий с non-root пользователем.
- **reflector тестируется только в vagrant-прогоне** — Docker CI пропускает через skip-tags.
  Это нормально: vagrant и есть тест для сетевых операций.
- **Время прогона:** arch-vm занимает ~8-10 минут из-за `pacman -Syu`. Оптимизация
  возможна через кастомный packer-образ с pre-upgraded системой.
- **Расписание:** workflow запускается раз в неделю (понедельник 04:00 UTC) — не на каждый push.
  Это компромисс между стоимостью (время GH Actions) и полнотой покрытия.
