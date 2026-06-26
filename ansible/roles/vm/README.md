# vm

Configures a guest operating system for the hypervisor it is running under.

The role detects the active virtualization environment from Ansible facts and
applies the matching guest integration pipeline for VirtualBox, VMware, Hyper-V,
or KVM. It does not manage a desired absent state.

## Contract

The role owns guest integration inside the VM:

| Hypervisor | Role-owned outcome |
|------------|--------------------|
| VirtualBox | Guest Additions from the host-matching ISO, shared folders, XDG/X11 desktop integration, guest service, required kernel modules |
| VMware | `open-vm-tools`, VMware user desktop integration, `vmtoolsd`, `vgauthd`, `vmblock-fuse`, required runtime modules |
| Hyper-V | Linux Integration Services packages, required guest daemons, VMBus runtime visibility, informational reports |
| KVM | QEMU Guest Agent package and service, virtio runtime visibility, informational version report |

The role requires:

- `gather_facts: true`
- OS family in `Archlinux`, `Debian`, `RedHat`, `Void`, `Gentoo`
- init system fact in `systemd`, `runit`, `openrc`, `s6`, `dinit`
- virtualization facts from Ansible
- `target_user` when VirtualBox shared-folder membership is configured

Containers and WSL are reported and skipped; they do not need guest tools.

## Flow

[tasks/main.yml](tasks/main.yml) is the orchestrator:

1. Validate role prerequisites.
2. Load OS-specific variables from `vars/<OsFamily>.yml`.
3. Report virtualization facts.
4. Dispatch to `tasks/hypervisor/<hypervisor>/main.yml` when the host is a supported guest.
5. Render the final execution report through `common/report_render.yml`.

Each hypervisor owns its own install/configure/service/verify/report phases
inside its directory.

## Hypervisors

### VirtualBox

VirtualBox uses Oracle Guest Additions from the versioned ISO, not distro Guest
Additions packages.

Flow:

1. Detect existing ISO Guest Additions under `/opt`.
2. Detect host version from `journalctl -k` / `dmesg`, or use `vm_vbox_host_version_override`.
3. Detect guest version from `VBoxControl --version` or `/opt/VBoxGuestAdditions-*`.
4. Install Guest Additions from ISO only when host and guest versions differ.
5. Configure `/dev/vboxguest` access and `vboxsf` user membership.
6. Configure XDG autostart for `VBoxClient-all`.
7. Configure time-sync policy for the active init system.
8. Start `vboxadd-service`.
9. Verify `vboxguest` and `vboxsf`; report optional `vboxvideo`.
10. Report version when `vm_vbox_version_check` is enabled.

ISO install cleanup lives in the ISO install flow. If ISO install fails, rescue
collects diagnostics and the role fails; there is no package-manager fallback.

### VMware

VMware installs `open-vm-tools`.

Flow:

1. Install VMware guest packages.
2. Configure VMware Tools time-sync policy for the active init system.
3. Configure XDG autostart for `vmware-user-suid-wrapper`.
4. Start `vgauthd`, `vmblock-fuse`, and `vmtoolsd`.
5. Verify required runtime modules.
6. Report VMware Tools version when enabled.

`vmblock-fuse` is required for X11 copy/paste and drag-and-drop support.

### Hyper-V

Hyper-V installs Linux Integration Services packages.

Flow:

1. Install Hyper-V integration packages.
2. Start file copy, key-value pair, and volume shadow copy services.
3. Verify VMBus runtime integration.
4. Report version, time-sync control, and Enhanced Session notes.

Hyper-V time synchronization is controlled by the host integration service; the
role reports this instead of writing a guest-side config file.

### KVM

KVM installs and starts QEMU Guest Agent.

Flow:

1. Install `qemu-guest-agent`.
2. Require `/dev/virtio-ports/org.qemu.guest_agent.0` before starting the agent.
3. Start `qemu-guest-agent`.
4. Verify virtio runtime devices under `/sys/bus/virtio/devices`.
5. Report `qemu-ga` version when enabled.

The virtio channel is a hypervisor-side VM setting. If it is absent, the role
fails with an explicit message.

## Init Systems

