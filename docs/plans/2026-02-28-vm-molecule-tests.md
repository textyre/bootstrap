# vm role — molecule tests in 3 environments: Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Docker + Vagrant molecule scenarios to the `vm` role so CI runs and passes in 3 environments (Docker Arch/Ubuntu, Vagrant arch-vm, Vagrant ubuntu-base), then merge via PR.

**Architecture:** Mirror the `pam_hardening` pattern — `shared/` converge+verify playbooks reused by `docker/` and `vagrant/` scenarios. Two role register-naming bugs fixed first (Docker unaffected; Vagrant fails without fix). No workflow changes needed — CI auto-detects scenarios by file presence.

**Tech Stack:** Ansible, Molecule, Docker (systemd containers), Vagrant/libvirt, GitHub Actions

---

## Task 1: Create feature branch

**Files:** none

**Step 1: Create and checkout branch**

```bash
git checkout -b fix/vm-molecule-tests
```

**Step 2: Verify**

```bash
git branch --show-current
```
Expected: `fix/vm-molecule-tests`

---

## Task 2: Fix register naming bug — `_install_packages.yml`

**Files:**
- Modify: `ansible/roles/vm/tasks/_install_packages.yml:35-45`

**Context:** `register: vm_pkg_install_result` but the `until:` condition and callers (e.g. `_reboot_flag.yml`) reference `_vm_pkg_install_result`. The `_` prefix is missing from `register:`. In Vagrant/KVM, the retry loop evaluates `_vm_pkg_install_result is succeeded` → undefined → always false → 3 retries exhausted → task fails even on successful install.

**Step 1: Edit `_install_packages.yml`**

Change line 40:
```yaml
# Before
register: vm_pkg_install_result

# After
register: _vm_pkg_install_result
```

**Step 2: Verify the fix looks correct**

Read the file and confirm `register: _vm_pkg_install_result` and `until: _vm_pkg_install_result is succeeded` now match.

**Step 3: Commit**

```bash
git add ansible/roles/vm/tasks/_install_packages.yml
git commit -m "fix(vm): fix register naming in _install_packages.yml — _vm_pkg_install_result"
```

---

## Task 3: Fix register naming bug — `_manage_services.yml`

**Files:**
- Modify: `ansible/roles/vm/tasks/_manage_services.yml:42-55`

**Context:** `register: vm_svc_result` but `failed_when` uses `_vm_svc_result is failed` and the report task uses `_vm_svc_result.results[idx]`. Same `_` prefix missing pattern. Causes `failed_when` to silently never trigger and the report task to error on `_vm_svc_result` undefined.

**Step 1: Edit `_manage_services.yml`**

Change line 51:
```yaml
# Before
register: vm_svc_result

# After
register: _vm_svc_result
```

**Step 2: Verify**

Read the file and confirm `register: _vm_svc_result`, `failed_when: - _vm_svc_result is failed`, and the report task's `_vm_svc_result.results[idx]` all use the same variable name.

**Step 3: Commit**

```bash
git add ansible/roles/vm/tasks/_manage_services.yml
git commit -m "fix(vm): fix register naming in _manage_services.yml — _vm_svc_result"
```

---

## Task 4: Create `molecule/shared/converge.yml`

**Files:**
- Create: `ansible/roles/vm/molecule/shared/converge.yml`

**Context:** Simple converge — apply the `vm` role. No `vars_files` references to vault or packages (role uses its own `defaults/main.yml`). This is shared by both docker and vagrant scenarios.

