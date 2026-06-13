# packages

Ensures package lists from inventory are installed on the target host.

The role does not own package data. Public inputs come from inventory and role
defaults. The role builds internal package lists in `vars/main.yml`, then routes
install, verify, and report work to an OS-family task directory.

Implemented install backends:

- `Archlinux`
- `Debian` (Ubuntu uses this Ansible OS family)

Declared placeholder backends:

- `Gentoo`
- `RedHat`
- `Void`

For Arch AUR packages, this role calls the `yay` backend in package-management
mode only. It does not set up `yay`, the AUR builder user, sudoers, makepkg, or
the `yay` binary. In the workstation flow that preparation belongs to
`package_manager`.

## Role Flow

`tasks/main.yml` contains the role flow:

1. **Packages role**
   Guarded by `packages_enabled | bool`. If disabled, the whole role block is skipped.

2. **Install packages (OS-specific)**
   Includes `tasks/{{ ansible_facts['os_family'] | lower }}/install.yml`.

3. **Verify packages**
   Includes `tasks/{{ ansible_facts['os_family'] | lower }}/verify.yml`.

4. **Report package phases**
   Includes `tasks/{{ ansible_facts['os_family'] | lower }}/report.yml`.

5. **Packages -- Execution Report**
   Calls `common` role task `report_render.yml` for `_packages_phases`.

The role does not validate OS family in a separate task. If an OS-family task
directory is missing, the include fails with Ansible's missing-file error. The
currently declared but unimplemented OS backends have no-op task files.

## Derived Variables

`vars/main.yml` is role-internal. Ansible loads it when the role starts.

| Variable | Meaning |
|----------|---------|
| `_packages_official_all` | Official package list selected for the current OS |
| `_packages_archlinux_aur` | Arch AUR package list from `packages_aur` |
| `_packages_archlinux_verify_all` | Official packages plus AUR packages |
| `_packages_debian_verify_all` | Official packages only |
| `_packages_verify_all` | Expected package list for the current OS family |

These variables are not inventory API. They are the private interface between
the role entrypoint, OS-specific task files, reports, and Molecule verify.

## Public Inputs

Override these through inventory, usually `inventory/group_vars/all/packages*.yml`.

| Variable | Default | Description |
|----------|---------|-------------|
| `packages_enabled` | `true` | Master toggle for the role |
| `packages_base` | `[]` | Core CLI utilities |
| `packages_editors` | `[]` | Editors |
| `packages_docker` | `[]` | Docker and container tools |
| `packages_xorg` | `[]` | X.Org packages |
| `packages_wm` | `[]` | Window-manager packages and helpers |
| `packages_filemanager` | `[]` | File manager packages |
| `packages_network` | `[]` | Network packages |
| `packages_media` | `[]` | Media control packages |
| `packages_desktop` | `[]` | Desktop integration packages |
| `packages_graphics` | `[]` | Graphics packages |
| `packages_session` | `[]` | Session/display-manager packages |
| `packages_terminal` | `[]` | Terminal packages |
| `packages_fonts` | `[]` | Font packages |
| `packages_theming` | `[]` | Theme/icon packages |
| `packages_search` | `[]` | Search tools |
| `packages_viewers` | `[]` | Viewers and data tools |
| `packages_archlinux` | `[]` | Arch Linux package and pacman group list passed to pacman |
| `packages_ubuntu` | `[]` | Ubuntu package list passed to apt |
| `packages_aur` | `[]` | Arch-only AUR packages requested by inventory |
| `packages_aur_remove_conflicts` | `[]` | Arch packages to remove before installing AUR replacements |
| `packages_aur_transport_proxy_enabled` | `false` | Enables optional AUR transport proxy workaround |

Package names are passed to the selected backend as-is. This role does not
translate package names between distributions.

## Backend Tasks

### Archlinux Install

`tasks/archlinux/install.yml`:

1. **Install packages (pacman)**
   Installs `_packages_official_all` with `ansible.builtin.package`.

2. **Apply AUR transport proxy workaround layer**
   Includes role `aur_transport_proxy` only when `_packages_archlinux_aur` is
   non-empty and `packages_aur_transport_proxy_enabled` is true.

3. **Install AUR packages**
   Includes role `yay` only when `_packages_archlinux_aur` is non-empty.
   Passes:

   - `yay_manage_setup: false`
   - `yay_manage_aur_packages: true`
   - `yay_packages_aur: "{{ _packages_archlinux_aur }}"`
   - `yay_packages_aur_remove_conflicts: "{{ packages_aur_remove_conflicts }}"`
   - `yay_packages_official: "{{ _packages_official_all }}"`

This keeps package installation inside the Arch backend task file without
moving AUR helper setup into `packages`.

### Archlinux Verify

`tasks/archlinux/verify.yml`:

1. Probes every entry in `_packages_official_all` with `pacman -Q`.
2. For entries that are not installed package names, resolves them with
   `pacman -Sgq` as pacman groups and verifies each resolved group member with
   `pacman -Q`.
3. Runs `pacman -Q {{ item }}` for every package in `_packages_archlinux_aur`
   under the `aur` tag.

### Archlinux Report

`tasks/archlinux/report.yml`:

1. Adds an install phase row to `_packages_phases`.
2. Adds a verify phase row to `_packages_phases`.

### Debian Install

`tasks/debian/install.yml`:

