# GPU Drivers Role: Molecule Testing Plan

**Date:** 2026-02-25
**Status:** Draft
**Role:** `ansible/roles/gpu_drivers/`

---

## 1. Current State

### What the role does

The `gpu_drivers` role auto-detects GPU hardware via `lspci` and installs the appropriate driver stack (NVIDIA, AMD, or Intel) with Vulkan and VA-API support. It has six execution phases orchestrated by `tasks/main.yml`:

1. **Preflight** (`preflight.yml`) -- validates OS family, vendor value, variant value, pciutils availability, and guards against unimplemented features (CUDA, headless)
2. **Detect** (`detect.yml`) -- runs `lspci -nn` for auto-detection or applies manual override via `gpu_drivers_vendor`. Sets `gpu_drivers_has_nvidia`, `gpu_drivers_has_amd`, `gpu_drivers_has_intel` facts
3. **Install** (`install.yml`) -- dispatches to `install-archlinux.yml` or `install-debian.yml` based on OS family
4. **Configure** (`configure.yml`) -- deploys modprobe.d configs (NVIDIA DRM KMS, nouveau blacklist), enables/disables NVIDIA suspend/resume services, manages VA-API environment variables (`/etc/environment.d/gpu.conf`)
5. **Initramfs** (`initramfs.yml`) -- detects initramfs tool (mkinitcpio/dracut/initramfs-tools), deploys NVIDIA module drop-ins, triggers regeneration via handler
6. **Report** (`report.yml`) -- debug summary of detected/configured state

### Supported vendors and variants

| Vendor | Variants | Arch packages | Debian packages |
|--------|----------|---------------|-----------------|
| NVIDIA | `proprietary` (default) | `nvidia`, `nvidia-utils`, `nvidia-settings` | `nvidia-driver` |
| NVIDIA | `open-kernel` | `nvidia-open`, `nvidia-utils`, `nvidia-settings` | `nvidia-open-kernel-dkms`, `nvidia-driver` |
| NVIDIA | `nouveau` | `mesa`, `xf86-video-nouveau` | `xserver-xorg-video-nouveau`, `libgl1-mesa-dri` |
| AMD | (single) | `mesa`, `vulkan-radeon`, `libva-mesa-driver` | `firmware-amd-graphics`, `mesa-vulkan-drivers`, `libgl1-mesa-dri` |
| Intel | (single) | `mesa`, `vulkan-intel`, `intel-media-driver` | `intel-media-va-driver`, `mesa-vulkan-drivers`, `libgl1-mesa-dri` |

Additional packages managed:
- Vulkan ICD loader (`vulkan-icd-loader` / `libvulkan1`)
- Vulkan tools (`vulkan-tools`)
- NVIDIA VA-API driver (`nvidia-vaapi-driver`)
- Multilib (32-bit) variants when `gpu_drivers_multilib: true`

### Templates deployed

| Template | Destination | When |
|----------|-------------|------|
| `nvidia-modprobe.conf.j2` | `/etc/modprobe.d/nvidia.conf` | NVIDIA proprietary/open-kernel + KMS |
| `nvidia-blacklist.conf.j2` | `/etc/modprobe.d/nvidia-blacklist.conf` | NVIDIA proprietary/open-kernel + blacklist nouveau |
| `gpu-environment.conf.j2` | `/etc/environment.d/gpu.conf` | VA-API enabled + any GPU detected |
| `mkinitcpio-nvidia.conf.j2` | `/etc/mkinitcpio.conf.d/nvidia.conf` | NVIDIA + mkinitcpio (Arch) |
| `dracut-nvidia.conf.j2` | `/etc/dracut.conf.d/nvidia.conf` | NVIDIA + dracut |
| `initramfs-tools-nvidia-modules.j2` | `/etc/initramfs-tools/hooks/nvidia-ansible` | NVIDIA + initramfs-tools (Debian) |

### Handlers

- `regenerate initramfs` -- dispatches to mkinitcpio, dracut, or initramfs-tools based on `gpu_drivers_initramfs_tool` fact

### Existing tests

```
molecule/default/
  molecule.yml    -- default driver (localhost), vault, ANSIBLE_ROLES_PATH
  converge.yml    -- pre_tasks: install pciutils, then apply role
  verify.yml      -- GPU detection via lspci, OS-aware package checks, config file stat assertions
```

