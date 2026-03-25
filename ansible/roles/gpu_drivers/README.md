# gpu_drivers

Automates GPU driver setup so the system is fully usable after provisioning: Wayland compositing works, hardware video decode works, and the GPU is stable across reboots.

Detects the installed GPU automatically via `lspci`, or accepts a manual override. Handles NVIDIA, AMD, and Intel across Arch Linux and Debian (stubs for RedHat, Void, Gentoo). For NVIDIA, also registers the driver in the initramfs and configures kernel module options — without this the proprietary driver either fails to load at boot or breaks suspend/resume.

## Execution flow

1. **Package facts** (`tasks/preflight.yml`) — gathers installed package list so later assertions can check for `pciutils`
2. **Preflight** (`tasks/preflight.yml`) — asserts supported OS family, valid variable values, and pciutils availability for auto-detection. Fails fast with a clear message on any violation.
3. **Load OS vars** — includes `vars/archlinux.yml` or `vars/debian.yml` with distro-specific internal package name mappings
4. **Detect GPU** (`tasks/detect.yml`) — runs `lspci -nn` (auto) or applies vendor override; sets `gpu_drivers_has_nvidia/amd/intel` facts. Warns if hybrid GPU detected.
5. **Install drivers** (`tasks/install.yml` → `install-archlinux.yml` or `install-debian.yml`) — installs the correct driver stack, Vulkan loader, and VA-API packages for the detected vendor and variant
6. **Configure** (`tasks/configure.yml`) — deploys `/etc/modprobe.d/nvidia.conf` (KMS options), `/etc/modprobe.d/nvidia-blacklist.conf`, and `/etc/environment.d/gpu.conf` (VA-API). Enables NVIDIA suspend systemd services. **Triggers handler:** if modprobe config changes, initramfs will be regenerated before verification.
7. **Initramfs** (`tasks/initramfs.yml`) — detects initramfs tool (mkinitcpio/dracut/initramfs-tools), deploys NVIDIA drop-in, removes stale drop-ins when switching variants. **Triggers handler:** if drop-in changes.
8. **Flush handlers** — runs pending initramfs regeneration (handler: `regenerate initramfs`) so verification reflects the new state
9. **Verify** (`tasks/verify.yml`) — checks installed packages, config file existence and permissions, and pciutils availability. Fails with a clear message if any postcondition is not met.
10. **Report** (`tasks/report.yml`) — emits structured execution report via `common/report_phase.yml` and `common/report_render.yml`

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `regenerate initramfs` (mkinitcpio) | `configure.yml` modprobe change, `initramfs.yml` drop-in change | Runs `mkinitcpio -P` to regenerate all initramfs images |
| `regenerate initramfs` (dracut) | Same | Runs `dracut --force` |
| `regenerate initramfs` (initramfs-tools) | Same | Runs `update-initramfs -u -k all` |

## Why these choices

**mkinitcpio / dracut drop-in instead of editing base config** — drop-in files in `conf.d/` survive package upgrades and do not conflict with user or distro customizations.

**Separate modprobe.d files per concern** — `nvidia.conf` for module options, `nvidia-blacklist.conf` for blacklisting. Easier to audit and remove individually.

**`nvidia-vaapi-driver` as a separate install step** — VA-API support for NVIDIA requires an independent bridge package; it is not included in the base driver. Without it, `LIBVA_DRIVER_NAME=nvidia` is set but the library is not present, causing VA-API-enabled apps to crash.

**`open-kernel` variant** — since NVIDIA open-sourced their kernel modules (2022), the `nvidia-open` package is the recommended path for Turing+ (RTX 2000 and newer). It is more compatible with future kernel changes. Older cards must use `proprietary`.

## Supported platforms

| OS family | Status | Package manager | NVIDIA | AMD | Intel |
|-----------|--------|----------------|--------|-----|-------|
| Arch Linux | ✅ Full | pacman | proprietary / open-kernel / nouveau | mesa + amdgpu | mesa + vulkan-intel |
| Debian/Ubuntu | ✅ Full | apt | proprietary / nouveau | firmware-amd-graphics + mesa | intel-media-va-driver + mesa |
| RedHat/Fedora | 🔧 Stub | dnf | — | — | — |
| Void Linux | 🔧 Stub | xbps | — | — | — |
| Gentoo | 🔧 Stub | portage | — | — | — |

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
| `gpu_drivers_nvidia_suspend` | `true` | Enable `nvidia-suspend/hibernate/resume.service` for stable suspend. systemd only. |
| `gpu_drivers_nvidia_preserve_video_memory` | `1` | `NVreg_PreserveVideoMemoryAllocations` value. Set `0` to disable on old cards. |
| `gpu_drivers_nvidia_modprobe_overwrite` | `{}` | Dict of additional `options <module> <param>` entries merged into `nvidia.conf`. |

