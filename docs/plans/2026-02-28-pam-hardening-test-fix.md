# pam_hardening Test Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix failing pam_hardening molecule tests in Docker (pacman-on-Ubuntu bug) and align vagrant molecule.yml to standard pattern, then open a PR.

**Architecture:** Two file edits only. No CI workflow changes. The "only run when changed" detection already works correctly in `molecule.yml`.

**Tech Stack:** Ansible, Molecule, Docker, Vagrant/libvirt, GitHub Actions

---

### Task 1: Fix `molecule/docker/prepare.yml` — OS-conditional package cache update

**Files:**
- Modify: `ansible/roles/pam_hardening/molecule/docker/prepare.yml`

**Context:**
The file currently has `gather_facts: false` and runs `community.general.pacman` unconditionally. The docker scenario includes both `Archlinux-systemd` and `Ubuntu-systemd` platforms. Ubuntu has no `pacman`, so prepare fails immediately.

The fix mirrors the pattern already used in `molecule/vagrant/prepare.yml`.

**Step 1: Replace the file content**

The file should become:

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

**Step 2: Verify the file looks correct**

Read the file and confirm both tasks are present with correct `when` conditions and `gather_facts: true`.

**Step 3: Commit**

```bash
git add ansible/roles/pam_hardening/molecule/docker/prepare.yml
git commit -m "fix(pam_hardening): fix docker prepare.yml — conditional pacman/apt by OS family"
```

---

### Task 2: Align `molecule/vagrant/molecule.yml` to standard pattern

**Files:**
- Modify: `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml`

**Context:**
Compared to all passing vagrant roles (fail2ban, locale, git, ntp, etc.), pam_hardening's vagrant molecule.yml has:
- An extra `inventory.host_vars.localhost.ansible_python_interpreter` block (not needed, not in other roles)
- Missing `options: skip-tags: report` in the provisioner

**Step 1: Replace the provisioner block**

The full file should become:

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

**Step 2: Verify the diff**

Run: `git diff ansible/roles/pam_hardening/molecule/vagrant/molecule.yml`

Expected: removal of `inventory.host_vars` block, addition of `options: skip-tags: report`.

**Step 3: Commit**

```bash
git add ansible/roles/pam_hardening/molecule/vagrant/molecule.yml
git commit -m "fix(pam_hardening): align vagrant molecule.yml to standard pattern"
```

---

### Task 3: Create the PR

**Step 1: Push the branch**

```bash
git push -u origin HEAD
```

**Step 2: Create PR**

```bash
gh pr create \
  --title "fix(pam_hardening): fix molecule tests — docker OS-conditional prepare, vagrant alignment" \
  --body "$(cat <<'EOF'
## Problem

Two issues block `pam_hardening` molecule tests:

1. **Docker test fails** — `molecule/docker/prepare.yml` ran `community.general.pacman` unconditionally on all containers. Ubuntu has no `pacman` → fatal during prepare.

2. **Vagrant molecule.yml misaligned** — had an extra `inventory.host_vars.localhost` block not present in other roles, and was missing `options: skip-tags: report`.

## Changes

- `molecule/docker/prepare.yml` — add `gather_facts: true`, split into OS-conditional pacman (Arch) and apt (Ubuntu) tasks
- `molecule/vagrant/molecule.yml` — remove `inventory.host_vars.localhost`, add `options: skip-tags: report` to match standard pattern

## No changes to

- Role tasks (correct)
- Shared `converge.yml` / `verify.yml` (correct)
- CI workflows (detect/change logic already correct for all roles)

## Test plan

- [ ] `test (pam_hardening)` Docker job passes (Archlinux-systemd + Ubuntu-systemd)
- [ ] `test-vagrant (pam_hardening, arch-vm)` continues to pass
- [ ] `test-vagrant (pam_hardening, ubuntu-base)` passes (was CI-runner-flaky; may need retry)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Confirm PR URL is returned and share with user**