The existing verify.yml is comprehensive: it re-detects the GPU via `lspci`, resolves OS-specific package names, checks packages via `check_mode: true` with `failed_when: is changed`, and verifies config files (`/etc/modprobe.d/nvidia.conf`, `/etc/modprobe.d/nvidia-blacklist.conf`, `/etc/environment.d/gpu.conf`).

### Known bug in gpu-environment.conf.j2

The template uses underscore-prefixed variables (`_gpu_drivers_has_nvidia`, `_gpu_drivers_has_amd`, `_gpu_drivers_has_intel`) but the `detect.yml` tasks set facts WITHOUT the underscore prefix (`gpu_drivers_has_nvidia`, etc.). This means the template will always render empty content. The `configure.yml` task has a `when:` guard that checks the correct variable names, so the file is only deployed when a GPU is detected -- but its content will be wrong (empty).

This bug should be fixed as part of or before the molecule work: change `gpu-environment.conf.j2` to use `gpu_drivers_has_nvidia`, `gpu_drivers_has_amd`, `gpu_drivers_has_intel` (without the underscore prefix).

---

## 2. Hardware Testing Limitation

GPU driver functionality **cannot** be tested in CI environments (Docker containers or headless VMs). Specifically:

- **No GPU hardware** -- Docker containers and CI VMs have no PCI GPU devices. `lspci` returns no VGA/Display/3D entries.
- **DKMS modules fail** -- NVIDIA proprietary and open-kernel drivers build kernel modules via DKMS. Without matching kernel headers AND a real GPU, module compilation fails or is meaningless.
- **Initramfs regeneration** -- `mkinitcpio -P`, `dracut --force`, and `update-initramfs -u` may fail or produce broken images without a real kernel + modules tree.
- **Service enablement** -- `nvidia-suspend.service`, `nvidia-hibernate.service`, `nvidia-resume.service` exist only after the NVIDIA driver package installs successfully.
- **VA-API / Vulkan runtime** -- `vainfo`, `vulkaninfo` require a GPU and loaded kernel modules.

### Test scope for CI

The only realistically testable behavior in CI is:

1. **Preflight assertions** pass (valid OS, valid vendor value, valid variant value)
2. **Package installation** -- Mesa and non-DKMS packages install cleanly (e.g., `mesa`, `vulkan-icd-loader`, `vulkan-tools`)
3. **Config file deployment** -- templates render to correct paths with correct permissions and content
4. **Idempotence** -- second converge run produces zero changed tasks
5. **Conditional logic** -- the `when:` guards correctly skip tasks when no GPU is detected or when vendor is set to `none`

### Test strategy

Force a specific vendor via `gpu_drivers_vendor: intel` (Intel drivers are pure Mesa -- no DKMS, no kernel modules, no proprietary blobs). This allows testing:
- Package installation (mesa, vulkan-intel, intel-media-driver on Arch; intel-media-va-driver, mesa-vulkan-drivers on Debian)
- VA-API environment config deployment
- Vulkan ICD loader installation
- Vulkan tools installation

For NVIDIA-specific config file testing, force `gpu_drivers_vendor: nvidia` but **skip the actual package installation** (those packages have DKMS dependencies). Instead, test only the configure and initramfs phases by pre-creating the necessary facts. This is addressed in the verify design (section 7).

---

## 3. Cross-Platform Analysis

### Intel driver packages (primary CI test path)

| Package purpose | Arch Linux | Debian/Ubuntu |
|----------------|------------|---------------|
| Mesa OpenGL | `mesa` | `libgl1-mesa-dri` (dep of `mesa-vulkan-drivers`) |
| Vulkan driver | `vulkan-intel` | `mesa-vulkan-drivers` |
| VA-API driver | `intel-media-driver` | `intel-media-va-driver` |
| Vulkan ICD loader | `vulkan-icd-loader` | (auto-dependency) |
| Vulkan tools | `vulkan-tools` | `vulkan-tools` |

### AMD driver packages (reference)

| Package purpose | Arch Linux | Debian/Ubuntu |
|----------------|------------|---------------|
| Mesa OpenGL | `mesa` | `libgl1-mesa-dri` |
| Vulkan driver | `vulkan-radeon` | `mesa-vulkan-drivers` |
| VA-API driver | `libva-mesa-driver` | `mesa-va-drivers` |
| Firmware | (in kernel) | `firmware-amd-graphics` |

### NVIDIA driver packages (untestable in CI without GPU)

