# package_manager

Configures the system package manager for Arch Linux, Debian, Ubuntu, Fedora, and Void Linux.

Manages package manager settings via Jinja2 templates — no `lineinfile` patching.
Dispatches by `ansible_distribution`, so Debian and Ubuntu get independent configs despite sharing the same apt base.

## Requirements

- Ansible 2.15+
- `become: true` (root access required)
- Arch Linux: `pacman-contrib` installed (for paccache timer) — installed automatically by the role

## Supported distributions

| Distribution | Package manager | Config path |
|---|---|---|
| Arch Linux | pacman | `/etc/pacman.conf`, `/etc/makepkg.conf.d/ansible.conf` |
| Debian | apt / dpkg | `/etc/apt/apt.conf.d/` |
| Ubuntu | apt / dpkg | `/etc/apt/apt.conf.d/` |
| Fedora | dnf | `/etc/dnf/dnf.conf` |
| Void Linux | xbps | `/etc/xbps.d/ansible.conf` |

## Role variables

### Arch Linux / pacman

| Variable | Default | Description |
|---|---|---|
| `package_manager_pacman_parallel_downloads` | `5` | Number of parallel downloads |
| `package_manager_pacman_color` | `true` | Enable color output |
| `package_manager_pacman_verbose_pkg_lists` | `true` | Verbose package lists |
| `package_manager_pacman_check_space` | `true` | Check available disk space before install |
| `package_manager_pacman_siglevel` | `"Required DatabaseOptional"` | Signature verification level |
| `package_manager_pacman_multilib` | `false` | Enable [multilib] repository |
| `package_manager_pacman_external_cache` | `false` | Use external shared cache |
| `package_manager_pacman_cache_root` | `""` | Path to external cache root (requires `package_manager_pacman_external_cache: true`) |

### Arch Linux / paccache (cache cleanup)

| Variable | Default | Description |
|---|---|---|
| `package_manager_paccache_enabled` | `true` | Enable paccache.timer (weekly cache cleanup) |
| `package_manager_paccache_keep` | `3` | Number of package versions to keep in cache |

### Arch Linux / makepkg (AUR build optimization)

| Variable | Default | Description |
|---|---|---|
| `package_manager_makepkg_enabled` | `true` | Deploy makepkg drop-in config |
| `package_manager_makepkg_makeflags` | `"-j<nproc>"` | Parallel make jobs (defaults to CPU count) |
| `package_manager_makepkg_pkgext` | `".pkg.tar.zst"` | Package archive format |

### Debian / Ubuntu / apt

| Variable | Default | Description |
|---|---|---|
| `package_manager_apt_parallel_queue_mode` | `"host"` | Parallel download queue mode |
| `package_manager_apt_retries` | `3` | Number of download retries |
| `package_manager_apt_dpkg_force_confdef` | `true` | Use default on config file conflict |
| `package_manager_apt_dpkg_force_confold` | `true` | Keep old config file on conflict |

### Fedora / dnf

| Variable | Default | Description |
|---|---|---|
| `package_manager_dnf_parallel_downloads` | `5` | Number of parallel downloads |
| `package_manager_dnf_fastestmirror` | `true` | Enable fastest mirror plugin |
| `package_manager_dnf_color` | `"always"` | Color output mode |
| `package_manager_dnf_defaultyes` | `true` | Default yes to prompts |
| `package_manager_dnf_keepcache` | `false` | Keep downloaded packages in cache |
| `package_manager_dnf_installonly_limit` | `3` | Number of kernel versions to keep |

### Void Linux / xbps

| Variable | Default | Description |
|---|---|---|
| `package_manager_xbps_cache_cleanup_enabled` | `true` | Schedule weekly cache cleanup via cron |
| `package_manager_xbps_cache_cron_minute` | `"0"` | Cron minute for cache cleanup |
| `package_manager_xbps_cache_cron_hour` | `"3"` | Cron hour for cache cleanup |
| `package_manager_xbps_cache_cron_weekday` | `"0"` | Cron weekday for cache cleanup (0 = Sunday) |

## Dependencies

None.

## Example playbook

```yaml
- name: Configure package manager
  hosts: workstations
  become: true
  roles:
    - role: package_manager
```

With custom variables:

```yaml
- name: Configure package manager
  hosts: archlinux_hosts
  become: true
  roles:
    - role: package_manager
      vars:
        package_manager_pacman_parallel_downloads: 10
        package_manager_pacman_multilib: true
        package_manager_paccache_keep: 2
```

## License

MIT
