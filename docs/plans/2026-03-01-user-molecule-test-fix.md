# User Role Molecule Test Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix molecule tests for the `user` role so they pass in all 3 CI environments: Docker (Arch + Ubuntu), Vagrant arch-vm, Vagrant ubuntu-base.

**Architecture:** Infrastructure-only fixes to `molecule/` — no role task changes. Fix prepare.yml gaps (missing group creation, missing logrotate install), create a vagrant-specific converge.yml so VMs get appropriate variable overrides distinct from Docker containers.

**Tech Stack:** Ansible, Molecule, Docker driver, Vagrant+libvirt driver. GitHub Actions workflow `molecule.yml` auto-detects changed roles and runs Docker + Vagrant tests for all platforms.

---

### Task 1: Create worktree

**Files:** git worktree at `.claude/worktrees/fix-user-molecule/`

**Step 1: Create isolated worktree**

```bash
git worktree add .claude/worktrees/fix-user-molecule -b fix/user-molecule-tests
```

Expected: new directory `.claude/worktrees/fix-user-molecule/` on branch `fix/user-molecule-tests`.

**Step 2: Verify worktree**

```bash
git worktree list
```

Expected: shows two worktrees — master + fix/user-molecule-tests.

---

### Task 2: Fix docker/prepare.yml

**Files:**
- Modify: `ansible/roles/user/molecule/docker/prepare.yml`

**Problem:** `testuser_extra` is added to the `video` group during converge. If `video` doesn't exist in the Docker container, `ansible.builtin.user` fails with "group 'video' does not exist".

**Step 1: Read current file**

```bash
cat ansible/roles/user/molecule/docker/prepare.yml
```

**Step 2: Replace file with fixed version**

The fixed `docker/prepare.yml` must:
- Update pacman cache (Arch only)
- Update apt cache (Ubuntu only)
- Ensure `video` group exists on all platforms (no `when:` guard needed — `ansible.builtin.group` is cross-platform)
- Ensure `logrotate` is installed on all platforms (already there, verify it stays)

Full content:

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

    - name: Ensure video group exists (required by testuser_extra)
      ansible.builtin.group:
        name: video
        state: present

    - name: Ensure logrotate is installed (for sudo logrotate test)
      ansible.builtin.package:
        name: logrotate
        state: present
```

**Step 3: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/user/molecule/docker/prepare.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 4: Commit**

```bash
git add ansible/roles/user/molecule/docker/prepare.yml
git commit -m "fix(user/molecule): ensure video group exists in docker prepare"
```

---

### Task 3: Fix vagrant/prepare.yml

**Files:**
- Modify: `ansible/roles/user/molecule/vagrant/prepare.yml`

**Problems:**
1. `logrotate` only installed for Arch — Ubuntu skipped entirely
2. No `update_cache: true` for Arch before installing packages
3. `video` group not created (same issue as Docker)

**Step 1: Read current file**

```bash
cat ansible/roles/user/molecule/vagrant/prepare.yml
```

**Step 2: Replace with fixed version**

Full content:

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

    - name: Ensure video group exists (required by testuser_extra)
      ansible.builtin.group:
        name: video
        state: present

    - name: Ensure logrotate is installed (Arch)
      community.general.pacman:
        name: logrotate
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Ensure logrotate is installed (Ubuntu)
      ansible.builtin.apt:
        name: logrotate
        state: present
      when: ansible_facts['os_family'] == 'Debian'
```

Note: Using platform-specific modules (`pacman`, `apt`) instead of generic `package` for vagrant to avoid ambiguity with package manager detection on fresh VMs.

**Step 3: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/user/molecule/vagrant/prepare.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 4: Commit**

```bash
git add ansible/roles/user/molecule/vagrant/prepare.yml
git commit -m "fix(user/molecule): fix vagrant prepare — logrotate for Ubuntu, video group, update_cache"
```

---

### Task 4: Create vagrant/converge.yml

**Files:**
- Create: `ansible/roles/user/molecule/vagrant/converge.yml`

**Problem:** Shared `converge.yml` has `user_manage_password_aging: false` (safe for Docker containers). Vagrant VMs are real machines and should use representative variable values. A separate vagrant converge allows VM-specific overrides without touching the shared/docker config.

