# Mirror Selection Module

Unified mirror selection system for package managers across all supported Linux distributions.

Automatically selects optimal mirrors for:
- **Arch Linux** (pacman via reflector)
- **Ubuntu/Debian** (apt)
- **Fedora** (dnf)
- **Gentoo** (emerge/portage)

Supports **5 countries**: Kazakhstan (KZ), Russia (RU), Germany (DE), France (FR), Netherlands (NL).

## Quick Start

```bash
# Auto-detect distro and use default mirrors (Kazakhstan by default)
sudo ./scripts/bootstrap/mirror/mirror-manager.sh

# Select mirrors for a specific country
sudo ./scripts/bootstrap/mirror/mirror-manager.sh --country RU

# Germany with validation
sudo ./scripts/bootstrap/mirror/mirror-manager.sh --country DE --validate

# Use with bootstrap (Kazakhstan by default)
./bootstrap.sh --install
```

## Architecture

```
mirror-manager.sh      ← Main entry point, CLI parsing, distro routing
    ↓
mirror-common.sh       ← Shared utilities (logging, backup, validation)
    ├── arch.sh        ← Arch Linux: reflector-based mirror selection
    ├── ubuntu.sh      ← Ubuntu/Debian: APT mirror selection
    ├── fedora.sh      ← Fedora: DNF repository configuration
    └── gentoo.sh      ← Gentoo: Portage mirror selection
```

## Supported Countries

| Code | Country | Arch | Ubuntu | Fedora | Gentoo |
|------|---------|------|--------|--------|--------|
| KZ | Kazakhstan | ✓ (Russian mirrors) | ru.archive | mirror.ru | mirror.rol.ru |
| RU | Russia | ✓ | ru.archive | mirror.ru | mirror.rol.ru |
| DE | Germany | ✓ | de.archive | mirror.de | mirror.eu.oneandone |
| FR | France | ✓ | fr.archive | mirror.fr | mirror.switch.ch |
| NL | Netherlands | ✓ (defaults) | archive.ubuntu | default | gentoo.osuosl.org |

## CLI Options

```bash
mirror-manager.sh [OPTIONS]

Options:
  --distro DISTRO          Force distro: arch, ubuntu, fedora, gentoo
  --protocol PROTO         Protocol: https (default), http
  --latest N               Latest mirrors (default: 5, Arch only)
  --age N                  Max mirror age hours (default: 12, Arch only)
  --sort-by METHOD         Sort: rate (default), age, location (Arch only)
  --country CODE           Country: KZ (default), RU, DE, FR, NL
  --validate               Test mirrors before using (recommended)
  --debug                  Show debug output
  -h, --help               Show help
```

## Usage Examples

### Basic Usage

```bash
# Auto-detect distro (uses Kazakhstan mirrors by default)
sudo ./mirror-manager.sh

# Specific country
sudo ./mirror-manager.sh --country RU

# Country with validation
sudo ./mirror-manager.sh --country DE --validate

# Debug mode
sudo ./mirror-manager.sh --country FR --debug
```

### Advanced (Arch Linux)

```bash
# 10 mirrors, 24-hour age limit
sudo ./mirror-manager.sh --country RU --latest 10 --age 24

# Sort by age instead of speed
sudo ./mirror-manager.sh --country DE --sort-by age

# HTTP protocol (fallback)
sudo ./mirror-manager.sh --protocol http
```

### With Bootstrap

```bash
# Use Kazakhstan mirrors (default)
./bootstrap.sh --install

# Use different country during bootstrap
MIRROR_COUNTRY=DE ./bootstrap.sh --install

# Use specific options
export MIRROR_OPTS="--country RU --validate"
./bootstrap.sh --install

# Multiple options
MIRROR_COUNTRY=FR MIRROR_VALIDATE=1 ./bootstrap.sh --install
```

### With Environment Variables

```bash
export MIRROR_DISTRO=arch
export MIRROR_COUNTRY=DE
export MIRROR_LATEST=10
export MIRROR_VALIDATE=1
sudo -E ./mirror-manager.sh
```

## Features by Distribution

### Arch Linux (`arch.sh`)
- Dynamic mirror selection via **reflector**
- Automatic reflector installation if missing
- Configurable protocol, count, age, sorting
- Country-based filtering (maps KZ → RU for reflector compatibility)
- Optional validation with retries
- **Three-tier fallback**:
  1. Primary: Strict parameters with country filter
  2. Secondary: Relaxed parameters (no country filter, older age, more mirrors)
  3. Tertiary: Aggressive fallback (50+ mirrors, 48-hour age, HTTPS only)
- Timestamped mirrorlist backups
- Auto pacman DB refresh

### Ubuntu/Debian (`ubuntu.sh`)
- Mirror selection from Canonical network
- Country code to mirror mapping
- Dynamic sources.list generation
- Optional mirror validation
- Timestamped backups
- Auto apt cache refresh

### Fedora (`fedora.sh`)
- DNF repository configuration
- Country-based mirror selection
- Generates fedora.repo and fedora-updates.repo
- Optional mirror validation
- Timestamped backups
- Auto dnf cache refresh

### Gentoo (`gentoo.sh`)
- Portage make.conf configuration
- Country-based GENTOO_MIRRORS setting
- Optional mirror validation with fallback
- Timestamped backups
- Auto portage tree sync

## Common Features

- **Automatic sudo escalation**: Auto-rerun with sudo if needed
- **Timestamped backups**: All changes backed up as `*.bak.YYYYMMDDHHMMSS`
- **4-level logging**: Info, warn, error, debug
- **Mirror validation**: Optional accessibility checks
- **Fallback logic**: Graceful degradation on failure
- **Easy recovery**: Simple restore from backup

