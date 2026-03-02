# gpu_drivers Molecule Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix two confirmed bugs in gpu_drivers molecule tests so all 3 CI environments pass (Docker Arch+Ubuntu, Vagrant Arch, Vagrant Ubuntu).

**Architecture:** Two targeted file edits — one variable name fix in `tasks/initramfs.yml`, one missing apt block in `molecule/docker/prepare.yml`. No structural changes. Each fix is independent and can be committed separately.

**Tech Stack:** Ansible, Molecule, Docker driver, Vagrant+libvirt driver, GitHub Actions

---

### Task 0: Create worktree

**Files:**
- (no files — worktree setup)

**Step 1: Create git worktree for this branch**

```bash
git worktree add .claude/worktrees/gpu-drivers-molecule-fix -b fix/gpu-drivers-molecule-tests
```

Expected output: `Preparing worktree (new branch 'fix/gpu-drivers-molecule-tests')`

**Step 2: Verify worktree**

```bash
git worktree list
```

Expected: shows both main tree and new worktree at `.claude/worktrees/gpu-drivers-molecule-fix`

---

### Task 1: Fix Bug 1 — initramfs.yml variable name

**Files:**
- Modify: `ansible/roles/gpu_drivers/tasks/initramfs.yml:22-26`

**Context:** Task `Check if dracut is available` registers result as `gpu_drivers_dracut_check`. Task `Set initramfs tool fact` references `_gpu_drivers_dracut_check` (with extra underscore). On Ubuntu/Debian, `_gpu_drivers_dracut_check` is undefined → Ansible error. On Arch it short-circuits to `mkinitcpio` so the bug is silent.

**Step 1: Verify the bug in the file**

Read `ansible/roles/gpu_drivers/tasks/initramfs.yml` lines 9-27.
Expected: `register: gpu_drivers_dracut_check` on one line, `_gpu_drivers_dracut_check` (underscore prefix) in the set_fact expression below.

**Step 2: Apply the fix**

In `ansible/roles/gpu_drivers/tasks/initramfs.yml`, change the `Set initramfs tool fact` task:

```yaml
# BEFORE (buggy):
- name: Set initramfs tool fact
  ansible.builtin.set_fact:
    gpu_drivers_initramfs_tool: >-
      {{ 'mkinitcpio' if ansible_facts['os_family'] == 'Archlinux'
         else ('dracut' if (_gpu_drivers_dracut_check is not skipped
                           and _gpu_drivers_dracut_check.rc == 0)
         else 'initramfs-tools') }}
  when: gpu_drivers_manage_initramfs
  tags: ['gpu', 'nvidia']

# AFTER (fixed):
- name: Set initramfs tool fact
  ansible.builtin.set_fact:
    gpu_drivers_initramfs_tool: >-
      {{ 'mkinitcpio' if ansible_facts['os_family'] == 'Archlinux'
         else ('dracut' if (gpu_drivers_dracut_check is not skipped
                           and gpu_drivers_dracut_check.rc == 0)
         else 'initramfs-tools') }}
  when: gpu_drivers_manage_initramfs
  tags: ['gpu', 'nvidia']
```

Only change: remove the `_` prefix from both occurrences of `_gpu_drivers_dracut_check`.

**Step 3: Run ansible-lint on the file**

From the worktree root, on the remote VM:
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-lint ansible/roles/gpu_drivers/tasks/initramfs.yml"
```
Expected: no errors (or only pre-existing warnings)

**Step 4: Run molecule syntax check**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/gpu_drivers && source ../../.venv/bin/activate && molecule syntax -s docker"
```
Expected: `INFO  Sanity checks passed.`

**Step 5: Commit**

```bash
cd .claude/worktrees/gpu-drivers-molecule-fix
git add ansible/roles/gpu_drivers/tasks/initramfs.yml
git commit -m "fix(gpu_drivers): fix variable name in initramfs tool detection

_gpu_drivers_dracut_check was an undefined variable reference.
The registered variable is gpu_drivers_dracut_check (no underscore).
This caused an Ansible error on Ubuntu/Debian when gpu_drivers_manage_initramfs: true."
```

---

### Task 2: Fix Bug 2 — docker/prepare.yml missing Ubuntu pciutils

**Files:**
- Modify: `ansible/roles/gpu_drivers/molecule/docker/prepare.yml`

