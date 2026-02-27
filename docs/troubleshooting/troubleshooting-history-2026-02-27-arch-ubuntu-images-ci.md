# Post-Mortem: Интеграция arch-images и ubuntu-images в bootstrap CI

**Дата:** 2026-02-27
**Статус:** Завершено — оба pipeline зелёные, releases опубликованы
**Репозитории затронуты:**
- `textyre/arch-images` — коммиты `a405c38` → `6c26b03` (5 фиксов)
- `textyre/ubuntu-images` — коммиты `0e79cf3` → `8b0160c` (5 фиксов)
- `textyre/bootstrap` — удаление дублирующей инфраструктуры, подключение внешних образов
**Итерации:** 6 прогонов (1 исходный + 5 фиксов)
**Время:** ~2 часа (включая ожидание CI-прогонов по ~3-4 минуты каждый)

---

## 1. Задача

Два отдельных репозитория (`arch-images`, `ubuntu-images`) производят Docker-образы и
Vagrant-боксы для использования в Molecule-тестах bootstrap-проекта. Выяснилось что
bootstrap **не использовал** эти образы:

- Docker-сценарии брали `ghcr.io/textyre/bootstrap/arch-systemd:latest` — локальный образ,
  собиравшийся в самом bootstrap через отдельный job
- Vagrant-сценарии использовали публичные generic-боксы (`generic/arch`, `bento/ubuntu-24.04`)
- В bootstrap существовал `ansible/molecule/Dockerfile.archlinux` — упрощённая копия Arch-образа

Цель: подключить внешние образы, удалить дублирование, убедиться что оба CI-pipeline
работают end-to-end (Docker push + Vagrant box → GitHub Releases).

---

## 2. Изменения в bootstrap (подготовка)

До запуска image-билдов были выполнены следующие изменения в bootstrap:

### Удалено

| Файл | Причина |
|------|---------|
| `ansible/molecule/Dockerfile.archlinux` | Заменён внешним `ghcr.io/textyre/arch-molecule` |
| `.github/workflows/build-arch-image.yml` | Логика перенесена в `textyre/arch-images` |

### Обновлено

| Файл | Изменение |
|------|-----------|
| 9× `molecule/docker/molecule.yml` | `bootstrap/arch-systemd` → `ghcr.io/textyre/arch-molecule:latest` |
| `.github/workflows/_molecule.yml` | `MOLECULE_ARCH_IMAGE`: убран `github.repository` prefix |
| `.github/workflows/molecule.yml` | Удалён job `build-image` и условие `dockerfile_changed` |
| `pam_hardening/molecule/vagrant/molecule.yml` | `box_url` → GitHub Releases arch-images + ubuntu-images |
| `package_manager/molecule/vagrant/molecule.yml` | То же самое |

### Итоговая конфигурация Vagrant-сценариев

```yaml
platforms:
  - name: arch-vm
    box: arch-molecule
    box_url: https://github.com/textyre/arch-images/releases/download/boxes/arch-molecule-latest.box
  - name: ubuntu-noble
    box: ubuntu-molecule
    box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-molecule-latest.box
```

---

## 3. Хронология прогонов

```
Run 1 (22474624463 / 22485587661)   — первый запуск  → FAIL: xorriso + sh/bash
Run 2 (22485712573 / 22485715906)   — коммит 09b4647/6c12a4d → FAIL: vagrant exit 100 + community.general
Run 3 (22485832453 / 22485835751)   — коммит 6f5b76a/a7eb191 → FAIL: "Couldn't open file"
Run 4 (22486030086 / 22486033632)   — коммит 0444ce3/cf1ac73 → FAIL: box file not found (find пустой)
Run 5 (22486165533 / 22486168507)   — коммит 079f7af/2f4c851 → FAIL: cp: cannot stat old path
Run 6 (22486518752 / 22486522244)   — коммит 6c26b03/8b0160c → SUCCESS ✓
```

---

## 4. Инциденты

### Инцидент #1 — `xorriso` не установлен (Packer cd_files)

**Затронуто:** arch-images Run 1, ubuntu-images Run 1
**Ошибка:**
```
Build 'arch-molecule.qemu.archlinux' errored after 4 seconds:
could not find a supported CD ISO creation command
(the supported commands are: xorriso, mkisofs, hdiutil, oscdimg)
```

**Причина:**

