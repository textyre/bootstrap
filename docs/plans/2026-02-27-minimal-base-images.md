# Minimal Base Images Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `arch-images` and `ubuntu-images` produce truly minimal base boxes — only SSH + Python + sudo — so bootstrap roles test on a clean slate, and upgrade CI verification from archive-check to a real `vagrant up` boot test.

**Architecture:** Three repos change in parallel: arch-images and ubuntu-images lose everything role-specific (aur_builder, qemu-guest-agent), get renamed to `arch-base`/`ubuntu-noble`, and get a real boot-based contract test. Bootstrap updates all references. The Docker molecule image path and Vagrant box_url both change.

**Tech Stack:** Packer (QEMU builder + Ansible provisioner + Vagrant post-processor), GitHub Actions (ubuntu-latest + nested KVM), Vagrant (libvirt provider), Ansible (community.general).

---

## Context: what changes and why

| What | Before | After | Why |
|------|--------|-------|-----|
| arch box name | `arch-molecule` | `arch-base` | Not molecule-specific |
| ubuntu box name | `ubuntu-molecule` | `ubuntu-noble` | Same reason |
| `aur_builder` user in image | ✓ pre-installed | ✗ removed | Roles must install it themselves — otherwise tests pass trivially |
| `qemu-guest-agent` in image | ✓ pre-installed | ✗ removed | Same — `vm` role must test its own installation |
| Vagrant verification in CI | archive check (tar) | `vagrant up` + SSH | Archive check doesn't verify the box actually boots |
| `contracts/vagrant.sh` (Arch) | checks gcc, git, aur_builder | checks only python3, sudo, systemd, SSH | Removed checks for things no longer in image |

**macOS note:** Vagrant libvirt boxes require Linux + KVM. On macOS, use the Docker molecule scenario — it works everywhere. Vagrant scenarios are Linux + CI only. This is documented, not worked around.

---

## Repos and local paths

```
textyre/arch-images   → /c/Users/user/AppData/Local/Temp/arch-images-fix/
textyre/ubuntu-images → /c/Users/user/AppData/Local/Temp/ubuntu-images-fix/
textyre/bootstrap     → /d/projects/bootstrap/
```

Both image repos are git clones with remotes pointing to GitHub. GPG signing must be disabled in these repos before committing:
```bash
git -C /c/Users/user/AppData/Local/Temp/arch-images-fix   config commit.gpgsign false
git -C /c/Users/user/AppData/Local/Temp/ubuntu-images-fix config commit.gpgsign false
```

---

## Task 1: Strip arch-images to minimal base

**Files:**
- Modify: `ansible/site.yml` — remove `archlinux/aur_tools` role
- Modify: `ansible/roles/common/base/tasks/main.yml` — remove qemu-guest-agent
- Delete:  `ansible/roles/archlinux/aur_tools/` (entire directory)
- Modify: `contracts/vagrant.sh` — remove gcc/git/aur_builder checks
- Modify: `packer/archlinux.pkrvars.hcl` — rename box

**Step 1: Remove aur_tools from site.yml**

File: `/c/Users/user/AppData/Local/Temp/arch-images-fix/ansible/site.yml`

Replace:
```yaml
  roles:
    - common/base
    - archlinux/keyring
    - archlinux/aur_tools
    - common/vagrant_user
    - common/cleanup
```
With:
```yaml
  roles:
    - common/base
    - archlinux/keyring
    - common/vagrant_user
    - common/cleanup
```

**Step 2: Remove qemu-guest-agent from common/base**

File: `/c/Users/user/AppData/Local/Temp/arch-images-fix/ansible/roles/common/base/tasks/main.yml`

Remove from both Arch and Ubuntu package lists:
```yaml
      - qemu-guest-agent
```

Remove the enable task entirely:
```yaml
- name: Enable qemu-guest-agent (best-effort — not available in all environments)
  ansible.builtin.systemd:
    name: qemu-guest-agent
    enabled: true
  failed_when: false
```

**Step 3: Delete aur_tools role directory**

```bash
rm -rf /c/Users/user/AppData/Local/Temp/arch-images-fix/ansible/roles/archlinux/aur_tools
```

**Step 4: Update contracts/vagrant.sh**

File: `/c/Users/user/AppData/Local/Temp/arch-images-fix/contracts/vagrant.sh`

