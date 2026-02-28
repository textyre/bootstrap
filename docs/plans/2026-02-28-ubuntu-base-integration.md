# ubuntu-base Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate `ghcr.io/textyre/ubuntu-base` Docker image and `ubuntu-base.box` Vagrant box into all cross-platform Molecule scenarios, replacing all legacy image references.

**Architecture:** Purely mechanical YAML edits across ~49 files. No logic changes. Arch platform stays untouched — Ubuntu is added alongside it. Python scripts handle batch updates where possible; manual edits for special cases.

**Tech Stack:** Python 3 (in-place YAML string manipulation), bash sed, Molecule/Ansible YAML

**Design doc:** `docs/plans/2026-02-28-ubuntu-base-integration-design.md`

---

## Task 1: Update `_molecule.yml` CI workflow

**Files:**
- Modify: `.github/workflows/_molecule.yml`

**Step 1: Open the file and make two changes**

Current `env:` block (line 25-27):
```yaml
    env:
      PY_COLORS: "1"
      ANSIBLE_FORCE_COLOR: "1"
      MOLECULE_ARCH_IMAGE: ghcr.io/textyre/arch-base:latest
```

Replace with:
```yaml
    env:
      PY_COLORS: "1"
      ANSIBLE_FORCE_COLOR: "1"
      MOLECULE_ARCH_IMAGE: ghcr.io/textyre/arch-base:latest
      MOLECULE_UBUNTU_IMAGE: ghcr.io/textyre/ubuntu-base:latest
```

Also update job name (line 19):
```yaml
# Before
    name: "${{ inputs.role_name }} (Arch/systemd)"

# After
    name: "${{ inputs.role_name }} (Arch+Ubuntu/systemd)"
```

**Step 2: Verify**
```bash
grep -E "UBUNTU_IMAGE|Arch\+Ubuntu" .github/workflows/_molecule.yml
```
Expected: 2 matches.

**Step 3: Commit**
```bash
git add .github/workflows/_molecule.yml
git commit -m "ci(molecule): add MOLECULE_UBUNTU_IMAGE env var to _molecule.yml"
```

---

## Task 2: Fix Docker fallback images (22 files)

**Files to modify** (22 files, all currently use old `bootstrap/arch-systemd` fallback):
```
ansible/roles/caddy/molecule/docker/molecule.yml
ansible/roles/chezmoi/molecule/docker/molecule.yml
ansible/roles/docker/molecule/docker/molecule.yml
ansible/roles/fail2ban/molecule/docker/molecule.yml
ansible/roles/firewall/molecule/docker/molecule.yml
ansible/roles/git/molecule/docker/molecule.yml
ansible/roles/gpu_drivers/molecule/docker/molecule.yml
ansible/roles/greeter/molecule/docker/molecule.yml
ansible/roles/lightdm/molecule/docker/molecule.yml
ansible/roles/packages/molecule/docker/molecule.yml
ansible/roles/power_management/molecule/docker/molecule.yml
ansible/roles/reflector/molecule/docker/molecule.yml
ansible/roles/shell/molecule/docker/molecule.yml
ansible/roles/ssh/molecule/docker/molecule.yml
ansible/roles/ssh_keys/molecule/docker/molecule.yml
ansible/roles/sysctl/molecule/docker/molecule.yml
ansible/roles/teleport/molecule/docker/molecule.yml
ansible/roles/user/molecule/docker/molecule.yml
ansible/roles/vaultwarden/molecule/docker/molecule.yml
ansible/roles/xorg/molecule/docker/molecule.yml
ansible/roles/yay/molecule/docker/molecule.yml
ansible/roles/zen_browser/molecule/docker/molecule.yml
```

**Step 1: Run sed replacement across all 22 files**
```bash
grep -rl "bootstrap/arch-systemd" ansible/roles/*/molecule/docker/molecule.yml \
  | xargs sed -i 's|ghcr.io/textyre/bootstrap/arch-systemd:latest|ghcr.io/textyre/arch-base:latest|g'
```

**Step 2: Verify no old references remain**
```bash
grep -r "bootstrap/arch-systemd" ansible/roles/*/molecule/docker/molecule.yml
```
Expected: no output.

