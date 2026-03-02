# Teleport Molecule Tests — Real Binary Install

**Date:** 2026-03-02
**PR:** #58 (ci/track-teleport)
**Closes:** PR #45 (superseded)

## Problem

Teleport molecule tests fail in Docker:
- Arch: AUR `teleport-bin` package unavailable
- Ubuntu: SSL certificate validation failure for APT GPG key
- PR #45 solved this with mock binaries — unacceptable, hides real issues

## Design Decisions

1. **No mocks** — real binary from `cdn.teleport.dev`
2. **`teleport_install_method: binary`** for Docker and Vagrant
3. **Single shared/verify.yml** with `when` guards for Docker vs non-Docker
4. **`skip-tags: report,service`** — service doesn't start without auth cluster (honest boundary)

## Installation Strategy

Docker and Vagrant both use binary install method:
- Download tarball from `cdn.teleport.dev`
- Extract to `/usr/local/bin/`
- Create systemd unit file for binary installs
- stat-check prevents re-download (idempotency)

## prepare.yml

**Docker:**
- Arch: `pacman -Sy` (update cache)
- Ubuntu: `apt update` + `ca-certificates` + `update-ca-certificates`
- No mock binaries

**Vagrant:**
- Ubuntu: `apt update`

## converge.yml

```yaml
vars:
  teleport_auth_server: "localhost:3025"
  teleport_join_token: "test-token-molecule"
  teleport_node_name: "molecule-test"
  teleport_session_recording: "node"
  teleport_export_ca_key: false
```

## shared/verify.yml — Full Verification

### Section 1: Binary
- `command -v teleport` — found in PATH
- `teleport version` — rc=0, stdout contains "Teleport"

### Section 2: Config File
- `/etc/teleport.yaml` exists
- owner=root, group=root, mode=0600
- Content contains:
  - `version: v3`
  - `nodename: molecule-test`
  - `auth_server: localhost:3025`
  - `auth_token:` (present)
  - `data_dir: /var/lib/teleport`
  - Sections: `ssh_service:`, `proxy_service:`, `auth_service:`
  - `mode: node` (session recording)
  - Ansible managed header

### Section 3: Data Directory
- `/var/lib/teleport` exists, directory, root:root, 0750

### Section 4: Systemd Unit (binary install)
- `/etc/systemd/system/teleport.service` exists
- Contains `ExecStart=/usr/local/bin/teleport start`
- `systemctl is-enabled teleport` → enabled (non-Docker only)

### Section 5: Negative Checks
- Competitor daemons not running

## Edge Cases

- Idempotency: stat-check prevents re-download
- `teleport_enabled: false` doesn't break existing config
- Custom labels appear in config
- Session recording mode values validated

## molecule.yml

```yaml
provisioner:
  inventory:
    host_vars:
      Archlinux-systemd:
        teleport_install_method: binary
      Ubuntu-systemd:
        teleport_install_method: binary
  options:
    skip-tags: report,service
```
