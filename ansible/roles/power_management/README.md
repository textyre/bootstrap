# power_management

Configures the full power management stack so the system behaves correctly on both AC and battery without manual tuning: the right CPU frequency profile is active, the disk is not spinning unnecessarily, USB devices sleep when idle, and the lid and power button do what you expect.

On a **laptop**, TLP switches between two complete profiles automatically when the power source changes — performance on AC, powersave on battery. On a **desktop**, the CPU governor is set once and survives reboot via a udev rule. On all systemd systems, logind controls lid close, power button, and idle actions independently of the desktop environment.

A daily audit script checks that the configuration is still in effect and writes the results to the system journal — ready for Loki/Alloy to collect without any further configuration.

## What this role actually does

### Laptop — TLP power profiles

| Effect | AC | Battery |
|--------|----|----|
| CPU frequency governor | `performance` | `powersave` |
| CPU turbo boost | on | **off** — single biggest battery saver (+30–40% runtime) |
| CPU energy/performance preference (Intel HWP, AMD EPP) | `performance` | `power` |
| Disk APM level | 254 (no spindown) | 128 (spindown + head park, less power and noise) |
| SATA link power | `max_performance` | `min_power` |
| USB autosuspend | on | on — USB devices sleep when idle |
| PCIe ASPM | `default` | `powersupersave` |
| WiFi power saving | off (full speed) | on (reduces TX power) |
| Sound card (HDA) autosuspend | — | on |
| Runtime power management | `on` | `auto` |

Battery charge thresholds (ThinkPad, Dell, and other supported hardware): configures `charge_control_start_threshold` / `charge_control_end_threshold` in `/sys/` to stop charging at e.g. 80% — extends battery lifespan significantly for machines that spend most time on AC.

### Desktop — CPU governor

Sets the CPU frequency governor via `cpupower` and persists it through reboot with a udev rule (`/etc/udev/rules.d/50-cpu-governor.rules`). The udev approach works on any init system — systemd, OpenRC, runit — without requiring a service.

Default: `schedutil` — kernel-native, tracks CPU load in real time, better than `ondemand` for modern workloads.

### Lid, power button, idle — logind

Configures `/etc/systemd/logind.conf` to define system-level behaviour independently of any desktop environment:

| Event | Default action |
|-------|---------------|
| Lid close | suspend |
| Lid close on AC | suspend |
| Lid close when docked | ignore |
| Power button | poweroff |
| Suspend key | suspend |
| Hibernate key | ignore |
| Idle action | ignore *(safe default — does not interrupt SSH sessions)* |

### Sleep modes

Deploys `/etc/systemd/sleep.conf` with explicit suspend, hibernate, and hybrid-sleep modes.

Default hibernate mode: `platform` (not `shutdown`) — resumes via firmware even if the battery ran out completely while sleeping. `shutdown` risks an unclean state if the system powers off before fully saving to swap.

### Conflict prevention

Masks `power-profiles-daemon` before TLP starts. Without this, both tools fight over the CPU governor: TLP sets `powersave`, PPD overrides it back to `balanced`, and neither one controls the system predictably. The mask is guarded — applied only when TLP is enabled.

On Arch Linux, also masks `systemd-rfkill.service` and `systemd-rfkill.socket` — rfkill conflicts with TLP's radio device management.

### Post-deploy verification

After every apply, the role reads the actual system state and asserts 6 conditions:

- TLP service is `active`
- `power-profiles-daemon` is masked or absent
- CPU governor matches the configured value (reads `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`)
- `/etc/systemd/sleep.conf` contains the expected `SuspendMode`
- `/etc/systemd/logind.conf` contains the expected `HandleLidSwitch`
- Battery charge thresholds are applied in `/sys/` (when configured)

All assertions respect `power_management_assert_strict`: `true` (default) fails the play on mismatch; `false` logs a warning and continues.

### Drift detection

On each subsequent run, the role compares the current `power_management_status` fact against the state saved to `/var/lib/ansible-power-management/last_state.json` during the previous run. If the CPU governor or TLP status changed outside of Ansible, a `DRIFT DETECTED` warning is emitted. Useful for catching manual changes or conflicting automation.

### Audit and observability

Deploys `/usr/local/bin/power-audit.sh` and schedules it to run daily. The script checks:

- CPU governor on all cores
- TLP service status
- Battery capacity and charging status
- Battery wear level — emits `WARNING` if wear exceeds `power_management_audit_battery_wear_threshold` (default 20%)
- Conflicting services (`power-profiles-daemon`, `auto-cpufreq`)
- Charge threshold values from `/sys/`

All output goes to the system journal via `logger -t power-audit`. Query with:

```bash
journalctl -t power-audit --since "7 days ago"
journalctl -t power-audit -g WARNING
```