The role validates all five project init systems and dispatches through
`ansible_facts['service_mgr']`.

Current service implementations are systemd-backed. Non-systemd service files
exist for `runit`, `openrc`, `s6`, and `dinit` and fail explicitly until those
service contracts are implemented for the corresponding hypervisor.

Timesync configuration follows the same init-specific directory layout. For
VirtualBox and VMware, systemd paths can disable hypervisor time sync when an
existing guest time-sync service is active. Non-systemd paths currently report
that guest-side disable is not implemented and point the operator to host-side
controls.

## Time Sync

The role must not leave a guest without any time source.

For VirtualBox and VMware, it gathers service facts and checks for one of:

- `chronyd.service`
- `ntpd.service`
- `openntpd.service`
- `systemd-timesyncd.service`

If one is running, the role disables hypervisor-provided time sync. If none is
running, it leaves hypervisor time sync enabled and reports why.

| Hypervisor | Guest-side behavior |
|------------|---------------------|
| VirtualBox | systemd drop-in for `vboxadd-service` with `VBoxService -f --disable-timesync` |
| VMware | `/etc/vmware-tools/tools.conf`, `[timeSync] disable-all=true` |
| KVM | No autonomous guest time-sync service is configured by this role |
| Hyper-V | Host-side control only; role reports operator guidance |

## Desktop Integration

Desktop integration is user-session integration, not a system service.

| Hypervisor | File | Starts |
|------------|------|--------|
| VirtualBox | `/etc/xdg/autostart/vboxclient.desktop` | `/usr/bin/VBoxClient-all` |
| VMware | `/etc/xdg/autostart/vmware-user.desktop` | `/usr/bin/vmware-user-suid-wrapper` |

These files are for XDG-compliant graphical sessions. X11 is the current
priority for clipboard and drag-and-drop behavior.

## Variables

### External Contract

Variables in `defaults/main.yml` are the supported external role contract.

| Variable | Default | Description |
|----------|---------|-------------|
| `vm_packages_vmware_guest` | `['open-vm-tools']` | Default VMware guest package list |
| `vm_packages_hyperv_guest` | `['hyperv']` | Default Hyper-V package list for distros that consume the generic value |
| `vm_packages_kvm_guest` | `['qemu-guest-agent']` | Default KVM guest package list for distros that consume the generic value |
| `vm_vbox_host_version_override` | `""` | Explicit VirtualBox host version when kernel log detection is unavailable |
| `vm_vbox_version_check` | `true` | Detect and enforce VirtualBox host/guest Guest Additions version alignment |
| `vm_vmware_version_report` | `true` | Report VMware Tools version |
| `vm_hyperv_version_report` | `true` | Report Hyper-V VMBus kernel metadata |
| `vm_kvm_version_report` | `true` | Report QEMU Guest Agent version |

### Internal Data

`vars/main.yml` contains internal constants:

- `_vm_supported_os`
- `_vm_supported_init_systems`
- `_vm_supported_hypervisors`
- `vm_vbox_guest_service_name`
- `vm_time_sync_service_names`

`vars/<OsFamily>.yml` contains distro-specific package names, service names, and
VirtualBox kernel header package mappings.

## Distro Mappings

| OS family | Hyper-V packages | KVM packages | VMware package | VirtualBox header packages |
|-----------|------------------|--------------|----------------|----------------------------|
| Archlinux | `vm_packages_hyperv_guest` (`hyperv`) | `vm_packages_kvm_guest` (`qemu-guest-agent`) | `open-vm-tools` | `linux-headers` or `linux-lts-headers` |
| Debian | `hyperv-daemons` | `qemu-guest-agent` | `open-vm-tools` | `linux-headers-{{ ansible_kernel }}` |
| RedHat | `hyperv-daemons` | `qemu-guest-agent` | `open-vm-tools` | `kernel-devel` |
| Void | `vm_packages_hyperv_guest` (`hyperv`) | `vm_packages_kvm_guest` (`qemu-guest-agent`) | `open-vm-tools` | `linux-headers` |
| Gentoo | `sys-apps/hv_kvp_daemon` | `app-emulation/qemu-guest-agent` | `open-vm-tools` | none; kernel sources provide headers |

