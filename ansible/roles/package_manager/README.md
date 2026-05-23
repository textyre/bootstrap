# package_manager

[![Molecule](https://github.com/textyre/bootstrap/actions/workflows/molecule.yml/badge.svg)](https://github.com/textyre/bootstrap/actions/workflows/molecule.yml)
[![Molecule Vagrant](https://github.com/textyre/bootstrap/actions/workflows/molecule-vagrant.yml/badge.svg)](https://github.com/textyre/bootstrap/actions/workflows/molecule-vagrant.yml)

Configure the system package manager for Arch Linux, Debian/Ubuntu, Fedora, Void Linux, and Gentoo.
Deploys optimized configuration via Jinja2 templates — no `lineinfile` patching.

## What this role does

- [x] Deploys pacman.conf with parallel downloads, Color, SigLevel, optional multilib (Arch)
- [x] Configures paccache.timer for automatic cache cleanup with customizable retention (Arch)
- [x] Deploys makepkg.conf drop-in with MAKEFLAGS and PKGEXT (Arch)
- [x] Configures apt parallel downloads and dpkg conflict-resolution options (Debian/Ubuntu)
- [x] Deploys dnf.conf with parallel downloads, fastestmirror, keepcache settings (Fedora)
- [x] Deploys xbps config and schedules weekly cache cleanup via cron (Void)
- [x] Runs yay setup-only on Arch as part of the Arch package manager contract
- [x] Refreshes package indexes as package manager preparation (Arch pacman databases, Debian apt package index)
- [x] Validates OS is in supported list before any configuration
- [x] Runs in-role verification after deployment (verify.yml)
- [x] Supports external pacman cache on shared storage

## What this role does not do

- It does not perform full OS upgrades or force `archlinux-keyring` to `latest`; that belongs to the pre-workstation `system_update` lifecycle.
- It does not install the workstation package set; that remains the responsibility of the `packages` role.

## Ownership contract

This role owns the package manager configuration files it templates:

- Arch Linux: `/etc/pacman.conf`
- Fedora / RedHat family: `/etc/dnf/dnf.conf`
- Debian / Ubuntu: role-owned drop-ins under `/etc/apt/apt.conf.d/`
- Void Linux: role-owned drop-in `/etc/xbps.d/ansible.conf`

Manual changes to the fully owned files are expected to be overwritten on the
next role run. Use inventory variables instead of editing managed files directly.

## Execution flow

1. **Validate** (`tasks/validate.yml`) — fail fast for unsupported OS families and invalid package-manager inputs
2. **OS dispatch** (`tasks/main.yml`) — include `tasks/<os_family>/main.yml` based on `ansible_facts['os_family']`
3. **Archlinux path** (`tasks/archlinux/main.yml`):
   1. Configure pacman → `tasks/archlinux/pacman.yml` (template `/etc/pacman.conf`, optional external cache)
   2. Refresh pacman package indexes → `tasks/archlinux/cache.yml`
      (only when enabled and when config changed, indexes are missing, or the
      local sync directory is older than the configured freshness window)
   3. Configure paccache → `tasks/archlinux/paccache.yml` (assert systemd support, then include `tasks/archlinux/systemd/paccache.yml`)
   4. Configure makepkg → `tasks/archlinux/makepkg.yml` (template drop-in to `/etc/makepkg.conf.d/`)
   5. Include `tasks/archlinux/yay.yml`, which imports `yay` in setup-only mode (builder user + binary). This is intentional: on Arch, this project treats `pacman` + `yay` as the complete package manager surface.
4. **Debian path** (`tasks/debian/main.yml`):
   1. Configure apt → `tasks/debian/apt.yml` (template to `/etc/apt/apt.conf.d/10-ansible-parallel.conf`)
   2. Configure dpkg → `tasks/debian/dpkg.yml` (template to `/etc/apt/apt.conf.d/20-ansible-dpkg.conf`)
   3. Refresh apt package index → `tasks/debian/cache.yml` (`apt update` with cache validity guard)
5. **RedHat path** (`tasks/redhat/main.yml`):
   1. Configure dnf → `tasks/redhat/dnf.yml` (template `/etc/dnf/dnf.conf`)
6. **Void path** (`tasks/void/main.yml`):
   1. Configure xbps → `tasks/void/xbps.yml` (template to `/etc/xbps.d/ansible.conf`)
   2. Configure cache cron → `tasks/void/cache.yml` (weekly `xbps-remove -O`)
7. **Gentoo path** (`tasks/gentoo/main.yml`) — stub, logs a message
8. **In-role verification** (`tasks/verify.yml`) — dispatch to OS-specific verify files and run lightweight parser/runtime probes
9. **Explicit state transitions**: systemd daemon reload is scoped to the `paccache.timer` systemd task
10. **Structured logging** — `report_phase` + `report_render` via common role

The role does not publish computed package-manager state as host facts. Values
needed by later tasks are kept as registered task results or task-local vars.
The role refreshes package indexes as package-manager preparation. That means
`pacman -Sy` / `apt update` style index refresh only, guarded by cache age where
the package manager supports it. It does not run full package upgrades.
On Arch, cache age is measured from the local pacman sync directory, not from
the `*.db` file timestamps, because pacman preserves repository timestamps on
those database files.
The role does not use handlers for package-manager state transitions; systemd
daemon-reload happens in the task that enables `paccache.timer`.

## Variables

### Global

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_enabled` | `true` | safe | Master toggle — set `false` to skip the entire role |
| `package_manager_refresh_package_indexes` | `true` | safe | Refresh package indexes before later install-only package roles |
| `package_manager_package_index_cache_valid_time` | `3600` | safe | Minimum freshness window in seconds before package indexes are refreshed again. Arch uses the local sync directory timestamp for this check. |

### Arch Linux / pacman

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_pacman_parallel_downloads` | `5` | safe | Number of parallel downloads |
| `package_manager_pacman_color` | `true` | safe | Enable color output |
| `package_manager_pacman_verbose_pkg_lists` | `true` | safe | Verbose package lists |
| `package_manager_pacman_check_space` | `true` | safe | Check available disk space before install |
| `package_manager_pacman_siglevel` | `"Required DatabaseOptional"` | internal | Signature verification level. Preflight rejects unsafe overrides such as `Never`, `TrustAll`, or values that stop requiring official package signatures. `LocalFileSigLevel` remains `Optional` so locally built AUR packages still install. |
| `package_manager_pacman_multilib` | `false` | careful | Enable [multilib] repository — adds 32-bit package support |
| `package_manager_pacman_external_cache` | `false` | careful | Use external shared cache — requires `cache_root` |
| `package_manager_pacman_cache_root` | `""` | careful | Path to external cache root (requires `external_cache: true`) |

### Arch Linux / paccache

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_paccache_enabled` | `true` | safe | Enable paccache.timer (weekly cache cleanup) |
| `package_manager_paccache_keep` | `3` | safe | Number of package versions to keep in cache |

### Arch Linux / makepkg

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_makepkg_enabled` | `true` | safe | Deploy makepkg drop-in config |
| `package_manager_makepkg_makeflags` | `"-j<vcpus>"` | safe | Parallel make jobs (auto-detects CPU count) |
| `package_manager_makepkg_pkgext` | `".pkg.tar.zst"` | safe | Package archive format. Must be one of the role allow-listed pacman package suffixes such as `.pkg.tar.zst`, `.pkg.tar.xz`, `.pkg.tar.gz`, or `.pkg.tar`. |

### Debian / Ubuntu / apt

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_apt_parallel_queue_mode` | `"host"` | safe | Parallel download queue mode |
| `package_manager_apt_retries` | `3` | safe | Number of download retries |
| `package_manager_apt_dpkg_force_confdef` | `true` | careful | Use default on config file conflict during upgrade |
| `package_manager_apt_dpkg_force_confold` | `true` | careful | Keep old config file on conflict during upgrade |

### Fedora / dnf

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_dnf_parallel_downloads` | `5` | safe | Number of parallel downloads |
| `package_manager_dnf_fastestmirror` | `true` | safe | Enable fastest mirror plugin |
| `package_manager_dnf_color` | `"always"` | safe | Color output mode |
| `package_manager_dnf_defaultyes` | `true` | safe | Default yes to prompts |
| `package_manager_dnf_keepcache` | `false` | safe | Keep downloaded packages in cache |
| `package_manager_dnf_installonly_limit` | `3` | careful | Number of kernel versions to keep |

### Void Linux / xbps

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_xbps_cache_cleanup_enabled` | `true` | safe | Schedule weekly cache cleanup via cron |
| `package_manager_xbps_cache_cron_minute` | `"0"` | safe | Cron minute for cache cleanup |
| `package_manager_xbps_cache_cron_hour` | `"3"` | safe | Cron hour for cache cleanup |
| `package_manager_xbps_cache_cron_weekday` | `"0"` | safe | Cron weekday for cache cleanup (0 = Sunday) |

## Examples

**Minimal** — use all defaults (in `group_vars/all/package_manager.yml`):

```yaml
# No variables needed — defaults apply for all supported OS families
```

**Arch Linux power user** (in `host_vars/workstation.yml`):

```yaml
package_manager_pacman_parallel_downloads: 10
package_manager_pacman_multilib: true
package_manager_paccache_keep: 2
package_manager_makepkg_makeflags: "-j8"
```

**Disable paccache and makepkg** (in `group_vars/servers.yml`):

```yaml
package_manager_paccache_enabled: false
package_manager_makepkg_enabled: false
```

**External pacman cache on NFS** (in `host_vars/build-server.yml`):

```yaml
package_manager_pacman_external_cache: true
package_manager_pacman_cache_root: "/mnt/shared/pacman"
```

**Fedora — keep cache for offline installs** (in `group_vars/fedora.yml`):

```yaml
package_manager_dnf_keepcache: true
package_manager_dnf_installonly_limit: 5
```

## Cross-platform details

| Aspect | Arch Linux | Debian / Ubuntu | Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|--------|------------|--------|
| Package manager | pacman | apt | dnf | xbps | portage |
| Config path | `/etc/pacman.conf` | `/etc/apt/apt.conf.d/` | `/etc/dnf/dnf.conf` | `/etc/xbps.d/` | — (stub) |
| Service | `paccache.timer` | — | — | cron job | — |
| System user | `alpm` (cache ownership) | — | — | — | — |
| Init system | systemd | systemd | systemd | runit (cron) | — |
| Package index refresh | guarded pacman database refresh | `apt update` with cache validity guard | — | — | — |
| Cache cleanup | paccache timer | — (manual) | — (manual) | cron `xbps-remove -O` | — |

## Logs

| OS | Log file | Format | Rotation |
|----|----------|--------|----------|
| Arch Linux | `/var/log/pacman.log` | timestamped action log | logrotate (system) |
| Debian/Ubuntu | `/var/log/apt/history.log` | apt operation history | logrotate (system) |
| Debian/Ubuntu | `/var/log/dpkg.log` | dpkg operation log | logrotate (system) |
| Fedora | `/var/log/dnf.log` | dnf operation log | logrotate (system) |
| Void | xbps has no dedicated log | — | — |

This role does not create additional log files. It configures the package manager, which writes its own logs.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `pacman.conf` not deployed | Role skipped — check `ansible_facts['os_family']` matches `Archlinux` | Verify target is Arch Linux; check `package_manager_enabled: true` |
| paccache.timer not starting | Missing `pacman-contrib` package or non-systemd init | Ensure role ran fully; check `systemctl status paccache.timer` |
| `[multilib]` section missing | `package_manager_pacman_multilib: false` (default) | Set `package_manager_pacman_multilib: true` in vars |
| External cache dirs not created | `package_manager_pacman_external_cache: false` or `cache_root` empty | Set both `external_cache: true` and `cache_root` to mount path |
| apt package search still uses stale data | Package index refresh disabled or cache still inside valid time window | Enable `package_manager_refresh_package_indexes` or lower `package_manager_package_index_cache_valid_time` |
| dnf.conf overwritten by dnf update | dnf package update replaces config | Re-run role; config has backup enabled (`backup: true` on template) |
| Gentoo: "stub" message | Gentoo support not yet implemented | Expected behavior — portage configuration not yet automated |
| `alpm` group ownership skipped | `alpm` user doesn't exist (older pacman) | Expected — role checks `getent` before setting group ownership |

## Testing

Three Molecule scenarios:

| Scenario | Driver | Platforms | Coverage |
|----------|--------|-----------|----------|
| `default` | localhost | Local host | Smoke — syntax + converge + idempotence |
| `docker` | docker | `arch-base`, `ubuntu-base` | Config deployment, permissions, content assertions |
| `vagrant` | vagrant (libvirt) | `arch-vm`, `ubuntu-base` | Full platform test with systemd, services, idempotence |

```bash
# Docker test (fast, CI-friendly)
cd ansible/roles/package_manager
molecule test -s docker

# Vagrant KVM test (full platform)
molecule test -s vagrant

# Localhost smoke
molecule test -s default
```

**Success criteria:**
- All templates deployed with correct permissions (root:root 0644)
- Config contents match variable values in Molecule verification (slurp + assert)
- In-role package manager parsers/read-only probes succeed (`pacman-conf`, `apt-config`, `dnf --version`, `xbps-query`)
- paccache.timer enabled (Arch, systemd only)
- Idempotence check passes (no changes on second run)

**Common failures:**
- Docker: `pacman-contrib` install fails if package cache is stale → prepare.yml runs `update_cache`
- Arch scenarios: yay setup needs AUR/network/build dependencies because yay is part of the Arch package manager contract

## Tags

| Tag | Use case |
|-----|----------|
| `package_manager` | Whole role: validate, OS-specific configuration, verify, report |

Example: apply the package manager role:
```bash
task workstation -- --tags package_manager
```

## File map

| File | Purpose | When to edit |
|------|---------|-------------|
| `defaults/main.yml` | User-facing variables and supported OS list | Adding new variables or OS support |
| `vars/main.yml` | Internal OS-family mappings | Adding OS-specific internal values |
| `tasks/main.yml` | Orchestrator: validate → dispatch → verify → report | Changing role flow or adding phases |
| `tasks/validate.yml` | Preflight validation for OS support and input values | Adding new variables or validation rules |
| `tasks/archlinux/main.yml` | Arch dispatcher: pacman → cache refresh → paccache → makepkg → yay setup | Adding Arch-specific sub-tasks |
| `tasks/archlinux/pacman.yml` | pacman.conf template + external cache | Changing pacman config logic |
| `tasks/archlinux/cache.yml` | pacman package index refresh | Changing Arch package index refresh behavior |
| `tasks/archlinux/paccache.yml` | paccache dispatcher and systemd-only assert | Changing paccache support policy |
| `tasks/archlinux/systemd/paccache.yml` | paccache timer install + systemd drop-in | Changing systemd cache cleanup behavior |
| `tasks/archlinux/makepkg.yml` | makepkg drop-in config | Changing build optimization |
| `tasks/archlinux/yay.yml` | yay setup-only import | Changing Arch AUR helper setup |
| `tasks/archlinux/verify.yml` | Arch-specific in-role verification | Changing Arch verification logic |
| `tasks/debian/main.yml` | Debian/Ubuntu dispatcher: apt → dpkg → cache refresh | Adding Debian-specific sub-tasks |
| `tasks/debian/apt.yml` | apt parallel config template | Changing apt behavior |
| `tasks/debian/dpkg.yml` | dpkg options template | Changing dpkg conflict resolution |
| `tasks/debian/cache.yml` | apt package index refresh | Changing Debian package index refresh behavior |
| `tasks/debian/verify.yml` | Debian-specific in-role verification | Changing Debian verification logic |
| `tasks/redhat/main.yml` | RedHat/Fedora dispatcher: dnf | Adding RedHat-specific sub-tasks |
| `tasks/redhat/dnf.yml` | dnf.conf template | Changing dnf behavior |
| `tasks/redhat/verify.yml` | RedHat-specific in-role verification | Changing RedHat verification logic |
| `tasks/void/main.yml` | Void dispatcher: xbps → cache | Adding Void-specific sub-tasks |
| `tasks/void/xbps.yml` | xbps config template | Changing xbps behavior |
| `tasks/void/cache.yml` | xbps cache cleanup cron | Changing cleanup schedule |
| `tasks/void/verify.yml` | Void-specific in-role verification | Changing Void verification logic |
| `tasks/gentoo/main.yml` | Gentoo stub | Implementing portage support |
| `tasks/gentoo/verify.yml` | Gentoo verification stub | Implementing Gentoo verification |
| `tasks/verify.yml` | In-role verification dispatcher | Adding platform verify dispatch |
| `handlers/main.yml` | Empty by design; explicit state transitions live in task files | Adding new handlers |
| `meta/main.yml` | Galaxy metadata | Changing role metadata |
| `templates/archlinux/pacman.conf.j2` | pacman.conf template | Changing pacman config format |
| `templates/archlinux/makepkg.conf.j2` | makepkg drop-in template | Changing makepkg format |
| `templates/debian/10-parallel.conf.j2` | apt parallel config template | Changing apt config format |
| `templates/debian/20-dpkg.conf.j2` | dpkg options template | Changing dpkg config format |
| `templates/redhat/dnf.conf.j2` | dnf.conf template | Changing dnf config format |
| `templates/void/xbps.conf.j2` | xbps config template | Changing xbps config format |
| `molecule/shared/converge.yml` | Shared converge playbook and OS-specific edge-case dispatch | Changing test converge flow |
| `molecule/shared/converge/archlinux.yml` | Arch-specific converge edge cases | Changing Arch test inputs |
| `molecule/shared/verify.yml` | Shared verification dispatcher | Adding test platform dispatch |
| `molecule/shared/verify/<os>.yml` | OS-specific Molecule verification | Adding test assertions |
| `molecule/docker/molecule.yml` | Docker scenario config | Changing Docker test setup |
| `molecule/docker/prepare.yml` | Docker test preparation | Changing Docker pre-test setup |
| `molecule/vagrant/molecule.yml` | Vagrant scenario config | Changing Vagrant test setup |
| `molecule/vagrant/prepare.yml` | Vagrant test preparation | Changing Vagrant pre-test setup |
| `molecule/default/molecule.yml` | Localhost scenario config | Changing localhost test setup |

## Dependencies

- `yay` — AUR helper setup (builder user + binary), imported in setup-only mode on Arch
- `common` — Structured logging (`report_phase.yml`, `report_render.yml`)

`reflector` is not orchestrated by this role. Workstation playbooks should keep
`reflector` before `package_manager` when mirror freshness is required before
later Arch package installation.

These are local project roles, not Galaxy dependencies. The role intentionally
does not declare `requirements.yml`; execution must provide the bootstrap roles
tree through `ANSIBLE_ROLES_PATH`, as the project Molecule and Taskfile paths do.

## License

MIT
