# packages molecule fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix `verify.yml` so molecule tests actually verify all configured packages are installed, then get all 3 CI environments green (Docker, Vagrant Arch, Vagrant Ubuntu).

**Architecture:** Single file change — remove `vars_files` from `verify.yml` and add `| default([])` guards. The `vars_files` directive has Ansible precedence 14, which silently overrides molecule inventory group_vars (precedence 4), making the expected package list empty and all assertions trivially true.

**Tech Stack:** Ansible, Molecule, community.general.pacman, ansible.builtin.apt, ansible.builtin.package_facts

---

### Task 0: Create git worktree

**Files:** none

**Step 1: Create worktree for the fix branch**

```bash
cd /Users/umudrakov/Documents/bootstrap
git worktree add .claude/worktrees/fix/packages-molecule-fix -b fix/packages-molecule-fix
```

**Step 2: Verify worktree is on the right branch**

```bash
git -C .claude/worktrees/fix/packages-molecule-fix status
```

Expected: `On branch fix/packages-molecule-fix`, nothing to commit.

---

### Task 1: Fix verify.yml — remove vars_files, add default guards, drop redundant check_mode section

**Files:**
- Modify: `ansible/roles/packages/molecule/shared/verify.yml`

**Step 1: Read the current file**

```bash
cat ansible/roles/packages/molecule/shared/verify.yml
```

**Step 2: Replace the file with the fixed version**

Write the following content to `ansible/roles/packages/molecule/shared/verify.yml` (in the worktree at `.claude/worktrees/fix/packages-molecule-fix/`):

```yaml
---
- name: Verify packages role
  hosts: all
  become: true
  gather_facts: true

  tasks:

    # ---- Build expected package list ----

    - name: Build combined package list (mirrors tasks/main.yml logic)
      ansible.builtin.set_fact:
        packages_verify_expected: >-
          {{ (packages_base | default([]))
             + (packages_editors | default([]))
             + (packages_docker | default([]))
             + (packages_xorg | default([]))
             + (packages_wm | default([]))
             + (packages_filemanager | default([]))
             + (packages_network | default([]))
             + (packages_media | default([]))
             + (packages_desktop | default([]))
             + (packages_graphics | default([]))
             + (packages_session | default([]))
             + (packages_terminal | default([]))
             + (packages_fonts | default([]))
             + (packages_theming | default([]))
             + (packages_search | default([]))
             + (packages_viewers | default([]))
             + (packages_distro[ansible_facts['os_family']] | default([])) }}

    # ---- Gather package facts ----

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    # ---- Assert all expected packages are installed ----

    - name: Assert each expected package is installed
      ansible.builtin.assert:
        that: "item in ansible_facts.packages"
        fail_msg: "Package '{{ item }}' not found in installed packages"
        quiet: true
      loop: "{{ packages_verify_expected }}"
      loop_control:
        label: "{{ item }}"

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          packages verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}:
          all {{ packages_verify_expected | length }} packages present.
```

**Step 3: Verify the diff looks correct**

```bash
cd .claude/worktrees/fix/packages-molecule-fix
git diff ansible/roles/packages/molecule/shared/verify.yml
```

Expected diff:
- Line removed: `vars_files:`
- Line removed: `  - "../../defaults/main.yml"`
- Each list entry in set_fact wrapped with `| default([])`
- Entire idempotence hint section removed (two `community.general.pacman`/`ansible.builtin.apt` check_mode tasks + two assert tasks)
- Summary message simplified (removed "and idempotent" text)

**Step 4: Run ansible-lint on the changed file**

```bash
cd .claude/worktrees/fix/packages-molecule-fix
ansible-lint ansible/roles/packages/molecule/shared/verify.yml
```

Expected: no violations. Fix any lint warnings before proceeding.

**Step 5: Run molecule syntax check**

```bash
cd .claude/worktrees/fix/packages-molecule-fix/ansible/roles/packages
molecule syntax -s docker
```

Expected: `INFO     Sanity checks: 'docker'` with no errors.

**Step 6: Commit**

