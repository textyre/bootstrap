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
- [x] Optionally imports reflector and runs yay setup-only on Arch (tagged `molecule-notest`)
- [x] Validates OS is in supported list before any configuration
- [x] Runs in-role verification after deployment (verify.yml)
- [x] Supports external pacman cache on shared storage

## Execution flow

1. **Preflight assert** (`tasks/main.yml`) — fail fast if OS family is not in `_package_manager_supported_os`
2. **OS dispatch** (`tasks/main.yml`) — include `tasks/<os_family>.yml` based on `ansible_facts['os_family']`
3. **Archlinux path** (`tasks/archlinux.yml`):
   1. Configure pacman → `tasks/archlinux/pacman.yml` (template `/etc/pacman.conf`, optional external cache)
   2. Configure paccache → `tasks/archlinux/paccache.yml` (install `pacman-contrib`, systemd timer drop-in)
   3. Configure makepkg → `tasks/archlinux/makepkg.yml` (template drop-in to `/etc/makepkg.conf.d/`)
   4. Import reflector role (tagged `molecule-notest`)
   5. Import yay role in setup-only mode (builder user + binary, tagged `molecule-notest`)
4. **Debian path** (`tasks/debian.yml`):
   1. Configure apt → `tasks/apt/apt.yml` (template to `/etc/apt/apt.conf.d/10-ansible-parallel.conf`)
   2. Configure dpkg → `tasks/apt/dpkg.yml` (template to `/etc/apt/apt.conf.d/20-ansible-dpkg.conf`)
5. **RedHat path** (`tasks/redhat.yml`):
   1. Configure dnf → `tasks/fedora/dnf.yml` (template `/etc/dnf/dnf.conf`)
6. **Void path** (`tasks/void.yml`):
   1. Configure xbps → `tasks/void/xbps.yml` (template to `/etc/xbps.d/ansible.conf`)
   2. Configure cache cron → `tasks/void/cache.yml` (weekly `xbps-remove -O`)
7. **Gentoo path** (`tasks/gentoo.yml`) — stub, logs a message
8. **In-role verification** (`tasks/verify.yml`) — slurp deployed configs, assert expected values
9. **Handler**: `Reload systemd daemon` (guarded by `service_mgr == 'systemd'`)
10. **Structured logging** — `report_phase` + `report_render` via common role

## Variables

