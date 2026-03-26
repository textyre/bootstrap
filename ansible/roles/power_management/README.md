# power_management

Manages CPU frequency, TLP power profiles, sleep modes, and lid/power button behaviour across laptops and desktops.

## Execution flow

1. **Assert OS** (`tasks/main.yml`) -- verifies `ansible_facts['os_family']` is in the supported list; fails immediately on unsupported OS
2. **Detect hardware** (`tasks/detect.yml`) -- reads DMI chassis type from `/sys/class/dmi/id/chassis_type`, CPU vendor from `/proc/cpuinfo`, init system from `ansible_facts['service_mgr']`. Sets `power_management_is_laptop`, `power_management_init`, CPU vendor facts.
3. **Pre-flight checks** (`tasks/preflight.yml`) -- asserts swap is active when hibernate is configured (reads `/proc/swaps`). Warns about SSH lockout if `idle_action` is `suspend`/`hibernate` over non-local connection.
4. **Disable conflicts** (`tasks/conflicts.yml`) -- stops and masks `power-profiles-daemon` (conflicts with TLP and manual governor) and `auto-cpufreq`. Skips gracefully if services not found. Systemd only.
5. **Install packages** (`tasks/install.yml`) -- loads OS-specific vars from `vars/<os_family>.yml`, installs base packages (`cpupower`) and laptop packages (`tlp`, `tlp-rdw`) via `ansible.builtin.package`. On Debian, tries kernel-versioned `linux-tools` first with `linux-cpupower` fallback. On Arch laptop, masks `systemd-rfkill`.
6. **Configure TLP** (`tasks/tlp.yml`) -- laptop only, gated by `power_management_manage_tlp`. Backs up existing `/etc/tlp.conf` (skip if already Ansible-managed), deploys template, verifies with `tlp-stat -c`. block/rescue restores backup on failure. **Triggers handler:** `restart tlp` on config change. Enables TLP service.
7. **Configure CPU governor** (`tasks/governor.yml`) -- desktop only, gated by `power_management_manage_governor`. Validates governor value, sets via `cpupower frequency-set`, persists via udev rule (`/etc/udev/rules.d/50-cpu-governor.rules`) or systemd service dropin. **Triggers handler:** `reload udev rules` on rule change.
8. **Configure sleep** (`tasks/sleep.yml`) -- systemd only, gated by `power_management_manage_sleep`. Deploys `/etc/systemd/sleep.conf` with `HibernateMode`, `SuspendState`, `HibernateDelaySec`.
9. **Configure logind** (`tasks/logind.yml`) -- systemd only, gated by `power_management_manage_logind`. Warns about SSH lockout, deploys `/etc/systemd/logind.conf` with lid switch, power key, and idle actions. **Triggers handler:** `reload systemd-logind` on config change.
10. **Collect facts** (`tasks/collect_facts.yml`) -- reads actual governor from `/sys/`, battery status, TLP status, charge thresholds. Assembles `power_management_status` fact dict.
11. **Assert effectiveness** (`tasks/assert.yml`) -- verifies TLP service active (laptop), PPD masked, governor matches config, `HibernateMode` in sleep.conf, `HandleLidSwitch` in logind.conf, charge thresholds applied. Controlled by `power_management_assert_strict`.
12. **Drift detection** (`tasks/drift_detection.yml`) -- compares current `power_management_status` against `/var/lib/ansible-power-management/last_state.json` from previous run. Emits `DRIFT DETECTED` warning on governor or TLP status change. Saves current state.
13. **Audit monitoring** (`tasks/audit.yml`) -- gated by `power_management_manage_audit`. Deploys `/usr/local/bin/power-audit.sh`, systemd service + timer (or cron fallback on non-systemd). Enables and starts timer.
14. **Report** (`tasks/main.yml`) -- writes structured execution report via `common/report_phase.yml` + `common/report_render.yml`.

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `restart tlp` | TLP config change (step 6) | Restarts TLP service. Only fires on laptops. |
| `reload systemd-logind` | logind.conf change (step 9) | Reloads systemd-logind to apply new config without session disruption. |
| `reload udev rules` | udev governor rule change (step 7) | Runs `udevadm control --reload-rules` to load new governor persistence rule. |

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
| `power_management_manage_tlp` | `true` | safe | Set `false` to skip TLP configuration (laptop). Other subsystems continue. |
| `power_management_manage_governor` | `true` | safe | Set `false` to skip CPU governor configuration (desktop) |
| `power_management_manage_sleep` | `true` | safe | Set `false` to skip sleep.conf deployment |
| `power_management_manage_logind` | `true` | safe | Set `false` to skip logind.conf deployment |
| `power_management_manage_audit` | `true` | safe | Set `false` to skip audit script and timer deployment |