**Step 3: Verify all docker scenarios now use arch-base**
```bash
grep -r "MOLECULE_ARCH_IMAGE" ansible/roles/*/molecule/docker/molecule.yml | wc -l
```
Expected: 31 (all Docker scenarios).

**Step 4: Commit**
```bash
git add ansible/roles/*/molecule/docker/molecule.yml
git commit -m "fix(molecule): update Docker fallback to ghcr.io/textyre/arch-base:latest in 22 scenarios"
```

---

## Task 3: Add Ubuntu Docker platform to 24 cross-platform roles

**Files to modify** (24 cross-platform roles with Docker scenario):
```
ansible/roles/chezmoi/molecule/docker/molecule.yml
ansible/roles/docker/molecule/docker/molecule.yml
ansible/roles/fail2ban/molecule/docker/molecule.yml
ansible/roles/firewall/molecule/docker/molecule.yml
ansible/roles/git/molecule/docker/molecule.yml
ansible/roles/gpu_drivers/molecule/docker/molecule.yml
ansible/roles/hostctl/molecule/docker/molecule.yml
ansible/roles/hostname/molecule/docker/molecule.yml
ansible/roles/locale/molecule/docker/molecule.yml
ansible/roles/ntp/molecule/docker/molecule.yml
ansible/roles/ntp_audit/molecule/docker/molecule.yml
ansible/roles/package_manager/molecule/docker/molecule.yml
ansible/roles/packages/molecule/docker/molecule.yml
ansible/roles/pam_hardening/molecule/docker/molecule.yml
ansible/roles/power_management/molecule/docker/molecule.yml
ansible/roles/shell/molecule/docker/molecule.yml
ansible/roles/ssh/molecule/docker/molecule.yml
ansible/roles/ssh_keys/molecule/docker/molecule.yml
ansible/roles/sysctl/molecule/docker/molecule.yml
ansible/roles/teleport/molecule/docker/molecule.yml
ansible/roles/timezone/molecule/docker/molecule.yml
ansible/roles/user/molecule/docker/molecule.yml
ansible/roles/vconsole/molecule/docker/molecule.yml
ansible/roles/yay/molecule/docker/molecule.yml
```

**Ubuntu platform block to insert** (add after the Arch platform block, before `provisioner:`):
```yaml
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
```

Note: Ubuntu `command` is `/lib/systemd/systemd` (not `/usr/lib/...` like Arch).

**Step 1: Run Python script to insert Ubuntu platform into all 24 files**

```python
#!/usr/bin/env python3
"""Insert Ubuntu-systemd platform block into cross-platform docker molecule.yml files."""

import os

ROLES = [
    "chezmoi", "docker", "fail2ban", "firewall", "git", "gpu_drivers",
    "hostctl", "hostname", "locale", "ntp", "ntp_audit", "package_manager",
    "packages", "pam_hardening", "power_management", "shell", "ssh",
    "ssh_keys", "sysctl", "teleport", "timezone", "user", "vconsole", "yay",
]

UBUNTU_BLOCK = """\
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
"""

BASE = "ansible/roles"

for role in ROLES:
    path = f"{BASE}/{role}/molecule/docker/molecule.yml"
    if not os.path.exists(path):
        print(f"SKIP (no file): {path}")
        continue

    with open(path) as f:
        content = f.read()

    if "Ubuntu-systemd" in content:
        print(f"SKIP (already has Ubuntu): {path}")
        continue

    # Insert before "provisioner:"
    if "\nprovisioner:" not in content:
        print(f"WARN (no provisioner): {path}")
        continue

    new_content = content.replace("\nprovisioner:", f"\n{UBUNTU_BLOCK}\nprovisioner:", 1)

    with open(path, "w") as f:
        f.write(new_content)
    print(f"OK: {path}")
```

Save as `/tmp/add_ubuntu_platform.py`, then run:
```bash
cd /path/to/bootstrap
python3 /tmp/add_ubuntu_platform.py
```

**Step 2: Handle roles with `Archlinux-systemd` host_vars (4 roles)**

These roles have `host_vars: Archlinux-systemd:` in provisioner — the same vars must also apply to `Ubuntu-systemd`. Check each file and duplicate the host_vars block:

- `ansible/roles/docker/molecule/docker/molecule.yml` — add `Ubuntu-systemd: { docker_enable_service: false }`
- `ansible/roles/git/molecule/docker/molecule.yml` — copy all `Archlinux-systemd:` vars to `Ubuntu-systemd:`
- `ansible/roles/teleport/molecule/docker/molecule.yml` — copy `teleport_install_method` to `Ubuntu-systemd:`
- `ansible/roles/chezmoi/molecule/docker/molecule.yml` — set `chezmoi_install_method: apt` for Ubuntu (Arch uses `pacman`; Ubuntu uses `apt`). Keep Arch as `pacman`.

Example for `docker` role — change:
```yaml
      host_vars:
        Archlinux-systemd:
          docker_enable_service: false
```
To:
```yaml
      host_vars:
        Archlinux-systemd:
          docker_enable_service: false
        Ubuntu-systemd:
          docker_enable_service: false
```

Example for `chezmoi` — change:
```yaml
      host_vars:
        Archlinux-systemd:
          chezmoi_install_method: pacman
          chezmoi_user: testuser
          chezmoi_source_dir: /opt/dotfiles
          chezmoi_verify_has_dotfiles: true
          chezmoi_verify_fixture: true
          chezmoi_verify_full: false
```
To:
```yaml
      host_vars:
        Archlinux-systemd:
          chezmoi_install_method: pacman
          chezmoi_user: testuser
          chezmoi_source_dir: /opt/dotfiles
          chezmoi_verify_has_dotfiles: true
          chezmoi_verify_fixture: true
          chezmoi_verify_full: false
        Ubuntu-systemd:
          chezmoi_install_method: apt
          chezmoi_user: testuser
          chezmoi_source_dir: /opt/dotfiles
          chezmoi_verify_has_dotfiles: true
          chezmoi_verify_fixture: true
          chezmoi_verify_full: false
```

**Step 3: Verify**
```bash
grep -c "Ubuntu-systemd" ansible/roles/*/molecule/docker/molecule.yml \
  | grep -v ":0" | wc -l
```
Expected: 24

**Step 4: Verify YAML syntax on all modified files**
```bash
for f in ansible/roles/*/molecule/docker/molecule.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>&1 && echo "OK: $f" || echo "ERROR: $f"
done | grep ERROR
```
Expected: no output.

**Step 5: Commit**
```bash
git add ansible/roles/*/molecule/docker/molecule.yml
git commit -m "feat(molecule): add Ubuntu-systemd platform to 24 cross-platform Docker scenarios"
```

---

## Task 4: Migrate Vagrant Ubuntu boxes (21 files)

**Files to modify** (currently use `bento/ubuntu-24.04`):
```
ansible/roles/chezmoi/molecule/vagrant/molecule.yml
ansible/roles/docker/molecule/vagrant/molecule.yml
ansible/roles/fail2ban/molecule/vagrant/molecule.yml
ansible/roles/firewall/molecule/vagrant/molecule.yml
ansible/roles/git/molecule/vagrant/molecule.yml
ansible/roles/gpu_drivers/molecule/vagrant/molecule.yml
ansible/roles/hostctl/molecule/vagrant/molecule.yml
ansible/roles/hostname/molecule/vagrant/molecule.yml
ansible/roles/locale/molecule/vagrant/molecule.yml
ansible/roles/ntp/molecule/vagrant/molecule.yml
ansible/roles/ntp_audit/molecule/vagrant/molecule.yml
ansible/roles/packages/molecule/vagrant/molecule.yml
ansible/roles/power_management/molecule/vagrant/molecule.yml
ansible/roles/shell/molecule/vagrant/molecule.yml
ansible/roles/ssh_keys/molecule/vagrant/molecule.yml
ansible/roles/sysctl/molecule/vagrant/molecule.yml
ansible/roles/teleport/molecule/vagrant/molecule.yml
ansible/roles/timezone/molecule/vagrant/molecule.yml
ansible/roles/user/molecule/vagrant/molecule.yml
ansible/roles/vconsole/molecule/vagrant/molecule.yml
ansible/roles/yay/molecule/vagrant/molecule.yml
```

**Step 1: Replace box name with sed**
```bash
grep -rl "bento/ubuntu-24.04" ansible/roles/*/molecule/vagrant/molecule.yml \
  | xargs sed -i 's|box: bento/ubuntu-24.04|box: ubuntu-base|g'
```

