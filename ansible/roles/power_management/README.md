# power_management

Manages CPU frequency, TLP power profiles, sleep modes, and lid/power button behaviour across laptops and desktops.

## Execution flow

1. **Validate** (`tasks/validate.yml`) -- verifies that the host OS family and init system are within the role's supported platform set.
2. **Load variables** (`tasks/load_vars.yml`) -- loads OS package mappings from `vars/<os_family>/main.yml`.
3. **Detect hardware** (`tasks/detect.yml`) -- reads DMI chassis type from `/sys/class/dmi/id/chassis_type` only when `power_management_device_type: auto`. Derived state lives in `vars/main.yml`; the role does not publish mutable bookkeeping facts.
4. **Configure stack** (`tasks/configure/main.yml`) -- dispatches the owned configuration phases: package install, TLP config/service state, desktop governor config, and systemd sleep/logind config.
5. **Report** (`tasks/main.yml`) -- renders the structured execution report from phase records written by the role.

### Service application

The role does not use handlers, `meta: flush_handlers`, or a separate service phase. TLP service state is declared inside the TLP configuration process. systemd-logind reload is applied inside the logind configuration process when the managed file changes.

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

#### Global

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_enabled` | `true` | safe | Set `false` to skip this role entirely |
| `power_management_device_type` | `auto` | safe | `auto` -- detect via DMI chassis type; `laptop` -- force laptop mode (TLP); `desktop` -- force desktop mode (governor only) |

#### Per-subsystem toggles

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_manage_tlp` | `true` | safe | Set `false` to skip TLP packages, configuration, and service management |
| `power_management_manage_governor` | `true` | safe | Set `false` to skip CPU governor persistence |
| `power_management_manage_sleep` | `true` | safe | Set `false` to skip sleep.conf deployment |
| `power_management_manage_logind` | `true` | safe | Set `false` to skip logind.conf deployment |

#### TLP -- CPU

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_cpu_governor_ac` | `schedutil` | safe | Kernel-driven balanced scaling on AC |
| `power_management_tlp_cpu_governor_bat` | `schedutil` | safe | Kernel-driven balanced scaling on battery; avoids forcing low-performance `powersave` |
| `power_management_tlp_cpu_boost_ac` | `true` | safe | Allows normal CPU turbo/boost on AC |
| `power_management_tlp_cpu_boost_bat` | `false` | safe | Disables turbo/boost on battery to reduce heat and power draw |
| `power_management_tlp_cpu_epp_ac` | `balance_performance` | safe | Balanced performance preference on AC (Intel HWP, AMD EPP) |
| `power_management_tlp_cpu_epp_bat` | `balance_power` | safe | Balanced battery preference without forcing minimum performance |

#### TLP -- Disk

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_disk_devices` | `""` | internal | Disk device names. Empty = auto-detect. |
| `power_management_tlp_disk_iosched` | `mq-deadline` | careful | I/O scheduler for rotational disks |
| `power_management_tlp_disk_apm_ac` | `254` | careful | Advanced Power Management level on AC. 1=max saving, 254=max performance, 255=disable |
| `power_management_tlp_disk_apm_bat` | `254` | safe | Avoids aggressive HDD head parking on battery |
| `power_management_tlp_sata_linkpwr_ac` | `max_performance` | careful | SATA link power on AC |
| `power_management_tlp_sata_linkpwr_bat` | `med_power_with_dipm` | safe | Balanced SATA power saving on battery |