#### TLP -- CPU

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_cpu_governor_ac` | `performance` | careful | CPU frequency governor on AC. Changing to `powersave` reduces performance on AC. |
| `power_management_tlp_cpu_governor_bat` | `powersave` | safe | CPU frequency governor on battery |
| `power_management_tlp_cpu_boost_ac` | `true` | safe | CPU turbo boost on AC |
| `power_management_tlp_cpu_boost_bat` | `false` | safe | CPU turbo boost on battery. `false` saves 30-40% battery. |
| `power_management_tlp_cpu_epp_ac` | `performance` | careful | Energy/performance preference on AC (Intel HWP, AMD EPP). Values: `performance`, `balance_performance`, `balance_power`, `power` |
| `power_management_tlp_cpu_epp_bat` | `power` | safe | Energy/performance preference on battery |
| `power_management_tlp_cpu_min_freq_ac` | `""` | internal | Minimum CPU frequency on AC (kHz). Empty = no limit. |
| `power_management_tlp_cpu_max_freq_bat` | `""` | internal | Maximum CPU frequency on battery (kHz). Empty = no limit. |

#### TLP -- Disk

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_disk_devices` | `""` | internal | Disk device names. Empty = auto-detect. |
| `power_management_tlp_disk_iosched` | `mq-deadline` | careful | I/O scheduler for rotational disks |
| `power_management_tlp_disk_apm_ac` | `254` | careful | Advanced Power Management level on AC. 1=max saving, 254=max performance, 255=disable |
| `power_management_tlp_disk_apm_bat` | `128` | careful | APM level on battery. 128 enables head parking. Disable (254) for media servers with constant disk access. |
| `power_management_tlp_sata_linkpwr_ac` | `max_performance` | careful | SATA link power on AC |
| `power_management_tlp_sata_linkpwr_bat` | `min_power` | careful | SATA link power on battery |

#### TLP -- USB, PCIe, WiFi, Sound, Runtime PM

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_usb_autosuspend` | `true` | careful | Suspend USB devices when idle. Set `false` for USB drives, gaming peripherals, audio interfaces. |
| `power_management_tlp_usb_allowlist` | `[]` | safe | USB device IDs excluded from autosuspend. Format: `["1234:5678"]` |
| `power_management_tlp_usb_denylist` | `[]` | safe | USB device IDs always suspended |
| `power_management_tlp_pcie_aspm_ac` | `default` | careful | PCIe Active State Power Management on AC |
| `power_management_tlp_pcie_aspm_bat` | `powersupersave` | safe | PCIe ASPM on battery |
| `power_management_tlp_wifi_pwr_ac` | `"off"` | safe | WiFi power saving on AC |
| `power_management_tlp_wifi_pwr_bat` | `"on"` | safe | WiFi power saving on battery |
| `power_management_tlp_sound_powersave_bat` | `true` | careful | HDA audio autosuspend on battery. Causes ~1s audio dropout on wake. Set `false` for audio production. |
| `power_management_tlp_sound_powersave_controller` | `true` | safe | HDA controller power save |
| `power_management_tlp_runtime_pm_ac` | `"on"` | safe | Runtime power management for PCI devices on AC |
| `power_management_tlp_runtime_pm_bat` | `auto` | safe | Runtime power management on battery |

#### TLP -- Battery charge thresholds

Only effective on ThinkPad, Dell, and hardware exposing `/sys/class/power_supply/BAT0/charge_control_*_threshold`. Leave empty to skip.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_tlp_bat0_charge_start` | `""` | careful | Start charging BAT0 below this %. Recommended: `40` |
| `power_management_tlp_bat0_charge_stop` | `""` | careful | Stop charging BAT0 at this %. Recommended: `80` |
| `power_management_tlp_bat1_charge_start` | `""` | careful | Same for BAT1 (dual-battery ThinkPads) |
| `power_management_tlp_bat1_charge_stop` | `""` | careful | |

