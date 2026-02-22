# gpu_drivers

Automates GPU driver setup so the system is fully usable after provisioning: Wayland compositing works, hardware video decode works, and the GPU is stable across reboots.

Detects the installed GPU automatically via `lspci`, or accepts a manual override. Handles NVIDIA, AMD, and Intel across Arch Linux and Debian. For NVIDIA, also registers the driver in the initramfs and configures kernel module options — without this the proprietary driver either fails to load at boot or breaks suspend/resume.

## What this role does

- [x] Detects installed GPU vendor via `lspci` (auto) or a user-set variable (manual override)
- [x] Installs the correct driver stack for the detected vendor and chosen variant
- [x] Configures NVIDIA DRM kernel mode setting (`nvidia-drm.modeset=1`) — required for Wayland compositors (KDE Plasma, GNOME, Hyprland)
- [x] Adds NVIDIA modules to the initramfs (mkinitcpio on Arch, dracut on Debian) — without this the proprietary driver is not available at boot
- [x] Blacklists `nouveau` when using proprietary or open-kernel NVIDIA — prevents conflict at boot that causes a black screen
- [x] Configures `NVreg_PreserveVideoMemoryAllocations=1` — required for stable suspend/resume with NVIDIA
- [x] Sets `LIBVA_DRIVER_NAME` in `/etc/environment.d/gpu.conf` — tells applications (mpv, Firefox, OBS) which VA-API backend to use for hardware video decode
- [x] Validates preconditions before making any change (OS family, variable values, pciutils availability)
- [x] Cleans up conflicting config files when switching driver variant (e.g. proprietary → nouveau removes blacklist and initramfs drop-in)

## Why these choices

**mkinitcpio / dracut drop-in instead of editing base config** — drop-in files in `conf.d/` survive package upgrades and do not conflict with user or distro customizations.

**Separate modprobe.d files per concern** — `nvidia.conf` for module options, `nvidia-blacklist.conf` for blacklisting. Easier to audit and remove individually.

**`nvidia-vaapi-driver` as a separate install step** — VA-API support for NVIDIA requires an independent bridge package; it is not included in the base driver. Without it, `LIBVA_DRIVER_NAME=nvidia` is set but the library is not present, causing VA-API-enabled apps to crash.

**`open-kernel` variant** — since NVIDIA open-sourced their kernel modules (2022), the `nvidia-open` package is the recommended path for Turing+ (RTX 2000 and newer). It is more compatible with future kernel changes. Older cards must use `proprietary`.

## Supported platforms

| OS family | Package manager | NVIDIA | AMD | Intel |
|-----------|----------------|--------|-----|-------|
| Arch Linux | pacman | proprietary / open-kernel / nouveau | mesa + amdgpu | mesa + vulkan-intel |
| Debian | apt | proprietary / nouveau | firmware-amd-graphics + mesa | intel-media-va-driver + mesa |

## Variables

### Detection

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_vendor` | `auto` | GPU vendor: `auto` (detect via lspci), `nvidia`, `amd`, `intel`, `none` |

### NVIDIA driver variant

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_nvidia_variant` | `proprietary` | `proprietary` — closed-source, best performance; `open-kernel` — open kernel modules, requires Turing+ (RTX 2000+); `nouveau` — open-source, limited performance, no Wayland KMS |

### Kernel integration (NVIDIA only)

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_nvidia_kms` | `true` | Enable DRM kernel mode setting (`nvidia-drm.modeset=1`). Required for Wayland. |
| `gpu_drivers_nvidia_blacklist_nouveau` | `true` | Blacklist the `nouveau` driver. Required when using `proprietary` or `open-kernel`. |
| `gpu_drivers_manage_initramfs` | `true` | Add NVIDIA modules to initramfs and regenerate it. Required for the driver to load at boot. |

### Feature flags

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_multilib` | `false` | Install 32-bit driver libraries (required for Wine, Steam Proton) |
| `gpu_drivers_vulkan_tools` | `true` | Install `vulkan-tools` (`vulkaninfo`, `vkcube`) for verifying Vulkan works |
| `gpu_drivers_vaapi` | `true` | Configure VA-API: install the VA-API bridge package and set `LIBVA_DRIVER_NAME` |
| `gpu_drivers_cuda` | `false` | Reserved: CUDA compute packages (not yet implemented) |
| `gpu_drivers_headless` | `false` | Reserved: skip display components for compute-only servers (not yet implemented) |

## Tags

| Tag | Scope |
|-----|-------|
| `gpu` | All tasks in the role |
| `drivers` | Detection, install dispatch, environment config, report |
| `nvidia` | NVIDIA-specific tasks (driver install, modprobe.d, initramfs, blacklist) |
| `amd` | AMD-specific tasks |
| `intel` | Intel-specific tasks |
| `vulkan` | Vulkan ICD loader and tools |

## Example playbook

### Desktop workstation (auto-detect, defaults)

```yaml
- name: Configure GPU drivers
  hosts: workstations
  become: true
  roles:
    - role: gpu_drivers
```

### NVIDIA RTX card with Wayland, Wine gaming (multilib)

```yaml
- name: Configure GPU drivers
  hosts: gaming_rigs
  become: true
  roles:
    - role: gpu_drivers
      vars:
        gpu_drivers_nvidia_variant: open-kernel   # RTX 2000+
        gpu_drivers_multilib: true                # Wine / Steam Proton
        gpu_drivers_nvidia_kms: true
        gpu_drivers_vaapi: true
```

### Legacy NVIDIA card (Maxwell / Pascal — no open-kernel support)

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_nvidia_variant: proprietary
    gpu_drivers_multilib: false
```

### AMD card only (skip detection overhead)

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_vendor: amd
    gpu_drivers_vaapi: true
    gpu_drivers_multilib: true
```

### VM or container — no GPU

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_vendor: none
```

## Requirements

- Ansible 2.15+
- `become: true` (root — package install, modprobe.d, initramfs regeneration)
- `pciutils` installed on the target host (required for `gpu_drivers_vendor: auto`). The role asserts this in preflight and fails with a clear message if missing.
- NVIDIA `open-kernel` variant requires Turing or newer GPU (RTX 2000 / GTX 1600 series and up)

## Dependencies

None.

## License

MIT
