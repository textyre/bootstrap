# CI Workflows

This directory contains all GitHub Actions workflows for the bootstrap project.

## Overview

| File | Purpose | Trigger | Depends On |
|------|---------|---------|------------|
| `molecule.yml` | Detect changed roles → run `molecule test -s docker` in `ci-env` container | push/PR (`ansible/roles/**`), manual | `ci-env` image |
| `molecule-vagrant.yml` | Detect changed roles → run `molecule test -s vagrant` on KVM | push/PR (`ansible/roles/**`), manual | `arch-base.box`, `ubuntu-base.box` |
| `lint.yml` | YAML lint + ansible-lint + playbook syntax check | push/PR (`ansible/**`), manual | `ci-env-lint` image |
| `build-ci-image.yml` | Build `ci-env` image → GHCR | push (`Dockerfile.ci`, `requirements.txt`) | — |
| `build-lint-image.yml` | Build `ci-env-lint` image → GHCR | push (`Dockerfile.ci-lint`, `requirements-lint.txt`) | — |

## Workflow Relationships

```
molecule.yml          — standalone, no calls to other workflows
molecule-vagrant.yml  — standalone, no calls to other workflows
lint.yml              — standalone, uses ci-env-lint image
build-ci-image.yml    — standalone, produces ci-env image
build-lint-image.yml  — standalone, produces ci-env-lint image
```

## CI Image Map

| Image | Built By | Used By | Dockerfile |
|-------|---------|---------|------------|
| `ghcr.io/<repo>/ci-env:latest` | `build-ci-image.yml` | `molecule.yml` | `.github/docker/Dockerfile.ci` |
| `ghcr.io/<repo>/ci-env-lint:latest` | `build-lint-image.yml` | `lint.yml` | `.github/docker/Dockerfile.ci-lint` |
| `ghcr.io/textyre/arch-base:latest` | textyre/arch-images repo | `molecule.yml` | external |
| `ghcr.io/textyre/ubuntu-base:latest` | textyre/ubuntu-images repo | `molecule.yml` | external |
| `arch-base.box` (libvirt) | textyre/arch-images releases | `molecule-vagrant.yml` | external |
| `ubuntu-base.box` (libvirt) | textyre/ubuntu-images releases | `molecule-vagrant.yml` | external |

## Molecule Role Coverage

| Scenario | Workflow | Count |
|----------|---------|-------|
| Docker (`molecule/docker/`) | `molecule.yml` | 32 roles |
| Vagrant (`molecule/vagrant/`) | `molecule-vagrant.yml` | 27 roles |