#### CPU governor -- Desktop

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_cpu_governor` | `schedutil` | careful | Frequency governor. `schedutil` (kernel-native), `performance` (always max), `powersave` (always min) |
| `power_management_governor_persist` | `udev` | careful | Persistence method: `udev` (init-agnostic), `service` (systemd cpupower.service), `oneshot` (no reboot survival) |

#### Sleep

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_hibernate_mode` | `platform` | careful | `platform` (firmware-managed, safe), `shutdown`, `reboot`. `shutdown` risks data loss if battery drains while hibernated. |
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

#### Audit and monitoring

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_audit_enabled` | `true` | safe | Deploy audit script and schedule |
| `power_management_audit_schedule` | `daily` | safe | systemd `OnCalendar` value |
| `power_management_audit_battery` | `true` | safe | Include battery health check in audit |
| `power_management_audit_battery_wear_threshold` | `20` | safe | Battery wear % above which a `WARNING` is logged |
| `power_management_audit_cron_hour` | `"0"` | safe | Hour for cron fallback (non-systemd only) |
| `power_management_audit_cron_minute` | `"0"` | safe | Minute for cron fallback (non-systemd only) |

#### Drift detection

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_drift_detection` | `true` | safe | Compare state with previous run and warn on drift |
| `power_management_drift_state_dir` | `/var/lib/ansible-power-management` | internal | Directory for state file (mode 0700) |

#### Assertions

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `power_management_assert_strict` | `true` | careful | `true` fails the play on post-deploy check failure; `false` logs warnings and continues |

### Internal mappings (`vars/`)

Do not override via inventory. Edit these files directly only when adding platform or init system support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | Arch packages (`cpupower`, `tlp`), service names, rfkill mask list | Adding Arch-specific packages |
| `vars/debian.yml` | Debian packages (`linux-tools-common`, `tlp`), service names | Adding Debian-specific packages |
| `vars/redhat.yml` | Fedora packages (`kernel-tools`, `tlp`), service names | Stub -- when Fedora testing is available |
| `vars/void.yml` | Void packages (`cpupower`, `tlp`), service names | Stub -- when Void testing is available |
| `vars/gentoo.yml` | Gentoo packages (`sys-power/cpupower`, `app-laptop/tlp`), service names | Stub -- when Gentoo testing is available |
| `vars/environments.yml` | Service name per init system (`systemd`, `runit`, `openrc`, `s6`, `dinit`) | Adding init system support |

## Examples

### Laptop -- defaults (auto-detect)

```yaml
# In group_vars/laptops/power.yml or host_vars/<hostname>/power.yml:
- role: power_management
```

Auto-detects laptop via DMI chassis type. Installs TLP, sets performance/powersave profiles, deploys logind.conf.

### ThinkPad -- battery health with charge thresholds

```yaml
# In host_vars/thinkpad-x1/power.yml:
power_management_tlp_bat0_charge_start: 40
power_management_tlp_bat0_charge_stop: 80
```

Stops charging at 80%, resumes at 40%. Extends battery lifespan. Silently skipped on unsupported hardware.

### Desktop -- performance governor

```yaml
# In group_vars/desktops/power.yml:
power_management_device_type: desktop
power_management_cpu_governor: performance
power_management_governor_persist: service
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
power_management_tlp_disk_apm_bat: 192
power_management_tlp_sound_powersave_bat: false
power_management_idle_action: ignore
```

### Gaming on battery

```yaml
# In host_vars/gaming-laptop/power.yml:
power_management_tlp_cpu_boost_bat: true
power_management_tlp_cpu_governor_bat: performance
power_management_tlp_cpu_epp_bat: balance_performance
power_management_tlp_usb_autosuspend: false
power_management_tlp_sound_powersave_bat: false
power_management_tlp_runtime_pm_bat: "on"
```

### Headless server

```yaml
# In host_vars/server/power.yml:
power_management_device_type: desktop
power_management_cpu_governor: performance
power_management_power_key_action: ignore
power_management_manage_logind: true
power_management_audit_enabled: true
```

## Cross-platform details

