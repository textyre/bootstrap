# Bootstrap Module

Automated bootstrap and configuration system for containerized Linux environments with multi-distro support.

## Overview

The bootstrap module provides a complete system for:
1. **Mirror Selection** - Dynamic package mirror selection for all distros
2. **Package Installation** - Distro-aware package manager integration
3. **Environment Deployment** - GUI-based configuration and desktop environment setup

## Architecture

```
bootstrap.sh (main orchestrator)
├── PHASE 0: Externals initialization (optional)
├── PHASE 1: Install (mirror selection + package installation)
│   ├── mirror-manager.sh (unified mirror selection)
│   │   ├── mirror-common.sh (shared utilities)
│   │   └── [arch|ubuntu|fedora|gentoo].sh (distro-specific)
│   └── packager/ (package installation)
│       ├── packager.sh (distro router)
│       └── [arch|ubuntu|fedora|gentoo].sh (distro implementations)
└── PHASE 2: Deploy (environment configuration)
    └── gui/ (desktop environment setup)
        ├── launch.sh (entry point)
        └── display/ (display configuration)
```

## Components

### 1. Mirror Selection Module (`mirror/`)

**Purpose**: Dynamically select optimal package mirrors for all supported Linux distributions.

**Supported Distros**: Arch, Ubuntu/Debian, Fedora, Gentoo

**Features**:
- Country-based mirror selection
- Mirror validation and accessibility checks
- Automatic fallback strategies
- Timestamped configuration backups
- CLI customization via flags or environment variables

**Documentation**: [mirror/README.md](mirror/README.md)

**Quick Usage**:
```bash
# Auto-detect distro and select mirrors with defaults
sudo ./scripts/bootstrap/mirror/mirror-manager.sh

# Select German mirrors with validation
sudo ./scripts/bootstrap/mirror/mirror-manager.sh --country DE --validate

# Integration with bootstrap
./bootstrap.sh --install
```

### 2. Package Manager Integration (`packager/`)

**Purpose**: Unified package installation interface across all supported distros.

**Supported Distros**: Arch (pacman), Ubuntu/Debian (apt), Fedora (dnf), Gentoo (emerge)

**Features**:
- Automatic distro detection
- Externals root support (chroot/container environments)
- Common interface (`pm_update`, `pm_install`, `pm_prepare_root`)

**Package Lists**: Configured in `packager/packages.sh`

### 3. GUI Deployment (`gui/`)

**Purpose**: Interactive desktop environment and display configuration.

**Features**:
- Display server detection (X11/Wayland)
- Window manager configuration (i3, etc.)
- Display setup via multiple strategies
- Python-based GUI launcher

### 4. External Roots Support (`externals/`)

**Purpose**: Initialize and manage externally mounted filesystem roots.

**Use Cases**: Chroot environments, container rootfs, VM instances

## Usage

### Basic Bootstrap Flow

```bash
# 1. Make scripts executable
chmod +x scripts/bootstrap/**/*.sh scripts/bootstrap/mirror/*.sh

# 2. Run bootstrap (interactive)
./scripts/bootstrap/bootstrap.sh

# 3. Or run specific phases
./scripts/bootstrap/bootstrap.sh --install   # Only mirror + packages
./scripts/bootstrap/bootstrap.sh --deploy    # Only GUI configuration
```

### Advanced Usage

#### Mirror Customization

```bash
# Run bootstrap with custom mirror parameters
MIRROR_OPTS="--country DE --validate" ./scripts/bootstrap/bootstrap.sh --install

# Or direct mirror manager call
sudo ./scripts/bootstrap/mirror/mirror-manager.sh \
  --distro arch \
  --country RU \
  --latest 10 \
  --validate
```

#### Package Manager Operations

```bash
# Manual package operations (from packager directory)
./scripts/bootstrap/packager/packager.sh update
./scripts/bootstrap/packager/packager.sh install vim git

# With externals root
./scripts/bootstrap/packager/packager.sh update /path/to/root
./scripts/bootstrap/packager/packager.sh install /path/to/root vim
```

#### Environment Customization

```bash
# Run deploy phase with custom display setup
./scripts/bootstrap/bootstrap.sh --deploy

# Or run GUI launcher directly
./scripts/bootstrap/gui/launch.sh
```

## Configuration

### Package Lists

Edit `packager/packages.sh` to customize installed packages:

```bash
packages=(
  base
  base-devel
  linux
  vim
  git
  # ... add your packages
)
```

### Mirror Preferences

Set environment variables before running bootstrap:

```bash
export MIRROR_COUNTRY=DE           # Germany
export MIRROR_VALIDATE=1           # Validate mirrors
export MIRROR_LATEST=10            # Use 10 mirrors (Arch)
export MIRROR_PROTOCOL=https       # Use HTTPS
export MIRROR_DEBUG=1              # Debug logging
```

### Display Configuration

Configure display settings through the GUI launcher or by editing:
- `gui/display/` - Display strategy implementations
- `gui/launch.sh` - Launcher configuration

## Phases

### PHASE 0: Externals Initialization (Optional)

Initializes an externally mounted root filesystem (e.g., for chroot/container environments).

```bash
./bootstrap.sh --externals /path/to/root
```