### Feature flags

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_multilib` | `false` (or `true` for `gaming` profile) | Install 32-bit driver libraries (required for Wine, Steam Proton). Profile-aware. |
| `gpu_drivers_vulkan_tools` | `true` | Install `vulkan-tools` (`vulkaninfo`, `vkcube`) for verifying Vulkan works |
| `gpu_drivers_vaapi` | `true` | Configure VA-API: install the VA-API bridge package and set `LIBVA_DRIVER_NAME` |
| `gpu_drivers_cuda` | `false` | Reserved: CUDA compute packages (not yet implemented) |
| `gpu_drivers_headless` | `false` | Reserved: skip display components for compute-only servers (not yet implemented) |

### Audit

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_audit_enabled` | `false` | Enable audit logging. See `wiki/roles/gpu_drivers.md` for event table. |

## Logs

This role does not produce its own log files. Relevant logs are written by the system:

| Source | Path | What to look for |
|--------|------|-----------------|
| Kernel (NVIDIA) | `journalctl -k \| grep -i nvidia` | Module load errors, DKMS failures |
| Kernel (AMD) | `journalctl -k \| grep -i amdgpu` | Module load errors, firmware missing |
| Kernel (Intel) | `journalctl -k \| grep -i i915` | Module load errors |
| initramfs regeneration | `journalctl -u mkinitcpio` (Arch) | Errors during `mkinitcpio -P` |
| Ansible execution | stdout | Structured report from `report_render.yml` |

Log rotation: not applicable (no role-owned log files).

## Troubleshooting

### Black screen after boot (NVIDIA)

**Symptom:** System boots but display stays black after login screen.

**Diagnosis:**
1. Boot with `nomodeset` kernel parameter (temporary)
2. Check if nouveau is loaded: `lsmod | grep nouveau`
3. Check initramfs: `lsinitcpio /boot/initramfs-linux.img | grep nvidia`

**Fix:**
- If nouveau is loaded → `gpu_drivers_nvidia_blacklist_nouveau` was not applied. Re-run the role.
- If NVIDIA modules missing from initramfs → `gpu_drivers_manage_initramfs: false` or initramfs regeneration failed. Run `mkinitcpio -P` manually, check output for errors.

### Wayland compositor fails (NVIDIA)

**Symptom:** KDE/GNOME/Hyprland fails to start on Wayland; falls back to X11 or crashes.

**Diagnosis:** Check `cat /proc/driver/nvidia/params | grep DRM` — should show `ModesettingEnabled: 1`.

**Fix:** `gpu_drivers_nvidia_kms` must be `true`. Re-run the role, then reboot.

### VA-API not working

**Symptom:** `vainfo` returns errors; mpv/Firefox hardware decode not available.

**Diagnosis:**
1. `cat /etc/environment.d/gpu.conf` — must contain `LIBVA_DRIVER_NAME`
2. `echo $LIBVA_DRIVER_NAME` — must be set in user session (requires re-login)
3. `vainfo` — check for supported profiles

**Fix:**
- File missing: `gpu_drivers_vaapi: false` or no GPU detected. Check `gpu_drivers_vendor` and re-run.
- Session not updated: log out and back in after first run (environment.d changes take effect on new login).
- NVIDIA: ensure `nvidia-vaapi-driver` is installed: `pacman -Q nvidia-vaapi-driver` or `dpkg -l nvidia-vaapi-driver`.

### pciutils missing (auto-detection fails)

**Symptom:** Role fails at preflight with: `pciutils must be installed for GPU auto-detection`.

**Fix:** Either install `pciutils` before running this role, or set `gpu_drivers_vendor: nvidia|amd|intel|none` to skip lspci detection.

### Suspend/resume fails (NVIDIA)

**Symptom:** System freezes or black screen after resume from suspend.

**Diagnosis:** `cat /etc/modprobe.d/nvidia.conf | grep NVreg` — should show `NVreg_PreserveVideoMemoryAllocations=1`.