**Context:** `prepare.yml` only installs pciutils for Arch. Ubuntu path only runs `apt update`. The converge.yml compensates, but prepare.yml should be self-sufficient per molecule convention. The vagrant/prepare.yml already has the correct Ubuntu block.

**Step 1: View current file**

Read `ansible/roles/gpu_drivers/molecule/docker/prepare.yml`.
Expected: only Arch pciutils task, no Ubuntu pciutils task.

**Step 2: Apply the fix**

Add Ubuntu pciutils task after the existing Arch task:

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

    - name: Install pciutils (required by gpu_drivers preflight)
      community.general.pacman:
        name: pciutils
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Install pciutils (Ubuntu)
      ansible.builtin.apt:
        name: pciutils
        state: present
      when: ansible_facts['os_family'] == 'Debian'
```

**Step 3: Run ansible-lint**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-lint ansible/roles/gpu_drivers/molecule/docker/prepare.yml"
```
Expected: no errors

**Step 4: Commit**

```bash
cd .claude/worktrees/gpu-drivers-molecule-fix
git add ansible/roles/gpu_drivers/molecule/docker/prepare.yml
git commit -m "fix(gpu_drivers): install pciutils for Ubuntu in docker prepare.yml

Docker prepare only handled Arch. Ubuntu path got pciutils incidentally
via converge.yml pre_tasks, but prepare should be self-sufficient."
```

---

### Task 3: Push branch and open PR

**Step 1: Push the branch**

```bash
cd .claude/worktrees/gpu-drivers-molecule-fix
git push -u origin fix/gpu-drivers-molecule-tests
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "fix(gpu_drivers): fix molecule tests for Docker + Vagrant" \
  --body "$(cat <<'EOF'
## Summary

- Fix undefined variable `_gpu_drivers_dracut_check` in `tasks/initramfs.yml` — caused Ansible error on Ubuntu/Debian with default `gpu_drivers_manage_initramfs: true`
- Add pciutils install for Ubuntu in `molecule/docker/prepare.yml` — prepare was only handling Arch

## Test plan

- [ ] Docker test passes (Arch + Ubuntu platforms)
- [ ] Vagrant Arch test passes
- [ ] Vagrant Ubuntu test passes
- [ ] All idempotence checks pass (second run = zero changes)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Note the PR URL**

Save the PR URL for monitoring.

---

### Task 4: Monitor CI and fix any additional failures

**Step 1: Watch the CI run**

```bash
gh pr checks --watch
```

Or check individual job status:
```bash
gh run list --branch fix/gpu-drivers-molecule-tests --limit 5
```

**Step 2: If Docker job fails — read logs**

```bash
gh run view <run-id> --log-failed
```

**Step 3: Triage any new failures**

Common failure patterns to look for:
- Package not found: wrong package name for Ubuntu 24.04 (e.g. `intel-media-va-driver` renamed)
- Idempotence failure: task runs on second converge (template/file changes on every run)
- Permission error: wrong `mode:` in template or file task
- Service not found: NVIDIA services attempted on non-NVIDIA path

For each new failure: fix → commit → push (CI auto-re-runs on new push).

**Step 4: If Vagrant Arch fails**

Arch-specific checks:
- pciutils available after pacman update
- Pacman cache fresh (arch-base box is our own, should be fresh)
- No DKMS failures (Intel path skips all DKMS tasks)

**Step 5: If Vagrant Ubuntu fails**

Ubuntu-specific checks:
- `intel-media-va-driver` package available in Ubuntu 24.04 noble repos
- `vulkan-tools` available
- `mesa-vulkan-drivers` available

If any package is wrong, fix `tasks/install-debian.yml` and `molecule/shared/verify.yml` accordingly.

---

### Task 5: Merge PR and clean up

**Prerequisites:** All CI checks green (Docker + both Vagrant platforms).

**Step 1: Verify all checks pass**

```bash
gh pr checks
```
Expected: all checks show ✓

**Step 2: Merge PR**

```bash
gh pr merge --squash --delete-branch
```

Use squash merge to keep master history clean.

**Step 3: Remove worktree**

```bash
git worktree remove .claude/worktrees/gpu-drivers-molecule-fix
```

**Step 4: Verify cleanup**

```bash
git worktree list
```
Expected: only main worktree remains.

**Step 5: Pull master**

```bash
git pull
```
