# ssh_keys Molecule Tests — First-Pass Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make ssh_keys molecule tests pass in all three GHA environments (Docker Arch+Ubuntu, Vagrant arch-vm, Vagrant ubuntu-base), then merge the PR and clean up the worktree.

**Architecture:** Two targeted code fixes (typo + missing pacman cache update) in the molecule scenarios, delivered via an isolated git worktree + PR. CI is the test oracle — if GHA fails, diagnose from logs, fix, push, repeat until green.

**Tech Stack:** Ansible molecule (docker + vagrant/libvirt), GitHub Actions, `gh` CLI for monitoring runs.

---

## Pre-flight: Key paths

| What | Where |
|------|-------|
| Role root | `ansible/roles/ssh_keys/` |
| Default scenario | `ansible/roles/ssh_keys/molecule/default/molecule.yml` |
| Docker scenario | `ansible/roles/ssh_keys/molecule/docker/` |
| Vagrant scenario | `ansible/roles/ssh_keys/molecule/vagrant/` |
| Shared playbooks | `ansible/roles/ssh_keys/molecule/shared/` |
| Design doc | `docs/plans/2026-03-01-ssh-keys-molecule-fix-design.md` |
| GHA docker workflow | `.github/workflows/_molecule.yml` |
| GHA vagrant workflow | `.github/workflows/_molecule-vagrant.yml` |

---

### Task 1: Create the worktree

**Files:** none (git operation only)

**Step 1: Create worktree on new branch**

```bash
git worktree add .worktrees/ssh-keys-molecule fix/ssh-keys-molecule-tests 2>/dev/null \
  || git worktree add .worktrees/ssh-keys-molecule -b fix/ssh-keys-molecule-tests
```

Expected: directory `.worktrees/ssh-keys-molecule/` created, branch `fix/ssh-keys-molecule-tests` checked out there.

**Step 2: Verify worktree exists**

```bash
git worktree list
```

Expected: three lines — main worktree, plus `.worktrees/ssh-keys-molecule` on `fix/ssh-keys-molecule-tests`.

**Step 3: Switch all subsequent file edits to the worktree path**

All file edits in the remaining tasks use the worktree root:
`/Users/umudrakov/Documents/bootstrap/.worktrees/ssh-keys-molecule/`

---

### Task 2: Fix the `idempotency` typo in `default/molecule.yml`

**Files:**
- Modify: `ansible/roles/ssh_keys/molecule/default/molecule.yml` (in worktree)

**Step 1: Read the file to confirm the typo**

Read: `ansible/roles/ssh_keys/molecule/default/molecule.yml`

Look for `test_sequence` block — it currently contains `- idempotency` which is invalid; molecule only accepts `- idempotence`.

**Step 2: Apply the fix**

Replace `- idempotency` with `- idempotence` in the `test_sequence` section.

Result after fix:
```yaml
scenario:
  test_sequence:
    - syntax
    - prepare
    - converge
    - idempotence
    - verify
```

**Step 3: Commit**

```bash
cd .worktrees/ssh-keys-molecule
git add ansible/roles/ssh_keys/molecule/default/molecule.yml
git commit -m "fix(ssh_keys): fix idempotency typo → idempotence in default scenario"
```

---

### Task 3: Add Arch pacman cache update to `vagrant/prepare.yml`

**Files:**
- Modify: `ansible/roles/ssh_keys/molecule/vagrant/prepare.yml` (in worktree)

**Step 1: Read the current file**

Read: `ansible/roles/ssh_keys/molecule/vagrant/prepare.yml`

Confirm the file starts with a play that has `gather_facts: true` and goes straight to `- name: Update apt cache (Ubuntu)`.

**Step 2: Add the Arch task before the apt task**

Insert before the "Update apt cache (Ubuntu)" task:

```yaml
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'
```

The final tasks block order should be:
1. Update pacman cache (Arch) ← new
2. Update apt cache (Ubuntu) ← existing
3. Create test user ← existing
4. Create absent_user ← existing
5. Create .ssh dir for absent_user ← existing
6. Plant authorized_keys for absent_user ← existing
7. Set molecule_test_user fact ← existing

**Step 3: Commit**

```bash
cd .worktrees/ssh-keys-molecule
git add ansible/roles/ssh_keys/molecule/vagrant/prepare.yml
git commit -m "fix(ssh_keys): add pacman cache update to vagrant prepare (Arch pattern)"
```

---

### Task 4: Push the branch and open a PR

**Step 1: Push the branch**

```bash
cd .worktrees/ssh-keys-molecule
git push -u origin fix/ssh-keys-molecule-tests
```