Replace entire file with:
```bash
#!/usr/bin/env bash
# Arch Vagrant box contract — run inside the booted VM via: vagrant ssh -c "bash -s" < contracts/vagrant.sh
# Checks only what the base image ships. Role-specific tools (aur_builder, gcc, git)
# are installed by bootstrap roles and tested by their own Molecule scenarios.
set -euo pipefail

echo "=== Arch Vagrant Box Contract ==="
echo -n "python3:  " && python3 --version
echo -n "sudo:     " && sudo --version | head -1
echo -n "systemd:  " && systemctl is-system-running 2>/dev/null || true
echo -n "SSH:      " && systemctl is-active sshd 2>/dev/null || echo "unknown"
echo -n "keyring:  " && pacman-key --list-sigs 2>/dev/null | head -1 && echo "OK"
echo "=== Contract: PASS ==="
```

**Step 5: Rename box in pkrvars.hcl**

File: `/c/Users/user/AppData/Local/Temp/arch-images-fix/packer/archlinux.pkrvars.hcl`

Change:
```hcl
box_name = "arch-molecule"
```
To:
```hcl
box_name = "arch-base"
```

**Step 6: Commit**

```bash
cd /c/Users/user/AppData/Local/Temp/arch-images-fix
git add -A
git commit -m "feat: strip to minimal base — remove aur_tools, qemu-guest-agent; rename arch-base"
```

---

## Task 2: Strip ubuntu-images to minimal base

**Files:**
- Modify: `ansible/roles/common/base/tasks/main.yml` — remove qemu-guest-agent
- Modify: `packer/ubuntu.pkrvars.hcl` — rename box

**Step 1: Remove qemu-guest-agent from common/base**

File: `/c/Users/user/AppData/Local/Temp/ubuntu-images-fix/ansible/roles/common/base/tasks/main.yml`

This is the same shared file as arch. Apply the same removal (the file is duplicated across repos):
- Remove `- qemu-guest-agent` from Ubuntu package list
- Remove the `Enable qemu-guest-agent` task at the bottom

**Step 2: Rename box**

File: `/c/Users/user/AppData/Local/Temp/ubuntu-images-fix/packer/ubuntu.pkrvars.hcl`

Change:
```hcl
box_name = "ubuntu-molecule"
```
To:
```hcl
box_name = "ubuntu-noble"
```

**Step 3: Commit**

```bash
cd /c/Users/user/AppData/Local/Temp/ubuntu-images-fix
git add -A
git commit -m "feat: strip to minimal base — remove qemu-guest-agent; rename ubuntu-noble"
```

---

## Task 3: Upgrade arch-images CI — real vagrant up verification

**Files:**
- Modify: `.github/workflows/build.yml` — rename IMAGE_NAME/BOX_NAME, replace verify step

**Step 1: Update env vars at top of workflow**

File: `/c/Users/user/AppData/Local/Temp/arch-images-fix/.github/workflows/build.yml`

Change:
```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/arch-molecule
  BOX_NAME: arch-molecule
```
To:
```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/arch-base
  BOX_NAME: arch-base
```

**Step 2: Replace "Verify Vagrant box contract" step**

Find the current step (archive check) and replace entirely with:
```yaml
      - name: Verify Vagrant box contract
        run: |
          # Install HashiCorp repo (vagrant not in ubuntu-24.04 standard repos)
          wget -O- https://apt.releases.hashicorp.com/gpg | \
            sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
            https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list
          sudo apt-get update -qq
          sudo apt-get install -y vagrant ruby-dev build-essential pkg-config libvirt-dev
          sudo chmod a+rw /var/run/libvirt/libvirt-sock
          vagrant plugin install vagrant-libvirt

          BOX_FILE="arch-base.box"
          vagrant box add --name verify-box "$BOX_FILE"

          mkdir /tmp/verify-vm && cd /tmp/verify-vm
          cat > Vagrantfile <<'EOF'
          Vagrant.configure("2") do |config|
            config.vm.box = "verify-box"
            config.vm.provider :libvirt do |l|
              l.memory = 1024
              l.cpus   = 1
            end
          end
          EOF

          vagrant up --provider libvirt --no-provision
          vagrant ssh -c "bash -s" < "$GITHUB_WORKSPACE/contracts/vagrant.sh"
          vagrant destroy -f
```

**Step 3: Update BOX_FILE in Publish step**

Find:
```yaml
          BOX_FILE="arch-molecule.box"
```
Replace:
```yaml
          BOX_FILE="arch-base.box"
```