## Reporting And Logs

The role appends phase records through `common/report_phase.yml` and renders the
final report with `common/report_render.yml`.

The role does not create its own log files. Runtime logs are owned by the guest
tools and init system.

| Source | Typical command |
|--------|-----------------|
| VirtualBox service | `journalctl -u vboxadd-service` |
| VMware tools | `journalctl -u vmtoolsd` |
| KVM agent | `journalctl -u qemu-guest-agent` |
| Hyper-V file copy | distro-specific Hyper-V service unit from `vars/<OsFamily>.yml` |
| VirtualBox ISO installer | `/var/log/vboxadd-install.log` |

## Testing

Molecule tests do not duplicate role verification and do not define role-specific
test variables. They only run the role and check that it converges and is
idempotent.

| Scenario | Test sequence | Purpose |
|----------|---------------|---------|
| `default` | `syntax -> converge -> idempotence` | Fast delegated smoke on the current test VM |
| `docker` | `syntax -> create -> prepare -> converge -> idempotence -> destroy` | Container smoke for package-cache preparation and container skip behavior |
| `vagrant` | `syntax -> create -> prepare -> converge -> idempotence -> destroy` | Full VM smoke on real guest VMs |

Prepare playbooks are test-environment setup only:

- `molecule/docker/prepare.yml` imports the shared Docker prepare playbook.
- `molecule/vagrant/prepare.yml` imports the shared Vagrant prepare playbook.

Docker platform settings such as the systemd command, cgroup mounts, and
privileged mode are Molecule driver configuration. They are not role input and
are not part of the vm role contract.

There are no Molecule `verify.yml` playbooks for this role. Runtime contract
checks live inside the role.

All project test execution must follow the repository Test VM Workflow. Do not
run Ansible or Molecule locally outside that workflow.

## Tags

| Tag | What it runs |
|-----|--------------|
| `vm` | Entire role |

The role does not expose internal phase tags.

## Troubleshooting

| Symptom | Meaning | Action |
|---------|---------|--------|
| Unsupported OS failure | `ansible_facts['os_family']` is outside the role contract | Use Archlinux, Debian, RedHat, Void, or Gentoo |
| Unsupported init failure | `ansible_facts['service_mgr']` is outside the role contract | Use systemd, runit, openrc, s6, or dinit |
| Missing virtualization facts | Facts were not gathered | Run with `gather_facts: true` |
| VirtualBox host version not detected | Kernel log has no `host-version` entry | Set `vm_vbox_host_version_override` |
| VirtualBox ISO install deferred | Running kernel modules directory is missing after a kernel upgrade | Reboot and re-run the role |
| VirtualBox ISO install failed | ISO installer failed and rescue diagnostics were printed | Check `/var/log/vboxadd-install.log` and the rescue output |
| KVM virtio channel missing | VM lacks QEMU guest agent virtio serial channel | Add the channel in hypervisor VM settings and re-run |
| Non-systemd service failure | The detected init system has an explicit fail path for that hypervisor | Implement that init-specific service contract before using that combination |

## File Map

| Path | Purpose |
|------|---------|
| `tasks/main.yml` | Role orchestrator |
| `tasks/validate.yml` | Input and platform contract validation |
| `tasks/load_vars.yml` | OS-specific variable loading |
| `tasks/detect.yml` | Virtualization fact reporting |
| `tasks/configure/main.yml` | Hypervisor dispatch |
| `tasks/hypervisor/virtualbox/` | VirtualBox guest pipeline |
| `tasks/hypervisor/vmware/` | VMware guest pipeline |
| `tasks/hypervisor/hyperv/` | Hyper-V guest pipeline |
| `tasks/hypervisor/kvm/` | KVM guest pipeline |
| `defaults/main.yml` | External role variables |
| `vars/main.yml` | Internal role constants |
| `vars/<OsFamily>.yml` | Distro-specific package and service data |
| `handlers/main.yml` | VirtualBox udev and membership notification handlers |
| `molecule/default/` | Delegated smoke scenario |
| `molecule/docker/` | Docker smoke scenario |
| `molecule/vagrant/` | Vagrant smoke scenario |