| Variant | Arch Linux | Debian/Ubuntu |
|---------|------------|---------------|
| proprietary | `nvidia`, `nvidia-utils`, `nvidia-settings` | `nvidia-driver` |
| open-kernel | `nvidia-open`, `nvidia-utils`, `nvidia-settings` | `nvidia-open-kernel-dkms`, `nvidia-driver` |
| nouveau | `mesa`, `xf86-video-nouveau` | `xserver-xorg-video-nouveau`, `libgl1-mesa-dri` |
| VA-API | `nvidia-vaapi-driver` | `nvidia-vaapi-driver` |

### Key difference: `nvidia` and `nvidia-open` packages

On Arch, `nvidia` and `nvidia-open` are DKMS packages that compile kernel modules during installation. They require:
- `linux-headers` matching the running kernel
- A build toolchain (`gcc`, `make`)
- Successful module compilation

In a Docker container, there is no real kernel. The container uses the host kernel, but `linux-headers` for that exact kernel version is unlikely to be available in the Arch repository inside the container. DKMS build will fail.

On Debian, `nvidia-driver` pulls in the pre-built kernel module package for the running kernel. In a container, the matching module package does not exist.

**Conclusion:** NVIDIA proprietary/open-kernel driver installation is not testable in Docker containers. Nouveau and Intel/AMD (pure Mesa) are testable.

---

## 4. Shared Migration

### Current structure

```
molecule/
  default/
    molecule.yml     -- localhost, vault
    converge.yml     -- pre_tasks: pciutils install, role application
    verify.yml       -- lspci detection, OS-aware package checks, config stats
```

### Target structure

```
molecule/
  shared/
    converge.yml     -- clean: force intel vendor, apply role
    verify.yml       -- comprehensive, cross-platform assertions (config-only safe)
  default/
    molecule.yml     -- points to ../shared/*, vault, localhost
  docker/
    molecule.yml     -- Arch systemd container, skip-tags: report
    prepare.yml      -- pacman update + pciutils install
  vagrant/
    molecule.yml     -- Arch + Ubuntu VMs via KVM/libvirt
    prepare.yml      -- cross-platform prep + pciutils install
```

### Migration steps

1. Create `molecule/shared/` directory
2. Create `molecule/shared/converge.yml` -- sets `gpu_drivers_vendor: intel` to bypass lspci and avoid DKMS packages
3. Create `molecule/shared/verify.yml` -- see section 7
4. Update `molecule/default/molecule.yml`:
   - Change playbooks to `../shared/converge.yml` and `../shared/verify.yml`
   - Keep vault_password_file (localhost scenario may use vault vars)
5. Delete `molecule/default/converge.yml` and `molecule/default/verify.yml`

### shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  pre_tasks:
    - name: Gather package facts (required by preflight pciutils assertion)
      ansible.builtin.package_facts:
        manager: auto

    - name: Ensure pciutils is installed
      ansible.builtin.package:
        name: pciutils
        state: present

    - name: Re-gather package facts after pciutils install
      ansible.builtin.package_facts:
        manager: auto

  roles:
    - role: gpu_drivers
      vars:
        gpu_drivers_vendor: intel
```

The `gpu_drivers_vendor: intel` override is critical: it skips `lspci` auto-detection (which would find no GPU in CI) and routes to Intel driver installation (pure Mesa, no DKMS). The `package_facts` gather is required because the preflight task asserts `'pciutils' in ansible_facts.packages` when vendor is `auto` -- with the intel override this assertion is skipped, but gathering facts is still good practice for verify.

---

## 5. Docker Scenario

### molecule/docker/molecule.yml

```yaml
---
driver:
  name: docker

platforms:
  - name: Archlinux-systemd
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/bootstrap/arch-systemd:latest}"
    pre_build_image: true
    command: /usr/lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    privileged: true
    dns_servers:
      - 8.8.8.8
      - 8.8.4.4

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

### molecule/docker/prepare.yml

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true

    - name: Install pciutils (required by gpu_drivers preflight)
      community.general.pacman:
        name: pciutils
        state: present