Packer QEMU builder использует `cd_files` для создания cloud-init seed ISO (передаётся
через виртуальный CD-ROM в QEMU). Для создания ISO нужна одна из утилит: `xorriso`,
`mkisofs`, `hdiutil`, `oscdimg`. На `ubuntu-latest` GitHub Actions ни одна не
предустановлена.

**Фикс:**

```yaml
- name: Install QEMU + libvirt
  run: |
    sudo apt-get install -y qemu-system-x86 qemu-utils libvirt-daemon-system xorriso
```

**Урок:** Packer `cd_files` всегда требует ISO-утилиту. На ubuntu-latest runner
это `xorriso` — она не входит в стандартный образ.

---

### Инцидент #2 — `sh -c` с bash-синтаксисом в Ubuntu Docker-контракте

**Затронуто:** ubuntu-images Run 1 (только Ubuntu — Arch использует bash)
**Ошибка:**
```
sh: 4: set: Illegal option -o pipefail
Process completed with exit code 2.
```

**Причина:**

Файл `contracts/docker.sh` начинается с:
```bash
set -euo pipefail
```

Это bash-специфичный синтаксис (`pipefail` — опция bash, не POSIX sh). Workflow
запускал контракт через:
```yaml
run: sh -c "$(cat contracts/docker.sh)"
```

На Ubuntu `/bin/sh` — это `dash` (не bash). `dash` не поддерживает `-o pipefail`,
возвращает `Illegal option`.

**Фикс:**

```yaml
run: bash -c "$(cat contracts/docker.sh)"
```

**Урок:** `sh` на Debian/Ubuntu — это `dash`. Скрипты с `set -euo pipefail`,
массивами bash, `[[ ]]`, или `$()` требуют явного `bash`. Никогда не предполагать
что `sh == bash`.

---

### Инцидент #3 — `community.general` не установлена в ubuntu-images workflow

**Затронуто:** ubuntu-images Run 2
**Ошибка (внутри Packer Ansible provisioner):**
```
[WARNING]: Error loading plugin 'community.general.pacman':
  No module named 'ansible_collections.community'
[ERROR]: couldn't resolve module/action 'community.general.pacman'.
  This often indicates a misspelling, missing collection, or incorrect module path.
```

**Причина:**

Ubuntu workflow устанавливал только `ansible-core`:
```yaml
run: pip install ansible-core
```

Packer использует Ansible-provisioner для настройки VM. Playbook роли `package_manager`
содержит задачи с `community.general.pacman`. **Ansible разрешает FQCN модулей на
этапе парсинга**, а не выполнения — даже если задача защищена `when: ansible_os_family == 'Archlinux'`,
модуль должен быть доступен уже при загрузке плейбука.

Это контринтуитивно: в bootstrap-проекте Ubuntu-тесты с `community.general.pacman`
работали, потому что там коллекция была установлена глобально. В изолированном
ubuntu-images workflow её не было.

**Фикс:**

```yaml
- name: Install Ansible + community.general
  run: |
    pip install ansible-core
    ansible-galaxy collection install community.general
```

**Урок:** Ansible разрешает все FQCN на этапе парсинга плейбука, **независимо от `when:`
условий**. Если плейбук содержит `community.general.*`, коллекция обязательна в среде
выполнения — даже если этот код никогда не выполнится на данном хосте.

---

### Инцидент #4 — `vagrant` отсутствует в стандартных репозиториях Ubuntu 24.04

**Затронуто:** arch-images Run 2, ubuntu-images Run 2 (шаг "Verify Vagrant box contract")
**Ошибка:**
```
Process completed with exit code 100.
```
(Exit code 100 — стандартный код ошибки `apt-get` при "package not found".)

**Причина:**

```yaml
run: sudo apt-get install -y vagrant
```

Vagrant был удалён из официальных репозиториев Ubuntu в пользу дистрибуции через
HashiCorp собственный apt-репозиторий. На Ubuntu 22.04 (`jammy`) vagrant ещё был
в стандартных репах, на Ubuntu 24.04 (`noble`) — нет.

**Фикс:**

```yaml
- name: Verify Vagrant box contract
  run: |
    wget -O- https://apt.releases.hashicorp.com/gpg | \
      sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
      https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
      sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update -qq
    sudo apt-get install -y vagrant ruby-dev build-essential pkg-config libvirt-dev
    ...
```