**Step 1: Create the file**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Override owner to a test user (don't modify real running user)
    user_owner:
      name: testuser_owner
      shell: /bin/bash
      groups:
        - "{{ user_sudo_group }}"
      password_hash: ""
      update_password: on_create
      umask: "027"
      password_max_age: 365
      password_min_age: 1
      password_warn_age: 7
    user_additional_users:
      - name: testuser_extra
        shell: /bin/bash
        groups:
          - video
        sudo: false
        password_hash: ""
        update_password: on_create
        umask: "077"
    user_manage_password_aging: false  # chage/shadow interactions vary across VMs
    user_manage_umask: true
    user_verify_root_lock: false       # vagrant boxes don't lock root by default
    user_sudo_logrotate_enabled: true
    user_sudo_log_input: false
    user_sudo_log_output: false

  roles:
    - role: user
```

**Step 2: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/user/molecule/vagrant/converge.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 3: Commit**

```bash
git add ansible/roles/user/molecule/vagrant/converge.yml
git commit -m "fix(user/molecule): add vagrant-specific converge.yml"
```

---

### Task 5: Update vagrant/molecule.yml to use local converge.yml

**Files:**
- Modify: `ansible/roles/user/molecule/vagrant/molecule.yml`

**Problem:** `vagrant/molecule.yml` currently points `converge` to `../shared/converge.yml`. Now that we have a local `vagrant/converge.yml`, point to it.

**Step 1: Read current file**

```bash
cat ansible/roles/user/molecule/vagrant/molecule.yml
```

**Step 2: Change the converge playbook reference**

Find this block:
```yaml
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
```

Replace with:
```yaml
  playbooks:
    prepare: prepare.yml
    converge: converge.yml
    verify: ../shared/verify.yml
```

**Step 3: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/user/molecule/vagrant/molecule.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

**Step 4: Commit**

```bash
git add ansible/roles/user/molecule/vagrant/molecule.yml
git commit -m "fix(user/molecule): point vagrant scenario to local converge.yml"
```

---

### Task 6: Lint check

**Step 1: Run ansible-lint on role**

On the remote VM (via ssh-run.sh):

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-lint ansible/roles/user/"
```

Expected: no violations, or only pre-existing ones unrelated to our changes. Fix any new violations before proceeding.

---

### Task 7: Push branch and open PR

**Step 1: Push the branch**

```bash
git push -u origin fix/user-molecule-tests
```

**Step 2: Create PR**

```bash
gh pr create \
  --title "fix(user): fix molecule tests for Docker + Vagrant" \
  --body "$(cat <<'EOF'
## Summary

- Fix `docker/prepare.yml`: create `video` group before converge so `testuser_extra` can be added to it
- Fix `vagrant/prepare.yml`: add `logrotate` install for Ubuntu, `video` group creation, `update_cache` for Arch
- Add `vagrant/converge.yml`: vagrant-specific variable overrides (separate from shared Docker converge)
- Update `vagrant/molecule.yml`: point converge to local file

## Test plan

- [ ] Docker scenario: Arch-systemd passes all steps (syntax/create/prepare/converge/idempotence/verify/destroy)
- [ ] Docker scenario: Ubuntu-systemd passes all steps
- [ ] Vagrant scenario: arch-vm passes all steps
- [ ] Vagrant scenario: ubuntu-base passes all steps

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

---

### Task 8: Monitor CI and iterate

**Step 1: Watch the CI run**

```bash
gh pr checks <PR-NUMBER> --watch
```

Expected: all checks green. If any fail:

**Step 2: Read failure logs**

```bash
gh run list --branch fix/user-molecule-tests
gh run view <RUN-ID> --log-failed
```

**Step 3: Fix failures, push, repeat**

Diagnose from logs → fix the relevant file → commit → push → watch.

Common failure patterns to look for:
- `group 'video' does not exist` → ensure prepare.yml runs before converge
- `logrotate: command not found` / package not found → check prepare.yml Ubuntu block
- `changed: 1` in idempotence → find non-idempotent task in role, investigate
- `failed_when` assertion failures in verify.yml → check actual vs expected values in logs

---

### Task 9: Merge and cleanup

Only after all CI checks pass:

**Step 1: Merge PR**

```bash
gh pr merge <PR-NUMBER> --squash --delete-branch
```

**Step 2: Remove worktree**

```bash
git worktree remove .claude/worktrees/fix-user-molecule
```

**Step 3: Update local master**

```bash
git fetch origin master
git merge origin/master
```

**Step 4: Confirm CI passed on master**

```bash
gh run list --branch master --limit 3
```

Expected: latest run shows green for the merge commit.
