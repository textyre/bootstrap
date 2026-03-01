# CI Workflows

This directory contains all GitHub Actions workflows for the bootstrap project.

## Overview

| File | Purpose | Trigger | Depends On |
|------|---------|---------|------------|
| `molecule.yml` | **Orchestrator** — detect changed roles, dispatch Docker + Vagrant matrix | push/PR (`ansible/roles/**`), manual | `_molecule.yml`, `_molecule-vagrant.yml` |
| `_molecule.yml` | **Reusable** — Docker-based molecule test for one role | workflow_call | `ci-env` image |
| `_molecule-vagrant.yml` | **Reusable** — Vagrant/KVM molecule test for one role + platform | workflow_call | `arch-base.box`, `ubuntu-base.box` |
| `lint.yml` | YAML lint + ansible-lint + playbook syntax check | push/PR (`ansible/**`), manual | `ci-env-lint` image |
| `build-ci-image.yml` | Build `ci-env` image → GHCR | push (`Dockerfile.ci`, `requirements.txt`) | — |
| `build-lint-image.yml` | Build `ci-env-lint` image → GHCR | push (`Dockerfile.ci-lint`, `requirements-lint.txt`) | — |

## Workflow Relationships

```
molecule.yml (orchestrator)
├── calls → _molecule.yml          (Docker, per changed role)
├── calls → _molecule-vagrant.yml  (Vagrant, per changed role × platform)
└── calls → _molecule-vagrant.yml  (Vagrant-laptop scenario)

lint.yml
└── uses → ci-env-lint image

_molecule.yml
└── uses → ci-env image
         → arch-base image (Arch tests)
         → ubuntu-base image (Ubuntu tests)

_molecule-vagrant.yml
└── uses → arch-base.box (libvirt)
         → ubuntu-base.box (libvirt)
```

## CI Image Map

| Image | Built By | Used By | Dockerfile |
|-------|---------|---------|------------|
| `ghcr.io/<repo>/ci-env:latest` | `build-ci-image.yml` | `_molecule.yml` | `.github/docker/Dockerfile.ci` |
| `ghcr.io/<repo>/ci-env-lint:latest` | `build-lint-image.yml` | `lint.yml` | `.github/docker/Dockerfile.ci-lint` |
| `ghcr.io/textyre/arch-base:latest` | textyre/arch-images repo | `_molecule.yml` | external |
| `ghcr.io/textyre/ubuntu-base:latest` | textyre/ubuntu-images repo | `_molecule.yml` | external |
| `arch-base.box` (libvirt) | textyre/arch-images releases | `_molecule-vagrant.yml` | external |
| `ubuntu-base.box` (libvirt) | textyre/ubuntu-images releases | `_molecule-vagrant.yml` | external |

## Known Issues

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| 1 | 🟢 MAINTENANCE | `_molecule-vagrant.yml` | Pip cache key has hardcoded versions (`ansible-core-2.20.1-molecule-25.12.0`); stale on dep upgrade | Use `hashFiles` on pip requirements or inline dynamic key |
| 2 | 🟢 GAP | `lint.yml` | `.github/workflows/**` not in path filter; no `actionlint` step | Expand filter, add actionlint |

## Molecule Role Coverage

| Scenario | Count |
|----------|-------|
| Docker (`molecule/docker/`) — CI-ready | 32 roles |
| Vagrant (`molecule/vagrant/`) — realistic KVM tests | 27 roles |
| Vagrant-laptop (`molecule/vagrant-laptop/`) | 1 role (`power_management`) |
