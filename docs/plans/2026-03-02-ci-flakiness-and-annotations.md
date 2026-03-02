# CI Flakiness Fix & GHA Annotations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate Vagrant molecule test flakiness caused by stale pacman mirrors and add GitHub Actions annotations to both molecule workflows for readable error reporting.

**Architecture:** Two repos, three layers of change:
1. **`textyre/arch-images`**: Add `archlinux/mirrors` role to box build — sets `geo.mirror.pkgbuild.com` as primary mirror so every box ships with a CDN-backed, always-in-sync mirrorlist.
2. **`textyre/bootstrap`**: Create shared vagrant prepare playbook with `pacman -Syy` as defense-in-depth, replace duplicated prepare logic in 27 roles.
3. **`textyre/bootstrap`**: Add `::error`/`::warning` GHA annotations to `molecule.yml` and `molecule-vagrant.yml`.

**Tech Stack:** Packer, Ansible, GitHub Actions, shell

---

## Part 1: Fix Vagrant Box Mirrorlist (`textyre/arch-images`)

### Task 1: Add `archlinux/mirrors` role

This role sets `geo.mirror.pkgbuild.com` (Arch's official CDN, always in sync with master mirror) as the sole mirror in the box. Partial sync 404s become impossible.

**Repo:** `textyre/arch-images`

**Files:**
- Create: `ansible/roles/archlinux/mirrors/tasks/main.yml`

**Step 1: Create the role**

```yaml
---
# Set geo.mirror.pkgbuild.com as the sole pacman mirror.
# This is Arch's official CDN-backed geo-redirect — always in sync,
# no partial-sync 404s that plague individual mirrors.

- name: Set geo.mirror.pkgbuild.com as sole mirror
  ansible.builtin.copy:
    dest: /etc/pacman.d/mirrorlist
    content: |
      # Managed by arch-images build pipeline.
      # geo.mirror.pkgbuild.com is Arch's official CDN (CloudFlare).
      Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
    mode: '0644'
    owner: root
    group: root

- name: Force-refresh package database against new mirror
  community.general.pacman:
    update_cache: true
    force: true
```

**Step 2: Verify file was created**

```bash
cat ansible/roles/archlinux/mirrors/tasks/main.yml
```

### Task 2: Wire mirrors role into site.yml

**Repo:** `textyre/arch-images`

**Files:**
- Modify: `ansible/site.yml`

**Step 1: Add mirrors role before base**

Current `site.yml`:
```yaml
  roles:
    - common/base
    - archlinux/keyring
    - common/vagrant_user
    - common/cleanup
```

Change to:
```yaml
  roles:
    - archlinux/mirrors
    - archlinux/keyring
    - common/base
    - common/vagrant_user
    - common/cleanup
```

Order rationale: mirrors first (so keyring update and base upgrade use the reliable CDN), then keyring, then base (upgrade + packages), then vagrant_user, then cleanup.

**Step 2: Verify site.yml**

```bash
cat ansible/site.yml
```

### Task 3: Add mirror contract check

**Repo:** `textyre/arch-images`

**Files:**
- Modify: `contracts/vagrant.sh`

**Step 1: Add mirror check to contract**

Add before the final `=== Contract: PASS ===` line:

```bash
echo -n "mirror:   " && grep -c 'geo.mirror.pkgbuild.com' /etc/pacman.d/mirrorlist && echo "OK"
```

**Step 2: Verify contract**

```bash
cat contracts/vagrant.sh
```

### Task 4: Commit and push arch-images changes

```bash
git add ansible/roles/archlinux/mirrors/ ansible/site.yml contracts/vagrant.sh
git commit -m "feat: add mirrors role — use geo.mirror.pkgbuild.com CDN

Eliminates partial-sync 404 errors in downstream Molecule tests.
geo.mirror.pkgbuild.com is Arch's official CDN-backed geo-redirect,
always in sync with the master mirror.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push
```

### Task 5: Trigger box rebuild and wait for completion

```bash
gh workflow run build.yml -f artifact=vagrant
# Wait for completion
gh run list --workflow=build.yml --limit 1 --json databaseId,status
```

---

## Part 2: Shared Vagrant Prepare (`textyre/bootstrap`)

### Task 6: Create shared vagrant prepare playbook

This playbook provides defense-in-depth: even with a good mirrorlist in the box, `pacman -Syy` ensures the package DB is fresh if the box was cached.

**Repo:** `textyre/bootstrap`

**Files:**
- Create: `ansible/molecule/shared/prepare-vagrant.yml`

**Step 1: Write shared prepare**

```yaml
---
# Shared Vagrant prepare — import this at the TOP of every role's
# molecule/vagrant/prepare.yml to ensure Arch package DB is fresh.
#
# Usage in role prepare.yml:
#   - name: Bootstrap Vagrant VM
#     ansible.builtin.import_playbook: ../../../../molecule/shared/prepare-vagrant.yml
#
#   - name: Prepare (role-specific)
#     hosts: all
#     become: true
#     gather_facts: true
#     tasks:
#       - name: Install role-specific deps
#         ...

- name: Bootstrap Vagrant VM
  hosts: all
  become: true
  gather_facts: true
  tasks:
    # ---- Arch Linux ----
    - name: Force-refresh pacman package database (Arch)
      community.general.pacman:
        update_cache: true
        force: true
      when: ansible_facts['os_family'] == 'Archlinux'

    # ---- Ubuntu/Debian ----
    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**Step 2: Verify file**

```bash
cat ansible/molecule/shared/prepare-vagrant.yml
```

### Task 7: Update gpu_drivers vagrant prepare

The role that actually failed. Replace its prepare with shared import + role-specific tasks.

**Repo:** `textyre/bootstrap`

**Files:**
- Modify: `ansible/roles/gpu_drivers/molecule/vagrant/prepare.yml`

**Step 1: Rewrite prepare.yml**

```yaml
---
- name: Bootstrap Vagrant VM
  ansible.builtin.import_playbook: ../../../../molecule/shared/prepare-vagrant.yml

- name: Prepare (gpu_drivers)
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Install pciutils (Arch)
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

**Step 2: Verify file**

```bash
cat ansible/roles/gpu_drivers/molecule/vagrant/prepare.yml
```

### Task 8: Update all other vagrant prepare files

For each role with a vagrant prepare, replace duplicated `update_cache` / apt update logic with the shared import, keeping only role-specific tasks.

**Roles to update (26 remaining):**

Roles with **no role-specific tasks** (prepare becomes just the import):
`firewall`, `git`, `hostctl`, `hostname`, `locale`, `ntp`, `ntp_audit`, `package_manager`, `packages`, `pam_hardening`, `reflector`, `shell`, `teleport`, `timezone`, `vconsole`, `yay`

Template for roles with NO role-specific tasks:
```yaml
---
- name: Bootstrap Vagrant VM
  ansible.builtin.import_playbook: ../../../../molecule/shared/prepare-vagrant.yml
```

Wait — some of these DO have role-specific tasks (e.g., `locale` installs `locales` package, `ntp` disables timesyncd). Keep those. Only replace the `update_cache` / apt update boilerplate.

**Full list with role-specific tasks to preserve:**

| Role | Role-specific tasks to keep |
|------|---------------------------|
| chezmoi | Create dotfiles fixture directory, deploy .chezmoi.toml.tmpl, deploy test marker |
| docker | Install docker + shadow (Arch), install docker.io + uidmap (Ubuntu) |
| fail2ban | Install iptables-nft (Arch), create /var/log/auth.log (Arch) |
| firewall | (none) |
| git | (none) |
| hostctl | (none) |
| hostname | (none) |
| locale | Install locales package (Ubuntu) |
| ntp | Stop/disable systemd-timesyncd (Ubuntu) |
| ntp_audit | (none — tasks: []) |
| package_manager | (none) |
| packages | (none) |
| pam_hardening | (none) |
| power_management | modprobe acpi-cpufreq + cpufreq_schedutil |
| reflector | (none — tasks: []) |
| shell | (none) |
| ssh | Ensure /run/sshd directory exists |
| ssh_keys | Create test users, plant authorized_keys, set facts |
| sysctl | (none) |
| teleport | (none) |
| timezone | (none) |
| user | Create video group, install logrotate, create test user, lock root, sudo workaround |
| vaultwarden | Install Docker+prereqs, enable Docker, create proxy network, create Caddy dirs |
| vconsole | Install kbd package |
| vm | (full bootstrap — keyring refresh, upgrade, DNS fix) |
| yay | (none) |

**Special case: `vm` and `power_management`** — these have their own full bootstrap (keyring, upgrade, DNS fix). Since the shared prepare now handles `pacman -Syy`, these should be simplified:

For **`power_management`**: remove the keyring refresh + full upgrade + DNS fix (the shared prepare handles package DB freshness, and the box already ships with fresh keyring). Keep only the modprobe tasks.

For **`vm`**: remove the keyring refresh + full upgrade + DNS fix from prepare. The shared prepare + the box's built-in keyring/upgrade handles this. Keep only gather_facts without Python install (box ships Python).

**Step 1: Update each prepare.yml**

Each file follows this pattern:
```yaml
---
- name: Bootstrap Vagrant VM
  ansible.builtin.import_playbook: ../../../../molecule/shared/prepare-vagrant.yml

# Only include this play if the role has role-specific prepare tasks:
- name: Prepare (<role_name>)
  hosts: all
  become: true
  gather_facts: true  # or false for vm/power_management
  tasks:
    # ... role-specific tasks only, no update_cache / apt update ...
```

**Step 2: Verify each file doesn't contain duplicated update_cache/apt update logic**

```bash
grep -r "update_cache" ansible/roles/*/molecule/vagrant/prepare.yml
# Should return ZERO results (all update_cache is now in shared prepare)
```

### Task 9: Commit shared prepare changes

```bash
git add ansible/molecule/shared/prepare-vagrant.yml ansible/roles/*/molecule/vagrant/prepare.yml
git commit -m "refactor(molecule): shared vagrant prepare with pacman -Syy

Extract duplicated update_cache/apt update logic from 27 role
prepare.yml files into ansible/molecule/shared/prepare-vagrant.yml.

Defense-in-depth: even with geo.mirror.pkgbuild.com in the box,
force-refresh ensures the package DB is current if the box is cached.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Part 3: GHA Annotations (`textyre/bootstrap`)

### Task 10: Add annotations to molecule.yml (Docker workflow)

**Files:**
- Modify: `.github/workflows/molecule.yml`

**Step 1: Add annotation step after "Run Molecule"**

Add these steps after the existing `Run Molecule` step (line 119) and before the end of the job:

```yaml
      - name: Annotate failure
        if: failure()
        run: |
          echo "::error title=Molecule FAILED (${{ matrix.role }})::Docker scenario for role '${{ matrix.role }}' failed. Check the log above for details."

      - name: Annotate success
        if: success()
        run: |
          echo "::notice title=Molecule PASSED (${{ matrix.role }})::Docker scenario for role '${{ matrix.role }}' passed."
```

**Step 2: Verify workflow syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/molecule.yml'))"
```

### Task 11: Add annotations to molecule-vagrant.yml (Vagrant workflow)

**Files:**
- Modify: `.github/workflows/molecule-vagrant.yml`

**Step 1: Add annotation step after "Run Molecule" (before "Upload logs on failure")**

Insert between the `Run Molecule` step and the `Upload logs on failure` step:

```yaml
      - name: Annotate failure
        if: failure()
        run: |
          echo "::error title=Molecule FAILED (${{ matrix.role }}/${{ matrix.platform }})::Vagrant scenario for role '${{ matrix.role }}' on '${{ matrix.platform }}' failed. Check the log above for details."

      - name: Annotate success
        if: success()
        run: |
          echo "::notice title=Molecule PASSED (${{ matrix.role }}/${{ matrix.platform }})::Vagrant scenario for role '${{ matrix.role }}' on '${{ matrix.platform }}' passed."
```

**Step 2: Verify workflow syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/molecule-vagrant.yml'))"
```

### Task 12: Commit annotation changes

```bash
git add .github/workflows/molecule.yml .github/workflows/molecule-vagrant.yml
git commit -m "feat(ci): add GHA annotations to molecule workflows

Failed roles show ::error annotations in PR summary.
Passed roles show ::notice annotations for visibility.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Part 4: Verification

### Task 13: Trigger full test run and verify

**Step 1: Push bootstrap changes**

```bash
git push
```

**Step 2: Verify arch-images box build completed**

```bash
gh api repos/textyre/arch-images/releases/latest --jq '.tag_name'
# Should show today's date (new build with mirrors role)
```

**Step 3: Trigger molecule-vagrant with new box**

```bash
gh workflow run molecule-vagrant.yml -f role_filter=gpu_drivers
```

**Step 4: Wait and check**

```bash
gh run watch <run-id> --exit-status
```

Expected: `gpu_drivers (test-vagrant/arch)` passes. Annotations visible in workflow summary.

**Step 5: Verify annotations visible**

Open the workflow run in browser. Check:
- Failed jobs (if any) show `::error` annotation in summary
- Passed jobs show `::notice` annotation in summary
- Annotations include role name and platform

### Task 14: Run full regression

```bash
gh workflow run molecule.yml -f role_filter=all
gh workflow run molecule-vagrant.yml -f role_filter=all
```

Wait for both to complete. All 32 Docker + 54 Vagrant jobs should pass.
