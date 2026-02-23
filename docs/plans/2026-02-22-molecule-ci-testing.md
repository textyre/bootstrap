# Molecule CI Testing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Docker-based Molecule testing for the timezone role, running in GitHub Actions with a reusable workflow pattern.

**Architecture:** Reusable GitHub Actions workflow (`_molecule.yml`) called by per-role callers. Shared Dockerfile for Arch+systemd. New `docker/` molecule scenario alongside existing `default/` (VM).

**Tech Stack:** Molecule, molecule-plugins[docker], Docker, GitHub Actions, Ansible, systemd

---

### Task 1: Add Docker dependencies to requirements.txt

**Files:**
- Modify: `ansible/requirements.txt`

**Step 1: Add molecule-plugins and docker packages**

Add after the `molecule==25.12.0` line:

```
molecule-plugins[docker]==23.6.1
docker>=7.0.0
```

**Step 2: Commit**

```bash
git add ansible/requirements.txt
git commit -m "deps: add molecule-plugins[docker] and docker to requirements"
```

---

### Task 2: Create shared Dockerfile for Arch + systemd

**Files:**
- Create: `ansible/molecule/Dockerfile.archlinux`

**Step 1: Write the Dockerfile**

```dockerfile
FROM archlinux:base

ENV container=docker

RUN pacman -Sy --noconfirm python sudo && \
    rm -rf /var/cache/pacman/pkg/*

RUN (for i in /lib/systemd/system/sysinit.target.wants/*; do \
      [ "$i" = "/lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup.service" ] || rm -f "$i"; \
    done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*; \
    rm -f /etc/systemd/system/*.wants/*; \
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*

STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup", "/tmp", "/run"]
CMD ["/usr/lib/systemd/systemd"]
```

**Step 2: Commit**

```bash
git add ansible/molecule/Dockerfile.archlinux
git commit -m "ci: add shared Arch+systemd Dockerfile for molecule testing"
```

---

### Task 3: Create molecule docker scenario for timezone

**Files:**
- Create: `ansible/roles/timezone/molecule/docker/molecule.yml`
- Create: `ansible/roles/timezone/molecule/docker/converge.yml`
- Create: `ansible/roles/timezone/molecule/docker/verify.yml`

**Step 1: Write molecule.yml**

```yaml
---
driver:
  name: docker

platforms:
  - name: archlinux-systemd
    image: archlinux:base
    dockerfile: ../../../../molecule/Dockerfile.archlinux
    pre_build_image: false
    command: /usr/lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    privileged: true

provisioner:
  name: ansible
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - converge
    - idempotence
    - verify
    - destroy
```

**Step 2: Write converge.yml**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: timezone
      vars:
        timezone_name: "Asia/Almaty"
        packages_tzdata:
          default: "tzdata"
```

**Step 3: Write verify.yml**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: false

  vars:
    _test_timezone: "Asia/Almaty"

  tasks:
    - name: Check /etc/localtime symlink
      ansible.builtin.command: readlink -f /etc/localtime
      register: _verify_localtime
      changed_when: false

    - name: Assert timezone matches
      ansible.builtin.assert:
        that:
          - _test_timezone in _verify_localtime.stdout
        fail_msg: "Expected '{{ _test_timezone }}' in '{{ _verify_localtime.stdout }}'"

    - name: Check tzdata is installed
      ansible.builtin.command: pacman -Q tzdata
      register: _verify_tzdata
      changed_when: false
      failed_when: _verify_tzdata.rc != 0

    - name: Show result
      ansible.builtin.debug:
        msg: "Timezone verification passed: {{ _test_timezone }}, tzdata installed"
```

**Step 4: Commit**

```bash
git add ansible/roles/timezone/molecule/docker/
git commit -m "test(timezone): add molecule docker scenario for CI testing"
```

---

### Task 4: Create reusable GitHub Actions workflow

**Files:**
- Create: `.github/workflows/_molecule.yml`

**Step 1: Write the reusable workflow**

```yaml
---
name: "Molecule Test"

on:
  workflow_call:
    inputs:
      role_name:
        required: true
        type: string
        description: "Role name (directory under ansible/roles/)"
      molecule_scenario:
        required: false
        type: string
        default: docker
        description: "Molecule scenario name"
      python_version:
        required: false
        type: string
        default: "3.12"

jobs:
  test:
    name: "${{ inputs.role_name }} (Arch/systemd)"
    runs-on: ubuntu-latest
    env:
      PY_COLORS: "1"
      ANSIBLE_FORCE_COLOR: "1"

    concurrency:
      group: "molecule-${{ inputs.role_name }}-${{ github.event.pull_request.number || github.sha }}"
      cancel-in-progress: true

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "${{ inputs.python_version }}"
          cache: pip
          cache-dependency-path: ansible/requirements.txt

      - name: Install dependencies
        run: pip install -r ansible/requirements.txt molecule-plugins[docker] docker

      - name: Install Ansible collections
        run: ansible-galaxy collection install community.general

      - name: Run Molecule
        run: molecule test -s "${{ inputs.molecule_scenario }}"
        working-directory: "ansible/roles/${{ inputs.role_name }}"
```

**Step 2: Commit**

```bash
git add .github/workflows/_molecule.yml
git commit -m "ci: add reusable molecule workflow for role testing"
```

---

### Task 5: Create timezone caller workflow

**Files:**
- Create: `.github/workflows/molecule-timezone.yml`

**Step 1: Write the caller workflow**

```yaml
---
name: "Molecule: timezone"

on:
  push:
    branches: [master]
    paths:
      - 'ansible/roles/timezone/**'
      - 'ansible/roles/common/**'
      - 'ansible/molecule/Dockerfile.*'
      - '.github/workflows/molecule-timezone.yml'
      - '.github/workflows/_molecule.yml'
  pull_request:
    branches: [master]
    paths:
      - 'ansible/roles/timezone/**'
      - 'ansible/roles/common/**'
      - 'ansible/molecule/Dockerfile.*'
      - '.github/workflows/molecule-timezone.yml'
      - '.github/workflows/_molecule.yml'
  workflow_dispatch:

jobs:
  test:
    uses: ./.github/workflows/_molecule.yml
    with:
      role_name: timezone
```

**Step 2: Commit**

```bash
git add .github/workflows/molecule-timezone.yml
git commit -m "ci(timezone): add molecule test workflow"
```

---

### Task 6: Verify — push and check GitHub Actions

**Step 1: Push branch and verify workflow triggers**

```bash
git push origin HEAD
```

**Step 2: Check GitHub Actions UI**

- Verify `Molecule: timezone` workflow appears
- Verify it runs: syntax → create → converge → idempotence → verify → destroy
- Verify green status

**Step 3: If failure — read logs, fix, push again**

Common failure points:
- Dockerfile build fails → check pacman mirrors, package names
- systemd doesn't start → check cgroup volumes, privileged flag
- `community.general.timezone` not found → check galaxy install step
- converge fails → check ANSIBLE_ROLES_PATH resolves common role
- idempotence fails → check role reports changed=0 on second run