Alloy picks this up via its `journald` source with `matches = [{__journal_syslog_identifier = "power-audit"}]` — no additional configuration needed.

On non-systemd systems (OpenRC, runit), a cron job is deployed instead of the systemd timer.

## Why these choices

**TLP over power-profiles-daemon** — PPD offers three coarse profiles (performance, balanced, power-saver) with no per-subsystem control. TLP configures each subsystem independently per power source with ~100 parameters. PPD is appropriate for desktops and GNOME integration; TLP is appropriate for laptops where battery life matters.

**`CPU_BOOST_ON_BAT=0`** — disabling turbo boost on battery is the single most impactful TLP parameter. A modern laptop CPU draws 3–5× more power at boost frequencies. Disabling it costs negligible performance for typical mobile workloads (document editing, browsing, meetings) and adds 30–40% runtime.

**`DISK_APM_LEVEL_ON_BAT=128`** — APM 128 enables HDD head parking after idle timeout and reduces rotational speed. NVMe drives ignore this parameter. HDDs on battery benefit significantly; the laptop also runs noticeably quieter.

**udev rule for governor on desktop** — `cpupower frequency-set` is a one-shot command that does not survive reboot. A systemd service works only on systemd. A udev rule runs on `ACTION==add, SUBSYSTEM==cpu` — fires on every CPU hotplug event, works on any init system, requires no daemon.

**`platform` hibernate mode** — with `shutdown` mode, if the battery drains to zero while the system is hibernated, the saved state on swap may be inconsistent. `platform` delegates resume to the firmware, which can recover from a full power loss safely.

**logind for lid/power behaviour** — configuring these in logind rather than in a DE-specific config means they work in TTY sessions, with window managers that do not have their own power management, and before any DE starts. A DE can override logind with `InhibitDelayMaxSec` if needed.

**`idle_action=ignore` default** — `suspend` on idle would kill SSH sessions and background jobs. The safe default is to leave idle action to the user's DE or screen locker. Override explicitly for kiosk-style systems.

**Journal for audit output** — `logger -t power-audit` integrates with the existing journal infrastructure. `journalctl -t power-audit` queries are fast. Loki/Alloy can filter by `SYSLOG_IDENTIFIER` without parsing log files. No separate log rotation needed.

## Supported platforms

| OS family | Package manager | TLP | cpupower |
|-----------|----------------|-----|---------|
| Arch Linux | pacman | `tlp`, `tlp-rdw` | `cpupower` |
| Debian / Ubuntu | apt | `tlp` | `linux-tools-common`, `linux-tools-$(uname -r)` |

## Variables

### Global

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_enabled` | `true` | Master switch. Set to `false` to skip the entire role. |
| `power_management_device_type` | `auto` | `auto` — detect via DMI chassis type; `laptop` — force laptop mode (TLP); `desktop` — force desktop mode (governor only) |

### TLP — CPU

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_tlp_cpu_governor_ac` | `performance` | CPU frequency governor on AC |
| `power_management_tlp_cpu_governor_bat` | `powersave` | CPU frequency governor on battery |
| `power_management_tlp_cpu_boost_ac` | `true` | CPU turbo boost on AC |
| `power_management_tlp_cpu_boost_bat` | `false` | CPU turbo boost on battery. **Set to `false` for maximum battery life.** |
| `power_management_tlp_cpu_epp_ac` | `performance` | Energy/performance preference on AC (Intel HWP, AMD EPP). Values: `performance`, `balance_performance`, `balance_power`, `power` |
| `power_management_tlp_cpu_epp_bat` | `power` | Energy/performance preference on battery |
| `power_management_tlp_cpu_min_freq_ac` | `""` | Minimum CPU frequency on AC. Empty = no limit. Example: `800000` (kHz) |
| `power_management_tlp_cpu_max_freq_bat` | `""` | Maximum CPU frequency on battery. Empty = no limit. |

