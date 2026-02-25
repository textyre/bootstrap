# Post-Mortem: Vagrant KVM CI для роли `package_manager`

**Дата:** 2026-02-24 → 2026-02-25
**Статус:** Завершено — CI зелёный (оба job: arch-vm + ubuntu-noble)
**Коммиты:** `891be50` → `1a77a14` (13 итераций)
**Время:** ~10 часов (включая ожидание CI-прогонов)

---

## 1. Задача

Добавить molecule vagrant сценарий для роли `package_manager`:
- тестировать на настоящих VM (не Docker) — systemd, pacman, реальные таймеры
- покрыть обе платформы: Arch Linux и Ubuntu 24.04
- переиспользовать `shared/converge.yml` и `shared/verify.yml` без изменений
- запускать на GitHub Actions через KVM (`ubuntu-latest` + `/dev/kvm`)

---

## 2. Хронология инцидентов

```
891be50  feat(package_manager): add vagrant molecule scenario (Arch + Ubuntu)
         └─ FAIL: Vagrant не находит molecule binary (GITHUB_WORKSPACE path)

efb198c  fix(ci): use GITHUB_WORKSPACE absolute path for molecule binary
         └─ FAIL: No module named 'vagrant' (python-vagrant не установлен)

a120fbb  fix(ci): set ANSIBLE_LIBRARY to molecule-plugins vagrant module path
2a06621  fix(ci): add HashiCorp apt repo for vagrant installation
d429c77  fix(ci): add python-vagrant to pip install in molecule-vagrant workflow
         └─ FAIL: python-vagrant установлен в venv, но Ansible использует system Python

c3162b3  fix(vagrant): set ansible_python_interpreter to ansible_playbook_python for localhost
6ba80e0  fix(ci): install python-vagrant to user site-packages for system Python
7c95dbd  fix(ci): install python-vagrant to system Python via sudo pip install
         └─ FAIL: archlinux/archlinux и generic/ubuntu2404 не работают с libvirt

fe109a5  fix(vagrant): use generic/arch + bento/ubuntu-24.04 boxes (both support libvirt)
6b266a4  fix(ci): use actions/setup-python and correct ANSIBLE_LIBRARY path
         └─ FAIL(arch-vm): idempotency — No module named 'molecule.command.idempotency'
         └─ FAIL(arch-vm): generic/arch не имеет python3 pre-installed

8ebec19  fix(vagrant): bootstrap python3 on generic/arch; fix idempotence step name
         └─ FAIL(arch-vm): PGP signature — unknown trust на pacman-contrib

49e8ea5  fix(vagrant): refresh archlinux-keyring in prepare (generic/arch has stale keys)
ad9e0db  fix(vagrant): full pacman -Syu on Arch to restore openssl/ssl compatibility
         └─ FAIL(arch-vm): reflector запускается в CI, падает на URLError: https

7251ca8  fix(vagrant): skip mirrors,aur tags in vagrant scenario (matches docker scenario)
         └─ FAIL: options.skip-tags не применяется к converge-команде в vagrant driver

1a77a14  fix(package_manager): tag reflector+yay imports as molecule-notest
         └─ SUCCESS ✓ (arch-vm: 5m21s, ubuntu-noble: 4m13s)
```

---

## 3. Инциденты и root cause анализ

### Инцидент #1 — Python окружение: venv vs system Python

**Коммиты:** `a120fbb`, `d429c77`, `c3162b3`, `6ba80e0`, `7c95dbd`, `6b266a4`

**Ошибки (последовательные):**
```
No module named 'vagrant'
ModuleNotFoundError: No module named 'python_vagrant'
```

**Причина:**

Изначальный workflow создавал venv и устанавливал всё туда:
```bash
python3 -m venv .venv
.venv/bin/pip install ansible-core molecule molecule-plugins[vagrant]
```

`molecule-plugins[vagrant]` при создании Vagrant-инстансов выполняет Ansible-плейбук
через `localhost` с `module_path` = путь к `molecule_plugins/vagrant/modules/`.
Этот модуль импортирует `import vagrant` (python-vagrant). Но Ansible на localhost
использует **system Python**, а не Python из venv. Поэтому `import vagrant` падает —
пакет установлен только в venv.