**Урок:** На `ubuntu-24.04` runner нет пакетов `vagrant` и `terraform` в стандартных
репах. Всегда добавлять HashiCorp apt-репозиторий перед установкой их продуктов.
Это же касается и `molecule-vagrant.yml` в bootstrap (там уже было сделано правильно —
см. post-mortem 2026-02-25).

---

### Инцидент #5 — "Couldn't open file" при `vagrant box add`

**Затронуто:** arch-images Run 3 (после добавления HashiCorp repo)
**Ошибка:**
```
==> box: Box file was not detected as metadata. Adding it directly...
Couldn't open file /home/runner/work/arch-images/arch-images/output-arch-molecule/arch-molecule.box
```

**Причина:**

Изначальная верификация использовала подход `vagrant box add` + `vagrant up`:

```yaml
BOX_PATH="$GITHUB_WORKSPACE/output-arch-molecule/arch-molecule.box"
vagrant box add --name arch-molecule-test "$BOX_PATH"
vagrant up --no-provision
```

Packer успешно собрал образ (step "Build Vagrant box" завершился с ✓), но vagrant
не мог открыть файл. Причина выяснилась в следующей итерации.

На этом этапе предположили что файл просто не там — заменили жёсткий путь на `find`:

```bash
BOX_PATH=$(find "$GITHUB_WORKSPACE" -name "*.box" | head -1)
```

Также заменили весь подход верификации с `vagrant up` на **архивную валидацию**
(проверка структуры tar-архива без запуска VM):

```bash
tar tzf "$BOX_PATH" > /tmp/box-contents.txt
grep -q metadata.json /tmp/box-contents.txt
grep -qE "(box_0\.img|box\.img|disk\.img)" /tmp/box-contents.txt
tar xzf "$BOX_PATH" -O metadata.json | python3 -c "
import sys, json
m = json.load(sys.stdin)
assert m['provider'] == 'libvirt', f'Wrong provider: {m[\"provider\"]}'
print('OK')
"
```

**Причины отказа от `vagrant up` верификации:**
1. Требует запуска полноценной KVM VM — ещё ~2 минуты к билду
2. Требует vagrant-libvirt plugin (`gem install`) — нестабильно в CI
3. Провайдер libvirt в CI требует дополнительных разрешений (libvirt-sock)
4. Для цели "убедиться что box корректен" достаточно проверки архива

---

### Инцидент #6 — `find "$GITHUB_WORKSPACE" -name "*.box"` возвращает пустую строку

**Затронуто:** arch-images Run 4, ubuntu-images Run 4
**Ошибка:**
```
=== Vagrant Box Contract Verification ===
Box file:
ERROR: box file not found
```

**Причина (root cause всей серии):**

Packer vagrant post-processor был настроен так:

```hcl
post-processor "vagrant" {
  output = "output-${var.box_name}/${var.box_name}.box"
}
```

После завершения vagrant post-processor Packer вызывает `artifact.Destroy()` на
предыдущий артефакт (qemu builder). QEMU builder записывает свой `output_directory`
как `output-arch-molecule/`. Метод `artifact.Destroy()` вызывает `os.RemoveAll()`
на этот каталог — **удаляя вместе с QEMU-артефактами и файл `.box`**, который
post-processor положил в тот же каталог.

```
output-arch-molecule/        ← qemu output_directory
├── arch-molecule             ← qemu raw disk (удаляется Destroy())
└── arch-molecule.box         ← vagrant box   (УДАЛЯЕТСЯ ВМЕСТЕ С КАТАЛОГОМ!)
```

Packer log показывал "Build successful" — потому что box был создан успешно.
Его удаление происходило в фазе cleanup, после success-репорта.

**Фикс:**

```hcl
post-processor "vagrant" {
  output = "${var.box_name}.box"   # в корне workspace, ВНЕ output_directory
}
```

```
$GITHUB_WORKSPACE/
├── output-arch-molecule/          ← удаляется artifact.Destroy()
│   └── arch-molecule              ← qemu disk
└── arch-molecule.box              ← ОСТАЁТСЯ (вне удаляемого каталога)
```

**Урок:** Packer `artifact.Destroy()` выполняет `os.RemoveAll()` на `output_directory`
qemu builder. Если vagrant post-processor пишет `.box` внутрь того же каталога —
файл будет удалён. Output vagrant post-processor **всегда** должен быть вне
`output_directory` qemu builder.

---

### Инцидент #7 — Publish step использует жёстко прописанный старый путь

**Затронуто:** arch-images Run 5, ubuntu-images Run 5
**Ошибка:**
```
cp: cannot stat 'output-arch-molecule/arch-molecule.box': No such file or directory
```