#### TLP -- USB, PCIe, WiFi, Sound, Runtime PM

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_usb_autosuspend` | `true` | careful | Suspend USB devices when idle. Set `false` for USB drives, gaming peripherals, audio interfaces. |
| `power_management_tlp_usb_allowlist` | `[]` | safe | USB device IDs excluded from autosuspend. Format: `["1234:5678"]` |
| `power_management_tlp_usb_denylist` | `[]` | safe | USB device IDs always suspended |
| `power_management_tlp_pcie_aspm_ac` | `default` | careful | PCIe Active State Power Management on AC |
| `power_management_tlp_pcie_aspm_bat` | `default` | safe | Leaves PCIe ASPM policy to kernel/firmware defaults |
| `power_management_tlp_wifi_pwr_ac` | `"off"` | safe | WiFi power saving on AC |
| `power_management_tlp_wifi_pwr_bat` | `"on"` | safe | WiFi power saving on battery |
| `power_management_tlp_sound_powersave_bat` | `1` | careful | HDA audio idle timeout on battery in seconds. `0` disables audio power saving. |
| `power_management_tlp_sound_powersave_controller` | `true` | safe | HDA controller power save |
| `power_management_tlp_runtime_pm_ac` | `"on"` | safe | Runtime power management for PCI devices on AC |
| `power_management_tlp_runtime_pm_bat` | `auto` | safe | Runtime power management on battery |

#### TLP -- Battery charge thresholds

Only effective on ThinkPad, Dell, and hardware exposing `/sys/class/power_supply/BAT0/charge_control_*_threshold`. Leave empty to skip. Configure start and stop together for each battery.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_bat0_charge_start` | `""` | careful | Start charging BAT0 below this %. Use together with BAT0 stop. Example: `40` |
| `power_management_tlp_bat0_charge_stop` | `""` | careful | Stop charging BAT0 at this %. Use together with BAT0 start. Example: `80` |
| `power_management_tlp_bat1_charge_start` | `""` | careful | Same for BAT1. Use together with BAT1 stop. |
| `power_management_tlp_bat1_charge_stop` | `""` | careful | Same for BAT1. Use together with BAT1 start. |

### Default power profile

The defaults are intentionally balanced rather than aggressive:

| Area | Default behavior | Why |
|------|------------------|-----|
| CPU governor | `schedutil` on AC and battery | Lets the kernel scale CPU frequency by load instead of forcing maximum performance or minimum performance |
| CPU boost | enabled on AC, disabled on battery | Keeps AC responsiveness while reducing battery heat and drain |
| EPP | `balance_performance` on AC, `balance_power` on battery | Nudges modern Intel/AMD platforms without hard frequency caps |
| CPU min/max frequency | unmanaged | Avoids pinning the CPU into too-low or too-high manual limits |
| Disk APM | `254` on AC and battery | Avoids aggressive HDD head parking; SSDs generally ignore unsupported APM details |
| SATA link power | `max_performance` on AC, `med_power_with_dipm` on battery | Saves some battery without forcing the most aggressive `min_power` policy |
| PCIe ASPM | `default` | Leaves risky low-level PCIe policy decisions to kernel/firmware defaults |
| USB autosuspend | enabled | Saves laptop battery; disable for devices that must never sleep |
| Sound power save | `1` second on battery | Saves power with a possible short audio wake-up delay; set `0` to disable |

These settings do not overclock the CPU, raise voltage, or bypass firmware
thermal/current limits. They should not damage the CPU or power supply. Disk
defaults avoid aggressive head parking to reduce HDD wear risk.

#### CPU governor -- Desktop

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_cpu_governor` | `schedutil` (`performance` with `gaming` profile) | careful | Frequency governor. `schedutil` (kernel-native), `performance` (always max), `powersave` (always min) |

#### Sleep

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_hibernate_mode` | `""` | careful | Optional hibernate mode override. Empty leaves systemd/kernel default. Values include `platform`, `shutdown`, `reboot`. |
| `power_management_suspend_state` | `""` | internal | Kernel sleep state override (`mem`, `standby`, `freeze`). Empty = system default. |
| `power_management_hibernate_delay_sec` | `""` | internal | Seconds of suspend before switching to hibernate. Empty = no auto-hibernate. |