```

### What can be tested in Docker

| Check | Possible | Note |
|-------|----------|------|
| Preflight assertions pass | Yes | vendor=intel, valid variant, pciutils installed |
| Intel Mesa packages installed | Yes | `mesa`, `vulkan-intel`, `intel-media-driver` |
| Vulkan ICD loader installed | Yes | `vulkan-icd-loader` |
| Vulkan tools installed | Yes | `vulkan-tools` |
| `/etc/environment.d/gpu.conf` deployed | Yes | Template renders for Intel |
| `/etc/environment.d/gpu.conf` content correct | Yes | Should contain `LIBVA_DRIVER_NAME=iHD` |
| NVIDIA modprobe configs NOT deployed | Yes | vendor=intel, so NVIDIA configs should be absent |
| Idempotence (zero changed on 2nd run) | Yes | All tasks are declarative |
| NVIDIA driver packages install | No | DKMS requires kernel headers |
| NVIDIA suspend services enabled | No | Services only exist after nvidia pkg install |
| Initramfs regeneration | No | No real kernel in container |
| `vainfo` / `vulkaninfo` runtime | No | No GPU hardware |

---

## 6. Vagrant Scenario

### molecule/vagrant/molecule.yml

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: generic/arch
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: bento/ubuntu-24.04
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

### molecule/vagrant/prepare.yml

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Bootstrap Python on Arch (raw -- no Python required)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts
      ansible.builtin.gather_facts:

    - name: Refresh pacman keyring on Arch (generic/arch box has stale keys)
      ansible.builtin.shell: |
        sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
        pacman -Sy --noconfirm archlinux-keyring
        sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
        pacman-key --populate archlinux
      args:
        executable: /bin/bash
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade on Arch (ensures openssl/ssl compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Install pciutils on Arch
      community.general.pacman:
        name: pciutils
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Install pciutils on Ubuntu
      ansible.builtin.apt:
        name: pciutils
        state: present
      when: ansible_facts['os_family'] == 'Debian'
```

### Vagrant vs Docker testing scope

The Vagrant scenario provides real VMs but still has **no GPU hardware** (unless GPU passthrough is configured, which is not feasible in CI). Therefore the testing scope is identical to Docker: Intel vendor override, Mesa packages, config files.

The benefit of Vagrant over Docker for this role:

| Capability | Docker | Vagrant |
|-----------|--------|---------|
| Real kernel available | No | Yes |
| mkinitcpio/dracut available | Partially (binary exists, but no kernel to rebuild) | Yes (but rebuilding for Intel is not triggered) |
| systemd fully functional | Partially | Yes |
| Cross-platform (Arch + Ubuntu) | No (Arch image only) | Yes |
| Debian-specific package names tested | No | Yes (ubuntu-noble platform) |

The main value of the Vagrant scenario for this role is **cross-platform verification**: confirming that `install-debian.yml` correctly installs `intel-media-va-driver`, `mesa-vulkan-drivers`, `libgl1-mesa-dri`, and `vulkan-tools` on Ubuntu.

---

## 7. Verify.yml Design

### Design principles

1. **Conservative** -- only assert things that are true in CI without a GPU
2. **Cross-platform** -- use OS-aware package name resolution (matching the existing verify.yml pattern)
3. **Vendor-aware** -- assertions adapt to whichever vendor was configured (converge uses `intel`)
4. **Config-file focused** -- stat + slurp + content assertions for deployed templates
5. **Negative assertions** -- verify that NVIDIA-only configs are absent when vendor is not NVIDIA

### molecule/shared/verify.yml