### Global

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_enabled` | `true` | safe | Master toggle — set `false` to skip the entire role |

### Arch Linux / pacman

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `package_manager_pacman_parallel_downloads` | `5` | safe | Number of parallel downloads |
| `package_manager_pacman_color` | `true` | safe | Enable color output |
| `package_manager_pacman_verbose_pkg_lists` | `true` | safe | Verbose package lists |
| `package_manager_pacman_check_space` | `true` | safe | Check available disk space before install |
| `package_manager_pacman_siglevel` | `"Required DatabaseOptional"` | internal | Signature verification level — supply chain risk if changed |
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
| `package_manager_makepkg_pkgext` | `".pkg.tar.zst"` | safe | Package archive format |

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
| apt config not applied after role | Template deployed but apt not refreshed | Run `apt-get update` — role deploys config, doesn't trigger cache refresh |
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
- Config contents match variable values (slurp + assert)
- paccache.timer enabled (Arch, systemd only)
- Idempotence check passes (no changes on second run)

**Common failures:**
- Docker: `pacman-contrib` install fails if package cache is stale → prepare.yml runs `update_cache`
- Vagrant: reflector/yay setup tasks attempt network access → tagged `molecule-notest`, skipped via `skip-tags`

## Tags

| Tag | Use case |
|-----|----------|
| `packages` | All package manager tasks |
| `package-manager` | Alias for `packages` |
| `pacman` | Arch Linux pacman.conf only |
| `paccache` | Arch Linux paccache timer only |
| `makepkg` | Arch Linux makepkg.conf only |
| `apt` | Debian/Ubuntu apt config only |
| `dnf` | Fedora dnf.conf only |
| `xbps` | Void Linux xbps config only |
| `xbps-cache` | Void Linux cache cron only |
| `portage` | Gentoo stub |
| `pacman-cache` | Pacman external cache setup |
| `mirrors` | Reflector mirror configuration (molecule-notest) |
| `aur` | Yay helper setup only (molecule-notest) |
| `report` | Structured logging phase reports |
| `molecule-notest` | Tasks skipped in molecule tests |

Example: apply only pacman config without paccache/makepkg:
```bash
ansible-playbook playbooks/workstation.yml --tags pacman
```

## File map

| File | Purpose | When to edit |
|------|---------|-------------|
| `defaults/main.yml` | User-facing variables and supported OS list | Adding new variables or OS support |
| `vars/main.yml` | Internal OS-family mappings | Adding OS-specific internal values |
| `tasks/main.yml` | Orchestrator: validate → dispatch → verify → report | Changing role flow or adding phases |
| `tasks/archlinux.yml` | Arch dispatcher: pacman → paccache → makepkg → reflector → yay setup | Adding Arch-specific sub-tasks |
| `tasks/archlinux/pacman.yml` | pacman.conf template + external cache | Changing pacman config logic |
| `tasks/archlinux/paccache.yml` | paccache timer install + drop-in | Changing cache cleanup behavior |
| `tasks/archlinux/makepkg.yml` | makepkg drop-in config | Changing build optimization |
| `tasks/debian.yml` | Debian/Ubuntu dispatcher: apt → dpkg | Adding Debian-specific sub-tasks |
| `tasks/apt/apt.yml` | apt parallel config template | Changing apt behavior |
| `tasks/apt/dpkg.yml` | dpkg options template | Changing dpkg conflict resolution |
| `tasks/redhat.yml` | RedHat/Fedora dispatcher: dnf | Adding RedHat-specific sub-tasks |
| `tasks/fedora/dnf.yml` | dnf.conf template | Changing dnf behavior |
| `tasks/void.yml` | Void dispatcher: xbps → cache | Adding Void-specific sub-tasks |
| `tasks/void/xbps.yml` | xbps config template | Changing xbps behavior |
| `tasks/void/cache.yml` | xbps cache cleanup cron | Changing cleanup schedule |
| `tasks/gentoo.yml` | Gentoo stub | Implementing portage support |
| `tasks/verify.yml` | In-role verification | Adding post-deploy checks |
| `handlers/main.yml` | systemd daemon-reload | Adding new handlers |
| `meta/main.yml` | Galaxy metadata | Changing role metadata |
| `requirements.yml` | Role dependencies (reflector, yay) | Adding role dependencies |
| `templates/archlinux/pacman.conf.j2` | pacman.conf template | Changing pacman config format |
| `templates/archlinux/makepkg.conf.j2` | makepkg drop-in template | Changing makepkg format |
| `templates/apt/10-parallel.conf.j2` | apt parallel config template | Changing apt config format |
| `templates/apt/20-dpkg.conf.j2` | dpkg options template | Changing dpkg config format |
| `templates/fedora/dnf.conf.j2` | dnf.conf template | Changing dnf config format |
| `templates/void/xbps.conf.j2` | xbps config template | Changing xbps config format |
| `molecule/shared/converge.yml` | Shared converge playbook | Changing test converge flow |
| `molecule/shared/verify.yml` | Shared verification playbook | Adding test assertions |
| `molecule/docker/molecule.yml` | Docker scenario config | Changing Docker test setup |
| `molecule/docker/prepare.yml` | Docker test preparation | Changing Docker pre-test setup |
| `molecule/vagrant/molecule.yml` | Vagrant scenario config | Changing Vagrant test setup |
| `molecule/vagrant/prepare.yml` | Vagrant test preparation | Changing Vagrant pre-test setup |
| `molecule/default/molecule.yml` | Localhost scenario config | Changing localhost test setup |

## Dependencies

- `reflector` — Arch Linux mirror configuration (imported with `molecule-notest` tag)
- `yay` — AUR helper setup (builder user + binary, imported with `molecule-notest` tag)
- `common` — Structured logging (`report_phase.yml`, `report_render.yml`)

## License

MIT