#### logind (systemd only)

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_lid_switch_action` | `suspend` | safe | Action on lid close: `suspend`, `hibernate`, `poweroff`, `ignore` |
| `power_management_lid_switch_ac_action` | `suspend` | safe | Action on lid close while on AC |
| `power_management_lid_switch_docked_action` | `ignore` | safe | Action on lid close while docked |
| `power_management_power_key_action` | `poweroff` | careful | Action on power button press. Set `ignore` for rack servers. |
| `power_management_suspend_key_action` | `suspend` | safe | Action on suspend key |
| `power_management_hibernate_key_action` | `ignore` | safe | Action on hibernate key |
| `power_management_idle_action` | `ignore` | careful | Action after idle timeout. Default `ignore` is safe for SSH. `suspend` will kill SSH sessions. |
| `power_management_idle_action_sec` | `"30min"` | safe | Idle timeout before `idle_action` fires |

### Internal mappings (`vars/`)

Do not override via inventory. Edit these files directly only when adding platform or init system support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | Internal constants and derived read-only state | Extending role internals |
| `vars/archlinux/main.yml` | Arch TLP packages | Adding Arch-specific packages |
| `vars/debian/main.yml` | Debian packages (`linux-tools-common`, `tlp`) | Adding Debian-specific packages |
| `vars/redhat/main.yml` | Fedora packages (`kernel-tools`, `tlp`) | Stub -- when Fedora testing is available |
| `vars/void/main.yml` | Void TLP packages | Stub -- when Void testing is available |
| `vars/gentoo/main.yml` | Gentoo TLP packages | Stub -- when Gentoo testing is available |

## Examples

### Laptop -- defaults (auto-detect)

```yaml
# In group_vars/laptops/power.yml or host_vars/<hostname>/power.yml:
- role: power_management
```

Auto-detects laptop via DMI chassis type. Installs TLP, applies the balanced TLP defaults from this role, enables/starts TLP, and deploys logind.conf on systemd hosts.

### ThinkPad -- battery health with charge thresholds

```yaml
# In host_vars/thinkpad-x1/power.yml:
power_management_tlp_bat0_charge_start: 40
power_management_tlp_bat0_charge_stop: 80
```

Stops charging at 80%, resumes at 40% when the hardware and TLP backend support charge thresholds.

### Desktop -- performance governor

```yaml
# In group_vars/desktops/power.yml:
power_management_device_type: desktop
power_management_cpu_governor: performance
```

### Disable logind without disabling the rest

```yaml
# In host_vars/<hostname>/power.yml:
power_management_manage_logind: false
```

### Laptop -- clamshell mode (external monitor)

```yaml
# In host_vars/<hostname>/power.yml:
power_management_lid_switch_action: ignore
power_management_lid_switch_ac_action: ignore
power_management_lid_switch_docked_action: ignore
```

### Media server -- prevent USB drive disconnection

```yaml
# In host_vars/media-server/power.yml:
power_management_device_type: laptop
power_management_tlp_usb_autosuspend: false
power_management_tlp_disk_apm_ac: 254
power_management_tlp_disk_apm_bat: 254
power_management_tlp_sound_powersave_bat: 0
power_management_idle_action: ignore
```

### Gaming on battery

```yaml
# In host_vars/gaming-laptop/power.yml:
power_management_tlp_cpu_boost_bat: true
power_management_tlp_cpu_governor_bat: performance
power_management_tlp_cpu_epp_bat: balance_performance
power_management_tlp_usb_autosuspend: false
power_management_tlp_sound_powersave_bat: 0
power_management_tlp_runtime_pm_bat: "on"
```

### Headless server

```yaml
# In host_vars/server/power.yml:
power_management_device_type: desktop
power_management_cpu_governor: performance
power_management_power_key_action: ignore
power_management_manage_logind: true
```

## Cross-platform details

On non-systemd hosts, systemd-owned sleep/logind tasks are skipped because
their target files and services do not exist there. Desktop CPU governor
persistence is handled through a udev rule on all supported init systems.

| Aspect | Arch Linux | Debian / Ubuntu | Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|--------|------------|--------|
| TLP packages | `tlp`, `tlp-rdw` | `tlp`, `tlp-rdw` | `tlp`, `tlp-rdw` | `tlp` | `app-laptop/tlp` |
| Desktop governor persistence | udev rule | udev rule | udev rule | udev rule | udev rule |
| Config path (TLP) | `/etc/tlp.conf` | `/etc/tlp.conf` | `/etc/tlp.conf` | `/etc/tlp.conf` | `/etc/tlp.conf` |
| Config path (logind) | `/etc/systemd/logind.conf` | `/etc/systemd/logind.conf` | `/etc/systemd/logind.conf` | N/A (no systemd) | N/A (no systemd) |

## Diagnostics

These commands are useful when troubleshooting the runtime services configured by the role.

| Source | Path / Command | Contents | Rotation |
|--------|---------------|----------|----------|
| TLP | `journalctl -u tlp` | TLP start/stop, profile switch events | System journal rotation |
| systemd-logind | `journalctl -u systemd-logind` | Lid switch, power key, idle action events | System journal rotation |

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS not in supported list | Check `ansible_facts['os_family']`. Only Archlinux, Debian, RedHat, Void, Gentoo are supported. |
| TLP not starting after role apply | `systemctl status tlp` and `journalctl -u tlp -n 50` | Check `/etc/tlp.conf` syntax with `tlp-stat -c`. Look for invalid parameter names (TLP silently ignores them). |
| CPU governor is not applied after boot/device add | `cat /etc/udev/rules.d/50-cpu-governor.rules` | The role manages governor persistence through udev. Runtime governor changes caused by other power managers are outside this role's contract. |
| Hibernate action does not work | `cat /proc/swaps` shows only header or resume is not configured | Enable a swap partition/swap file and resume configuration, or use `suspend`/`ignore` instead of `hibernate`/`hybrid-sleep`. |
| SSH session dies after role apply | `power_management_idle_action` is `suspend` or `hibernate` | Keep `power_management_idle_action: ignore` for remotely managed systems. |
| Battery charge thresholds not applied | `cat /sys/class/power_supply/BAT0/charge_control_start_threshold` returns error or unexpected value | Hardware must support threshold control (ThinkPad, Dell). Run `tlp-stat -b` to check. Unsupported hardware silently ignores the setting. |
| Idempotence failure on TLP config | Template produces different output on second run | Check for `ansible_date_time` or other volatile values in template. The backup task uses epoch which may differ between runs. |

## Testing

Use Docker for fast feedback, Vagrant for VM/systemd validation, and the laptop scenario for the TLP path. Molecule scenarios check syntax, convergence, and idempotence; they do not duplicate role verification with separate assert playbooks.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Syntax, convergence, idempotence, desktop/governor path |
| Vagrant (desktop VM) | `molecule test -s vagrant` | After changing OS-specific logic, systemd behavior, or VM-sensitive tasks | Syntax, convergence, idempotence, real systemd VM desktop path |
| Vagrant laptop | `molecule test -s vagrant-laptop` | After changing TLP or laptop detection behavior | Syntax, convergence, idempotence, laptop/TLP path in VM |
| Default (localhost) | `molecule test` | Local scenario only when explicitly allowed by the project workflow | Syntax, convergence, idempotence for the desktop path |

### Success criteria

- Default scenario completes: `syntax -> converge -> idempotence`
- Docker scenario completes: `syntax -> create -> prepare -> converge -> idempotence -> destroy`
- Vagrant scenarios complete: `syntax -> create -> prepare -> converge -> idempotence -> destroy`
- Idempotence step: `changed=0` on the second converge run
- Final line: no `failed` tasks

### What the tests cover

| Category | Coverage |
|----------|----------|
| Syntax | Role and scenario playbooks parse |
| Convergence | Templates, desktop/governor path, TLP packages/service on laptop path |
| Idempotence | Second run does not change an already converged host |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| Idempotence failure on TLP config | Template epoch-based backup creates different filename on each run | Expected for first-time deploy. Second run should show `changed=0` since backup is skipped for Ansible-managed configs. |
| Vagrant: `Python not found` | prepare.yml missing or Arch bootstrap skipped | Check `prepare.yml` has raw Python install (TEST-009) |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `power` | Entire role | Run the full role flow |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with per-subsystem toggles | No -- override via inventory |
| `vars/main.yml` | Internal constants and derived read-only state | When changing private role internals |
| `vars/archlinux/main.yml` | Arch package names | Only when adding Arch-specific packages |
| `vars/debian/main.yml` | Debian package names | Only when adding Debian-specific packages |
| `vars/redhat/main.yml` | Fedora package names (stub) | When Fedora testing is ready |
| `vars/void/main.yml` | Void package names (stub) | When Void testing is ready |
| `vars/gentoo/main.yml` | Gentoo package names (stub) | When Gentoo testing is ready |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/load_vars.yml` | OS and init variable loading | When changing variable layout |
| `tasks/detect.yml` | Hardware and init detection | When adding new hardware detection |
| `tasks/validate.yml` | Supported OS/init validation | When changing supported platforms |
| `tasks/configure/install.yml` | Package installation from OS variable mappings | When changing install logic |
| `tasks/configure/tlp.yml` | TLP config with block/rescue rollback | When changing TLP deployment |
| `tasks/configure/governor.yml` | CPU governor udev persistence | When changing governor logic |
| `tasks/configure/sleep.yml` | systemd sleep.conf deployment | Rarely |
| `tasks/configure/logind.yml` | logind.conf deployment | Rarely |
| `templates/tlp.conf.j2` | TLP config template | When adding TLP parameters |
| `templates/logind.conf.j2` | logind.conf template | When adding logind directives |
| `templates/sleep.conf.j2` | sleep.conf template | When adding sleep parameters |
| `templates/50-cpu-governor.rules.j2` | udev governor rule template | Rarely |
| `molecule/` | Test scenarios (default, docker, vagrant) | When changing test coverage |
| `meta/main.yml` | Galaxy metadata and platform list | When changing supported platforms |