### TLP — Disk

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_tlp_disk_devices` | `""` | Disk device names. Empty = auto-detect. Example: `"sda nvme0n1"` |
| `power_management_tlp_disk_iosched` | `mq-deadline` | I/O scheduler for rotational disks |
| `power_management_tlp_disk_apm_ac` | `254` | Advanced Power Management level on AC. 1=max power saving, 254=max performance, 255=disable |
| `power_management_tlp_disk_apm_bat` | `128` | APM level on battery. 128 enables head parking and spindown. |
| `power_management_tlp_sata_linkpwr_ac` | `max_performance` | SATA link power on AC |
| `power_management_tlp_sata_linkpwr_bat` | `min_power` | SATA link power on battery |

### TLP — USB, PCIe, WiFi, Sound, Runtime PM

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_tlp_usb_autosuspend` | `true` | Suspend USB devices when idle |
| `power_management_tlp_usb_allowlist` | `[]` | USB device IDs excluded from autosuspend. Format: `["1234:5678"]` |
| `power_management_tlp_usb_denylist` | `[]` | USB device IDs always suspended (overrides allowlist) |
| `power_management_tlp_pcie_aspm_ac` | `default` | PCIe Active State Power Management on AC |
| `power_management_tlp_pcie_aspm_bat` | `powersupersave` | PCIe ASPM on battery |
| `power_management_tlp_wifi_pwr_ac` | `"off"` | WiFi power saving on AC (`off` = full speed) |
| `power_management_tlp_wifi_pwr_bat` | `"on"` | WiFi power saving on battery |
| `power_management_tlp_sound_powersave_bat` | `true` | HDA audio autosuspend on battery |
| `power_management_tlp_sound_powersave_controller` | `true` | HDA controller power save |
| `power_management_tlp_runtime_pm_ac` | `"on"` | Runtime power management for PCI devices on AC |
| `power_management_tlp_runtime_pm_bat` | `auto` | Runtime power management on battery |

### TLP — Battery charge thresholds

Only effective on ThinkPad, Dell, and other hardware that exposes `/sys/class/power_supply/BAT0/charge_control_*_threshold`. Leave empty to skip configuration.

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_tlp_bat0_charge_start` | `""` | Start charging BAT0 when below this %. Recommended: `40` |
| `power_management_tlp_bat0_charge_stop` | `""` | Stop charging BAT0 at this %. Recommended: `80` |
| `power_management_tlp_bat1_charge_start` | `""` | Same for BAT1 (some ThinkPads have a second battery) |
| `power_management_tlp_bat1_charge_stop` | `""` | |

### CPU governor — Desktop

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_cpu_governor` | `schedutil` | Frequency governor. `schedutil` — kernel-native, tracks load; `performance` — always max; `powersave` — always min |
| `power_management_governor_persist` | `udev` | How to persist the governor across reboots: `udev` (init-agnostic, recommended), `service` (systemd cpupower.service), `oneshot` (no reboot survival) |

### Sleep

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_suspend_mode` | `suspend` | Suspend mode: `suspend`, `hibernate`, `hybrid-sleep` |
| `power_management_hibernate_mode` | `platform` | Hibernate mode: `platform` (firmware-managed, safe), `shutdown`, `reboot` |
| `power_management_hybrid_sleep_mode` | `suspend` | Hybrid sleep mode |
| `power_management_suspend_state` | `""` | Kernel sleep state. Empty = system default (`mem` or `freeze`). |
| `power_management_hibernate_delay_sec` | `""` | Seconds of suspend before switching to hibernate. Empty = no auto-hibernate. |

### logind (systemd only)

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_lid_switch_action` | `suspend` | Action on lid close: `suspend`, `hibernate`, `poweroff`, `ignore` |
| `power_management_lid_switch_ac_action` | `suspend` | Action on lid close while on AC |
| `power_management_lid_switch_docked_action` | `ignore` | Action on lid close while docked |
| `power_management_power_key_action` | `poweroff` | Action on power button press |
| `power_management_suspend_key_action` | `suspend` | Action on suspend key |
| `power_management_hibernate_key_action` | `ignore` | Action on hibernate key |
| `power_management_idle_action` | `ignore` | Action after idle timeout. **Default `ignore` — safe for SSH.** |
| `power_management_idle_action_sec` | `"30min"` | Idle timeout before `idle_action` fires |

### Audit and monitoring

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_audit_enabled` | `true` | Deploy audit script and schedule |
| `power_management_audit_schedule` | `daily` | systemd `OnCalendar` value or cron schedule |
| `power_management_audit_battery` | `true` | Include battery health check in audit |
| `power_management_audit_battery_wear_threshold` | `20` | Battery wear % above which a `WARNING` is logged |

### Drift detection

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_drift_detection` | `true` | Compare state with previous run and warn on drift |
| `power_management_drift_state_dir` | `/var/lib/ansible-power-management` | Directory for state file (mode 0700, state file mode 0600) |

### Assertions

| Variable | Default | Description |
|----------|---------|-------------|
| `power_management_assert_strict` | `true` | `true` — fail the play if post-deploy checks fail; `false` — log warnings and continue |

## Tags

| Tag | Scope |
|-----|-------|
| `power` | All tasks in the role |
| `power, detect` | Hardware and init system detection |
| `power, preflight` | Pre-deploy safety checks |
| `power, conflicts` | Conflicting service masking |
| `power, install` | Package installation |
| `power, tlp` | TLP configuration and service |
| `power, cpu` | CPU governor configuration |
| `power, sleep` | systemd sleep.conf |
| `power, logind` | logind.conf |
| `power, facts` | Collect system state into `power_management_status` |
| `power, assert` | Post-deploy effectiveness assertions |
| `power, drift` | Drift detection |
| `power, audit` | Audit script and timer deployment |
| `power, report` | Summary debug output |

