# Ansible Role: vm

Automatically detects and installs virtualization guest tools for VirtualBox, VMware, Hyper-V, and KVM environments.

## Supported Hypervisors

- **VirtualBox** - Guest Additions (package or ISO install with version enforcement)
- **VMware** - open-vm-tools
- **Hyper-V** - Integration Services
- **KVM** - QEMU Guest Agent (qemu-guest-agent)

## Requirements

- Ansible 2.9 or higher
- `gather_facts: true` (required for virtualization detection)
- `become: true` (root privileges required for package installation and service management)
- Supported OS families: Arch Linux, Debian/Ubuntu, Fedora/RHEL, Gentoo

## Role Variables

Available variables (see `defaults/main.yml`):

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `packages_virtualbox_guest` | list | `[]` | VirtualBox guest packages to install |
| `packages_vmware_guest` | list | `[]` | VMware guest packages to install |
| `packages_hyperv_guest` | list | `[]` | Hyper-V guest packages to install |
| `packages_kvm_guest` | list | `[]` | KVM/QEMU guest packages to install |
| `vm_vbox_version_check` | bool | `true` | Enforce VirtualBox version match between host and guest |
| `vm_vmware_version_report` | bool | `true` | Display VMware Tools version information |
| `vm_kvm_version_report` | bool | `true` | Display QEMU Guest Agent version information |

## Tags

| Tag | Purpose |
|-----|---------|
| `vm` | Run all tasks in the role |
| `vm:install` | Package installation tasks only |
| `vm:service` | Service management tasks only |
| `vm:verify` | Verification tasks (modules, X11, time sync) |
| `vm:report` | Debug output and status reports only |
| `vbox` | VirtualBox-specific tasks |
| `vmware` | VMware-specific tasks |
| `hyperv` | Hyper-V-specific tasks |
| `kvm` | KVM/QEMU-specific tasks |

## Example Playbook

```yaml
---
- name: Configure VM guest tools
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: vm
      vars:
        packages_virtualbox_guest:
          - virtualbox-guest-utils
        packages_vmware_guest:
          - open-vm-tools
          - gtkmm3
        packages_hyperv_guest:
          - hyperv
        packages_kvm_guest:
          - qemu-guest-agent

  tasks:
    - name: Reboot if required
      ansible.builtin.reboot:
      when: _vm_reboot_required | default(false)
```

Run specific tasks:

```bash
# Install packages only
ansible-playbook playbook.yml --tags vm:install

# Skip debug output
ansible-playbook playbook.yml --skip-tags vm:report

# VirtualBox only
ansible-playbook playbook.yml --tags vbox
```

## Features

- **Automatic detection** - Uses Ansible facts to identify hypervisor type
- **Version enforcement** - VirtualBox: downloads and installs matching ISO if version mismatch detected
- **Service management** - Enables and starts required services with health checks
- **Module verification** - Validates kernel modules are loaded
- **X11 integration** - Creates missing desktop autostart files for clipboard/seamless mode
- **Time sync checks** - Warns about systemd-timesyncd conflicts
- **Recovery handling** - VirtualBox ISO install failures automatically fall back to package manager

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
