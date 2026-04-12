# vm

Detects the active hypervisor and installs matching guest tools (VirtualBox Guest Additions, open-vm-tools, Hyper-V Integration Services, QEMU Guest Agent).

## Execution flow

1. **Assert OS support** — fails immediately on unsupported OS families (not in Archlinux/Debian/RedHat/Void/Gentoo)
2. **Validate prerequisites** — asserts virtualization facts are available; fails if `gather_facts: false`
3. **Load OS variables** (`vars/<OsFamily>.yml`) — loads distro-specific package names and service manager
4. **Detect virtualization** — sets `vm_virt_type`, `vm_virt_role`, `vm_is_guest`, `vm_is_container`, `vm_hypervisor` from Ansible facts
5. **Install guest tools** (`tasks/_install_guest_tools.yml`) — dispatches to hypervisor-specific task file:
   - **VirtualBox** (`tasks/virtualbox.yml`): checks VBoxControl, installs packages, runs version detection (`virtualbox_version.yml`), triggers ISO install (`virtualbox_iso_install.yml`) on mismatch, checks LTS kernel DKMS (`virtualbox_lts_kernel.yml`), manages vboxservice/vboxadd-service, verifies kernel modules, checks X11 autostart, sets reboot flag
   - **VMware** (`tasks/vmware.yml`): installs open-vm-tools, manages vmtoolsd/vgauthd, verifies vmw_balloon module, checks X11 autostart, reports version
   - **Hyper-V** (`tasks/hyperv.yml`): installs hyperv package, manages hv_*_daemon services, verifies hv_vmbus module, sets reboot flag
   - **KVM** (`tasks/kvm.yml`): installs qemu-guest-agent, manages service with virtio device guard, reports version
   - Skips gracefully for containers/WSL2 (no guest tools needed)
6. **Persist facts** (`tasks/_set_facts.yml`) — writes `/etc/ansible/facts.d/vm_guest.fact` (JSON with hypervisor, is_guest, is_container)
7. **Verify** (`tasks/verify.yml`) — asserts fact file content is correct; checks environment variable sanity
8. **Execution report** — writes structured report via `common/report_render.yml` with reboot_required footer

### Remove path (vm_state: absent)

Steps 1–4 run normally, then `_remove_guest_tools.yml` removes packages and stops services for the detected hypervisor.

### NTP guard and timesync disable

All hypervisors except Hyper-V run a time synchronization service that conflicts with NTP daemons. This role disables it to give exclusive authority to the ntp role.

**NTP guard pattern** — before disabling timesync, the role checks if an NTP daemon (chronyd, ntpd, openntpd, or systemd-timesyncd) is active. If no NTP daemon is running, timesync disable is skipped to prevent losing the only time source. Deploy the ntp role first, then re-run vm.

| Hypervisor | Timesync mechanism | Disable method | Guard enabled |
|-----------|-------------------|----------------|--------------|
| **VirtualBox** | `vboxservice` timesync module | systemd drop-in: `disable-timesync.conf` | Yes — NTP guard checks before writing drop-in |
| **VMware** | `vmtoolsd` timesync channel | modprobe blacklist or `vmware-toolbox-cmd timesync disable` | Yes — NTP guard checks before disabling |
| **KVM** | None (QEMU Guest Agent does not sync time) | N/A | N/A — no timesync to disable |
| **Hyper-V** | `hv_utils` kernel module (hv_vmbus) | Not disableable from guest (requires host-side PowerShell) | N/A — role warns operator to disable on host |

See `tasks/_ntp_guard.yml` for implementation.

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `Restart virtualbox services` | VBox package install/update | Restarts vboxservice or vboxadd-service |
| `Reload systemd daemon` | ISO service unit file creation | Runs `systemctl daemon-reload` (systemd only) |

## Variables

### Configurable (`defaults/main.yml`)

Override via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `vm_state` | `present` | safe | `present` installs guest tools, `absent` removes them |
| `vm_packages_virtualbox_guest` | `['virtualbox-guest-utils']` | careful | VirtualBox guest packages. Change only to pin a specific version |
| `vm_packages_vmware_guest` | `['open-vm-tools']` | careful | VMware guest packages |
| `vm_packages_hyperv_guest` | `['hyperv']` | careful | Hyper-V packages (Arch: `hyperv`, Debian: `hyperv-daemons`) |
| `vm_packages_kvm_guest` | `['qemu-guest-agent']` | careful | KVM/QEMU guest agent package |
| `vm_vbox_version_check` | `true` | careful | When `true`, enforces host/guest VirtualBox version match. Triggers ISO install on mismatch. Set `false` to disable auto-upgrade |
| `vm_vbox_lts_kernel_support` | OS-specific | careful | Set in `vars/<OsFamily>.yml`. When `true`, installs `virtualbox-guest-dkms` + `linux-lts-headers` for LTS kernels |
| `vm_vmware_version_report` | `true` | safe | Display VMware Tools version in execution report |
| `vm_kvm_version_report` | `true` | safe | Display QEMU Guest Agent version in execution report |
| `vm_ntp_daemon_services` | `['chronyd.service', 'ntpd.service', 'openntpd.service', 'systemd-timesyncd.service']` | careful | List of NTP daemon service names to check before disabling hypervisor timesync. Guard prevents losing time sync if no NTP daemon is running |

