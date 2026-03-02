# sysctl Boot Persistence Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure sysctl hardening values survive reboot on Ubuntu by renaming the drop-in file so it sorts after Ubuntu's `99-sysctl.conf`, and prove it with a new test that simulates boot.

**Architecture:** Two changes. First, a boot-persistence test is added to verify.yml — this test runs `sysctl --system` (same as systemd-sysctl does at boot) and re-asserts all security values. Second, the file is renamed `99-ansible.conf` → `99-z-ansible.conf` so it sorts last alphabetically and wins when systemd processes sysctl.d at boot.

The test is written before the fix to prove the fix is necessary. Without the rename, the test would catch the regression. With the rename, the test passes on all platforms including Ubuntu.

**Tech Stack:** Ansible roles, Molecule (Docker + Vagrant), GitHub Actions.

---

## Context

`/etc/sysctl.d/` files are processed in lexicographic order at boot by `systemd-sysctl.service` (equivalent of `sysctl --system`). Ubuntu ships `/etc/sysctl.d/99-sysctl.conf` as a symlink to `/etc/sysctl.conf`. Because `a` < `s`, our `99-ansible.conf` is processed **before** Ubuntu's file, which then overwrites some of our hardening values (confirmed: `fs.protected_fifos` reset from 2 to 1).

The handler already uses `-p <our-file>` (applied last during Ansible run), so Ansible runs appear correct. But reboot resets the values.