```yaml
---
- name: Verify gpu_drivers role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "../../defaults/main.yml"

  tasks:

    # ==========================================================
    # Phase 1: Determine what was configured
    # ==========================================================

    - name: Set vendor facts for verification
      ansible.builtin.set_fact:
        gpu_verify_has_nvidia: "{{ gpu_drivers_vendor == 'nvidia' }}"
        gpu_verify_has_amd: "{{ gpu_drivers_vendor == 'amd' }}"
        gpu_verify_has_intel: "{{ gpu_drivers_vendor == 'intel' }}"
        gpu_verify_has_any: "{{ gpu_drivers_vendor in ['nvidia', 'amd', 'intel'] }}"

    # ==========================================================
    # Phase 2: Package verification (OS-aware)
    # ==========================================================

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    # ---- Intel packages ----

    - name: Set Intel verify package names (Arch)
      ansible.builtin.set_fact:
        gpu_verify_intel_packages:
          - mesa
          - vulkan-intel
          - intel-media-driver
          - vulkan-icd-loader
      when:
        - gpu_verify_has_intel
        - ansible_facts['os_family'] == 'Archlinux'

    - name: Set Intel verify package names (Debian)
      ansible.builtin.set_fact:
        gpu_verify_intel_packages:
          - intel-media-va-driver
          - mesa-vulkan-drivers
          - libgl1-mesa-dri
      when:
        - gpu_verify_has_intel
        - ansible_facts['os_family'] == 'Debian'

    - name: Assert Intel driver packages are installed
      ansible.builtin.assert:
        that: "item in ansible_facts.packages"
        fail_msg: "Intel driver package '{{ item }}' not found in installed packages"
      loop: "{{ gpu_verify_intel_packages }}"
      when: gpu_verify_has_intel

    # ---- AMD packages ----

    - name: Set AMD verify package names (Arch)
      ansible.builtin.set_fact:
        gpu_verify_amd_packages:
          - mesa
          - vulkan-radeon
          - libva-mesa-driver
          - vulkan-icd-loader
      when:
        - gpu_verify_has_amd
        - ansible_facts['os_family'] == 'Archlinux'

    - name: Set AMD verify package names (Debian)
      ansible.builtin.set_fact:
        gpu_verify_amd_packages:
          - firmware-amd-graphics
          - mesa-vulkan-drivers
          - libgl1-mesa-dri
      when:
        - gpu_verify_has_amd
        - ansible_facts['os_family'] == 'Debian'

    - name: Assert AMD driver packages are installed
      ansible.builtin.assert:
        that: "item in ansible_facts.packages"
        fail_msg: "AMD driver package '{{ item }}' not found in installed packages"
      loop: "{{ gpu_verify_amd_packages | default([]) }}"
      when: gpu_verify_has_amd

    # ---- Vulkan tools ----

    - name: Assert vulkan-tools is installed (when enabled)
      ansible.builtin.assert:
        that: "'vulkan-tools' in ansible_facts.packages"
        fail_msg: "vulkan-tools package not found in installed packages"
      when:
        - gpu_verify_has_any
        - gpu_drivers_vulkan_tools

    # ==========================================================
    # Phase 3: Config file verification
    # ==========================================================

    # ---- VA-API environment config ----

    - name: Stat /etc/environment.d/gpu.conf
      ansible.builtin.stat:
        path: /etc/environment.d/gpu.conf
      register: gpu_verify_env_conf

    - name: Assert gpu.conf exists with correct permissions (when VA-API enabled)
      ansible.builtin.assert:
        that:
          - gpu_verify_env_conf.stat.exists
          - gpu_verify_env_conf.stat.isreg
          - gpu_verify_env_conf.stat.pw_name == 'root'
          - gpu_verify_env_conf.stat.gr_name == 'root'
          - gpu_verify_env_conf.stat.mode == '0644'
        fail_msg: >-
          /etc/environment.d/gpu.conf missing or wrong permissions
          (expected root:root 0644)
      when:
        - gpu_drivers_vaapi
        - gpu_verify_has_any

    - name: Read gpu.conf content
      ansible.builtin.slurp:
        src: /etc/environment.d/gpu.conf
      register: gpu_verify_env_raw
      when:
        - gpu_drivers_vaapi
        - gpu_verify_has_any
        - gpu_verify_env_conf.stat.exists

    - name: Assert gpu.conf contains correct LIBVA_DRIVER_NAME
      ansible.builtin.assert:
        that: >-
          ('LIBVA_DRIVER_NAME=iHD' in _gpu_verify_env_text and gpu_verify_has_intel)
          or ('LIBVA_DRIVER_NAME=radeonsi' in _gpu_verify_env_text and gpu_verify_has_amd)
          or ('LIBVA_DRIVER_NAME=nvidia' in _gpu_verify_env_text and gpu_verify_has_nvidia)
        fail_msg: >-
          /etc/environment.d/gpu.conf does not contain expected
          LIBVA_DRIVER_NAME for vendor={{ gpu_drivers_vendor }}.
          Content: {{ _gpu_verify_env_text }}
      vars:
        _gpu_verify_env_text: "{{ gpu_verify_env_raw.content | b64decode }}"
      when:
        - gpu_drivers_vaapi
        - gpu_verify_has_any
        - gpu_verify_env_conf.stat.exists

    - name: Assert gpu.conf is absent when VA-API disabled or no GPU
      ansible.builtin.assert:
        that: not gpu_verify_env_conf.stat.exists
        fail_msg: "/etc/environment.d/gpu.conf should not exist (VA-API disabled or no GPU)"
      when: not gpu_drivers_vaapi or not gpu_verify_has_any

    # ---- NVIDIA modprobe configs (should be ABSENT for Intel) ----

    - name: Stat /etc/modprobe.d/nvidia.conf
      ansible.builtin.stat:
        path: /etc/modprobe.d/nvidia.conf
      register: gpu_verify_nvidia_modprobe

    - name: Assert nvidia.conf is absent when vendor is not NVIDIA
      ansible.builtin.assert:
        that: not gpu_verify_nvidia_modprobe.stat.exists
        fail_msg: "/etc/modprobe.d/nvidia.conf should not exist for vendor={{ gpu_drivers_vendor }}"
      when: not gpu_verify_has_nvidia

    - name: Stat /etc/modprobe.d/nvidia-blacklist.conf
      ansible.builtin.stat:
        path: /etc/modprobe.d/nvidia-blacklist.conf
      register: gpu_verify_nvidia_blacklist

    - name: Assert nvidia-blacklist.conf is absent when vendor is not NVIDIA
      ansible.builtin.assert:
        that: not gpu_verify_nvidia_blacklist.stat.exists
        fail_msg: "/etc/modprobe.d/nvidia-blacklist.conf should not exist for vendor={{ gpu_drivers_vendor }}"
      when: not gpu_verify_has_nvidia

    # ---- NVIDIA initramfs drop-ins (should be ABSENT for Intel) ----

    - name: Stat mkinitcpio NVIDIA drop-in
      ansible.builtin.stat:
        path: /etc/mkinitcpio.conf.d/nvidia.conf
      register: gpu_verify_mkinitcpio_nvidia

    - name: Assert mkinitcpio nvidia.conf is absent when vendor is not NVIDIA
      ansible.builtin.assert:
        that: not gpu_verify_mkinitcpio_nvidia.stat.exists
        fail_msg: "/etc/mkinitcpio.conf.d/nvidia.conf should not exist for vendor={{ gpu_drivers_vendor }}"
      when: not gpu_verify_has_nvidia

    - name: Stat dracut NVIDIA drop-in
      ansible.builtin.stat:
        path: /etc/dracut.conf.d/nvidia.conf
      register: gpu_verify_dracut_nvidia

    - name: Assert dracut nvidia.conf is absent when vendor is not NVIDIA
      ansible.builtin.assert:
        that: not gpu_verify_dracut_nvidia.stat.exists
        fail_msg: "/etc/dracut.conf.d/nvidia.conf should not exist for vendor={{ gpu_drivers_vendor }}"
      when: not gpu_verify_has_nvidia

    - name: Stat initramfs-tools NVIDIA hook
      ansible.builtin.stat:
        path: /etc/initramfs-tools/hooks/nvidia-ansible
      register: gpu_verify_initramfs_nvidia

    - name: Assert initramfs-tools nvidia hook is absent when vendor is not NVIDIA
      ansible.builtin.assert:
        that: not gpu_verify_initramfs_nvidia.stat.exists
        fail_msg: "/etc/initramfs-tools/hooks/nvidia-ansible should not exist for vendor={{ gpu_drivers_vendor }}"
      when: not gpu_verify_has_nvidia

    # ==========================================================
    # Phase 4: /etc/environment.d/ directory
    # ==========================================================

    - name: Stat /etc/environment.d directory
      ansible.builtin.stat:
        path: /etc/environment.d
      register: gpu_verify_env_dir

    - name: Assert /etc/environment.d exists
      ansible.builtin.assert:
        that:
          - gpu_verify_env_dir.stat.exists
          - gpu_verify_env_dir.stat.isdir
          - gpu_verify_env_dir.stat.pw_name == 'root'
          - gpu_verify_env_dir.stat.mode == '0755'
        fail_msg: "/etc/environment.d missing or wrong permissions"
      when:
        - gpu_drivers_vaapi
        - gpu_verify_has_any

    # ==========================================================
    # Summary
    # ==========================================================

    - name: Show verification results
      ansible.builtin.debug:
        msg:
          - "=== GPU Drivers Verification Passed ==="
          - "Vendor override: {{ gpu_drivers_vendor }}"
          - "OS family: {{ ansible_facts['os_family'] }}"
          - "VA-API: {{ gpu_drivers_vaapi }}"
          - "Vulkan tools: {{ gpu_drivers_vulkan_tools }}"
          - "NVIDIA configs absent: {{ not gpu_verify_nvidia_modprobe.stat.exists and not gpu_verify_nvidia_blacklist.stat.exists }}"
```