### Internal mappings (`vars/`)

These files map OS families to distro-specific values. Edit only when adding distro support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/Archlinux.yml` | Package names, `vm_vbox_lts_kernel_support: true`, `vm_service_manager: systemd` | Adding Arch-specific packages |
| `vars/Debian.yml` | Package names for Ubuntu/Debian, `hyperv-daemons` instead of `hyperv` | Adding Debian-specific packages |
| `vars/RedHat.yml` | Package names for Fedora/RHEL, `hyperv-daemons` | Adding RHEL-specific packages |
| `vars/Void.yml` | Package names for Void Linux, `vm_service_manager: runit` | Adding Void-specific packages |
| `vars/Gentoo.yml` | Package names for Gentoo (`app-emulation/qemu-guest-agent`), openrc default | Adding Gentoo-specific packages |
| `vars/default.yml` | Fallback values if OS family file not found | Rarely |

## Examples

### Remove guest tools from a machine

```yaml
# In host_vars/<hostname>/vm.yml:
vm_state: absent
```

### Disable VirtualBox version enforcement

```yaml
# In host_vars/<vbox-host>/vm.yml:
vm_vbox_version_check: false
```

This skips the host/guest version comparison and ISO download. Useful when the host VirtualBox version cannot be detected.

### Override VirtualBox packages

```yaml
# In group_vars/virtualbox_guests/vm.yml:
vm_packages_virtualbox_guest:
  - virtualbox-guest-utils
  - virtualbox-guest-dkms
```

### Reboot if required after guest tools install

```yaml
# In your playbook:
- hosts: all
  become: true
  gather_facts: true
  roles:
    - role: vm
  post_tasks:
    - name: Reboot if guest tools require it
      ansible.builtin.reboot:
      when: vm_reboot_required | default(false)
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu/Debian | Fedora/RHEL | Void Linux | Gentoo |
|--------|-----------|---------------|-------------|------------|--------|
| Hyper-V package | `hyperv` | `hyperv-daemons` | `hyperv-daemons` | `hyperv` | `sys-apps/hv_kvp_daemon` |
| KVM package | `qemu-guest-agent` | `qemu-guest-agent` | `qemu-guest-agent` | `qemu-guest-agent` | `app-emulation/qemu-guest-agent` |
| VMware package | `open-vm-tools` | `open-vm-tools` | `open-vm-tools` | `open-vm-tools` | `open-vm-tools` |
| VBox LTS DKMS | supported | not applicable | not applicable | not applicable | not applicable |
| Default init | systemd | systemd | systemd | runit | openrc |
| Fact file path | `/etc/ansible/facts.d/vm_guest.fact` | same | same | same | same |

## Logs

### Role output

The role produces a structured execution report printed at the end of the run. Each phase is logged via `common/report_phase.yml`. To see only the report:

```bash
ansible-playbook playbook.yml --tags vm:report
```

### Runtime logs

| Source | Command | Contents |
|--------|---------|---------|
| VBox service | `journalctl -u vboxservice` or `journalctl -u vboxadd-service` | Guest Additions events, shared folder mounts |
| VMware tools | `journalctl -u vmtoolsd` | VM Tools status, time sync events |
| KVM agent | `journalctl -u qemu-guest-agent` | Guest agent events |
| Hyper-V | `journalctl -u hv_fcopy_daemon` | File copy service events |
| ISO installer | `/var/log/vboxadd-install.log` | VBoxLinuxAdditions.run output (VBox ISO path only) |

This role does not create its own log files; all output goes to the system journal.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family is not in the supported list | Check `ansible_facts['os_family']` — only Archlinux/Debian/RedHat/Void/Gentoo are supported |
| Role fails at "Validate prerequisites" | `gather_facts: false` in the playbook | Set `gather_facts: true` — virtualization detection requires Ansible facts |
| VirtualBox: no shared folders after install | `lsmod \| grep vboxsf` — is module loaded? | If missing: reboot (module requires it after first install). Check `vm_reboot_required` |
| VirtualBox ISO download fails | Network or URL not accessible | Check outbound HTTPS to `download.virtualbox.org`. Set `vm_vbox_version_check: false` to skip |
| VirtualBox ISO install fails, reverted to pacman | See "WARNING: ISO GA install failed" in output | Role auto-reverts; version mismatch persists. Check `/var/log/vboxadd-install.log` |
| KVM: qemu-guest-agent installed but service not verified | No `/dev/virtio-ports/org.qemu.guest_agent.0` | Virtio serial channel not configured in hypervisor. Configure virtio-serial device in VM settings |
| vm_guest.fact not created | Role did not detect `vm_is_guest=true` | Check `ansible_facts['virtualization_role']` — must be `guest`. Bare metal hosts are skipped |
| systemd-timesyncd conflict warning | Hypervisor and systemd both manage time sync | Disable systemd-timesyncd: `systemctl disable --now systemd-timesyncd` |

