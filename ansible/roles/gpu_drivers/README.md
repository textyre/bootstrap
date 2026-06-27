# gpu_drivers

Installs and configures the GPU driver package stack owned by this role.

The role is intended for Linux hosts where the GPU vendor is either detected with `lspci` or selected explicitly with `gpu_drivers_vendor`. It manages NVIDIA, AMD, and Intel package stacks for the implemented Arch Linux and Debian-family pipelines. It does not configure a desktop environment, display manager, compositor, X11, Wayland, PRIME/offloading, VM guest tools, or GPU passthrough.

## Contract

The role owns:

- GPU vendor detection or explicit vendor selection.
- Driver package installation for implemented distro pipelines.
- NVIDIA module options and nouveau blacklist when NVIDIA is selected.
- NVIDIA initramfs integration when enabled.
- NVIDIA suspend/resume services for systemd when enabled.
- VA-API package installation and `/etc/environment.d/gpu.conf` when VA-API is enabled.
- Final role verify of the expected package stack.

The role does not own:

- VM guest display integration. That belongs to the `vm` role.
- X11, Wayland, GNOME, KDE, Hyprland, display managers, or user sessions.
- PRIME/offloading configuration for hybrid GPUs.
- Runtime validation with `vainfo`, `vulkaninfo`, `nvidia-smi`, or compositor startup.
- GPU passthrough setup.
- Removal of previously managed files when a feature is no longer selected.
- Audit logging. `gpu_drivers_audit_enabled` is currently a reserved external contract and has no implemented tasks.

## Scenario Matrix

| Scenario | Expected role behavior |
|----------|------------------------|
| Bare metal with NVIDIA/AMD/Intel | Install and configure the selected or detected vendor package stack. NVIDIA also gets module options, blacklist, initramfs, and systemd suspend services when enabled. |
| VM with GPU passthrough | Treat as bare metal, because the guest sees the passed-through GPU. |
| VM without GPU passthrough, X11 | No bare-metal GPU driver stack is required unless a supported physical GPU is exposed or forced. VM guest graphics are handled by the `vm` role. |
| VM without GPU passthrough, Wayland | Same as VM X11. The role does not configure virtual GPU/Wayland guest integration. |
| Headless VM | Use `gpu_drivers_vendor: none` when no GPU driver stack is required. |
| Docker/container | Smoke/idempotence only. Containers are not kernel GPU driver environments. |

## Execution Flow

1. `tasks/validate.yml` checks supported OS family, supported init system, valid role inputs, and `pciutils` availability when `gpu_drivers_vendor: auto`.
2. `tasks/load_vars.yml` loads internal package mappings for the implemented distro pipeline.
3. `tasks/detect.yml` runs `lspci -nn` only when `gpu_drivers_vendor: auto`; manual vendor selection skips `lspci`.
4. `tasks/configure/main.yml` dispatches to `tasks/distro/<os>/main.yml`.
5. `tasks/distro/<os>/main.yml` runs `install`, `configure`, `service`, `initramfs`, `verify`, and `report`.
6. `tasks/main.yml` renders the final report with `common/report_render.yml`.

## Task Layout

Common tasks:

| Purpose | File |
|---------|------|
| Install a package stack | `tasks/common/install_packages.yml` |
| Verify a package stack | `tasks/common/verify_packages.yml` |
| Verify no supported GPU was selected | `tasks/common/verify_no_gpu.yml` |
| Configure NVIDIA module files | `tasks/configure/nvidia.yml` |
| Configure VA-API environment | `tasks/configure/vaapi.yml` |

Distro pipelines:

| Phase | File |
|-------|------|
| Pipeline | `tasks/distro/<os>/main.yml` |
| Install decisions | `tasks/distro/<os>/install/main.yml` |
| Configure decisions | `tasks/distro/<os>/configure/main.yml` |
| Service decisions | `tasks/distro/<os>/service/main.yml` |
| Initramfs | `tasks/distro/<os>/initramfs.yml` |
| Verify decisions | `tasks/distro/<os>/verify.yml` |
| Report | `tasks/distro/<os>/report.yml` |

Distro files own distro-specific package lists, package-manager preparation, and initramfs implementation. Shared actions are kept in common task files.

## Supported Platforms

| OS family | Current state | Notes |
|-----------|---------------|-------|
| Arch Linux | Implemented | Pacman package stack, mkinitcpio initramfs integration. |
| Debian/Ubuntu | Implemented | Apt package stack, dracut or initramfs-tools integration. |
| RedHat/Fedora | Stub | Pipeline files exist, package stack is not implemented. |
| Void Linux | Stub | Pipeline files exist, package stack is not implemented. |
| Gentoo | Stub | Pipeline files exist, package stack is not implemented. |

Supported init systems are `systemd`, `runit`, `openrc`, `s6`, and `dinit`. NVIDIA suspend/resume service management is implemented for `systemd`. The other supported init systems fail explicitly when NVIDIA service management applies.

## NVIDIA Initramfs

The initramfs phase rebuilds boot images directly and only when a managed NVIDIA boot file changed.

| Platform | Changed input | Rebuild command |
|----------|---------------|-----------------|
| Arch Linux | `/etc/modprobe.d/nvidia.conf`, `/etc/modprobe.d/nvidia-blacklist.conf`, or `/etc/mkinitcpio.conf.d/nvidia.conf` | `mkinitcpio -P` |
| Debian/Ubuntu with dracut | `/etc/modprobe.d/nvidia.conf`, `/etc/modprobe.d/nvidia-blacklist.conf`, or `/etc/dracut.conf.d/nvidia.conf` | `dracut --force` |
| Debian/Ubuntu with initramfs-tools | `/etc/modprobe.d/nvidia.conf`, `/etc/modprobe.d/nvidia-blacklist.conf`, or `/etc/initramfs-tools/hooks/nvidia-ansible` | `update-initramfs -u -k all` |