Попытки: `sudo pip install python-vagrant` → system python запрещает external packages.
Попытка: `pip install --user python-vagrant` → установился в `~/.local/lib/python3.x/`,
но Ansible видит другую Python-версию (toolcache vs system).

**Fix:**

Отказаться от venv. Использовать `actions/setup-python@v5` + `pip install` в toolcache.
GitHub Actions Auto-discover: Ansible автоматически находит Python из toolcache PATH
и использует его для localhost-модулей. Все пакеты в одном окружении.

```yaml
- name: Set up Python 3.12
  uses: actions/setup-python@v5
  with:
    python-version: '3.12'

- name: Install molecule + dependencies
  run: |
    pip install "ansible-core==2.20.1" "molecule==25.12.0" \
      "molecule-plugins[vagrant]==25.8.12" "jmespath" "rich"
    python -c "import vagrant; print('python-vagrant OK:', vagrant.__file__)"
```

`ANSIBLE_LIBRARY` указывается на `molecule_plugins/vagrant/modules/` (не родительский `vagrant/`):
```bash
VAGRANT_MODULES=$(python3 -c "import os, molecule_plugins.vagrant; \
  print(os.path.join(os.path.dirname(molecule_plugins.vagrant.__file__), 'modules'))")
export ANSIBLE_LIBRARY="$VAGRANT_MODULES"
```

**Урок:**
`molecule-plugins[vagrant]` использует system/PATH Python для localhost-модулей.
Не создавать venv — устанавливать всё через `actions/setup-python` + `pip`.
`python-vagrant` должен быть в **том же** Python-окружении, что и Ansible.

---

### Инцидент #2 — Vagrant boxes: libvirt совместимость

**Коммит:** `fe109a5`

**Ошибка:**
```
The box 'archlinux/archlinux' could not be found or could not be accessed
The box 'generic/ubuntu2404' could not be found (HTTP 404)
```

**Причина:**

Из дизайн-документа (`2026-02-24-package-manager-vagrant-design.md`) взяты boxes:
- `archlinux/archlinux` — официальный Arch box, но оптимизирован под **VirtualBox**,
  не имеет libvirt provider
- `generic/ubuntu2404` — box под таким именем отсутствует в Vagrant Cloud (404)

**Fix:**

```yaml
platforms:
  - name: arch-vm
    box: generic/arch          # generic provider-agnostic Arch box
  - name: ubuntu-noble
    box: bento/ubuntu-24.04    # bento поддерживает libvirt нативно
```

| Box | Provider | Причина выбора |
|-----|---------|----------------|
| `generic/arch` | libvirt ✓ | Provider-agnostic, обновляется regularly |
| `bento/ubuntu-24.04` | libvirt ✓ | Bento — стандарт де-факто для libvirt |

**Урок:**
Не использовать дистро-официальные boxes (`archlinux/archlinux`, `ubuntu/noble64`) —
они ориентированы на VirtualBox. Для libvirt: `generic/*` или `bento/*`.

---

### Инцидент #3 — `idempotency` vs `idempotence` в test_sequence

**Коммит:** `8ebec19`

**Ошибка:**
```
ModuleNotFoundError: No module named 'molecule.command.idempotency'
```

**Причина:**

В `molecule.yml` был указан:
```yaml
scenario:
  test_sequence:
    - idempotency   # ← неверно
```

В molecule 25.12.0 команда называется `idempotence`. Molecule пытается
`importlib.import_module("molecule.command.idempotency")` → модуль не найден.

**Fix:**
```yaml
scenario:
  test_sequence:
    - idempotence   # ← верно
```

**Урок:** В molecule ≥ 25.x шаг идемпотентности называется `idempotence` (без `y`).

---

### Инцидент #4 — `generic/arch` не имеет Python3

**Коммит:** `8ebec19`

**Ошибка:**
```
TASK [Gathering Facts]
fatal: [arch-vm]: FAILED! => {"changed": false, "module_stderr": "...",
  "msg": "/bin/sh: python3: not found"}
```

**Причина:**

`generic/arch` — минимальный Vagrant box без Python3. В отличие от Docker-образа
`arch-systemd`, где Python установлен как часть образа, здесь Python нужно
устанавливать вручную. Первый таск в prepare.yml был `gather_facts: true` —
он сразу падал, не успев установить Python.

**Fix:**