## Testing

Both scenarios are required (TEST-002). Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test` | After changing task logic, variables, or fact file writing | Container detection, fact file absent, idempotence |
| Vagrant (KVM) | `molecule test -s vagrant` | After changing service management, OS-specific tasks, or detection logic | Real packages, real services with virtio guard, Arch + Ubuntu |

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- No `failed` tasks in final summary

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Detection | `vm_is_guest`, `vm_is_container`, `vm_hypervisor` set correctly | TEST-008 |
| Fact file | `/etc/ansible/facts.d/vm_guest.fact` exists with valid JSON | TEST-008 |
| Packages | `qemu-guest-agent` installed on KVM guest | TEST-008 |
| Services | `qemu-guest-agent` enabled + active (KVM with virtio channel) | TEST-008 |
| Container path | No fact file created in Docker container | TEST-008 |
| Permissions | `facts.d` directory mode `0755` | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `OS family 'X' is not supported` | Container OS family not in `_vm_supported_os` | Add the OS family to `_vm_supported_os` or use a supported image |
| `vm_guest.fact should NOT exist in container` | Role incorrectly detected container as guest VM | Check `vm_virt_type` in container — should be `container` or `docker` |
| `qemu-guest-agent package not installed on KVM guest` | Package install failed | Run `molecule converge` again; check package manager output |
| Idempotence failure | First run writes fact file, second run re-writes it | Verify `_set_facts.yml` uses `when: vm_is_guest | bool` correctly |
| `Missing virtualization facts` | `gather_facts: false` in `converge.yml` | Ensure `gather_facts: true` in converge |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `vm` | Entire role | Full apply |
| `vm:install` | Package installation tasks only | Re-run package install without other steps |
| `vm:service` | Service management tasks only | Restart/enable services |
| `vm:verify` | Verification tasks (modules, X11, time sync, fact file) | Re-run verification |
| `vm:report` | Debug output and status reports only | Re-generate execution report |
| `vbox` | VirtualBox-specific tasks | VBox path only |
| `vmware` | VMware-specific tasks | VMware path only |
| `hyperv` | Hyper-V-specific tasks | Hyper-V path only |
| `kvm` | KVM/QEMU-specific tasks | KVM path only |

Example:

```bash
ansible-playbook playbook.yml --tags vm:verify
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable variables + supported OS list | No — override via inventory |
| `vars/Archlinux.yml` | Arch Linux package names and service manager | Only when adding Arch-specific support |
| `vars/Debian.yml` | Debian/Ubuntu package names | Only when adding Debian-specific support |
| `vars/RedHat.yml` | Fedora/RHEL package names | Only when adding RHEL-specific support |
| `vars/Void.yml` | Void Linux package names | Only when adding Void-specific support |
| `vars/Gentoo.yml` | Gentoo package names | Only when adding Gentoo-specific support |
| `vars/default.yml` | Fallback values | Rarely |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/verify.yml` | In-role self-verification | When changing verification logic |
| `tasks/virtualbox.yml` | VirtualBox guest tools pipeline | VBox-specific changes |
| `tasks/virtualbox_version.yml` | Host/guest version detection | Version enforcement logic |
| `tasks/virtualbox_iso_install.yml` | ISO download, mount, install with recovery | ISO install path changes |
| `tasks/virtualbox_lts_kernel.yml` | LTS kernel DKMS support | LTS kernel detection |
| `tasks/vmware.yml` | VMware guest tools pipeline | VMware-specific changes |
| `tasks/hyperv.yml` | Hyper-V pipeline | Hyper-V-specific changes |
| `tasks/kvm.yml` | KVM pipeline | KVM-specific changes |
| `tasks/_install_packages.yml` | Common package installation with error handling | Package install logic |
| `tasks/_manage_services.yml` | Enable/start services with idempotent handlers | Service management |
| `tasks/_verify_modules.yml` | Verify kernel modules are loaded | Module verification |
| `tasks/_check_x11.yml` | Check/create X11 integration files (desktop autostart) | X11 integration logic |
| `tasks/_version_report.yml` | Run version check commands and report | Version reporting |
| `tasks/_ntp_guard.yml` | Check if NTP daemon is active before disabling timesync | NTP guard logic |
| `tasks/_reboot_flag.yml` | Set reboot-required flag and create sentinel file | Reboot signaling |
| `tasks/_remove_guest_tools.yml` | Remove packages and disable services | Guest tools removal |
| `handlers/main.yml` | Service restart handlers | When adding new handlers |
| `molecule/docker/` | Docker test scenario | When changing container test logic |
| `molecule/vagrant/` | Vagrant/KVM test scenario | When changing guest VM test logic |
| `molecule/shared/verify.yml` | Shared verification tasks | When changing verification coverage |