**Step 1: Create file**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: vm
```

**Step 2: Commit**

```bash
git add ansible/roles/vm/molecule/shared/converge.yml
git commit -m "feat(vm): add molecule/shared/converge.yml"
```

---

## Task 5: Create `molecule/shared/verify.yml`

**Files:**
- Create: `ansible/roles/vm/molecule/shared/verify.yml`

**Context:** Handles two CI environments detected at runtime:
- **Docker** (`virtualization_type` ∈ `['container', 'docker']`): `vm_is_guest` = false → role skips installs → assert fact file NOT created
- **Vagrant KVM** (`virtualization_type == 'kvm'`): `vm_is_guest` = true → assert `qemu-guest-agent` active + fact file has `hypervisor: kvm`

No `vars_files`. No `vm_reboot_required` assertion (set_fact not persisted between molecule phases).

**Step 1: Create file**

```yaml
---
- name: Verify vm role
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Capture virtualization facts
      ansible.builtin.set_fact:
        vm_verify_virt_type: "{{ ansible_facts['virtualization_type'] | default('none') }}"
        vm_verify_virt_role: "{{ ansible_facts['virtualization_role'] | default('NA') }}"

    - name: Debug virtualization environment
      ansible.builtin.debug:
        msg: "Environment: {{ vm_verify_virt_type }} / {{ vm_verify_virt_role }}"

    # === Docker (container) — vm_is_guest is false, no fact file expected ===

    - name: Stat guest fact file (container check)
      ansible.builtin.stat:
        path: /etc/ansible/facts.d/vm_guest.fact
      register: vm_verify_fact_stat
      when: vm_verify_virt_type in ['container', 'docker']

    - name: Assert fact file NOT created in container
      ansible.builtin.assert:
        that:
          - not vm_verify_fact_stat.stat.exists
        fail_msg: >-
          vm_guest.fact should NOT exist in container environment
          (vm_is_guest=false for container type)
        success_msg: "Correct: no guest fact file in container"
      when: vm_verify_virt_type in ['container', 'docker']

    # === Vagrant KVM — vm_is_guest is true, qemu-ga + fact file expected ===

    - name: Check qemu-guest-agent service (KVM)
      ansible.builtin.systemd:
        name: qemu-guest-agent
      register: vm_verify_qemu_ga
      when: vm_verify_virt_type == 'kvm' and vm_verify_virt_role == 'guest'

    - name: Assert qemu-guest-agent is active (KVM)
      ansible.builtin.assert:
        that:
          - vm_verify_qemu_ga.status.ActiveState == 'active'
        fail_msg: "qemu-guest-agent is not running on KVM guest"
        success_msg: "qemu-guest-agent is active"
      when: vm_verify_virt_type == 'kvm' and vm_verify_virt_role == 'guest'

    - name: Stat guest fact file (KVM)
      ansible.builtin.stat:
        path: /etc/ansible/facts.d/vm_guest.fact
      register: vm_verify_kvm_fact_stat
      when: vm_verify_virt_type == 'kvm' and vm_verify_virt_role == 'guest'

    - name: Assert fact file exists (KVM)
      ansible.builtin.assert:
        that:
          - vm_verify_kvm_fact_stat.stat.exists
        fail_msg: "vm_guest.fact not found — _set_facts.yml should have created it"
        success_msg: "Guest fact file exists"
      when: vm_verify_virt_type == 'kvm' and vm_verify_virt_role == 'guest'

    - name: Read fact file content (KVM)
      ansible.builtin.slurp:
        src: /etc/ansible/facts.d/vm_guest.fact
      register: vm_verify_kvm_fact_content
      when:
        - vm_verify_virt_type == 'kvm'
        - vm_verify_virt_role == 'guest'
        - vm_verify_kvm_fact_stat.stat.exists | default(false)

    - name: Assert fact file has correct hypervisor and is_guest (KVM)
      ansible.builtin.assert:
        that:
          - (vm_verify_kvm_fact_content.content | b64decode | from_json).hypervisor == 'kvm'
          - (vm_verify_kvm_fact_content.content | b64decode | from_json).is_guest == true
        fail_msg: "vm_guest.fact content incorrect — expected hypervisor=kvm, is_guest=true"
        success_msg: "Fact file content correct"
      when:
        - vm_verify_virt_type == 'kvm'
        - vm_verify_virt_role == 'guest'
        - vm_verify_kvm_fact_content is defined
        - vm_verify_kvm_fact_content is not skipped

    - name: Verify summary
      ansible.builtin.debug:
        msg: >-
          vm role verify passed:
          env={{ vm_verify_virt_type }}/{{ vm_verify_virt_role }}
```

**Step 2: Commit**

```bash
git add ansible/roles/vm/molecule/shared/verify.yml
git commit -m "feat(vm): add molecule/shared/verify.yml — container + KVM assertions"
```

---

## Task 6: Create `molecule/docker/molecule.yml`

**Files:**
- Create: `ansible/roles/vm/molecule/docker/molecule.yml`

**Context:** Exact mirror of `pam_hardening/molecule/docker/molecule.yml`. Two platforms: Arch-systemd and Ubuntu-systemd. Privileged + cgroup mount for systemd. Shared converge/verify via `../shared/`.

**Step 1: Create file**

```yaml
---
driver:
  name: docker