**Step 2: Open the PR**

```bash
gh pr create \
  --title "fix(ssh_keys): fix molecule tests for Docker + Vagrant" \
  --body "$(cat <<'EOF'
## Summary

- Fix `idempotency` typo → `idempotence` in `default/molecule.yml` (invalid step name)
- Add `community.general.pacman: update_cache: true` to `vagrant/prepare.yml` for Arch (matches gpu_drivers/package_manager pattern)

## Test plan

- [ ] `test (ssh_keys) / ssh_keys (Arch+Ubuntu/systemd)` passes
- [ ] `test-vagrant (ssh_keys, arch-vm) / ssh_keys — arch-vm` passes
- [ ] `test-vagrant (ssh_keys, ubuntu-base) / ssh_keys — ubuntu-base` passes

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed. Note it for monitoring.

---

### Task 5: Monitor GHA and iterate until green

**Step 1: Wait for GHA to start**

```bash
sleep 30
gh run list --repo textyre/bootstrap --limit 5 \
  --json status,conclusion,name,headBranch,databaseId
```

Look for runs on branch `fix/ssh-keys-molecule-tests`.

**Step 2: Watch run status**

```bash
# Get the run ID of the Molecule run on our branch, then watch it
RUN_ID=$(gh run list --repo textyre/bootstrap --limit 10 \
  --json databaseId,headBranch,name \
  | python3 -c "
import json,sys
runs=json.load(sys.stdin)
for r in runs:
    if r['headBranch']=='fix/ssh-keys-molecule-tests' and 'Molecule' in r['name']:
        print(r['databaseId']); break
")
gh run watch "$RUN_ID" --repo textyre/bootstrap
```

**Step 3: If all green → proceed to Task 6**

**Step 4: If failures → diagnose**

```bash
# List failed jobs
gh run view "$RUN_ID" --repo textyre/bootstrap --json jobs \
  | python3 -c "
import json,sys
data=json.load(sys.stdin)
for j in data['jobs']:
    if j['conclusion']!='success':
        print(j['databaseId'], j['name'])
"

# Get logs for a failed job
gh run view --job <JOB_ID> --repo textyre/bootstrap --log-failed
```

**Step 5: Fix the identified issue**

Read the error, identify the root cause, make the minimal fix in the worktree, commit, push:

```bash
cd .worktrees/ssh-keys-molecule
# ... make fix ...
git add <changed files>
git commit -m "fix(ssh_keys): <describe fix>"
git push
```

GHA will automatically re-run on the new push.

**Step 6: Repeat Steps 2–5 until all three environments are green**

---

### Task 6: Merge the PR

**Step 1: Confirm all checks pass**

```bash
gh pr checks --repo textyre/bootstrap fix/ssh-keys-molecule-tests
```

All should show `pass`.

**Step 2: Merge**

```bash
gh pr merge fix/ssh-keys-molecule-tests \
  --repo textyre/bootstrap \
  --squash \
  --delete-branch
```

Use `--squash` to keep master history clean. `--delete-branch` removes the remote branch.

---

### Task 7: Clean up the local worktree

**Step 1: Remove the worktree**

```bash
cd /Users/umudrakov/Documents/bootstrap
git worktree remove .worktrees/ssh-keys-molecule
```

**Step 2: Verify cleanup**

```bash
git worktree list
```

Expected: only the main worktree listed.

**Step 3: Delete local branch (if not already deleted)**

```bash
git branch -d fix/ssh-keys-molecule-tests 2>/dev/null || true
```

---

## Failure patterns & known fixes

If GHA fails for reasons not anticipated by the two initial fixes, consult these patterns (from MEMORY.md and recent fixes):

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `EBUSY` on `/etc/hosts` or `/etc/resolv.conf` | Docker bind-mount; `lineinfile` atomic rename fails | Add `unsafe_writes: true` to the task |
| `hostname` not found (Arch) | `inetutils` not in arch-base Docker image | Use `python3 -c "import socket; print(socket.gethostname())"` |
| Vagrant fails with SSL/openssl errors | Stale Arch box ABI | Add `pacman -Syu` in vagrant prepare |
| `ansible.posix.authorized_key` not found | Collection not installed | Check `requirements.yml` includes `ansible.posix >= 1.5.0` |
| Idempotence `changed` on `authorized_key` | Bug in module exclusivity logic | Investigate `exclusive` flag interactions |
| DNS errors after `pacman -Syu` in vagrant | systemd replaces `/etc/resolv.conf` with IPv6 stub | Copy `8.8.8.8\n1.1.1.1` to `/etc/resolv.conf` with `unsafe_writes: true` after upgrade |