**Fix:** Verify `gpu_drivers_nvidia_preserve_video_memory: 1` and `gpu_drivers_nvidia_suspend: true`. Re-run the role and regenerate initramfs.

## Tags

| Tag | Scope | Example usage |
|-----|-------|---------------|
| `gpu` | All tasks in the role | `--tags gpu` (run everything) |
| `drivers` | Detection, install dispatch, environment config, report | `--tags drivers` |
| `nvidia` | NVIDIA-specific tasks (driver install, modprobe.d, initramfs, blacklist) | `--tags nvidia` |
| `amd` | AMD-specific tasks | `--tags amd` |
| `intel` | Intel-specific tasks | `--tags intel` |
| `vulkan` | Vulkan ICD loader and tools | `--tags vulkan` |
| `report` | Structured execution report only | `--tags report` |

## File map

Files managed by this role. **Do not edit manually** — changes will be overwritten on next run.

| File | Present when | Managed by |
|------|-------------|------------|
| `/etc/modprobe.d/nvidia.conf` | NVIDIA + KMS enabled | `tasks/configure.yml` via `templates/nvidia-modprobe.conf.j2` |
| `/etc/modprobe.d/nvidia-blacklist.conf` | NVIDIA + blacklist enabled | `tasks/configure.yml` via `templates/nvidia-blacklist.conf.j2` |
| `/etc/environment.d/gpu.conf` | VA-API enabled + GPU detected | `tasks/configure.yml` via `templates/gpu-environment.conf.j2` |
| `/etc/mkinitcpio.conf.d/nvidia.conf` | NVIDIA + mkinitcpio | `tasks/initramfs.yml` via `templates/mkinitcpio-nvidia.conf.j2` |
| `/etc/dracut.conf.d/nvidia.conf` | NVIDIA + dracut | `tasks/initramfs.yml` via `templates/dracut-nvidia.conf.j2` |
| `/etc/initramfs-tools/hooks/nvidia-ansible` | NVIDIA + initramfs-tools (Debian) | `tasks/initramfs.yml` via `templates/initramfs-tools-nvidia-modules.j2` |

All files include an "Ansible-managed" header comment. Files are **removed** when their condition becomes false (e.g. switching from proprietary to nouveau removes `nvidia-blacklist.conf`).

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

## Testing

Three Molecule scenarios are provided:

| Scenario | Driver | Platform | Purpose |
|----------|--------|----------|---------|
| `default` | localhost | Host machine | Fast local iteration |
| `docker` | Docker | Arch Linux + Ubuntu (systemd containers) | CI — package install + config file assertions |
| `vagrant` | Vagrant (libvirt) | Arch Linux + Ubuntu 24.04 | Cross-platform, real VMs |

All scenarios use `gpu_drivers_vendor: intel` (Intel = pure Mesa, no DKMS, no kernel modules) to enable testing in GPU-less environments.

**What is tested:**
- Intel driver packages installed (`mesa`, `vulkan-intel`, `intel-media-driver` on Arch; `intel-media-va-driver`, `mesa-vulkan-drivers`, `libgl1-mesa-dri` on Ubuntu)
- `vulkan-tools` installed
- `/etc/environment.d/gpu.conf` exists with mode `0644`, contains `LIBVA_DRIVER_NAME=iHD`
- NVIDIA-specific configs are absent (`/etc/modprobe.d/nvidia.conf`, `nvidia-blacklist.conf`, mkinitcpio/dracut drop-ins)
- Idempotence (zero changed on second run)

**NVIDIA driver packages cannot be tested in CI** — they require DKMS and kernel headers that are not present in containers or headless VMs.

```bash
# Run default scenario (localhost)
molecule test -s default

# Run Docker scenario
molecule test -s docker

# Run Vagrant scenario (requires libvirt)
molecule test -s vagrant
```

## Requirements

- Ansible 2.15+
- `become: true` (root — package install, modprobe.d, initramfs regeneration)
- `pciutils` installed on the target host (required for `gpu_drivers_vendor: auto`). The role asserts this in preflight and fails with a clear message if missing.
- NVIDIA `open-kernel` variant requires Turing or newer GPU (RTX 2000 / GTX 1600 series and up)

## Dependencies

- `common` role — provides `report_phase.yml` and `report_render.yml`

## License

MIT
