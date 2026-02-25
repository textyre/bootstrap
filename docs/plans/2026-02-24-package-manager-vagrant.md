# package_manager Vagrant KVM Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Добавить molecule vagrant сценарий для роли `package_manager` с параллельным тестированием Arch Linux и Ubuntu 24.04 на GitHub Actions через KVM.

**Architecture:** Один molecule сценарий `vagrant` с двумя платформами (`arch-vm`, `ubuntu-noble`). GitHub Actions workflow с matrix по платформам — каждый job запускает `molecule test -s vagrant --platform-name <platform>`. Переиспользуются `shared/converge.yml` и `shared/verify.yml` без изменений.

**Tech Stack:** molecule 25.12.0, molecule-plugins[vagrant] 25.8.12, vagrant-libvirt, KVM/qemu, Vagrant boxes: `archlinux/archlinux` + `generic/ubuntu2404`

---

## Task 1: Создать molecule/vagrant/molecule.yml

**Files:**
- Create: `ansible/roles/package_manager/molecule/vagrant/molecule.yml`
- Create: `ansible/roles/package_manager/molecule/vagrant/prepare.yml`

**Step 1: Создать molecule.yml**

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: archlinux/archlinux
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: generic/ubuntu2404
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotency
    - verify
    - destroy
```

**Step 2: Создать prepare.yml**

Нужен для обновления кэша пакетного менеджера перед converge. Vagrant boxes могут иметь устаревший кэш.

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Update pacman cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**Step 3: Проверить синтаксис YAML**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && \
  molecule syntax -s vagrant"
# working dir: ansible/roles/package_manager
```

Ожидается: `INFO     Running vagrant > syntax` без ошибок.

> Примечание: molecule-plugins[vagrant] должен быть установлен в venv на VM. Если нет — `pip install molecule-plugins[vagrant]`.

**Step 4: Commit**

```bash
git add ansible/roles/package_manager/molecule/vagrant/
git commit -m "feat(package_manager): add vagrant molecule scenario (Arch + Ubuntu)"
```

---

## Task 2: Создать .github/workflows/molecule-vagrant.yml

**Files:**
- Create: `.github/workflows/molecule-vagrant.yml`

**Step 1: Создать workflow**

```yaml
---
name: "Molecule Vagrant (KVM)"

on:
  schedule:
    - cron: '0 4 * * 1'  # Weekly, Monday 04:00 UTC
  workflow_dispatch:
    inputs:
      role:
        description: 'Role to test (must have molecule/vagrant/ scenario)'
        default: 'package_manager'
        required: false

jobs:
  vagrant-test:
    name: "${{ inputs.role || 'package_manager' }} — ${{ matrix.platform }}"
    runs-on: ubuntu-latest  # НЕ container — нужен /dev/kvm на хосте

    strategy:
      matrix:
        platform: [arch-vm, ubuntu-noble]
      fail-fast: false

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | \
            sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Install libvirt + vagrant
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y \
            libvirt-daemon-system libvirt-dev qemu-kvm \
            vagrant ruby-dev build-essential pkg-config
          sudo systemctl start libvirtd
          sudo chmod a+rw /var/run/libvirt/libvirt-sock
          vagrant plugin install vagrant-libvirt

      - name: Set up Python + molecule
        run: |
          python3 -m venv .venv
          .venv/bin/pip install --quiet --upgrade pip
          .venv/bin/pip install --quiet \
            "ansible-core==2.20.1" \
            "molecule==25.12.0" \
            "molecule-plugins[vagrant]==25.8.12" \
            "jmespath" "rich"

      - name: Install Ansible Galaxy collections
        run: .venv/bin/ansible-galaxy collection install -r ansible/requirements.yml

      - name: Run Molecule
        env:
          PY_COLORS: "1"
          ANSIBLE_FORCE_COLOR: "1"
        run: |
          .venv/bin/molecule test -s vagrant --platform-name ${{ matrix.platform }}
        working-directory: "ansible/roles/${{ inputs.role || 'package_manager' }}"
```

**Step 2: Проверить синтаксис YAML workflow**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/molecule-vagrant.yml'))" && echo OK
```

Ожидается: `OK`

**Step 3: Commit**

```bash
git add .github/workflows/molecule-vagrant.yml
git commit -m "ci: add molecule-vagrant workflow (KVM, Arch + Ubuntu matrix)"
```

---

## Task 3: Запустить и верифицировать в CI

**Step 1: Push и запустить workflow вручную**

```bash
git push
```

Затем в GitHub: Actions → Molecule Vagrant (KVM) → Run workflow.

**Step 2: Проверить оба matrix job**

Ожидаемый порядок шагов в каждом job:
```
PLAY [Converge] ...
TASK [package_manager : ...] ...
PLAY [Verify package_manager role] ...
```

Для `arch-vm` — проходят блоки `os_family == Archlinux` (pacman.conf, paccache, makepkg).
Для `ubuntu-noble` — проходят блоки `os_family == Debian` (apt parallel, dpkg).

**Step 3: Если провал — диагностика**

Частые проблемы:
- `vagrant-libvirt` не может подключиться к libvirt → проверить `sudo chmod a+rw /var/run/libvirt/libvirt-sock`
- Box `archlinux/archlinux` не найден → box зарегистрирован в Vagrant Cloud, должен скачаться автоматически
- `molecule-plugins[vagrant]` версия несовместима → проверить `pip show molecule-plugins`
- Arch box: `pacman -Sy` не работает → возможно устаревший keyring, добавить `pacman-key --refresh-keys` в prepare.yml

---

## Итоговая структура файлов

```
ansible/roles/package_manager/
  molecule/
    vagrant/
      molecule.yml     ← новый
      prepare.yml      ← новый
    shared/
      converge.yml     ← без изменений
      verify.yml       ← без изменений
    docker/            ← без изменений

.github/workflows/
  molecule-vagrant.yml ← новый
  molecule.yml         ← без изменений
```
