# sysctl Molecule Tests Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make sysctl role molecule tests pass in all 3 CI environments: Docker (Arch+Ubuntu systemd), Vagrant arch-vm, Vagrant ubuntu-base.

**Architecture:** Two minimal changes. (1) Handler guards against Docker where kernel params are read-only even in privileged containers — same `ansible_virtualization_type` detection pattern already used in verify.yml. (2) Add vagrant prepare.yml for package cache consistency, following project convention (all vagrant scenarios have prepare.yml).

**Tech Stack:** Ansible, Molecule (docker + vagrant/libvirt drivers), GitHub Actions.

**Design doc:** `docs/plans/2026-03-01-sysctl-molecule-fix-design.md`

---

### Task 1: Create git worktree for isolated work

**Files:** none (git plumbing)

**Step 1: Create worktree on new branch**

```bash
git worktree add .worktrees/sysctl-molecule-fix -b fix/sysctl-molecule-tests
```

Expected: `.worktrees/sysctl-molecule-fix/` created, branch `fix/sysctl-molecule-tests` checked out there.

**Step 2: Verify worktree**

```bash
git worktree list
```

Expected: shows both main worktree and `.worktrees/sysctl-molecule-fix`.

---

### Task 2: Fix handler — skip sysctl apply in Docker containers

**Files:**
- Modify: `ansible/roles/sysctl/handlers/main.yml`

**Context:** `sysctl -e --system` exits non-zero when kernel params are EPERM (read-only) in Docker. The `-e` flag only suppresses ENOENT (unknown key), not EPERM. Adding `when:` condition mirrors the pattern already in `shared/verify.yml` line 61: `ansible_virtualization_type | default('') == 'docker'`.

**Step 1: Read the current handler**

```
ansible/roles/sysctl/handlers/main.yml
```

Current content:
```yaml
- name: Apply sysctl settings
  listen: "reload sysctl"
  ansible.builtin.command: sysctl -e --system
  changed_when: false
```

**Step 2: Add `when` condition to handler**

Replace with:
```yaml
---
# Handlers for sysctl role

- name: Apply sysctl settings
  listen: "reload sysctl"
  # -e = ignore unknown keys (kernel.unprivileged_userns_clone absent on non-hardened kernels)
  # --system = applies all /etc/sysctl.d/*.conf
  # when: skip in Docker — kernel params are EPERM even with privileged:true.
  #        verify.yml Tier 2 skips live checks in containers, so nothing is lost.
  ansible.builtin.command: sysctl -e --system
  changed_when: false
  when: ansible_virtualization_type | default('') != 'docker'
```

**Step 3: Commit**

```bash
cd .worktrees/sysctl-molecule-fix
git add ansible/roles/sysctl/handlers/main.yml
git commit -m "fix(sysctl): skip sysctl --system handler in Docker containers

In Docker, even with privileged:true, kernel.* params are EPERM (read-only).
The -e flag only suppresses ENOENT (unknown keys), not EPERM.
Mirror the container detection already used in shared/verify.yml Tier 2."
```

---

### Task 3: Add vagrant prepare.yml

**Files:**
- Create: `ansible/roles/sysctl/molecule/vagrant/prepare.yml`

**Context:** Project convention — all vagrant scenarios have `prepare.yml` to update package cache before converge. Reference: `ansible/roles/gpu_drivers/molecule/vagrant/prepare.yml`. For sysctl, no extra packages needed beyond what's pre-installed in the custom boxes (procps/procps-ng are base packages). Just cache update.

**Step 1: Create the file**

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

**Step 2: Verify the vagrant/molecule.yml already references prepare**

The `molecule/vagrant/molecule.yml` does NOT have an explicit `playbooks.prepare` override, which means molecule uses `prepare.yml` from the scenario directory by default. Confirm there is no explicit override that would skip it.

**Step 3: Commit**

```bash
git add ansible/roles/sysctl/molecule/vagrant/prepare.yml
git commit -m "fix(sysctl): add vagrant prepare.yml for package cache update

Follow project convention: all vagrant scenarios have prepare.yml.
Updates Arch/Ubuntu package cache before converge.
No extra packages needed — procps/procps-ng pre-installed in base boxes."
```

---

### Task 4: Push branch and open PR

**Step 1: Push branch**

```bash
git push -u origin fix/sysctl-molecule-tests
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "fix(sysctl): fix molecule tests for Docker + Vagrant" \
  --body "$(cat <<'EOF'
## Summary

- Fix `sysctl -e --system` handler failing in Docker: add `when: ansible_virtualization_type | default('') != 'docker'` to skip in containers where kernel params are EPERM even with `privileged: true`
- Add `molecule/vagrant/prepare.yml` following project convention for package cache update

## Root cause

The `-e` flag on `sysctl` only suppresses unknown-key errors (ENOENT), not permission errors (EPERM). In Docker containers, kernel-namespace parameters are read-only regardless of `privileged: true`. Handler exited non-zero → converge failed.

## Test plan

- [ ] Docker: `molecule test -s docker` in `ansible/roles/sysctl/` — triggered automatically by this PR
- [ ] Vagrant arch-vm: trigger via `workflow_dispatch` on `molecule.yml` with `role_filter=sysctl`
- [ ] Vagrant ubuntu-base: same dispatch, both platforms run in matrix

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Note PR URL for monitoring**

```bash
gh pr view --json url -q .url
```

---

### Task 5: Monitor CI — Docker test

**Step 1: Watch Docker test run**

```bash
gh run list --workflow=molecule.yml --limit 5
```

Wait for the run triggered by the PR push. Expected: `sysctl (Arch+Ubuntu/systemd)` job passes.

**Step 2: If Docker test fails — inspect logs**

```bash
gh run view <run-id> --log-failed
```

Look for EPERM or other errors. Fix accordingly, commit to same branch, push.

---

### Task 6: Trigger and monitor Vagrant tests

**Step 1: Trigger Vagrant test via workflow_dispatch**

```bash
gh workflow run molecule.yml \
  --ref fix/sysctl-molecule-tests \
  --field role_filter=sysctl
```

This triggers both `test-vagrant` matrix jobs: `arch-vm` and `ubuntu-base`.

**Step 2: Watch Vagrant runs**

```bash
gh run list --workflow=molecule.yml --limit 5
```

Wait for both platforms to complete. Expected: both pass.

**Step 3: If Vagrant test fails — inspect**

```bash
gh run view <run-id> --log-failed
```

Common issues to check:
- `sysctl -e --system` returns non-zero on VM → verify `-e` handles all param variants
- Missing package → add to prepare.yml
- Live sysctl value mismatch → check if kernel supports the parameter

---

### Task 7: Merge PR and clean up worktree

**Step 1: Confirm all checks green**

```bash
gh pr checks
```

Expected: all checks pass (Docker + both Vagrant).

**Step 2: Merge PR**

```bash
gh pr merge --squash --delete-branch
```

**Step 3: Pull master in main worktree**

```bash
cd /Users/umudrakov/Documents/bootstrap
git pull origin master
```

**Step 4: Remove worktree**

```bash
git worktree remove .worktrees/sysctl-molecule-fix
```

**Step 5: Verify cleanup**

```bash
git worktree list
git branch -a | grep sysctl
```

Expected: worktree gone, remote branch deleted by `--delete-branch`, no local branch remains.