### Assertion summary

| # | Assertion | Docker | Vagrant (Arch) | Vagrant (Ubuntu) |
|---|-----------|--------|----------------|-----------------|
| 1 | Intel packages installed (OS-aware names) | Yes | Yes | Yes |
| 2 | Vulkan tools installed | Yes | Yes | Yes |
| 3 | `/etc/environment.d/gpu.conf` exists, root:root 0644 | Yes | Yes | Yes |
| 4 | `gpu.conf` contains `LIBVA_DRIVER_NAME=iHD` | Yes | Yes | Yes |
| 5 | `/etc/modprobe.d/nvidia.conf` absent | Yes | Yes | Yes |
| 6 | `/etc/modprobe.d/nvidia-blacklist.conf` absent | Yes | Yes | Yes |
| 7 | mkinitcpio nvidia.conf absent | Yes | Yes | Yes |
| 8 | dracut nvidia.conf absent | Yes | Yes | Yes |
| 9 | initramfs-tools nvidia hook absent | Yes | Yes | Yes |
| 10 | `/etc/environment.d/` dir permissions | Yes | Yes | Yes |

All assertions are safe in GPU-less CI environments because they test the Intel vendor path (pure Mesa packages + absence of NVIDIA artifacts).

---

## 8. Implementation Order