Also update the asset names (two lines below):
```yaml
          VERSIONED_ASSET="arch-base-${VERSION}.box"
          LATEST_ASSET="arch-base-latest.box"
```

**Step 4: Commit**

```bash
cd /c/Users/user/AppData/Local/Temp/arch-images-fix
git add .github/workflows/build.yml
git commit -m "feat: real vagrant-up verification; update image/box names to arch-base"
```

---

## Task 4: Upgrade ubuntu-images CI — real vagrant up verification

**Files:**
- Modify: `.github/workflows/build.yml` — rename IMAGE_NAME/BOX_NAME, replace verify step

**Step 1: Update env vars**

File: `/c/Users/user/AppData/Local/Temp/ubuntu-images-fix/.github/workflows/build.yml`

Change `ubuntu-molecule` → `ubuntu-noble` in:
```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/ubuntu-noble
  BOX_NAME: ubuntu-noble
```

**Step 2: Replace verify step**

Same structure as arch (Task 3 Step 2), but with ubuntu-noble names:
```yaml
      - name: Verify Vagrant box contract
        run: |
          wget -O- https://apt.releases.hashicorp.com/gpg | \
            sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
            https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list
          sudo apt-get update -qq
          sudo apt-get install -y vagrant ruby-dev build-essential pkg-config libvirt-dev
          sudo chmod a+rw /var/run/libvirt/libvirt-sock
          vagrant plugin install vagrant-libvirt

          BOX_FILE="ubuntu-noble.box"
          vagrant box add --name verify-box "$BOX_FILE"

          mkdir /tmp/verify-vm && cd /tmp/verify-vm
          cat > Vagrantfile <<'EOF'
          Vagrant.configure("2") do |config|
            config.vm.box = "verify-box"
            config.vm.provider :libvirt do |l|
              l.memory = 1024
              l.cpus   = 1
            end
          end
          EOF

          vagrant up --provider libvirt --no-provision
          vagrant ssh -c "bash -s" < "$GITHUB_WORKSPACE/contracts/vagrant.sh"
          vagrant destroy -f
```

**Step 3: Update BOX_FILE in Publish step**

```yaml
          BOX_FILE="ubuntu-noble.box"
          ...
          VERSIONED_ASSET="ubuntu-noble-${VERSION}.box"
          LATEST_ASSET="ubuntu-noble-latest.box"
```

**Step 4: Commit**

```bash
cd /c/Users/user/AppData/Local/Temp/ubuntu-images-fix
git add .github/workflows/build.yml
git commit -m "feat: real vagrant-up verification; update image/box names to ubuntu-noble"
```

---

## Task 5: Push both image repos and trigger CI

**Step 1: Push arch-images**

```bash
cd /c/Users/user/AppData/Local/Temp/arch-images-fix
git push origin main
```

**Step 2: Push ubuntu-images**

```bash
cd /c/Users/user/AppData/Local/Temp/ubuntu-images-fix
git push origin main
```

**Step 3: Trigger builds**

```bash
gh workflow run build.yml --repo textyre/arch-images   --field artifact=vagrant
gh workflow run build.yml --repo textyre/ubuntu-images --field artifact=vagrant
```

**Step 4: Watch until complete**