platforms:
  - name: Archlinux-systemd
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/arch-base:latest}"
    pre_build_image: true
    command: /usr/lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    privileged: true
    dns_servers:
      - 8.8.8.8
      - 8.8.4.4

  - name: Ubuntu-systemd
    image: "${MOLECULE_UBUNTU_IMAGE:-ghcr.io/textyre/ubuntu-base:latest}"
    pre_build_image: true
    command: /lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    privileged: true
    dns_servers:
      - 8.8.8.8
      - 8.8.4.4

provisioner:
  name: ansible
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
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
    - idempotence
    - verify
    - destroy
```

**Step 2: Commit**

```bash
git add ansible/roles/vm/molecule/docker/molecule.yml
git commit -m "feat(vm): add molecule/docker/molecule.yml — Arch+Ubuntu systemd platforms"
```

---

## Task 7: Create `molecule/docker/prepare.yml`

**Files:**
- Create: `ansible/roles/vm/molecule/docker/prepare.yml`

**Context:** OS-conditional cache update. `gather_facts: true` required for OS detection. Matches `pam_hardening` docker prepare pattern.

**Step 1: Create file**

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**Step 2: Commit**

```bash
git add ansible/roles/vm/molecule/docker/prepare.yml
git commit -m "feat(vm): add molecule/docker/prepare.yml — OS-conditional cache update"
```

---

## Task 8: Create `molecule/vagrant/molecule.yml`

**Files:**
- Create: `ansible/roles/vm/molecule/vagrant/molecule.yml`

**Context:** Exact mirror of `pam_hardening/molecule/vagrant/molecule.yml`. Both platforms in one scenario; CI workflow runs them in parallel via matrix. `skip-tags: report` to suppress role report formatting in Vagrant output.

**Step 1: Create file**

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
    memory: 2048
    cpus: 2
  - name: ubuntu-base
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
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
    - idempotence
    - verify
    - destroy
```

**Step 2: Commit**

```bash
git add ansible/roles/vm/molecule/vagrant/molecule.yml
git commit -m "feat(vm): add molecule/vagrant/molecule.yml — arch-vm + ubuntu-base platforms"
```

---

## Task 9: Create `molecule/vagrant/prepare.yml`

**Files:**
- Create: `ansible/roles/vm/molecule/vagrant/prepare.yml`

**Context:** Arch Vagrant box (`generic/arch`) has no Python pre-installed and stale keyring. Pattern from MEMORY.md: `gather_facts: false` → raw Python install → gather_facts → keyring refresh → `pacman -Syu` → DNS fix. Ubuntu just needs apt update. Cross-platform via `when:` on `os_family`.

**Step 1: Create file**

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false

  tasks:
    - name: Install Python on Arch (raw — no Python pre-installed on generic/arch)
      ansible.builtin.raw: pacman -Sy --noconfirm python
      when: inventory_hostname == 'arch-vm'
      changed_when: true

    - name: Gather facts
      ansible.builtin.setup:

    - name: Refresh Arch keyring (SigLevel=Never trick)
      ansible.builtin.shell: |
        pacman -Sy --noconfirm --config <(sed 's/SigLevel.*/SigLevel = Never/' /etc/pacman.conf) archlinux-keyring
        pacman-key --populate archlinux
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade (Arch)
      community.general.pacman:
        upgrade: true
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Fix DNS after pacman -Syu (systemd stub replaced resolv.conf)
      ansible.builtin.copy:
        content: "nameserver 8.8.8.8\nnameserver 1.1.1.1\n"
        dest: /etc/resolv.conf
        unsafe_writes: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**Step 2: Commit**

```bash
git add ansible/roles/vm/molecule/vagrant/prepare.yml
git commit -m "feat(vm): add molecule/vagrant/prepare.yml — Arch keyring+sysupgrade, apt update"
```

---

## Task 10: Sync to remote VM and run Docker test

**Context:** Per AGENTS.md, all molecule commands run on the remote VM. Sync local changes first, then run.

**Step 1: Sync changed files to remote VM**

```bash
bash scripts/ssh-scp-to.sh -r ansible/roles/vm/molecule/ /home/textyre/bootstrap/ansible/roles/vm/molecule/
bash scripts/ssh-scp-to.sh ansible/roles/vm/tasks/_install_packages.yml /home/textyre/bootstrap/ansible/roles/vm/tasks/_install_packages.yml
bash scripts/ssh-scp-to.sh ansible/roles/vm/tasks/_manage_services.yml /home/textyre/bootstrap/ansible/roles/vm/tasks/_manage_services.yml
```