```bash
cd .claude/worktrees/fix/packages-molecule-fix
git add ansible/roles/packages/molecule/shared/verify.yml
git commit -m "fix(packages): fix verify.yml — remove vars_files precedence bug, add default guards

vars_files (precedence 14) was silently overriding molecule inventory group_vars
(precedence 4), resulting in packages_verify_expected = [] and all assertions
being trivially true. Remove vars_files and use | default([]) guards instead.
Also remove redundant check_mode idempotence section — molecule's built-in
idempotence step already covers this.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Push branch and open PR

**Files:** none

**Step 1: Push branch to origin**

```bash
cd .claude/worktrees/fix/packages-molecule-fix
git push -u origin fix/packages-molecule-fix
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "fix(packages): fix verify.yml — remove vars_files precedence bug" \
  --body "$(cat <<'EOF'
## Summary

- `verify.yml` loaded `defaults/main.yml` via `vars_files` (Ansible precedence 14), silently overriding molecule inventory `group_vars` (precedence 4)
- Result: `packages_verify_expected = []` → empty assertion loop → tests passed trivially without checking any package
- Fix: remove `vars_files`, add `| default([])` guards so molecule inventory variables are correctly used
- Also removed redundant `check_mode` idempotence tasks — molecule's built-in `idempotence` step already covers this

## Packages now verified

| Scenario | Arch | Ubuntu |
|----------|------|--------|
| docker | git curl htop tmux unzip rsync vim fzf ripgrep jq base-devel | git curl htop tmux unzip rsync vim fzf ripgrep jq build-essential |
| vagrant | git curl htop tmux unzip rsync vim fzf jq base-devel | git curl htop tmux unzip rsync vim fzf jq build-essential |

## Test plan
- [ ] `test / packages` (Docker — Arch + Ubuntu)
- [ ] `test-vagrant / packages / arch-vm`
- [ ] `test-vagrant / packages / ubuntu-base`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Record the PR URL**

```bash
gh pr view --json url -q .url
```

Save the URL for monitoring.

---

### Task 3: Monitor CI and fix failures

**Files:** depends on failures

**Step 1: Watch CI status**

```bash
gh pr checks --watch
```

Wait for all 3 jobs to complete:
- `test / packages`
- `test-vagrant / packages / arch-vm`
- `test-vagrant / packages / ubuntu-base`

**Step 2: If all green → skip to Task 4**

**Step 3: If any job fails → read the logs**

```bash
gh run list --branch fix/packages-molecule-fix --limit 5
gh run view <run-id> --log-failed
```

**Step 4: Triage failure patterns**

Common failure patterns and fixes:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Package 'X' not found in installed packages` | Package name differs between Arch/Ubuntu | Remove package from shared list or add to distro-specific dict |
| `pacman: error` during converge | Stale mirror or missing package | Update prepare.yml to refresh cache, or remove bad package |
| `apt: error` during converge | Package not available in Ubuntu 24.04 | Add to packages_distro dict (Arch-only) or remove |
| Idempotence failure (converge reports changed on 2nd run) | Package manager reports change for already-installed package | Investigate module behavior; may need to add `--needed` flag or update_cache guard |
| `fzf` or `ripgrep` not in Ubuntu | Package not in ubuntu-base container | Remove from test list or add fallback |

**Step 5: Apply fix, commit, push**

```bash
cd .claude/worktrees/fix/packages-molecule-fix
# ... make fix ...
git add <files>
git commit -m "fix(packages): <description>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push
```

CI re-runs automatically on push.

**Step 6: Repeat Steps 1-5 until all 3 jobs are green**

---

### Task 4: Merge PR and clean up

**Files:** none

**Step 1: Verify all CI checks are green**

```bash
gh pr checks
```

All checks must show ✓ before merging.

**Step 2: Squash merge the PR**

```bash
gh pr merge --squash --delete-branch
```

**Step 3: Pull master in main worktree**

```bash
cd /Users/umudrakov/Documents/bootstrap
git pull
```

**Step 4: Remove the worktree**

```bash
git worktree remove .claude/worktrees/fix/packages-molecule-fix
```

**Step 5: Verify worktree is gone**

```bash
git worktree list
```

Expected: only the main worktree listed.

**Step 6: Move design and plan docs to done/**

```bash
mkdir -p docs/plans/done
git mv docs/plans/2026-03-01-packages-molecule-fix-design.md docs/plans/done/
git mv docs/plans/2026-03-01-packages-molecule-fix.md docs/plans/done/
git commit -m "docs(plans): move packages molecule fix docs to done/

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push
```

---

## Done

Branch merged, PR closed, worktree deleted. All 3 CI environments verify real package installation.