```bash
gh run watch --repo textyre/arch-images   $(gh run list --repo textyre/arch-images   --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch --repo textyre/ubuntu-images $(gh run list --repo textyre/ubuntu-images --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: both complete with ✓. New releases will have `arch-base-latest.box` and `ubuntu-noble-latest.box`.

**Step 5: Verify releases exist**

```bash
gh release view boxes --repo textyre/arch-images   --json assets --jq '.assets[].name'
gh release view boxes --repo textyre/ubuntu-images --json assets --jq '.assets[].name'
```

Expected:
```
arch-base-20260227.box
arch-base-latest.box
---
ubuntu-noble-20260227.box
ubuntu-noble-latest.box
```

---

## Task 6: Update bootstrap — Docker image references

All 9 Docker molecule scenarios reference the old `arch-molecule` image name.

**Files to modify** (all 9):
```
ansible/roles/hostctl/molecule/docker/molecule.yml
ansible/roles/hostname/molecule/docker/molecule.yml
ansible/roles/locale/molecule/docker/molecule.yml
ansible/roles/ntp/molecule/docker/molecule.yml
ansible/roles/ntp_audit/molecule/docker/molecule.yml
ansible/roles/package_manager/molecule/docker/molecule.yml
ansible/roles/pam_hardening/molecule/docker/molecule.yml
ansible/roles/timezone/molecule/docker/molecule.yml
ansible/roles/vconsole/molecule/docker/molecule.yml
```

**Step 1: Bulk replace image name**

```bash
cd /d/projects/bootstrap
grep -rl "arch-molecule" ansible/roles/*/molecule/docker/molecule.yml \
  | xargs sed -i 's|arch-molecule|arch-base|g'
```

**Step 2: Verify**

```bash
grep -r "arch-molecule\|arch-base" ansible/roles/*/molecule/docker/molecule.yml
```

Expected: all lines show `arch-base`, none show `arch-molecule`.

**Step 3: Commit**

```bash
cd /d/projects/bootstrap
git add ansible/roles/*/molecule/docker/molecule.yml
git commit -m "chore: update docker molecule scenarios to use arch-base image"
```

---

## Task 7: Update bootstrap — workflow env var

**File:** `.github/workflows/_molecule.yml`

**Step 1: Update MOLECULE_ARCH_IMAGE**

Change:
```yaml
      MOLECULE_ARCH_IMAGE: ghcr.io/textyre/arch-molecule:latest
```
To:
```yaml
      MOLECULE_ARCH_IMAGE: ghcr.io/textyre/arch-base:latest
```

**Step 2: Commit**

```bash
cd /d/projects/bootstrap
git add .github/workflows/_molecule.yml
git commit -m "chore: update MOLECULE_ARCH_IMAGE to arch-base"
```

---

## Task 8: Update bootstrap — Vagrant molecule scenarios

Both vagrant molecule.yml files reference the old box names and old release URLs.

**Files:**
- `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml`
- `ansible/roles/package_manager/molecule/vagrant/molecule.yml`

**Step 1: Update both files**

In both files, change the `platforms:` section from:
```yaml
platforms:
  - name: arch-vm
    box: arch-molecule
    box_url: https://github.com/textyre/arch-images/releases/download/boxes/arch-molecule-latest.box
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: ubuntu-molecule
    box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-molecule-latest.box
    memory: 2048
    cpus: 2
```
To:
```yaml
platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/download/boxes/arch-base-latest.box
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: ubuntu-noble
    box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-noble-latest.box
    memory: 2048
    cpus: 2
```

**Step 2: Commit**

```bash
cd /d/projects/bootstrap
git add ansible/roles/*/molecule/vagrant/molecule.yml
git commit -m "chore: update vagrant molecule scenarios to arch-base / ubuntu-noble boxes"
```

---

## Task 9: Verify bootstrap CI still passes

**Step 1: Push bootstrap changes**

```bash
cd /d/projects/bootstrap
git push origin master
```

**Step 2: Trigger molecule test for a role that uses both Docker and Vagrant**

```bash
cd /d/projects/bootstrap
gh workflow run molecule.yml --field role_filter=package_manager
```

**Step 3: Watch**

```bash
gh run watch $(gh run list --workflow=molecule.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: green.

---

## Task 10: Write post-mortem

Save to `docs/troubleshooting/troubleshooting-history-2026-02-27-minimal-base-images.md`.

Cover:
- Why pre-installing role artifacts in the base image is wrong (test contamination)
- What was removed and why
- The vagrant up verification upgrade
- macOS note (Docker driver = cross-platform; Vagrant/libvirt = Linux + CI only)

---

## Known risks

| Risk | Mitigation |
|------|-----------|
| `vagrant plugin install vagrant-libvirt` builds native gem — slow (~3min) | Acceptable; runs once per CI build |
| vagrant-libvirt may fail to connect to libvirt socket | `sudo chmod a+rw /var/run/libvirt/libvirt-sock` is already in the step |
| Roles that depended on aur_builder being pre-installed will now fail on vanilla Arch | This is correct — those roles should create aur_builder themselves |
| `arch-base-latest.box` and `ubuntu-noble-latest.box` don't exist until Task 5 completes | Do Tasks 1–5 (image repos) before Tasks 6–8 (bootstrap) |

## Order dependency

```
Tasks 1–2 (strip images)
    ↓
Tasks 3–4 (upgrade CI verification)
    ↓
Task 5 (push + trigger + wait for green releases)
    ↓
Tasks 6–8 (update bootstrap references in parallel — they're independent of each other)
    ↓
Task 9 (verify bootstrap CI)
    ↓
Task 10 (post-mortem)
```