| Aspect | Arch Linux | Debian / Ubuntu | Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|--------|------------|--------|
| cpupower package | `cpupower` | `linux-tools-common` + `linux-tools-$(uname -r)` (fallback: `linux-cpupower`) | `kernel-tools` | `cpupower` | `sys-power/cpupower` |
| TLP packages | `tlp`, `tlp-rdw` | `tlp`, `tlp-rdw` | `tlp`, `tlp-rdw` | `tlp` | `app-laptop/tlp` |
| rfkill masking | `systemd-rfkill.service` + `.socket` masked | Not needed | Not needed | Not needed | Not needed |
| Config path (TLP) | `/etc/tlp.conf` | `/etc/tlp.conf` | `/etc/tlp.conf` | `/etc/tlp.conf` | `/etc/tlp.conf` |
| Config path (logind) | `/etc/systemd/logind.conf` | `/etc/systemd/logind.conf` | `/etc/systemd/logind.conf` | N/A (no systemd) | N/A (no systemd) |

## Logs

### Log files

| Source | Path / Command | Contents | Rotation |
|--------|---------------|----------|----------|
| Audit script | `journalctl -t power-audit` | CPU governor, TLP status, battery health, conflicts, charge thresholds | System journal rotation |
| TLP | `journalctl -u tlp` | TLP start/stop, profile switch events | System journal rotation |
| systemd-logind | `journalctl -u systemd-logind` | Lid switch, power key, idle action events | System journal rotation |
| Drift state | `/var/lib/ansible-power-management/last_state.json` | JSON snapshot of `power_management_status` from last Ansible run | Overwritten each run |

### Reading the logs

- All audit events from last 7 days: `journalctl -t power-audit --since "7 days ago"`
- Battery warnings only: `journalctl -t power-audit -g WARNING`
- Last audit run: `journalctl -t power-audit -n 30`
- Run audit manually: `systemctl start power-audit.service`
- Current drift state: `cat /var/lib/ansible-power-management/last_state.json | python3 -m json.tool`

### Alloy / Loki integration

The `power-audit` syslog identifier is ready for Alloy's journald source:

```river
loki.source.journal "power_audit" {
  matches = [{__journal_syslog_identifier = "power-audit"}]
  forward_to = [loki.write.default.receiver]
}
```

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS not in supported list | Check `ansible_facts['os_family']`. Only Archlinux, Debian, RedHat, Void, Gentoo are supported. |
| TLP not starting after role apply | `systemctl status tlp` and `journalctl -u tlp -n 50` | Check `/etc/tlp.conf` syntax with `tlp-stat -c`. Look for invalid parameter names (TLP silently ignores them). |
| CPU governor reverts after reboot | `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` vs expected | Check persistence: `cat /etc/udev/rules.d/50-cpu-governor.rules` (udev) or `systemctl status cpupower` (service). Verify `power-profiles-daemon` is masked. |
| "Hibernate requires active swap" preflight failure | `cat /proc/swaps` shows only header | Enable a swap partition or swap file. Or change logind actions from `hibernate`/`hybrid-sleep` to `suspend`/`ignore`. |
| SSH session dies after role apply | `power_management_idle_action` is `suspend` or `hibernate` | Set `power_management_idle_action: ignore` for remotely managed systems. The role warns about this but does not block. |
| `DRIFT DETECTED` warning on every run | Governor or TLP status changes between runs | Check for conflicting services: `systemctl list-units --type=service \| grep -E 'power-profiles\|auto-cpufreq\|thermald'`. One of them overrides the governor after Ansible sets it. |
| Battery charge thresholds not applied | `cat /sys/class/power_supply/BAT0/charge_control_start_threshold` returns error or unexpected value | Hardware must support threshold control (ThinkPad, Dell). Run `tlp-stat -b` to check. Unsupported hardware silently ignores the setting. |
| Idempotence failure on TLP config | Template produces different output on second run | Check for `ansible_date_time` or other volatile values in template. The backup task uses epoch which may differ between runs. |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Logic correctness, idempotence, config deployment, service states |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic, services, or init tasks | Real systemd, real packages, Arch + Ubuntu matrix |
| Default (localhost) | `molecule test` | Fast iteration with full hardware access | Full hardware access, real cpufreq |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Packages | cpupower installed (Arch), linux-cpupower or linux-tools-common (Debian) | TEST-008 |
| Config files | sleep.conf, logind.conf deployed with correct content and permissions | TEST-008 |
| Services | TLP active (laptop), power-audit.timer enabled and active | TEST-008 |
| Udev rules | `50-cpu-governor.rules` contains expected governor (desktop) | TEST-008 |
| Permissions | Config files mode 0644, audit script mode 0755, drift dir mode 0700 | TEST-008 |
| Conflicts | power-profiles-daemon and auto-cpufreq masked or absent | TEST-008 |
| Drift state | State directory and JSON file with required keys and correct permissions | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `cpupower package not found` | Stale package cache in container | Rebuild: `molecule destroy && molecule test -s docker` |
| `power-profiles-daemon is not masked` | Service exists but conflicts task failed silently | Check container image has systemd properly initialized. Run `systemctl status power-profiles-daemon` in container. |
| Idempotence failure on TLP config | Template epoch-based backup creates different filename on each run | Expected for first-time deploy. Second run should show `changed=0` since backup is skipped for Ansible-managed configs. |
| `Assertion failed` with no details | Missing `fail_msg` in verify.yml assert | Add `fail_msg` with expected + actual values |
| Vagrant: `Python not found` | prepare.yml missing or Arch bootstrap skipped | Check `prepare.yml` has raw Python install (TEST-009) |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `power` | Entire role | Full apply: `ansible-playbook playbook.yml --tags power` |
| `power,detect` | Hardware and init system detection | Re-detect without reconfiguring |
| `power,preflight` | Pre-deploy safety checks | Verify swap and SSH safety only |
| `power,conflicts` | Conflicting service masking | Re-mask PPD/auto-cpufreq after package update |
| `power,install` | Package installation | Reinstall packages only |
| `power,tlp` | TLP configuration and service | Reconfigure TLP without touching governor or logind |
| `power,cpu` | CPU governor configuration | Change governor without TLP changes |
| `power,sleep` | systemd sleep.conf | Update hibernate/suspend modes |
| `power,logind` | logind.conf | Update lid/power/idle actions |
| `power,facts` | Collect system state | Read current state into `power_management_status` |
| `power,assert` | Post-deploy assertions | Verify all settings took effect |
| `power,drift` | Drift detection | Check and save drift state only |
| `power,audit` | Audit script and timer | Redeploy audit infrastructure |
| `report` | Structured execution report | Re-generate report: `ansible-playbook playbook.yml --tags report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with per-subsystem toggles | No -- override via inventory |
| `vars/archlinux.yml` | Arch package names and service mappings | Only when adding Arch-specific packages |
| `vars/debian.yml` | Debian package names and service mappings | Only when adding Debian-specific packages |
| `vars/redhat.yml` | Fedora package names (stub) | When Fedora testing is ready |
| `vars/void.yml` | Void package names (stub) | When Void testing is ready |
| `vars/gentoo.yml` | Gentoo package names (stub) | When Gentoo testing is ready |
| `vars/environments.yml` | Service name per init system | When adding init system support |
| `tasks/main.yml` | Execution flow orchestrator + structured report | When adding/removing steps |
| `tasks/detect.yml` | Hardware and init detection | When adding new hardware detection |
| `tasks/preflight.yml` | Pre-deploy safety assertions | When adding new safety checks |
| `tasks/conflicts.yml` | Conflicting service masking | When new conflicting services appear |
| `tasks/install.yml` | OS-dispatched package installation | When changing install logic |
| `tasks/tlp.yml` | TLP config with block/rescue rollback | When changing TLP deployment |
| `tasks/governor.yml` | CPU governor with udev/service persistence | When changing governor logic |
| `tasks/sleep.yml` | systemd sleep.conf deployment | Rarely |
| `tasks/logind.yml` | logind.conf deployment | Rarely |
| `tasks/collect_facts.yml` | System state fact collection | When adding new facts |
| `tasks/assert.yml` | Post-deploy effectiveness checks | When adding new assertions |
| `tasks/drift_detection.yml` | Drift comparison and state save | Rarely |
| `tasks/audit.yml` | Audit script and timer deployment | When changing audit logic |
| `templates/tlp.conf.j2` | TLP config template | When adding TLP parameters |
| `templates/logind.conf.j2` | logind.conf template | When adding logind directives |
| `templates/sleep.conf.j2` | sleep.conf template | When adding sleep parameters |
| `templates/50-cpu-governor.rules.j2` | udev governor rule template | Rarely |
| `templates/power-audit.sh.j2` | Audit script template | When adding audit checks |
| `templates/power-audit.service.j2` | Audit systemd service unit | Rarely |
| `templates/power-audit.timer.j2` | Audit systemd timer unit | Rarely |
| `handlers/main.yml` | Service restart/reload handlers | Rarely |
| `molecule/` | Test scenarios (default, docker, vagrant) | When changing test coverage |
| `meta/main.yml` | Galaxy metadata and platform list | When changing supported platforms |
