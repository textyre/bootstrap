# yay

AUR helper installation and AUR package management for Arch Linux.

## What this role does

- [x] Creates a dedicated `aur_builder` system user (UID < 1000, shell `/usr/bin/nologin`)
- [x] Grants `aur_builder` passwordless `sudo` access to `/usr/bin/pacman` only (`/etc/sudoers.d/yay-aur-builder`, mode `0440`)
- [x] Installs build dependencies (`base-devel`, `git`, `go`)
- [x] Checks if yay is already installed and validates shared libraries (`ldd`) to detect breakage after Go upgrades
- [x] Builds yay from source via `makepkg` as `aur_builder` (clones from AUR, compiles, installs via `pacman -U`)
- [x] Cleans up build artifacts (`/tmp/yay_build_*`) in an `always:` block
- [x] Optionally installs AUR packages via `kewlfft.aur.aur` with `use: yay`
- [x] Optionally removes conflicting official packages before AUR installs
- [x] Validates AUR vs official package conflicts via `validate-aur-conflicts.sh`

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `yay_source_url` | `https://aur.archlinux.org/yay.git` | AUR git repo URL |
| `yay_builder_user` | `aur_builder` | Dedicated non-root build user name |
| `yay_builder_sudoers_file` | `yay-aur-builder` | Sudoers drop-in filename in `/etc/sudoers.d/` |
| `yay_build_deps` | `[base-devel, git, go]` | Packages required to build yay from source |
| `yay_packages_aur` | `[]` | AUR packages to install (empty = skip AUR package management) |
| `yay_packages_aur_remove_conflicts` | `[]` | Official packages to remove before AUR installs |
| `yay_packages_official` | `[]` | Official packages list (used for conflict validation) |

## Supported platforms

Arch Linux only. The role asserts `os_family == Archlinux` and fails on any other distribution.
`makepkg`, `pacman`, and the AUR are Arch-specific tools with no equivalent on other distros.

## Tags

`aur`, `aur:setup` (user + sudoers + binary only), `aur:install` (AUR package management only)

## External dependencies

- `community.general.pacman` — package installation
- `kewlfft.aur.aur` — AUR package management (required only when `yay_packages_aur` is non-empty)

Install collections: `ansible-galaxy collection install -r ansible/requirements.yml`

## Testing

Three Molecule scenarios:

| Scenario | Driver | Coverage |
|----------|--------|---------|
| `default` | delegated (localhost) | Full: yay build + AUR package install (`rofi-greenclip`) |
| `docker` | Docker (`arch-systemd`) | yay build only (no AUR packages; skips `kewlfft.aur`) |
| `vagrant` | Vagrant + libvirt | yay build only (full VM, `generic/arch` box) |

```bash
# Localhost (requires Arch Linux VM — take a snapshot first!)
molecule test -s default

# Docker (requires Docker + arch-systemd image)
molecule test -s docker

# Vagrant (requires libvirt + vagrant-libvirt plugin, ~10 min)
molecule test -s vagrant
```

Verify assertions (14 total):

1. `aur_builder` user exists
2. Shell is `/usr/bin/nologin`
3. UID < 1000 (system user)
4. Sudoers file exists at `/etc/sudoers.d/yay-aur-builder`
5. Sudoers permissions `0440 root:root`
6. Sudoers syntax valid (`visudo -cf`)
7. Sudoers content has `NOPASSWD: /usr/bin/pacman`
8. Build dependencies installed (`base-devel`, `git`, `go`)
9. `yay` binary at `/usr/bin/yay`
10. `yay --version` succeeds
11. No broken shared libs (`ldd /usr/bin/yay`)
12. No leftover `/tmp/yay_build_*` directories
13. AUR packages installed (`pacman -Q`, conditional)
14. `aur_builder` can execute `yay --version`

## Notes

**Why a dedicated build user?**  `makepkg` refuses to run as root with `ERROR: Running makepkg as root is not allowed`. The `aur_builder` system user exists solely for this purpose and has no login shell or home directory access beyond what's needed for builds.

**Go module downloads:**  The build requires internet access to `proxy.golang.org`. In Docker/CI, set `dns_servers: [8.8.8.8, 8.8.4.4]` (already configured in the docker scenario).

**Broken libs detection:**  After major Go upgrades, shared libs can become invalid. The role runs `ldd /usr/bin/yay` before skipping the build — if `"not found"` appears in output, the binary is rebuilt.

**AUR package management is optional:**  Leave `yay_packages_aur: []` (the default) to install only yay itself without managing any AUR packages.
