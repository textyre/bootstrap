# Molecule Test Infrastructure

## arch-systemd Image Contract

The `Dockerfile.archlinux` builds an image used by all Docker-based Molecule scenarios.
The image MUST provide these capabilities:

| Guarantee | Path / Command | Needed by |
|-----------|---------------|-----------|
| systemd as PID 1 | `/usr/lib/systemd/systemd` | All roles (systemd services, timers) |
| python | `python --version` | Ansible connection |
| sudo | `sudo --version` | `become: true` in playbooks |
| locale definition files | `/usr/share/i18n/locales/ru_RU`, `en_US` | `locale` role (`community.general.locale_gen`) |
| SUPPORTED list | `/usr/share/i18n/SUPPORTED` | `locale` role (availability check) |
| locale-gen | `which locale-gen` | `locale` role (compilation) |

### Why locale data needs explicit restoration

`archlinux:base` strips `/usr/share/i18n/*` via `NoExtract` in `pacman.conf` to reduce image size.
The Dockerfile removes `NoExtract` rules and reinstalls `glibc` to restore full locale data.
See `docs/troubleshooting/troubleshooting-history-2026-02-23-locale-ci.md` for the full post-mortem.

### Modifying the Dockerfile

Before changing `Dockerfile.archlinux`:
1. Check this contract — will your change remove any guaranteed capability?
2. The `build-arch-image.yml` workflow verifies the contract after every build
3. The `molecule.yml` workflow rebuilds the image when Dockerfile changes before running tests

### CI Workflows

- `build-arch-image.yml` — builds, pushes to GHCR, then verifies contract
- `molecule.yml` — detects Dockerfile changes, rebuilds image if needed, then runs tests
- `_molecule.yml` — reusable workflow that runs `molecule test` for a single role