**Step 2: Add box_url after each `box: ubuntu-base` line using Python**

```python
#!/usr/bin/env python3
"""Add box_url for ubuntu-base in vagrant molecule.yml files."""
import os, glob

BOX_URL = "https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box"
TARGET_LINE = "    box: ubuntu-base"
NEXT_LINE_URL = f"    box_url: {BOX_URL}"

for path in sorted(glob.glob("ansible/roles/*/molecule/vagrant/molecule.yml")):
    with open(path) as f:
        lines = f.readlines()

    new_lines = []
    changed = False
    for i, line in enumerate(lines):
        new_lines.append(line)
        if line.rstrip() == TARGET_LINE:
            # Check if box_url already follows
            next_line = lines[i+1].strip() if i+1 < len(lines) else ""
            if not next_line.startswith("box_url:"):
                new_lines.append(NEXT_LINE_URL + "\n")
                changed = True

    if changed:
        with open(path, "w") as f:
            f.writelines(new_lines)
        print(f"OK: {path}")
    else:
        print(f"SKIP: {path}")
```

Save as `/tmp/add_ubuntu_box_url.py`, then run:
```bash
python3 /tmp/add_ubuntu_box_url.py
```

**Step 3: Verify**
```bash
grep -r "bento/ubuntu" ansible/roles/*/molecule/vagrant/molecule.yml
```
Expected: no output.

```bash
grep -c "ubuntu-images" ansible/roles/*/molecule/vagrant/molecule.yml \
  | grep -v ":0" | wc -l
```
Expected: 23 (21 new + 2 already migrated: package_manager, pam_hardening).

**Step 4: Commit**
```bash
git add ansible/roles/*/molecule/vagrant/molecule.yml
git commit -m "fix(molecule): migrate vagrant Ubuntu boxes from bento to ubuntu-base.box (21 scenarios)"
```

---

## Task 5: Fix ssh role vagrant scenario

**File:** `ansible/roles/ssh/molecule/vagrant/molecule.yml`

Currently uses `archlinux/archlinux` (Arch) and `generic/ubuntu2404` (Ubuntu) — both outdated.

**Step 1: Replace the entire `platforms:` section**

Current:
```yaml
platforms:
  - name: arch-vm
    box: archlinux/archlinux
    memory: 2048
    cpus: 2
  - name: ubuntu-base
    box: generic/ubuntu2404
    memory: 2048
    cpus: 2
```

Replace with:
```yaml
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
```

**Step 2: Verify**
```bash
grep -E "archlinux/archlinux|generic/ubuntu2404" ansible/roles/ssh/molecule/vagrant/molecule.yml
```
Expected: no output.

```bash
grep -E "arch-base|ubuntu-base" ansible/roles/ssh/molecule/vagrant/molecule.yml
```
Expected: 4 lines (2 `box:` + 2 `box_url:`).

**Step 3: Commit**
```bash
git add ansible/roles/ssh/molecule/vagrant/molecule.yml
git commit -m "fix(molecule): update ssh vagrant boxes to arch-base + ubuntu-base"
```

---

## Task 6: Final audit

**Step 1: Verify no old image references remain**
```bash
echo "=== Old arch-systemd references ==="
grep -r "bootstrap/arch-systemd" ansible/roles/ .github/

echo "=== Old bento/ubuntu ==="
grep -r "bento/ubuntu" ansible/roles/

echo "=== Old archlinux/archlinux ==="
grep -r "archlinux/archlinux" ansible/roles/

echo "=== Old generic/ubuntu2404 ==="
grep -r "generic/ubuntu2404" ansible/roles/
```
Expected: all commands return no output.

**Step 2: Count Ubuntu-systemd Docker platforms**
```bash
grep -rl "Ubuntu-systemd" ansible/roles/*/molecule/docker/molecule.yml | wc -l
```
Expected: 24

**Step 3: Count ubuntu-base vagrant boxes**
```bash
grep -rl "ubuntu-images" ansible/roles/*/molecule/vagrant/molecule.yml | wc -l
```
Expected: 23

**Step 4: Commit if any cleanup needed, then summarize**
```bash
git log --oneline -6
```