## Variables

### Detection

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_vendor` | `auto` | `auto`, `nvidia`, `amd`, `intel`, or `none`. `auto` requires `pciutils`. |

### NVIDIA

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_nvidia_variant` | `proprietary` | `proprietary` or `open-kernel`. `open-kernel` requires supported NVIDIA hardware. |
| `gpu_drivers_nvidia_kms` | `true` | Manage `nvidia-drm` KMS module option. |
| `gpu_drivers_nvidia_blacklist_nouveau` | `true` | Manage nouveau blacklist for NVIDIA proprietary/open-kernel driver use. |
| `gpu_drivers_manage_initramfs` | `true` | Manage NVIDIA initramfs integration and rebuild when managed boot files change. |
| `gpu_drivers_nvidia_suspend` | `true` | Enable NVIDIA suspend/hibernate/resume services when systemd is used. |
| `gpu_drivers_manage_security` | `true` | Manage NVIDIA KMS and nouveau blacklist unless another owner manages NVIDIA kernel module hardening. |
| `gpu_drivers_nvidia_preserve_video_memory` | `1` | `NVreg_PreserveVideoMemoryAllocations` value in the NVIDIA module options. |
| `gpu_drivers_nvidia_modprobe_overwrite` | `{}` | Extra module options merged into the managed NVIDIA modprobe file. |

### Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_drivers_multilib` | `true` for `gaming` profile, otherwise `false` | Install 32-bit driver libraries where the distro package stack supports them. |
| `gpu_drivers_vulkan_tools` | `true` | Install Vulkan tools package where the distro package stack supports it. |
| `gpu_drivers_vaapi` | `true` | Install VA-API package stack and manage `LIBVA_DRIVER_NAME`. |
| `gpu_drivers_audit_enabled` | `false` | Reserved external contract. No audit tasks are implemented yet. |

## Verify

Role verify checks the final package-stack contract for the selected vendor and distro. It does not check that Ansible modules wrote files correctly, and it does not run runtime GPU commands.

Runtime checks such as `nvidia-smi`, `vainfo`, `vulkaninfo`, compositor startup, and suspend/resume depend on hardware, VM passthrough, user session, display server, and reboot state. Those checks belong in scenario-specific VM or bare-metal validation, not in the generic role verify.

## Molecule

Molecule scenarios do not set role-specific variables. They prepare prerequisites, run the role with defaults, and check idempotence. There is no separate Molecule verify playbook because the role already runs its own `verify` phase during `converge`.

| Scenario | Driver | Platform | Purpose |
|----------|--------|----------|---------|
| `default` | default | Local execution VM or CI host | Fast syntax/converge/idempotence smoke. |
| `docker` | Docker | Arch Linux and Ubuntu systemd containers | Container smoke/idempotence only. No kernel GPU driver validation. |
| `vagrant` | Vagrant/libvirt | Arch Linux and Ubuntu VMs | VM smoke/idempotence without GPU passthrough. |

What Molecule tests:

- Syntax.
- Convergence.
- Idempotence.

What Molecule does not test:

- Real NVIDIA/AMD/Intel hardware driver loading.
- Runtime VA-API or Vulkan behavior.
- X11 or Wayland startup.
- GPU passthrough.
- Suspend/resume.

Run Molecule through the project VM/CI workflow. Do not run Molecule or Ansible directly from the local workstation.

## Files Managed

| File | Present when | Managed by |
|------|--------------|------------|
| `/etc/modprobe.d/nvidia.conf` | NVIDIA + KMS enabled | `tasks/configure/nvidia.yml` |
| `/etc/modprobe.d/nvidia-blacklist.conf` | NVIDIA + blacklist enabled | `tasks/configure/nvidia.yml` |
| `/etc/environment.d/gpu.conf` | VA-API enabled + supported GPU selected | `tasks/configure/vaapi.yml` |
| `/etc/mkinitcpio.conf.d/nvidia.conf` | NVIDIA + mkinitcpio | `tasks/distro/archlinux/initramfs.yml` |
| `/etc/dracut.conf.d/nvidia.conf` | NVIDIA + dracut | `tasks/distro/debian/initramfs.yml` |
| `/etc/initramfs-tools/hooks/nvidia-ansible` | NVIDIA + initramfs-tools | `tasks/distro/debian/initramfs.yml` |

The role configures files when their condition applies. It does not remove previously managed files when a feature is no longer selected.

## Examples

### Bare Metal Auto-Detect

```yaml
- name: Configure GPU drivers
  hosts: workstations
  become: true
  roles:
    - role: gpu_drivers
```

### NVIDIA RTX Bare Metal

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_nvidia_variant: open-kernel
    gpu_drivers_multilib: true
    gpu_drivers_nvidia_kms: true
    gpu_drivers_vaapi: true
```

### Legacy NVIDIA Bare Metal

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_nvidia_variant: proprietary
```

### AMD Bare Metal

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_vendor: amd
    gpu_drivers_vaapi: true
```

### Headless VM Or VM Without GPU Passthrough

```yaml
- role: gpu_drivers
  vars:
    gpu_drivers_vendor: none
```

## Requirements

- Ansible 2.15+.
- `become: true`.
- `pciutils` installed when `gpu_drivers_vendor: auto`.
- NVIDIA `open-kernel` requires supported NVIDIA hardware.

## Dependencies

- `common` role for `report_phase.yml` and `report_render.yml`.

## License

MIT