## Integration with Bootstrap

Automatically called during Phase 1 of `bootstrap.sh`:

```bash
if [ "$DO_INSTALL" = 1 ]; then
  "$SCRIPT_DIR/mirror/mirror-manager.sh" ${MIRROR_OPTS:-}
  "$INSTALL_SCRIPT"
fi
```

Pass options via environment:
```bash
export MIRROR_OPTS="--country DE --validate"
./bootstrap.sh --install
```

## Backup and Recovery

All changes are backed up with timestamps:

```bash
# Arch
/etc/pacman.d/mirrorlist.bak.YYYYMMDDHHMMSS

# Ubuntu
/etc/apt/sources.list.bak.YYYYMMDDHHMMSS

# Fedora
/etc/yum.repos.d/fedora.repo.bak.YYYYMMDDHHMMSS

# Gentoo
/etc/portage/make.conf.bak.YYYYMMDDHHMMSS
```

Restore from backup:

```bash
sudo cp /path/to/config.bak.YYYYMMDDHHMMSS /path/to/config

# Refresh package cache
sudo pacman -Syy        # Arch
sudo apt update         # Ubuntu
sudo dnf makecache      # Fedora
sudo emerge --sync      # Gentoo
```

## Troubleshooting

### Mirror Selection Fails

```bash
# Check internet connectivity
ping 8.8.8.8

# Try with more mirrors (Arch)
sudo ./mirror-manager.sh --latest 20

# Try without country filter
sudo ./mirror-manager.sh --country ""

# Try HTTP fallback
sudo ./mirror-manager.sh --protocol http
```

### Validation Issues

```bash
# Skip validation
sudo ./mirror-manager.sh --country RU

# Manual validation
curl -I https://ru.archive.ubuntu.com/ubuntu/

# Use different country
sudo ./mirror-manager.sh --country DE
```

### Cannot Install Packages After Mirror Setup

```bash
# Refresh package database
sudo pacman -Syy        # Arch
sudo apt update         # Ubuntu
sudo dnf makecache      # Fedora
sudo emerge --sync      # Gentoo

# Try installing
sudo pacman -S vim
```

### Restore Previous Configuration

```bash
# List available backups
ls -la /etc/pacman.d/mirrorlist.bak.*

# Restore most recent
LATEST=$(ls -t /etc/pacman.d/mirrorlist.bak.* | head -1)
sudo cp "$LATEST" /etc/pacman.d/mirrorlist

# Refresh
sudo pacman -Syy
```

## Country-Specific Examples

### Kazakhstan (KZ)
Uses Russian mirrors for geographic proximity:
```bash
sudo ./mirror-manager.sh --country KZ
```

### Russia (RU)
Russian mirrors with country filter on Arch:
```bash
sudo ./mirror-manager.sh --country RU --validate
```

### Germany (DE)
German mirrors:
```bash
sudo ./mirror-manager.sh --country DE --latest 10 --age 24
```

### France (FR)
French mirrors:
```bash
sudo ./mirror-manager.sh --country FR --sort-by age
```

### Netherlands (NL)
International default mirrors:
```bash
sudo ./mirror-manager.sh --country NL
```

## Performance Considerations

- **Reflector scan** (Arch): 10-30 seconds for full mirror list
- **Mirror validation**: Adds ~5-10 seconds per mirror check
- **First run**: May take longer for initial package DB sync
- **Network dependent**: Performance varies by connection quality

## Files

| File | Purpose | Lines |
|------|---------|-------|
| `mirror-manager.sh` | Main orchestrator | ~80 |
| `mirror-common.sh` | Shared utilities | ~189 |
| `arch.sh` | Arch implementation | ~90 |
| `ubuntu.sh` | Ubuntu implementation | ~80 |
| `fedora.sh` | Fedora implementation | ~120 |
| `gentoo.sh` | Gentoo implementation | ~100 |

## Adding New Countries

To add support for new countries:

1. Update `country_name_from_code()` in `mirror-common.sh`
2. Add country mapping to `COUNTRY_MIRRORS` in each distro script
3. Test: `sudo ./mirror-manager.sh --country XX --debug`

## Security Notes

- ✓ All operations require root/sudo
- ✓ HTTPS preferred for security
- ✓ Backups before any changes
- ✓ Package signatures verified where supported
- ✓ No untrusted mirrors used

## Testing

```bash
# Test distro detection
sudo ./mirror-manager.sh --debug

# Test country selection
sudo ./mirror-manager.sh --country RU --validate

# Test fallback (Arch)
sudo ./mirror-manager.sh --latest 2 --age 2

# Test package installation
sudo ./mirror-manager.sh --country DE
sudo pacman -S vim
```

## Support

For issues or feature requests, check:
- Mirror logs: `scripts/bootstrap/log/install.log`
- Distro-specific config files (paths listed above)
- Bootstrap log: `scripts/bootstrap/log/bootstrap.log`

## See Also

- `bootstrap.sh` - Main bootstrap orchestrator
- `scripts/bootstrap/packager/` - Package manager integration
- `/etc/os-release` - Distro detection source

## See Also

- [Bootstrap Documentation](../README.md)
- [Reflector Documentation](https://wiki.archlinux.org/title/Reflector)
- [APT Mirror Selection](https://help.ubuntu.com/community/Repositories/CommandLine)
- [DNF Configuration](https://docs.fedoraproject.org/en-US/fedora/latest/system-administrators-guide/configuring_dnf/)
- [Portage Mirror Configuration](https://wiki.gentoo.org/wiki/Portage/Mirrors)