```yaml
- name: Prepare
  hosts: all
  become: true
  gather_facts: false         # ← отключить auto gather_facts
  tasks:
    - name: Bootstrap Python on Arch (raw — no Python required)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts        # ← теперь Python есть, gather_facts работает
      ansible.builtin.gather_facts:
```

`ansible.builtin.raw` выполняется через SSH напрямую, без Python-интерпретатора.

**Урок:**
`generic/arch` (и любые bare Arch boxes) не имеют Python. Паттерн для prepare.yml:
`gather_facts: false` → `raw: установить python` → `gather_facts:` как отдельный шаг.

---

### Инцидент #5 — Устаревший keyring в `generic/arch`: PGP signature unknown trust

**Коммит:** `49e8ea5`

**Ошибка:**
```
fatal: [arch-vm]: FAILED! => {
  "msg": "Failed to install package(s)",
  "stderr": "error: pacman-contrib: signature from
    \"Daniel M. Capella <polyzen@archlinux.org>\" is unknown trust\n
    error: failed to commit transaction (invalid or corrupted package (PGP signature))"
}
```

**Причина:**

`generic/arch` box создаётся не очень часто и имеет устаревший `archlinux-keyring`.
Ключ Daniel M. Capella (мейнтейнер `pacman-contrib`) был добавлен в keyring
после снятия снимка box. Pacman не доверяет ключу → отказывает в установке.

Роль `package_manager` устанавливает `pacman-contrib` (provides `paccache`) в задаче
converge — именно здесь и падает.

**Fix:**

В `prepare.yml` перед converge: временно обойти проверку подписей, установить свежий
`archlinux-keyring`, восстановить SigLevel, заново заполнить keyring:

```yaml
- name: Refresh pacman keyring on Arch (generic/arch box has stale keys)
  ansible.builtin.shell: |
    sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
    pacman -Sy --noconfirm archlinux-keyring
    sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
    pacman-key --populate archlinux
  args:
    executable: /bin/bash
  when: ansible_facts['os_family'] == 'Archlinux'
  changed_when: true
```

Последовательность:
1. `SigLevel = Never` — временно отключить проверку подписей
2. Установить новый `archlinux-keyring` (без проверки — ключи ещё не обновлены)
3. Восстановить оригинальный SigLevel
4. `pacman-key --populate archlinux` — импортировать ключи из нового keyring

После этого keyring содержит ключ Capella → `pacman-contrib` устанавливается.

**Урок:**
`generic/arch` (и другие нечасто обновляемые Arch boxes) имеют устаревший keyring.
Всегда обновлять keyring в prepare.yml. Паттерн: `SigLevel=Never` → установить
`archlinux-keyring` → восстановить SigLevel → `pacman-key --populate archlinux`.

---

### Инцидент #6 — `reflector` запускается в CI VM без доступа к интернету

**Коммиты:** `7251ca8`, `1a77a14`

**Ошибка (первая итерация):**
```
fatal: [arch-vm]: FAILED! => {
  "msg": "non-zero return code", "rc": 1,
  "stderr": "error: failed to retrieve mirrorstatus data:
    URLError: <urlopen error unknown url type: https>"
}
```

**Ошибка (вторая итерация):**
```
fatal: [arch-vm]: FAILED! => {
  "msg": "Task failed: '_reflector_backups' is undefined"
}
```

**Причина:**

`ansible/roles/package_manager/tasks/archlinux.yml` содержит:
```yaml
- name: Set up Arch Linux mirrors
  ansible.builtin.import_role:
    name: reflector
  tags: ['mirrors', 'reflector']

- name: Install yay AUR helper
  ansible.builtin.import_role:
    name: yay
  tags: ['aur', 'yay']
```

В docker-сценарии это уже было решено через `options: skip-tags: report,aur,mirrors`
в `molecule/docker/molecule.yml`. Vagrant-сценарий создавался без этой настройки.

**Попытка #1 (неэффективная):** Добавить `options: skip-tags: report,aur,mirrors`
в `molecule/vagrant/molecule.yml` — аналогично docker-сценарию.

Результат: не помогло. Ansible-playbook команда в логах CI показывала только
`--skip-tags molecule-notest,notest`, без `report,aur,mirrors`. Vagrant-driver
molecule-plugins не применяет `options.skip-tags` так же, как docker-driver.

**Fix (рабочий):** Добавить тег `molecule-notest` напрямую к задачам в `archlinux.yml`:

