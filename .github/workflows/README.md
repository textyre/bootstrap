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
| `build-control-plane.yml` | Build and test the workstation deployment image; publish the tested image to GHCR | push/PR (`Dockerfile`, `.dockerignore`, `ansible/**`), manual | — |

## Workflow Relationships

```
molecule.yml          — standalone, no calls to other workflows
molecule-vagrant.yml  — standalone, no calls to other workflows
lint.yml              — standalone, uses ci-env-lint image
build-ci-image.yml    — standalone, produces ci-env image
build-lint-image.yml  — standalone, produces ci-env-lint image
build-control-plane.yml — standalone, produces the ready-to-run workstation deployment image
```

## CI Image Map

| Image | Built By | Used By | Dockerfile |
|-------|---------|---------|------------|
| `ghcr.io/<repo>/ci-env:latest` | `build-ci-image.yml` | `molecule.yml` | `.github/docker/Dockerfile.ci` |
| `ghcr.io/<repo>/ci-env-lint:latest` | `build-lint-image.yml` | `lint.yml` | `.github/docker/Dockerfile.ci-lint` |
| `ghcr.io/<repo>/control-plane:latest` | `build-control-plane.yml` | OpenStrap deployment | root `Dockerfile` |
| `ghcr.io/textyre/arch-base:latest` | textyre/arch-images repo | `molecule.yml` | external |
| `ghcr.io/textyre/ubuntu-base:latest` | textyre/ubuntu-images repo | `molecule.yml` | external |
| `arch-base.box` (libvirt) | textyre/arch-images releases | `molecule-vagrant.yml` | external |
| `ubuntu-base.box` (libvirt) | textyre/ubuntu-images releases | `molecule-vagrant.yml` | external |

## Molecule Role Coverage

| Scenario | Workflow | Count |
|----------|---------|-------|
| Docker (`molecule/docker/`) | `molecule.yml` | 32 roles |
| Vagrant (`molecule/vagrant/`) | `molecule-vagrant.yml` | 27 roles |

## Workstation deployment image

`build-control-plane.yml` builds one `linux/amd64` image containing the system
Ansible executable, Python, ARA, Galaxy collections, workstation playbook, roles
and public configuration. It starts that image, checks workstation syntax,
connects to a disposable SSH fixture using Ansible's native private-key/agent
support, and confirms that ARA recorded the run. The fixture uses a generated
test key and dummy Vault password; it does not execute workstation roles or
require deployment secrets. These checks run in CI before publication.

Pull requests only build and test. A successful push to `master`, or a manual run
on `master`, publishes the exact tested image as:

```text
ghcr.io/textyre/bootstrap/control-plane:latest
ghcr.io/textyre/bootstrap/control-plane:sha-<full Git commit SHA>
```

The workflow authenticates with the repository's `GITHUB_TOKEN` and
`packages: write`. No separate publication token is required. The full commit
tag identifies the source revision; use the image digest when a deployment must
pin the exact published artifact. The Docker host downloads this image and
runs it without checking out Git, installing Task or building dependencies.

For anonymous Docker pulls, set the GHCR package visibility to **public** after
the first publication. GitHub creates a new container package as private by
default. Package access and permissions are described in the
[GitHub Container Registry documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
