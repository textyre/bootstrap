# Molecule CI Testing — Design

**Date:** 2026-02-22
**Status:** Approved
**Scope:** timezone role (Arch + systemd), pattern for all roles

## Problem

No automated role testing in CI. Current setup:
- `lint.yml` — yamllint, ansible-lint, syntax-check only
- `molecule/default/` — runs on real VM via localhost, requires vault
- M1 Mac — no local Docker or VM available

## Decision

Molecule + Docker in GitHub Actions. No local infrastructure required.

## Architecture

### File Structure

```
.github/
└── workflows/
    ├── lint.yml                    # existing (untouched)
    ├── _molecule.yml               # reusable workflow (workflow_call)
    └── molecule-timezone.yml       # caller (per-role)

ansible/
├── molecule/
│   └── Dockerfile.archlinux        # shared Arch + systemd image
├── requirements.txt                # + molecule-plugins[docker], docker
└── roles/
    └── timezone/
        └── molecule/
            ├── default/            # existing VM scenario (untouched)
            └── docker/             # new CI scenario
                ├── molecule.yml
                ├── converge.yml
                └── verify.yml
```

### Reusable Workflow (`_molecule.yml`)

Contains all shared logic:
- Python setup with pip cache (`cache-dependency-path: ansible/requirements.txt`)
- Dependency install: `requirements.txt` + `molecule-plugins[docker]` + `docker`
- Ansible collections: `community.general`
- `molecule test -s <scenario>` execution
- `PY_COLORS=1`, `ANSIBLE_FORCE_COLOR=1` for readable logs
- Concurrency group per role + PR (cancel-in-progress)

Inputs:
- `role_name` (required) — directory under `ansible/roles/`
- `molecule_scenario` (default: `docker`)
- `python_version` (default: `3.12`)

### Per-Role Caller (`molecule-timezone.yml`)

Minimal — only defines triggers and paths:
- `paths:` — role dir, common/ (dependency), Dockerfile, workflow files
- `workflow_dispatch` — manual trigger from GitHub UI
- Calls `_molecule.yml` with `role_name: timezone`

### Dockerfile (`Dockerfile.archlinux`)

Minimal Arch + systemd image:
- Base: `archlinux:base`
- Installs: `python`, `sudo` (Ansible requirements)
- Strips systemd units that break in containers
- CMD: `/usr/lib/systemd/systemd`

Shared across all roles. Role-specific packages installed by Ansible during converge.

### Molecule Scenario (`docker/`)

- Driver: `docker` (not `default`)
- Platform: archlinux with systemd as PID 1, privileged, cgroup volume
- No vault dependency
- Test sequence: syntax → create → converge → idempotence → verify → destroy
- `ANSIBLE_ROLES_PATH` set to find sibling roles (common)

### Verify Tests

1. `/etc/localtime` symlink points to correct timezone (readlink, not timedatectl — more reliable in containers)
2. tzdata package installed
3. Debug output confirming success

## Patterns Referenced

| Project | Stars | Pattern Used |
|---------|-------|-------------|
| geerlingguy/ansible-role-mysql | 1117 | pip cache, PY_COLORS, molecule-plugins[docker] |
| dev-sec/ansible-collection-hardening | 5228 | per-role workflow, paths filter, concurrency, fail-fast: false |
| wahooli/ansible-collection-common | — | shared Dockerfile.archlinux-systemd, molecule-shared/ dir |
| CrowdStrike/falcon-scripts | 206 | reusable workflow_call pattern |
| fernandoaleman/ansible.okb.system | — | reusable workflow with role_name input |

## Future Extensions

- **Multi-distro matrix:** Add distro input to reusable workflow, matrix in caller or reusable
- **More roles:** Copy `molecule-timezone.yml`, change role_name and paths
- **Non-systemd init:** Custom Dockerfile per init system (Void/runit, Gentoo/openrc)
- **Pre-built images:** Push Dockerfile to GHCR for faster builds (skip Docker build step)
