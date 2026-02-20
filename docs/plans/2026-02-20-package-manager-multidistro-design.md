# package_manager: Multi-Distro + Feature Split Design

**Date:** 2026-02-20

## Goal

Расширить роль `ansible/roles/package_manager`:
1. Добавить поддержку Ubuntu, Fedora, Void Linux с полным паритетом фич
2. Разбить `archlinux.yml` на файлы по фиче (pacman / paccache / makepkg)

## Architecture

**Dispatch** меняется с `os_family` на `ansible_distribution` — это единственный способ разделить Debian и Ubuntu (оба имеют `os_family == 'Debian'`).

Каждый дистрибутив получает dispatcher-файл (`<distro>.yml`) и поддиректорию с файлами по одной фиче каждый.

Void Linux использует runit вместо systemd — реализация cache cleanup идёт через `ansible.builtin.cron` или runit sv, не через `ansible.builtin.systemd`.

## File Structure

```
tasks/
├── main.yml                     # dispatch по ansible_distribution
├── archlinux.yml                # include archlinux/{pacman,paccache,makepkg}
├── archlinux/
│   ├── pacman.yml               # Deploy pacman.conf.j2, external cache
│   ├── paccache.yml             # pacman-contrib + systemd timer drop-in
│   └── makepkg.yml              # /etc/makepkg.conf.d/ansible.conf
├── debian.yml                   # include debian/{apt,dpkg}
├── debian/
│   ├── apt.yml                  # apt.conf.d/10-ansible-parallel.conf
│   └── dpkg.yml                 # apt.conf.d/20-ansible-dpkg.conf
├── ubuntu.yml                   # include ubuntu/{apt,dpkg}
├── ubuntu/
│   ├── apt.yml                  # те же настройки + ubuntu-специфика
│   └── dpkg.yml
├── fedora.yml                   # include fedora/{dnf,cache}
├── fedora/
│   ├── dnf.yml                  # /etc/dnf/dnf.conf template
│   └── cache.yml                # installonly_limit уже в dnf.conf
├── void.yml                     # include void/{xbps,cache}
└── void/
    ├── xbps.yml                 # /etc/xbps.d/ansible.conf
    └── cache.yml                # cron: xbps-remove -O

templates/
├── archlinux/                   # уже есть
│   ├── pacman.conf.j2
│   └── makepkg.conf.j2
├── debian/                      # уже есть
│   ├── 10-parallel.conf.j2
│   └── 20-dpkg.conf.j2
├── ubuntu/
│   ├── 10-parallel.conf.j2
│   └── 20-dpkg.conf.j2
├── fedora/
│   └── dnf.conf.j2
└── void/
    └── xbps.conf.j2
```

## Feature Parity

| Фича | Arch | Debian | Ubuntu | Fedora | Void |
|------|------|--------|--------|--------|------|
| Parallel downloads | `ParallelDownloads` в pacman.conf | `Acquire::Queue-Mode` | `Acquire::Queue-Mode` | `max_parallel_downloads` в dnf.conf | `maxjobs` в xbps.conf |
| Cache cleanup | paccache systemd timer | — (installonly не применимо) | — | `installonly_limit` в dnf.conf | cron: `xbps-remove -O` |
| Non-interactive | `SigLevel` в pacman.conf | `Dpkg::Options` | `Dpkg::Options` | `defaultyes=True` в dnf.conf | — |
| Build optimization | makepkg.conf.d | — | — | — | — |
| Color/verbose output | `Color`, `VerbosePkgLists` | — | — | `color=always` в dnf.conf | — |

## Key Variables (additions to defaults/main.yml)

```yaml
# Fedora / dnf
pkgmgr_dnf_parallel_downloads: 5
pkgmgr_dnf_fastestmirror: true
pkgmgr_dnf_color: "always"
pkgmgr_dnf_defaultyes: true
pkgmgr_dnf_keepcache: false
pkgmgr_dnf_installonly_limit: 3   # аналог paccache_keep

# Void / xbps
pkgmgr_xbps_maxjobs: 5
pkgmgr_xbps_cache_cleanup_enabled: true
pkgmgr_xbps_cache_cron_schedule: "0 3 * * 0"  # воскресенье 03:00

# Ubuntu (apt, те же переменные что и Debian)
# pkgmgr_apt_* уже определены
```

## Dispatch Change (main.yml)

```yaml
# defaults/main.yml
_pkgmgr_supported_distributions:
  - Archlinux
  - Debian
  - Ubuntu
  - Fedora
  - Void

# tasks/main.yml
- name: Include distribution-specific package manager configuration
  ansible.builtin.include_tasks: "{{ ansible_distribution | lower }}.yml"
  when: ansible_distribution in _pkgmgr_supported_distributions
  tags: ['packages', 'package-manager']
```

## Init Agnosticism

- **Arch, Debian, Ubuntu, Fedora** — systemd (или без timer для Debian/Ubuntu)
- **Void** — runit по умолчанию; cache cleanup через `ansible.builtin.cron` (cron доступен на Void)

## Approved

Подход A одобрен 2026-02-20.