**Step 2: Run Docker molecule test**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/vm && source /home/textyre/bootstrap/ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule test -s docker"
```

Expected: Both `Archlinux-systemd` and `Ubuntu-systemd` instances pass all stages (syntax → create → prepare → converge → idempotence → verify → destroy).

Key verify assertions to watch:
- `Assert fact file NOT created in container` → PASS on both platforms
- `Verify summary` → `env=container/guest`

**Step 3: If failures occur**

- Syntax errors in yaml files → fix and re-run
- `vm_is_guest` detection differs (e.g. type is `docker` not `container`) → update `when:` condition in `verify.yml` to include the actual type returned
- Debug: add `- ansible.builtin.debug: var=ansible_facts['virtualization_type']` to verify.yml temporarily

---

## Task 11: Run Vagrant Arch test

**Step 1: Run Vagrant molecule test for arch-vm only**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/vm && source /home/textyre/bootstrap/ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule test -s vagrant -- --limit arch-vm"
```

Expected: `arch-vm` passes all stages. Key assertions:
- `qemu-guest-agent is active` → PASS
- `Fact file content correct` → PASS (`hypervisor=kvm, is_guest=true`)

**Step 2: If `qemu-guest-agent` service fails to start**

Arch Vagrant VMs run KVM → `virtualization_type = kvm` → role installs `qemu-guest-agent`. If the service doesn't start inside vagrant, check `journalctl -u qemu-guest-agent` via debug tasks. The service needs a running QEMU virtio channel — should be present in KVM VMs.

**Step 3: If idempotence fails**

Check which task reports `changed`. Common causes: `copy` tasks that aren't idempotent, or `set_fact` being re-set. The role's `_set_facts.yml` only writes the fact file `when: vm_is_guest | bool` — should be idempotent on second run.

---

## Task 12: Run Vagrant Ubuntu test

**Step 1: Run Vagrant molecule test for ubuntu-base only**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/vm && source /home/textyre/bootstrap/ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule test -s vagrant -- --limit ubuntu-base"
```

Expected: same as arch-vm. Ubuntu uses `qemu-guest-agent` from apt (defined in `vars/Debian.yml`).

**Step 2: If failures differ from Arch**

Check that `vars/Debian.yml` defines `vm_kvm_packages: [qemu-guest-agent]` — it does. Check that the `Debian` os_family correctly loads via `include_vars` in `main.yml`.

---

## Task 13: Push branch and create PR

**Step 1: Verify clean state**

```bash
git status
git log --oneline -10
```

**Step 2: Push branch**

```bash
git push -u origin fix/vm-molecule-tests
```

**Step 3: Create PR**

```bash
gh pr create \
  --title "fix(vm): add molecule tests — docker + vagrant scenarios, fix register bugs" \
  --body "$(cat <<'EOF'
## Summary

- Add `molecule/docker/` scenario (Arch+Ubuntu systemd containers)
- Add `molecule/vagrant/` scenario (arch-vm + ubuntu-base via KVM)
- Add `molecule/shared/` converge+verify playbooks
- Fix `register:` naming bugs in `_install_packages.yml` and `_manage_services.yml` (missing `_` prefix caused Vagrant test failures)

## Test plan

- [ ] Docker CI: both Archlinux-systemd and Ubuntu-systemd pass all molecule stages
- [ ] Vagrant CI: arch-vm passes (qemu-guest-agent running, fact file correct)
- [ ] Vagrant CI: ubuntu-base passes (qemu-guest-agent running, fact file correct)
- [ ] Idempotence passes on all 3 platforms

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Task 14: Monitor CI and verify all checks pass

**Step 1: Watch CI run**

```bash
gh pr checks --watch
```

Or view in browser:
```bash
gh pr view --web
```

**Step 2: If Docker CI fails**

```bash
gh run view --log-failed
```

Consult the failure and fix on the branch. Push fix commits.

**Step 3: If Vagrant CI fails**

Vagrant CI runs on a schedule + PR trigger. Check `molecule-vagrant.yml` workflow. The `_molecule-vagrant.yml` reusable workflow handles the actual run. View logs:

```bash
gh run list --branch fix/vm-molecule-tests
gh run view <run-id> --log-failed
```

---

## Task 15: Merge

**Step 1: Confirm all checks green**

```bash
gh pr checks
```
Expected: all checks show ✓

**Step 2: Merge**

```bash
gh pr merge --squash --delete-branch
```

Or if commit-per-task style is preferred:
```bash
gh pr merge --merge --delete-branch
```