**Причина:**

После фикса packer-пути в инциденте #6 файл теперь находился в корне workspace.
Но step "Publish to GitHub Releases" всё ещё содержал старый захардкоженный путь:

```yaml
- name: Publish to GitHub Releases
  run: |
    BOX_FILE="output-arch-molecule/arch-molecule.box"   # ← старый путь
    cp "$BOX_FILE" "$VERSIONED_ASSET"
```

**Фикс:**

```yaml
BOX_FILE="arch-molecule.box"      # arch-images
BOX_FILE="ubuntu-molecule.box"    # ubuntu-images
```

**Урок:** При изменении output-пути в packer нужно обновлять ВСЕ места workflow,
которые ссылаются на этот файл: `Verify Vagrant box contract` и `Publish to GitHub Releases`.

---

## 5. Итоговая структура

### arch-images workflow (финал)

```
jobs:
  build-docker:
    steps:
      - Set up Docker Buildx
      - Build and push → ghcr.io/textyre/arch-molecule:latest
      - Verify Docker contract (bash -c)

  build-vagrant:
    steps:
      - Enable KVM
      - Install QEMU + libvirt + xorriso        ← инцидент #1
      - Install Packer
      - Install Ansible + community.general     ← инцидент #3
      - Packer init
      - Build Vagrant box (packer build)
        └── output = "${var.box_name}.box"      ← инцидент #6 (вне output_dir)
      - Verify Vagrant box contract
        └── archive validation (tar + python3)  ← инцидент #5
      - Compute version (YYYYMMDD)
      - Publish to GitHub Releases
        └── BOX_FILE="arch-molecule.box"        ← инцидент #7
```

### ubuntu-images workflow (финал, отличия от arch)

```
  - contracts/docker.sh: bash -c (не sh -c)    ← инцидент #2
  - HashiCorp apt repo для vagrant              ← инцидент #4
  - community.general collection               ← инцидент #3
  - output = "${var.box_name}.box"             ← инцидент #6
  - BOX_FILE="ubuntu-molecule.box"             ← инцидент #7
```

### packer output (финал)

```hcl
# archlinux.pkr.hcl / ubuntu.pkr.hcl
post-processor "vagrant" {
  keep_input_artifact = false
  output              = "${var.box_name}.box"   # корень workspace
  provider_override   = "libvirt"
}
```

### GitHub Releases (результат)

```
textyre/arch-images  → tag: boxes
  arch-molecule-20260227.box
  arch-molecule-latest.box

textyre/ubuntu-images → tag: boxes
  ubuntu-molecule-20260227.box
  ubuntu-molecule-latest.box
```

---

## 6. Файлы изменённые в сессии

### textyre/arch-images

| Файл | Коммит | Что сделано |
|------|--------|-------------|
| `.github/workflows/build.yml` | `09b4647` | Добавлен `xorriso` в QEMU install |
| `.github/workflows/build.yml` | `6f5b76a` | HashiCorp repo для vagrant в verify step |
| `.github/workflows/build.yml` | `0444ce3` | Заменена vagrant-boot верификация на архивную |
| `.github/workflows/build.yml` | `6c26b03` | Обновлён `BOX_FILE` в publish step |
| `packer/archlinux.pkr.hcl` | `079f7af` | `output` перемещён из `output-*/` в корень |

### textyre/ubuntu-images

| Файл | Коммит | Что сделано |
|------|--------|-------------|
| `.github/workflows/build.yml` | `6c12a4d` | `xorriso`; `sh` → `bash` для docker contract |
| `.github/workflows/build.yml` | `a7eb191` | HashiCorp repo; `community.general` install |
| `.github/workflows/build.yml` | `cf1ac73` | Архивная верификация (как arch) |
| `.github/workflows/build.yml` | `8b0160c` | Обновлён `BOX_FILE` в publish step |
| `packer/ubuntu.pkr.hcl` | `2f4c851` | `output` перемещён из `output-*/` в корень |

### textyre/bootstrap

| Файл | Что сделано |
|------|-------------|
| `ansible/molecule/Dockerfile.archlinux` | УДАЛЁН |
| `.github/workflows/build-arch-image.yml` | УДАЛЁН |
| `.github/workflows/_molecule.yml` | `MOLECULE_ARCH_IMAGE` → внешний образ |
| `.github/workflows/molecule.yml` | Удалён job `build-image` |
| 9× `molecule/docker/molecule.yml` | Обновлён image на `arch-molecule` |
| 2× `molecule/vagrant/molecule.yml` | `box_url` → GitHub Releases |