## Example playbooks

### Laptop — defaults (auto-detect)

```yaml
- name: Configure power management
  hosts: laptops
  become: true
  roles:
    - role: power_management
```

Auto-detects laptop via DMI chassis type. Installs TLP, sets performance/powersave profiles, deploys logind.conf with lid-closes-suspend.

### ThinkPad — battery health with charge thresholds

```yaml
- role: power_management
  vars:
    power_management_tlp_bat0_charge_start: 40
    power_management_tlp_bat0_charge_stop: 80
```

Stops charging at 80%, resumes at 40%. Extends battery calendar lifespan by avoiding full charge cycles. Effective on ThinkPad X/T/L series; silently skipped on unsupported hardware.

### Laptop — lid close does nothing (clamshell mode with external monitor)

```yaml
- role: power_management
  vars:
    power_management_lid_switch_action: ignore
    power_management_lid_switch_ac_action: ignore
    power_management_lid_switch_docked_action: ignore
```

### Desktop — performance governor with service persistence

```yaml
- role: power_management
  vars:
    power_management_device_type: desktop
    power_management_cpu_governor: performance
    power_management_governor_persist: service   # systemd cpupower.service
```

### Desktop — developer workstation, schedutil + audit disabled

```yaml
- role: power_management
  vars:
    power_management_device_type: desktop
    power_management_cpu_governor: schedutil
    power_management_audit_enabled: false
    power_management_drift_detection: false
```

### Strict assertions off — for initial roll-out on unknown hardware

```yaml
- role: power_management
  vars:
    power_management_assert_strict: false
```

Post-deploy checks log warnings instead of failing. Useful when rolling out to a fleet where some hosts may have unsupported hardware (e.g. charge thresholds, missing swap for hibernate).

## Files deployed

| Path | Description |
|------|-------------|
| `/etc/tlp.conf` | TLP power management configuration (laptop only) |
| `/etc/systemd/logind.conf` | Lid switch, power key, and idle actions (systemd only) |
| `/etc/systemd/sleep.conf` | Suspend, hibernate, and hybrid-sleep modes (systemd only) |
| `/etc/udev/rules.d/50-cpu-governor.rules` | Persistent CPU governor on boot (desktop, `persist=udev`) |
| `/etc/systemd/system/cpupower.service.d/override.conf` | cpupower service override (desktop, `persist=service`) |
| `/usr/local/bin/power-audit.sh` | Daily audit script |
| `/etc/systemd/system/power-audit.service` | Audit oneshot unit (systemd) |
| `/etc/systemd/system/power-audit.timer` | Audit timer unit (systemd) |
| `/var/lib/ansible-power-management/last_state.json` | Drift detection state (mode 0600) |

## Exported facts

The role sets `power_management_status` with the actual system state after deploy:

```yaml
power_management_status:
  governor: schedutil           # actual governor read from /sys/
  is_laptop: false
  init_system: systemd
  tlp_active: "N/A"             # "enabled" | "N/A" (desktop)
  battery:
    capacity: "N/A"             # "87" (%) or "N/A"
    status: "N/A"               # "Discharging" | "Charging" | "Full" | "N/A"
    charge_start_threshold: "N/A"
    charge_stop_threshold: "N/A"
```

Use in subsequent roles or playbook tasks:

```yaml
- debug:
    msg: "Battery: {{ power_management_status.battery.capacity }}%"
  when: power_management_status.battery.capacity != 'N/A'
```

## Observability

### Query audit log

```bash
# All audit events from the last 7 days
journalctl -t power-audit --since "7 days ago"

# Battery warnings only
journalctl -t power-audit -g WARNING

# Last audit run
journalctl -t power-audit -n 30

# Run audit manually
systemctl start power-audit.service
```

### Drift detection state

```bash
cat /var/lib/ansible-power-management/last_state.json | python3 -m json.tool
```

### Alloy / Loki integration

The `power-audit` identifier is ready for Alloy's journald source without any changes to this role:

```river
loki.source.journal "power_audit" {
  matches = [{__journal_syslog_identifier = "power-audit"}]
  forward_to = [loki.write.default.receiver]
}
```

## Requirements

- Ansible 2.15+
- `become: true`
- `gather_facts: true`
- Supported OS: Arch Linux, Debian (and derivatives)
- Hibernate requires a swap partition or swap file. The role asserts this in preflight and fails with a clear message if swap is missing.

## Dependencies

None.

## License

MIT