### Step 1: Fix gpu-environment.conf.j2 template bug

1. In `templates/gpu-environment.conf.j2`, replace `_gpu_drivers_has_nvidia` with `gpu_drivers_has_nvidia`, `_gpu_drivers_has_amd` with `gpu_drivers_has_amd`, `_gpu_drivers_has_intel` with `gpu_drivers_has_intel`
2. This is a prerequisite -- the template currently renders empty content due to undefined underscore-prefixed variables

### Step 2: Create shared playbooks

3. Create `ansible/roles/gpu_drivers/molecule/shared/` directory
4. Create `molecule/shared/converge.yml` (vendor=intel override, pciutils pre-install)
5. Create `molecule/shared/verify.yml` (comprehensive, cross-platform, as designed in section 7)

### Step 3: Migrate default scenario

6. Update `molecule/default/molecule.yml`:
   - Change playbooks to `../shared/converge.yml` and `../shared/verify.yml`
   - Keep vault_password_file and localhost config
7. Delete `molecule/default/converge.yml`
8. Delete `molecule/default/verify.yml`
9. Test: `molecule syntax -s default`

### Step 4: Create Docker scenario

10. Create `molecule/docker/molecule.yml`
11. Create `molecule/docker/prepare.yml`
12. Test: `molecule test -s docker`

### Step 5: Create Vagrant scenario

13. Create `molecule/vagrant/molecule.yml`
14. Create `molecule/vagrant/prepare.yml` (cross-platform: Arch keyring refresh + pciutils, Ubuntu apt + pciutils)
15. Test: `molecule test -s vagrant` (both arch-vm and ubuntu-noble)

### Step 6: Validate

16. Confirm idempotence passes in Docker scenario
17. Confirm idempotence passes in Vagrant scenario on both platforms
18. Confirm the template bug fix renders `LIBVA_DRIVER_NAME=iHD` in gpu.conf on Intel

### Step 7: Commit

19. Stage all new/changed files
20. Commit: `feat(gpu_drivers): add molecule docker + vagrant scenarios, fix template variable bug`

---

## 9. Risks and Notes

### DKMS modules fail without matching kernel headers

The `nvidia` and `nvidia-open` Arch packages trigger DKMS module builds during `pacman -S`. In a Docker container, there is no matching kernel, so `pacman` will report DKMS build failures. The `community.general.pacman` task will likely succeed (pacman exits 0 even when DKMS post-install hooks fail), but the resulting system is broken. This is why the CI test path uses `gpu_drivers_vendor: intel` instead of `nvidia`.

If NVIDIA-specific testing is needed in the future, consider:
- A Vagrant VM with GPU passthrough (not CI-feasible)
- Mocking the `nvidia` package installation (complex, fragile)
- A dedicated `molecule/nvidia-config-only/` scenario that pre-sets facts and only runs configure+initramfs tasks (skipping install)

### Initramfs regeneration handlers

The handler `regenerate initramfs` is triggered by changes to mkinitcpio/dracut/initramfs-tools drop-in files. In the Intel test path, no NVIDIA drop-ins are deployed, so the handler is never triggered. This means initramfs regeneration is NOT tested in CI.

If the handler fires in a Docker container (e.g., during a future NVIDIA config-only test), `mkinitcpio -P` will fail because there is no kernel to rebuild. Add `failed_when: false` to the handler or use a CI-specific guard variable.