### PHASE 1: Install

1. Detects system distro
2. Selects optimal package mirrors (`mirror-manager.sh`)
3. Updates package manager database
4. Installs configured packages

```bash
./bootstrap.sh --install
```

**What happens**:
```
Mirror selection (country-based, with fallback)
    ↓
Package database update
    ↓
Package installation
    ↓
Cleanup (unmount pseudo-filesystems for chroot)
```

### PHASE 2: Deploy

Configures desktop environment and display settings through an interactive GUI.

```bash
./bootstrap.sh --deploy
```

**What happens**:
```
Python environment check
    ↓
GUI launcher start
    ↓
Display configuration
    ↓
Environment setup
```

## Error Handling

### Mirror Selection Fails

The system implements multi-level fallback:

1. **Primary**: Try with specified parameters
2. **Fallback 1**: Relax constraints (older mirrors, more mirrors)
3. **Fallback 2**: Use regional defaults
4. **Fallback 3**: Restore from backup

Each step logs errors; check logs with:

```bash
tail -f ./scripts/bootstrap/log/bootstrap.log
```

### Package Installation Fails

Check package availability for your distro:

```bash
# Arch
pacman -S vim

# Ubuntu
apt install vim

# Fedora
dnf install vim

# Gentoo
emerge vim
```

### GUI Configuration Fails

The deploy phase requires Python 3:

```bash
# Arch
sudo pacman -S python

# Ubuntu
sudo apt install python3

# Fedora
sudo dnf install python3

# Gentoo
sudo emerge python
```

## Logs

Bootstrap logs are written to:

```
scripts/bootstrap/log/
├── bootstrap.log      # Main bootstrap log
├── install.log        # Package installation details
└── gui.log            # GUI deployment details
```

View logs:

```bash
# Real-time monitoring
tail -f scripts/bootstrap/log/bootstrap.log

# Full log content
cat scripts/bootstrap/log/bootstrap.log
```

## Troubleshooting

### General Debugging

Enable debug mode for verbose output:

```bash
# Via environment variable
export MIRROR_DEBUG=1
./bootstrap.sh --install

# Or via direct mirror-manager call
sudo ./scripts/bootstrap/mirror/mirror-manager.sh --debug
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Permission denied | Run with `sudo`: `sudo ./bootstrap.sh --install` |
| Distro not supported | Check supported distros in `packager.sh` case statement |
| Mirrors unavailable | Use `--validate` flag to test accessibility |
| Package not found | Check `packager/packages.sh` for correct package names |
| GUI fails to start | Ensure Python 3 is installed: `sudo pacman -S python` |
| Display detection fails | Run with `--debug` to see detected display server |

### Rollback

To rollback mirror changes:

```bash
# List available backups
ls -la /etc/pacman.d/mirrorlist.bak.*

# Restore specific backup
sudo cp /etc/pacman.d/mirrorlist.bak.TIMESTAMP /etc/pacman.d/mirrorlist

# Refresh package cache
sudo pacman -Syy
```

## Multi-Distro Support

The bootstrap system automatically detects and adapts to:

| Distro | Mirror Tool | Package Manager | Status |
|--------|-------------|-----------------|--------|
| Arch | reflector | pacman | ✅ Full support |
| Ubuntu/Debian | apt sources | apt | ✅ Full support |
| Fedora | dnf repos | dnf | ✅ Full support |
| Gentoo | portage config | emerge | ✅ Full support |

Detection is automatic via `/etc/os-release` or can be forced:

```bash
export MIRROR_DISTRO=ubuntu
./bootstrap.sh --install
```

## Development

### Adding Mirror Support for New Distro

1. Create `mirror/newdistro.sh` following template from `mirror/arch.sh`
2. Source `mirror-common.sh` for utilities
3. Implement mirror selection logic
4. Update `mirror-manager.sh` case statement
5. Test: `sudo mirror-manager.sh --distro newdistro`

### Adding Package Manager Support

1. Create `packager/newdistro.sh` with `pm_update`, `pm_install`, `pm_prepare_root` functions
2. Update `packager/packager.sh` distro detection
3. Test: `./packager/packager.sh update` and `./packager/packager.sh install vim`

### Testing

```bash
# Test mirror selection
sudo ./scripts/bootstrap/mirror/mirror-manager.sh --debug

# Test package installation
./scripts/bootstrap/packager/packager.sh install vim

# Test full bootstrap
./scripts/bootstrap/bootstrap.sh --install --deploy
```

## Documentation

- **Mirror Module**: [mirror/README.md](mirror/README.md)
- **Migration Guide**: [mirror/MIGRATION.md](mirror/MIGRATION.md)
- **Usage Examples**: [mirror/examples.sh](mirror/examples.sh)
- **Package Manager**: `packager/README.md`
- **GUI Configuration**: `gui/README.md`

## See Also

- [Main Project README](../../README.md)
- [Reflector Documentation](https://wiki.archlinux.org/title/Reflector)
- [APT Documentation](https://manpages.debian.org/apt)
- [DNF Documentation](https://docs.fedoraproject.org/en-US/fedora/latest/system-administrators-guide/configuring_dnf/)
- [Portage Documentation](https://wiki.gentoo.org/wiki/Portage)