1. Updates apt cache with `cache_valid_time: 3600`.
2. Installs `_packages_official_all` with `ansible.builtin.apt`.
3. Runs `dpkg --audit` and fails if dpkg has pending configuration.

### Debian Verify

`tasks/debian/verify.yml`:

1. Runs `dpkg-query` for every package in `_packages_verify_all`.
2. Gathers package facts.
3. Asserts every package in `_packages_verify_all` exists in `ansible_facts.packages`.

### Debian Report

`tasks/debian/report.yml`:

1. Adds an install phase row to `_packages_phases`.
2. Adds a verify phase row to `_packages_phases`.

### Placeholder Backends

`tasks/gentoo/*`, `tasks/redhat/*`, and `tasks/void/*`:

1. Install task prints that the backend is not implemented and skips install.
2. Verify task prints that verification is not implemented and skips verify.
3. Report task records skipped install and verify phases.

## Molecule Tests

Required scenarios:

| Scenario | Platforms | Purpose |
|----------|-----------|---------|
| `docker` | `Archlinux-systemd`, `Ubuntu-systemd` | Fast role feedback on Arch and Ubuntu containers |
| `vagrant` | `arch-vm`, `ubuntu-base` | VM validation on Arch and Ubuntu |

Manual scenario:

| Scenario | Platform | Purpose |
|----------|----------|---------|
| `default` | `localhost` | Delegated smoke run on the current host |

All scenarios use Molecule Galaxy dependency resolution with
`ansible/requirements.yml`. This installs required collections such as
`community.general` and `kewlfft.aur`; it does not run any Ansible role.

AUR installation requires a prepared AUR backend. The Molecule `prepare` phase
sets up that backend on Arch when `packages_aur` is non-empty; the `packages`
role itself still runs only the package installation path.

### Docker Scenario Flow

`molecule/docker/molecule.yml` runs:

1. `syntax`
2. `create`
3. `prepare`
4. `converge`
5. `idempotence`
6. `verify`
7. `destroy`

`molecule/docker/prepare.yml`:

1. Updates pacman cache on Arch.
2. Updates apt cache on Debian/Ubuntu.
3. Imports `molecule/shared/prepare-aur-backend.yml`.

The scenario installs Galaxy collections from `ansible/requirements.yml` before
the playbooks run.

### Vagrant Scenario Flow

`molecule/vagrant/molecule.yml` runs the same sequence as Docker.

`molecule/vagrant/prepare.yml`:

1. Imports the shared Vagrant bootstrap playbook.
2. Imports `molecule/shared/prepare-aur-backend.yml`.

`molecule/shared/prepare-aur-backend.yml` sets up the Arch AUR backend when
`packages_aur` is non-empty. It calls `yay` setup-only mode and does not run
`packages`.

The scenario installs Galaxy collections from `ansible/requirements.yml` before
the playbooks run.

### Shared Converge

`molecule/shared/converge.yml`:

1. Loads `inventory/group_vars/all/packages.yml` through `vars_files`.
2. Runs the `packages` role on all Molecule hosts.

The role itself loads `vars/main.yml` during the role run.

### Shared Verify

`molecule/shared/verify.yml` is a separate Ansible run. It does not inherit
variables from converge.

It:

1. Loads `inventory/group_vars/all/packages.yml`.
2. Loads `roles/packages/vars/main.yml`.
3. Derives the expected package list for the current Molecule run.
4. Asserts the expected package list is not empty.
5. Gathers `ansible.builtin.package_facts`.
6. Asserts every expected package exists in `ansible_facts.packages`.

Molecule verify checks installed state. It does not call the role's own
`tasks/<os_family>/verify.yml` task files.

## Tags

| Tag | What it selects |
|-----|-----------------|
| `packages` | The role block and all role tasks tagged with `packages` |
| `install` | Install tasks |
| `aur` | Arch AUR-related tasks |
| `report` | Report tasks |

Examples:

```bash
ansible-playbook site.yml --tags install --skip-tags report
ansible-playbook site.yml --tags packages --skip-tags report
```

## File Map

| File | Purpose |
|------|---------|
| `defaults/main.yml` | Public defaults |
| `vars/main.yml` | Internal derived package lists |
| `tasks/main.yml` | Role entrypoint: install, verify, report, render report |
| `tasks/archlinux/install.yml` | Arch official package install and AUR package install |
| `tasks/archlinux/verify.yml` | Arch package verification via `pacman -Q` |
| `tasks/archlinux/report.yml` | Arch report rows |
| `tasks/debian/install.yml` | Debian/Ubuntu apt cache, install, and dpkg audit |
| `tasks/debian/verify.yml` | Debian/Ubuntu verification via `dpkg-query` and package facts |
| `tasks/debian/report.yml` | Debian/Ubuntu report rows |
| `tasks/gentoo/*` | Gentoo no-op placeholder backend |
| `tasks/redhat/*` | RedHat/Fedora no-op placeholder backend |
| `tasks/void/*` | Void no-op placeholder backend |
| `molecule/docker/` | Docker scenario |
| `molecule/vagrant/` | Vagrant scenario |
| `molecule/default/` | Delegated localhost scenario |
| `molecule/shared/prepare-aur-backend.yml` | Shared Arch AUR backend precondition |
| `molecule/shared/converge.yml` | Shared role run |
| `molecule/shared/verify.yml` | Shared installed-state verification |