**Fix:** Rename to `99-z-ansible.conf` (`z` > `s` → sorts after Ubuntu's file → wins at boot).

**Test:** Simulate boot (`sysctl -e --system`) inside verify.yml on Vagrant and re-assert all security params. This test would have caught the original bug.

---

### Task 1: Create worktree and branch

**Step 1: Create worktree**

```bash
cd /Users/umudrakov/Documents/bootstrap
git worktree add .worktrees/sysctl-boot-persistence -b fix/sysctl-boot-persistence
```

Expected: `.worktrees/sysctl-boot-persistence/` created, branch `fix/sysctl-boot-persistence` based on master.

**Step 2: Verify**

```bash
git worktree list
```

Expected: new entry with `.worktrees/sysctl-boot-persistence` and branch `fix/sysctl-boot-persistence`.

---

### Task 2: Add boot-persistence test to verify.yml

This is the TDD step — write the test first. On the current codebase (file still named `99-ansible.conf`) this test would FAIL on ubuntu-base because `sysctl --system` would let Ubuntu's file override ours. After the rename in Task 3, it passes.

**File:** `ansible/roles/sysctl/molecule/shared/verify.yml`

**Step 1: Read the current verify.yml to know where to insert**

The file ends with the Tier 3 section (currently around line 252–265). The new Tier 2b section goes AFTER the last Tier 2 assert block (filesystem hardening, around line 247) and BEFORE Tier 3.

**Step 2: Add the boot-persistence section**

Insert after the "Assert live filesystem hardening sysctl values match expected" block and before the Tier 3 comment, the following content:

```yaml
    # =====================================================================
    # Tier 2b: Boot persistence (Vagrant only — skipped in Docker)
    # Runs sysctl --system to replicate what systemd-sysctl does at boot,
    # then re-asserts all security values. Catches file-ordering bugs:
    # if our sysctl.d file sorts before a system-provided file (e.g. Ubuntu's
    # 99-sysctl.conf), that file overwrites our settings at every reboot.
    # =====================================================================
    - name: "Boot persistence | simulate systemd-sysctl boot sequence"
      ansible.builtin.command: sysctl -e --system
      changed_when: false
      when: not _sysctl_in_container

    - name: "Boot persistence | read kernel hardening values after boot simulation"
      ansible.builtin.command: "sysctl -n {{ item.param }}"
      register: _sysctl_verify_kernel_boot
      changed_when: false
      failed_when: false
      loop: "{{ _sysctl_kernel_hardening_params }}"
      loop_control:
        label: "{{ item.param }}"
      when: not _sysctl_in_container

    - name: "Boot persistence | assert kernel hardening values survive reboot"
      ansible.builtin.assert:
        that: item.stdout | string == item.item.expected | string
        fail_msg: >-
          [BOOT] {{ item.item.param }}: expected={{ item.item.expected }}
          got={{ item.stdout }} — value overwritten at boot by a later sysctl.d file
        success_msg: "[BOOT] {{ item.item.param }}={{ item.stdout }} OK"
      loop: "{{ _sysctl_verify_kernel_boot.results }}"
      loop_control:
        label: "{{ item.item.param }}"
      when:
        - not _sysctl_in_container
        - item.rc == 0

    - name: "Boot persistence | read network hardening values after boot simulation"
      ansible.builtin.command: "sysctl -n {{ item.param }}"
      register: _sysctl_verify_network_boot
      changed_when: false
      failed_when: false
      loop: "{{ _sysctl_network_hardening_params }}"
      loop_control:
        label: "{{ item.param }}"
      when: not _sysctl_in_container

    - name: "Boot persistence | assert network hardening values survive reboot"
      ansible.builtin.assert:
        that: item.stdout | string == item.item.expected | string
        fail_msg: >-
          [BOOT] {{ item.item.param }}: expected={{ item.item.expected }}
          got={{ item.stdout }} — value overwritten at boot by a later sysctl.d file
        success_msg: "[BOOT] {{ item.item.param }}={{ item.stdout }} OK"
      loop: "{{ _sysctl_verify_network_boot.results }}"
      loop_control:
        label: "{{ item.item.param }}"
      when:
        - not _sysctl_in_container
        - item.rc == 0

    - name: "Boot persistence | read filesystem hardening values after boot simulation"
      ansible.builtin.command: "sysctl -n {{ item.param }}"
      register: _sysctl_verify_fs_boot
      changed_when: false
      failed_when: false
      loop: "{{ _sysctl_filesystem_hardening_params }}"
      loop_control:
        label: "{{ item.param }}"
      when: not _sysctl_in_container

    - name: "Boot persistence | assert filesystem hardening values survive reboot"
      ansible.builtin.assert:
        that: item.stdout | string == item.item.expected | string
        fail_msg: >-
          [BOOT] {{ item.item.param }}: expected={{ item.item.expected }}
          got={{ item.stdout }} — value overwritten at boot by a later sysctl.d file
        success_msg: "[BOOT] {{ item.item.param }}={{ item.stdout }} OK"
      loop: "{{ _sysctl_verify_fs_boot.results }}"
      loop_control:
        label: "{{ item.item.param }}"
      when:
        - not _sysctl_in_container
        - item.rc == 0
```

**Step 3: Also update Tier 1 stat path** (anticipating the rename in Task 3 — update both in this commit so the test and the fix are atomic):

In the Tier 1 section, change:
```yaml
    - name: Stat sysctl drop-in file
      ansible.builtin.stat:
        path: /etc/sysctl.d/99-ansible.conf
```
to:
```yaml
    - name: Stat sysctl drop-in file
      ansible.builtin.stat:
        path: /etc/sysctl.d/99-z-ansible.conf
```

And in the assert message:
```yaml
        fail_msg: "/etc/sysctl.d/99-ansible.conf does not exist"
```
to:
```yaml
        fail_msg: "/etc/sysctl.d/99-z-ansible.conf does not exist"
```

**Step 4: Commit**

```bash
cd /Users/umudrakov/Documents/bootstrap/.worktrees/sysctl-boot-persistence
git add ansible/roles/sysctl/molecule/shared/verify.yml
git commit -m "test(sysctl): add boot-persistence Tier 2b verify — sysctl --system re-asserts security values"
```

---

### Task 3: Rename drop-in file and update handler

**Files:**
- `ansible/roles/sysctl/tasks/deploy.yml` — rename dest
- `ansible/roles/sysctl/handlers/main.yml` — update -p path and comments

**Step 1: Update deploy.yml**

Change:
```yaml
    dest: /etc/sysctl.d/99-ansible.conf
```
to:
```yaml
    dest: /etc/sysctl.d/99-z-ansible.conf
```

**Step 2: Update handlers/main.yml**

Replace the full file content:

```yaml
---
# Handlers for sysctl role

- name: Apply sysctl settings
  listen: "reload sysctl"
  # -e = игнорировать ошибки неизвестных параметров (например kernel.unprivileged_userns_clone
  #      отсутствует на стандартном upstream ядре — distro-agnostic поведение)
  # -p = применить ТОЛЬКО наш файл. Имя 99-z-ansible.conf выбрано намеренно:
  #      'z' > 's' лексикографически, поэтому файл сортируется ПОСЛЕ Ubuntu's
  #      99-sysctl.conf → /etc/sysctl.conf и выигрывает при sysctl --system
  #      (systemd-sysctl при загрузке).
  # changed_when: false — изменение репортит template-таск (notify), не handler
  # when: пропустить в Docker — kernel params read-only (EPERM) даже с privileged:true.
  #       Tier 2 verify тоже пропускает live-checks в контейнерах.
  ansible.builtin.command: sysctl -e -p /etc/sysctl.d/99-z-ansible.conf
  changed_when: false
  when: ansible_virtualization_type | default('') != 'docker'
```

**Step 3: Commit**

```bash
git add ansible/roles/sysctl/tasks/deploy.yml ansible/roles/sysctl/handlers/main.yml
git commit -m "fix(sysctl): rename drop-in to 99-z-ansible.conf for boot persistence on Ubuntu"
```

---

### Task 4: Push, open PR, monitor CI

**Step 1: Push branch**

```bash
git push -u origin fix/sysctl-boot-persistence
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "fix(sysctl): ensure hardening values survive reboot on Ubuntu" \
  --body "$(cat <<'EOF'
## Problem

`/etc/sysctl.d/99-ansible.conf` sorts before Ubuntu's `/etc/sysctl.d/99-sysctl.conf`
(symlink → `/etc/sysctl.conf`) alphabetically (`a` < `s`). At boot, `systemd-sysctl`
processes files in this order, so Ubuntu's defaults overwrite our hardening values
(confirmed: `fs.protected_fifos` reset to 1, expected 2).

The previous handler fix (`sysctl -p <our-file>`) only applied values correctly
during Ansible runs — not at reboot.

## Fix

Rename drop-in: `99-ansible.conf` → `99-z-ansible.conf` (`z` > `s`, sorts last).

## Test

New Tier 2b in `verify.yml` runs `sysctl -e --system` (simulates systemd-sysctl
boot sequence) then re-asserts all kernel/network/filesystem hardening values.
This test would catch any future regression where file ordering breaks boot persistence.

## Test plan

- [ ] Docker CI passes (Tier 1 checks 99-z-ansible.conf path, no live checks)
- [ ] Vagrant arch-vm passes (Tier 2 + Tier 2b boot simulation)
- [ ] Vagrant ubuntu-base passes (Tier 2b catches the previously broken case)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Trigger and monitor Docker CI**

Docker CI triggers automatically on PR push. Monitor:
```bash
gh pr checks <PR_NUMBER> --watch
```

**Step 4: Trigger Vagrant CI via workflow_dispatch**

```bash
gh workflow run molecule-vagrant.yml \
  --field role=sysctl \
  --field scenario=vagrant \
  --ref fix/sysctl-boot-persistence
```

Monitor:
```bash
gh run list --workflow=molecule-vagrant.yml --limit 5
gh run view <RUN_ID> --log-failed
```

**Step 5: Confirm all checks pass**

```bash
gh pr checks <PR_NUMBER>
```

Expected: all 6 checks green (Ansible Lint, YAML Lint, Docker Arch, Docker Ubuntu, Vagrant arch-vm, Vagrant ubuntu-base).

---

### Task 5: Merge PR and clean up worktree

**Step 1: Merge with squash**

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

**Step 2: Remove worktree**

```bash
cd /Users/umudrakov/Documents/bootstrap
git worktree remove .worktrees/sysctl-boot-persistence
```

**Step 3: Pull master**

```bash
git pull origin master
```

**Step 4: Delete local branch**

```bash
git branch -d fix/sysctl-boot-persistence
```

**Step 5: Verify**

```bash
git worktree list
git log --oneline -3
```

Expected: worktree gone, new squash commit on master.

---

## Success criteria

- `99-z-ansible.conf` deployed to all managed machines
- Vagrant ubuntu-base Tier 2b: `fs.protected_fifos` = 2 after `sysctl --system`
- All 6 CI checks green
- Boot persistence test exists as regression guard
