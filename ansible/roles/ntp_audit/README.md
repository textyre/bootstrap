# ntp_audit

Read-only NTP health auditing role. Deploys a scheduled Python audit script that queries `chronyc` and writes structured JSON logs for ingestion by Grafana Alloy and alerting via Loki ruler rules.

## What this role does

- [x] Deploys a Python zipapp (`/usr/local/bin/ntp-audit`) that calls `chronyc -c tracking` and parses CSV output
- [x] Writes structured JSON audit records to `/var/log/ntp-audit/audit.log` (one line per run)
- [x] Configures a **systemd timer** (primary) or **cron job** (non-systemd fallback) for scheduling
- [x] Deploys **logrotate** config for the audit log
- [x] Deploys a **Grafana Alloy** config fragment (optional, `ntp_audit_alloy_enabled`)
- [x] Deploys **Loki ruler alert rules** (optional, `ntp_audit_loki_enabled`)
- [x] Executes first run immediately on deploy and self-verifies the output
- [x] Detects competing time sync daemons (`systemd-timesyncd`, `ntpd`, `openntpd`, `vmtoolsd`) — reports **all** active conflicts in `ntp_conflict` field (comma-separated, e.g. `systemd-timesyncd_active,ntpd_active`)

This role is **audit-only** — it does NOT install or configure chrony. Requires chrony to be installed and running.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ntp_audit_enabled` | `true` | Enable/disable the entire role |
| `ntp_audit_interval_systemd` | `*:0/5` | Systemd timer schedule (every 5 min) |
| `ntp_audit_interval_cron` | `*/5 * * * *` | Cron schedule (non-systemd fallback) |
| `ntp_audit_log_dir` | `/var/log/ntp-audit` | Audit log directory |
| `ntp_audit_log_file` | `/var/log/ntp-audit/audit.log` | Audit log file path |
| `ntp_audit_logrotate_rotate` | `7` | Number of rotated logs to keep |
| `ntp_audit_logrotate_size` | `10M` | Rotate when log exceeds this size |
| `ntp_audit_competitor_services` | see defaults | Services to detect as NTP competitors |
| `ntp_audit_phc_devices` | `/dev/ptp_hyperv`, `/dev/ptp0` | PHC devices to check |
| `ntp_audit_kernel_modules` | `ptp_kvm` | Kernel modules to check for presence |
| `ntp_audit_alloy_enabled` | `true` | Deploy Grafana Alloy config fragment |
| `ntp_audit_alloy_config_dir` | `/etc/alloy/conf.d` | Alloy config directory |
| `ntp_audit_loki_enabled` | `true` | Deploy Loki ruler alert rules |
| `ntp_audit_loki_rules_dir` | `/etc/loki/rules/fake` | Loki rules directory |
| `ntp_audit_chrony_log_dir` | `/var/log/chrony` | Chrony log dir (for Alloy fragment) |
| `ntp_audit_alert_offset_threshold` | `0.1` | Alert when clock offset > N seconds |
| `ntp_audit_alert_stratum_max` | `4` | Alert when stratum exceeds this value |

## Tags

`ntp_audit` — wraps all tasks. Use `--skip-tags ntp_audit` to skip the role entirely.

## Dependencies

None declared. **Requires** chrony installed and running on the target host (handled by the playbook, not this role).

## Supported platforms

Arch Linux, Ubuntu, Debian, Fedora, Void Linux (any platform with chrony)

## Testing

Three molecule scenarios:

| Scenario | Driver | Platforms | Purpose |
|----------|--------|-----------|---------|
| `default` | localhost | Localhost | Quick local converge+verify; requires vault |
| `docker` | docker | Archlinux-systemd | Arch-only CI; systemd via cgroup |
| `disabled` | localhost | Localhost | Verifies `ntp_audit_enabled: false` skips all tasks |
| `vagrant` | vagrant/libvirt | Arch + Ubuntu 24.04 | Full cross-platform integration test |

Run the full cross-platform suite:

```bash
cd ansible/roles/ntp_audit
molecule test -s vagrant
```

Arch only first (faster feedback):

```bash
molecule test -s vagrant -- --limit arch-vm
```
