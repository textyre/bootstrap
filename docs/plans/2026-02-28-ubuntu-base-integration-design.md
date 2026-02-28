# Design: ubuntu-base Integration Across All Molecule Tests

**Date:** 2026-02-28
**Status:** Approved

## Context

Two standalone image repos now exist:
- `textyre/arch-images` → `ghcr.io/textyre/arch-base:latest` (Docker) + `arch-base.box` (Vagrant)
- `textyre/ubuntu-images` → `ghcr.io/textyre/ubuntu-base:latest` (Docker) + `ubuntu-base.box` (Vagrant)

Audit found that these images are not consistently used across all Molecule scenarios.

## Gaps Found

### Docker scenarios (31 roles)

| Problem | Count |
|---------|-------|
| Old fallback `ghcr.io/textyre/bootstrap/arch-systemd:latest` | 24 roles |
| No Ubuntu platform | all 31 roles |
| `MOLECULE_UBUNTU_IMAGE` not set in CI | `_molecule.yml` |

In CI, `_molecule.yml` sets `MOLECULE_ARCH_IMAGE=ghcr.io/textyre/arch-base:latest`, so Arch Docker tests already pull the correct image. The fallback fix is for local development runs.

### Vagrant scenarios (26 roles)

| Problem | Count |
|---------|-------|
| Ubuntu: `bento/ubuntu-24.04` instead of `ubuntu-base.box` | 22 roles |
| `ssh` role: `archlinux/archlinux` + `generic/ubuntu2404` (fully outdated) | 1 role |

## Design

### Arch-only roles (no Ubuntu platform added)

Docker-only, no cross-platform logic: `caddy`, `greeter`, `lightdm`, `xorg`, `zen_browser`
Vagrant arch-only: `reflector`, `vaultwarden`

### 1. Docker: Fix fallback images (24 roles)

Change in every `docker/molecule.yml` that still has the old fallback:

```yaml
# Before
image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/bootstrap/arch-systemd:latest}"

# After
image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/arch-base:latest}"
```

### 2. Docker: Add Ubuntu platform to cross-platform roles (25 roles)

Roles: chezmoi, docker, fail2ban, firewall, git, gpu_drivers, hostctl, hostname,
locale, ntp, ntp_audit, package_manager, packages, pam_hardening, power_management,
shell, ssh, ssh_keys, sysctl, teleport, timezone, user, vconsole, yay

Ubuntu platform block to append after the Arch platform:

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

Note: `command` differs — Arch uses `/usr/lib/systemd/systemd`, Ubuntu uses `/lib/systemd/systemd`.

### 3. CI workflow: Add MOLECULE_UBUNTU_IMAGE (_molecule.yml)

```yaml
env:
  MOLECULE_ARCH_IMAGE: ghcr.io/textyre/arch-base:latest
  MOLECULE_UBUNTU_IMAGE: ghcr.io/textyre/ubuntu-base:latest
```

Update job name: `"${{ inputs.role_name }} (Arch+Ubuntu/systemd)"`

### 4. Vagrant: Migrate Ubuntu boxes (22 roles)

Roles: chezmoi, docker, fail2ban, firewall, git, gpu_drivers, hostctl, hostname,
locale, ntp, ntp_audit, packages, power_management, shell, ssh_keys, sysctl,
teleport, timezone, user, vconsole, yay, ntp_audit

```yaml
# Before
  - name: ubuntu-base
    box: bento/ubuntu-24.04

# After
  - name: ubuntu-base
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
```

### 5. Vagrant: Fix ssh role (both platforms)

```yaml
# Before
  - name: arch-vm
    box: archlinux/archlinux
  - name: ubuntu-base
    box: generic/ubuntu2404

# After
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

## File Change Summary

| File type | Count |
|-----------|-------|
| `docker/molecule.yml` — fallback fix | 24 files |
| `docker/molecule.yml` — add Ubuntu platform | 25 files (overlaps above) |
| `vagrant/molecule.yml` — ubuntu-base.box | 22 files |
| `vagrant/molecule.yml` — ssh fix | 1 file |
| `.github/workflows/_molecule.yml` | 1 file |

Total: ~48 unique files, all mechanical YAML changes.

## Notes

- Arch platform is never removed — Ubuntu is added alongside it
- Roles that are Arch-only do not receive Ubuntu platform
- Docker systemd path differs: Arch `/usr/lib/systemd/systemd`, Ubuntu `/lib/systemd/systemd`
- The `packages` role in vagrant already uses `arch-base`; only its ubuntu platform needs updating