### gpu-environment.conf.j2 template bug (CRITICAL)

As documented in section 1, the template uses `_gpu_drivers_has_*` (underscore prefix) while tasks set `gpu_drivers_has_*` (no prefix). The Jinja2 `{% if _gpu_drivers_has_nvidia %}` evaluates to `false` (undefined variable treated as falsy in Jinja2 with `jinja2.Undefined`), so the template renders only comments -- no `LIBVA_DRIVER_NAME=` line.

The `configure.yml` deploy task has a `when:` guard checking the correct variable name, so the empty file IS deployed when VA-API is enabled and a GPU is detected. The file exists but contains only comments.

**Impact:** VA-API hardware video acceleration does not work because `LIBVA_DRIVER_NAME` is never set in the environment. Users may not notice because some applications fall back to software decoding.

**Fix:** Replace `_gpu_drivers_has_*` with `gpu_drivers_has_*` in the template (3 replacements).

### Idempotence considerations

- `package_facts` + `set_fact` tasks always run but do not change system state
- `package` install tasks are idempotent (already installed = no change)
- `template` tasks are idempotent (Ansible compares rendered content)
- `file state: directory` is idempotent
- `file state: absent` is idempotent (already absent = no change)
- `systemd` service enable is idempotent (already enabled = no change; skipped for Intel path)
- Expected: zero changed tasks on second run

### Vagrant box freshness

- `generic/arch` boxes have stale pacman keyrings -- the prepare.yml includes the standard keyring refresh workaround
- `bento/ubuntu-24.04` boxes may have outdated apt cache -- the prepare.yml includes `apt update`
- Intel GPU packages are in the base repositories for both Arch and Ubuntu; no additional repos needed

### Multilib not tested

The converge uses default variables, which include `gpu_drivers_multilib: false`. Testing 32-bit libraries (`lib32-*` packages on Arch) would require enabling the `[multilib]` repository in `pacman.conf`, which is not configured in the Docker image or Vagrant boxes by default. Multilib testing is out of scope for this plan.

### Preflight pciutils assertion with manual vendor override

When `gpu_drivers_vendor` is not `auto`, the preflight pciutils assertion is skipped (`when: gpu_drivers_vendor == 'auto'`). This means converge works even if pciutils is not installed, as long as a manual vendor is specified. However, the converge.yml still installs pciutils for completeness and to avoid confusing the existing verify.yml pattern.

### Default scenario divergence

The default (localhost) scenario previously used `gpu_drivers_vendor: auto` with real hardware detection. After migration to shared converge, it will use `gpu_drivers_vendor: intel`. If the host machine has a different GPU, this changes the test behavior. To preserve the original localhost behavior, the default scenario could override the vendor in its `molecule.yml` host_vars. However, since the default scenario is for development use and the host machine may or may not have a GPU, the Intel override is the safest choice for consistent results.

### Final file tree

```
ansible/roles/gpu_drivers/
  defaults/main.yml                              -- unchanged
  handlers/main.yml                              -- unchanged
  meta/main.yml                                  -- unchanged
  tasks/main.yml                                 -- unchanged
  tasks/detect.yml                               -- unchanged
  tasks/preflight.yml                            -- unchanged
  tasks/install.yml                              -- unchanged
  tasks/install-archlinux.yml                    -- unchanged
  tasks/install-debian.yml                       -- unchanged
  tasks/configure.yml                            -- unchanged
  tasks/initramfs.yml                            -- unchanged
  tasks/report.yml                               -- unchanged
  templates/nvidia-modprobe.conf.j2              -- unchanged
  templates/nvidia-blacklist.conf.j2             -- unchanged
  templates/gpu-environment.conf.j2              -- MODIFIED (fix _gpu_drivers_has_* -> gpu_drivers_has_*)
  templates/mkinitcpio-nvidia.conf.j2            -- unchanged
  templates/dracut-nvidia.conf.j2                -- unchanged
  templates/initramfs-tools-nvidia-modules.j2    -- unchanged
  molecule/
    shared/
      converge.yml                               -- NEW
      verify.yml                                 -- NEW
    default/
      molecule.yml                               -- MODIFIED (points to ../shared/*)
      converge.yml                               -- DELETED
      verify.yml                                 -- DELETED
    docker/
      molecule.yml                               -- NEW
      prepare.yml                                -- NEW
    vagrant/
      molecule.yml                               -- NEW
      prepare.yml                                -- NEW
```