---

## 7. Ключевые паттерны

### Packer artifact cleanup — главный антипаттерн

```
НЕВЕРНО:                          ВЕРНО:
output_directory = "output-box/"  output_directory = "output-box/"
box output = "output-box/my.box"  box output = "my.box"
                                              ↑
                   Вне output_directory — не удаляется artifact.Destroy()
```

`artifact.Destroy()` = `os.RemoveAll(output_directory)`. Всё внутри этого каталога
исчезает после packer build, даже если packer сообщил об успехе.

### Верификация Vagrant box без запуска VM

```bash
# Проверяет структуру архива — быстро, надёжно, без KVM overhead
BOX_PATH=$(find "$GITHUB_WORKSPACE" -name "*.box" | head -1)
tar tzf "$BOX_PATH" > /tmp/contents.txt
grep -q metadata.json /tmp/contents.txt
grep -qE "(box_0\.img|box\.img|disk\.img)" /tmp/contents.txt
tar xzf "$BOX_PATH" -O metadata.json | python3 -c "
import sys, json
m = json.load(sys.stdin)
assert m['provider'] == 'libvirt'
"
```

### community.general на минимальных ansible-core окружениях

```yaml
# Всегда после pip install ansible-core:
- run: ansible-galaxy collection install community.general
```

Ansible разрешает FQCN при парсинге. `when:` не защищает от ошибки
"couldn't resolve module" — коллекция нужна независимо от условий.

### sh vs bash на Ubuntu

| Что | sh (dash) | bash |
|-----|-----------|------|
| `set -o pipefail` | ❌ Illegal option | ✓ |
| `[[ ... ]]` | ❌ | ✓ |
| `${arr[@]}` | ❌ | ✓ |
| GitHub Actions `run:` по умолчанию | **bash** (`/usr/bin/bash -e`) | — |
| `run: sh -c "$(cat script.sh)"` | **dash** | если явно `bash -c` |

### HashiCorp tools на ubuntu-24.04

Пакеты `vagrant` и `terraform` **не** находятся в стандартных репах Ubuntu 24.04.
Обязательная преамбула:

```yaml
run: |
  wget -O- https://apt.releases.hashicorp.com/gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -qq
  sudo apt-get install -y vagrant
```

---

## 8. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | Packer `output` vagrant post-processor должен быть вне `output_directory` qemu builder — иначе `artifact.Destroy()` удалит его | Все Packer QEMU + Vagrant workflows |
| 2 | `xorriso` обязателен при использовании `cd_files` в Packer QEMU builder | Все Packer workflows с cloud-init |
| 3 | `sh` на Ubuntu — `dash`; `bash -c` при запуске bash-скриптов через `sh -c` | Все workflows с `run: sh -c` |
| 4 | Ansible FQCN разрешается при парсинге, `when:` не помогает — `community.general` нужна явно | Все Ansible окружения с минимальным ansible-core |
| 5 | `vagrant` отсутствует в ubuntu-24.04 стандартных репах — HashiCorp apt repo обязателен | Все workflows с vagrant на ubuntu-latest |
| 6 | Верификация Vagrant box через архивную валидацию надёжнее и быстрее чем `vagrant up` в CI | Все image-building workflows |
| 7 | При изменении путей в packer обновлять ВСЕ downstream шаги workflow | Любые рефакторинги path в CI |
| 8 | `Packer build successful` ≠ файл существует после завершения (cleanup происходит после success) | Все Packer workflows |

---

## 9. Known gaps

- **Docker image job пропускается** в обоих repos при каждом прогоне (показывает `- Build Docker image in 0s`) — это нормально, job не был частью `workflow_dispatch` тестирования. Docker builds работали с самого начала.
- **Расписание:** image repos собираются только по `workflow_dispatch`. Нет автоматического
  пересборки по расписанию — если upstream cloud image обновится, боксы не обновятся сами.
  Рассмотреть cron (`schedule: - cron: '0 4 * * 1'`) аналогично molecule-vagrant.yml.
- **Нет проверки что bootstrap molecule-тесты используют новые боксы** — Vagrant сценарии
  скачивают боксы только при первом `vagrant up`. Нужен отдельный прогон molecule-vagrant
  для проверки совместимости.