```yaml
- name: Set up Arch Linux mirrors
  ansible.builtin.import_role:
    name: reflector
  tags: ['mirrors', 'reflector', 'molecule-notest']   # ← добавлен

- name: Install yay AUR helper
  ansible.builtin.import_role:
    name: yay
  tags: ['aur', 'yay', 'molecule-notest']              # ← добавлен
```

Molecule **всегда** передаёт `--skip-tags molecule-notest,notest` в ansible-playbook,
независимо от драйвера (docker или vagrant). Это гарантированное поведение.

**Урок:**
`options: skip-tags` в `molecule.yml` ненадёжен — поведение зависит от драйвера.
Для задач, которые не должны выполняться в любом molecule-сценарии (сетевые операции,
AUR-хелперы, reflector), использовать тег `molecule-notest` непосредственно в задаче.
Это работает надёжно для всех драйверов: docker, vagrant, podman, etc.

---

## 4. Финальная структура

```
.github/workflows/
  molecule-vagrant.yml       ← ubuntu-latest + KVM; matrix: arch-vm, ubuntu-noble
                               actions/setup-python@v5; pip install в toolcache
                               ANSIBLE_LIBRARY → molecule_plugins/vagrant/modules/

ansible/roles/package_manager/
  tasks/
    archlinux.yml            ← reflector + yay с тегом molecule-notest
  molecule/
    vagrant/
      molecule.yml           ← generic/arch + bento/ubuntu-24.04; idempotence
      prepare.yml            ← gather_facts: false → raw: python → keyring refresh
                                → pacman -Syu → apt update
    shared/
      converge.yml           ← без изменений (hosts: all; roles: [package_manager])
      verify.yml             ← без изменений (Arch + Debian блоки)
```

### prepare.yml — полная последовательность для Arch

```yaml
gather_facts: false
tasks:
  1. raw: install python3 (if Arch)       # без Python — raw через SSH
  2. gather_facts:                        # теперь Python есть
  3. SigLevel=Never + archlinux-keyring   # обновить keyring
     + SigLevel=Required + populate
  4. pacman -Syu (upgrade: true)          # полный upgrade: openssl, glibc, etc.
  5. apt update_cache (Ubuntu)            # обновить apt cache
```

---

## 5. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `molecule-plugins[vagrant]` требует python-vagrant в **том же** Python, что использует Ansible (PATH/toolcache). Не создавать venv — использовать `actions/setup-python` | vagrant сценарии |
| 2 | `generic/arch` не имеет Python3. Первый шаг — `gather_facts: false` + `raw: pacman -Sy python` | Все Arch vagrant boxes |
| 3 | `generic/arch` имеет устаревший keyring. Всегда обновлять через `SigLevel=Never` → `archlinux-keyring` → restore → `pacman-key --populate` | `generic/arch`, любые старые Arch boxes |
| 4 | Для libvirt: `generic/arch` (Arch) и `bento/ubuntu-24.04` (Ubuntu). Дистро-официальные boxes (`archlinux/archlinux`, `ubuntu/noble64`) — только VirtualBox | vagrant сценарии |
| 5 | `idempotence` (не `idempotency`) в `test_sequence` начиная с molecule 25.x | Все molecule сценарии |
| 6 | `options: skip-tags` в provisioner ненадёжен в vagrant-driver. Использовать тег `molecule-notest` в самой задаче — гарантированно работает во всех драйверах | Все роли с внешними зависимостями |
| 7 | Сетевые операции (reflector, yay, AUR) не выполняются в CI Vagrant VM — метить `molecule-notest` | Роли, включающие reflector/yay через import_role |

---

## 6. Known gaps

- **`options: skip-tags` в vagrant driver** — причина игнорирования не установлена.
  Может быть багом в `molecule-plugins[vagrant]==25.8.12`. Оставить `molecule-notest`
  на задачах как основной механизм, `options: skip-tags` — как резерв.
- **Fedora/Void vagrant сценарии** — не добавлены. Для Fedora можно добавить
  `generic/fedora40` в matrix. Void не имеет libvirt-совместимого box.
- **`pacman -Syu` в prepare** — полный upgrade (~200 пакетов) занимает 2-3 минуты.
  Потенциальный кандидат на кастомный `generic/arch` box с предустановленным Python
  и свежим keyring, что сократит время подготовки.
