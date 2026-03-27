# ntp_audit

Read-only NTP health auditing role. Deploys a scheduled Python audit script that queries `chronyc` and writes structured JSON logs for ingestion by Grafana Alloy and alerting via Loki ruler rules.

## Execution flow

1. **Assert supported OS** (`tasks/main.yml:11`) — checks `ansible_facts['os_family']` against `_ntp_audit_supported_os` list; fails if OS not supported (Arch/Debian only)
2. **Deploy audit script** (`tasks/script.yml`) — creates `/usr/local/src/ntp-audit/` directory structure, deploys Python modules (`__main__.py`, `chrony.py`, `output.py`, `checkers.py`), builds zipapp via `python3 -m zipapp`, outputs to `/usr/local/bin/ntp-audit`. **Triggers handler:** if script changed, `Build ntp-audit zipapp` handler rebuilds the executable
3. **Configure log rotation** (`tasks/logrotate.yml`) — deploys `/etc/logrotate.d/ntp-audit` config with size-based rotation (`10M`) and retention (`7` logs)
4. **Configure systemd timer** (`tasks/scheduler_systemd.yml`) — deploys `/etc/systemd/system/ntp-audit.service` + `/etc/systemd/system/ntp-audit.timer`, enables both. **Triggers handler:** if service/timer changed, `Reload systemd` handler runs `systemctl daemon-reload`
5. **Configure cron fallback** (`tasks/scheduler_cron.yml`) — for non-systemd hosts: deploys `/etc/cron.d/ntp-audit` (skips if systemd detected)
6. **Assert scheduler active** (`tasks/scheduler_assert.yml`) — verifies either systemd timer or cron is enabled; fails if both missing
7. **Deploy Alloy config fragment** (`tasks/alloy.yml`) — if `ntp_audit_alloy_enabled: true`, deploys `/etc/alloy/conf.d/ntp-audit.alloy` (optional; requires Alloy to be installed separately)
8. **Deploy Loki alert rules** (`tasks/loki.yml`) — if `ntp_audit_loki_enabled: true`, deploys `/etc/loki/rules/fake/ntp-audit-rules.yaml` (optional; requires Loki ruler to be configured separately)
9. **Execute first run** (`tasks/first_run.yml`) — runs `/usr/local/bin/ntp-audit` immediately to validate installation and populate `/var/log/ntp-audit/audit.log` with first record
10. **Verify deployment** (`tasks/verify.yml`) — checks: script exists and executable, log file exists and non-empty, JSON record contains required keys, **`sync_status != 'error'`** (critical: catches chrony not installed or unreachable), systemd timer enabled/active (if systemd)

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `Reload systemd` | Service/timer file change (step 4) | Runs `systemctl daemon-reload` before verification (step 10). **Only fires on systemd hosts** (`when: ansible_facts['service_mgr'] == 'systemd'`). |
| `Build ntp-audit zipapp` | Script module change (step 2) | Rebuilds `/usr/local/bin/ntp-audit` zipapp. Flushed before first run (step 9). |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ntp_audit_enabled` | `true` | safe | Set `false` to skip this role entirely |
| `ntp_audit_interval_systemd` | `*:0/5` | careful | Systemd timer schedule (systemd.time format). `*:0/5` = every 5 min. Changing affects audit frequency — critical infrastructure may need tighter intervals |
| `ntp_audit_interval_cron` | `*/5 * * * *` | careful | Cron schedule (crontab format). Changing affects audit frequency |
| `ntp_audit_log_dir` | `/var/log/ntp-audit` | internal | Audit log directory. Changing breaks downstream Alloy/Loki paths — only change if also updating Alloy/Loki configs |
| `ntp_audit_log_file` | `/var/log/ntp-audit/audit.log` | internal | Audit log file path. Changing breaks downstream log ingestion |
| `ntp_audit_logrotate_rotate` | `7` | safe | Number of rotated logs to keep. Higher = more disk usage. Lower = less historical data |
| `ntp_audit_logrotate_size` | `10M` | safe | Rotate when log exceeds this size. Tune based on `ntp_audit_interval_systemd` and expected log line size (~300 bytes) |
| `ntp_audit_competitor_services` | `[systemd-timesyncd, ntpd, openntpd, vmtoolsd]` | safe | List of services to detect as NTP competitors. Extend if you have other time-sync daemons |
| `ntp_audit_phc_devices` | `[/dev/ptp_hyperv, /dev/ptp0]` | safe | PHC (Precision Time Protocol) devices to check for presence. List of paths to stat; role reports first found or 'absent' |
| `ntp_audit_kernel_modules` | `[ptp_kvm]` | safe | Kernel modules to check for presence. Role reports 'present' if any listed module is loaded, 'absent' otherwise |
| `ntp_audit_alloy_enabled` | `true` | safe | Deploy Grafana Alloy config fragment. Set `false` if Alloy not in use or you want to manage its config manually |
| `ntp_audit_alloy_config_dir` | `/etc/alloy/conf.d` | internal | Alloy config directory. Only change if your Alloy `config.alloy` scans a different directory |
| `ntp_audit_loki_enabled` | `true` | safe | Deploy Loki ruler alert rules. Set `false` if Loki not in use or you want to manage rules manually |
| `ntp_audit_loki_rules_dir` | `/etc/loki/rules/fake` | internal | Loki rules directory. Only change if your Loki is configured to scan a different directory |
| `ntp_audit_chrony_log_dir` | `/var/log/chrony` | internal | Chrony log directory (used by Alloy config fragment). Only change if chrony configured to write logs elsewhere |
| `ntp_audit_alert_offset_threshold` | `0.1` | careful | Alert when clock offset exceeds this value (seconds). Tune based on SLA requirements; too high = missed issues, too low = false alarms |
| `ntp_audit_alert_stratum_max` | `4` | careful | Alert when stratum exceeds this value. Stratum 1 = primary source, 4 = typical max for working sync. Higher = degraded source |

### Internal mappings (`vars/`)

| File | What it contains | When to edit |
|------|-----------------|-------------|
| None (no `vars/` files) | — | — |

## Examples

### Increasing audit frequency for high-availability clusters

```yaml
# In group_vars/ha-cluster/ntp_audit.yml:
ntp_audit_interval_systemd: "*:0/1"  # Every minute instead of every 5 minutes
ntp_audit_interval_cron: "* * * * *"  # Every minute cron equivalent
ntp_audit_alert_offset_threshold: "0.05"  # Alert on offset > 50ms (strict)
```

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/ntp_audit.yml:
ntp_audit_enabled: false
```

### Disabling Loki alerting but keeping Alloy ingestion

```yaml
# In group_vars/ntp-audit/ntp_audit.yml:
ntp_audit_loki_enabled: false
ntp_audit_alloy_enabled: true
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian |
|--------|-----------|-----------------|
| OS family | `Archlinux` | `Debian` |
| Scheduler (primary) | systemd timer: `/etc/systemd/system/ntp-audit.timer` | systemd timer: `/etc/systemd/system/ntp-audit.timer` |
| Scheduler (fallback) | cron: `/etc/cron.d/ntp-audit` | cron: `/etc/cron.d/ntp-audit` |
| Python version | Python 3.x (zipapp) | Python 3.x (zipapp) |
| Audit log path | `/var/log/ntp-audit/audit.log` | `/var/log/ntp-audit/audit.log` |

## Logs

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| audit.log | `/var/log/ntp-audit/audit.log` | One JSON record per run: timestamp, chrony metrics (stratum, offset, sync status), conflict detection, PHC/module status | logrotate: size-based (`10M`) + retention (`7` files) |

### Reading the logs

- **Last audit run (human readable)**:
  ```bash
  tail -1 /var/log/ntp-audit/audit.log | jq .
  ```

- **Check sync status**:
  ```bash
  tail -1 /var/log/ntp-audit/audit.log | jq '.sync_status'
  # Output: "synced", "unsynced", "making_steps", or "error"
  ```

- **Check for service conflicts**:
  ```bash
  grep -E '"ntp_conflict"\s*:\s*"[^"]*_active' /var/log/ntp-audit/audit.log
  # Output: conflicts like systemd-timesyncd_active, ntpd_active
  ```

- **Search for high clock offsets**:
  ```bash
  jq -r 'select(.last_offset > 0.1 or .last_offset < -0.1) | "\(.timestamp): offset=\(.last_offset)s"' /var/log/ntp-audit/audit.log
  ```

- **Syslog entries**:
  ```bash
  journalctl -u ntp-audit.service -u ntp-audit.timer -n 50
  ```

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Deployment passes but `sync_status: 'error'` in log | chrony not installed or not running, or `/var/run/chrony.sock` not accessible | `systemctl status chrony` — if not running, `systemctl start chrony`. If socket permission denied, check chrony user has read access |
| Script hangs after deploy | `chronyc` taking too long to respond (usually first connect on slow systems) | Normal on first run; script has internal 5s timeout. If it persists: `chronyc -c tracking` locally; if that hangs, chrony is unresponsive |
| Audit log not created | First run failed silently, or role disabled | Check `ntp_audit_enabled: true` and run `ansible-playbook ... --tags ntp_audit` to retry |
| Timer not firing (systemd hosts) | Timer disabled or not active | `systemctl status ntp-audit.timer` — if inactive, `systemctl enable --now ntp-audit.timer`; if disabled, `systemctl enable ntp-audit.timer && systemctl start ntp-audit.timer` |
| High offset alerts for all records | Clock actually drifting (common in VMs or when chrony was just started) | Normal during initial sync (first 60s); if persistent, check NTP source via `chronyc sources` — if all `^?`, no servers reachable |
| Cron job not running (non-systemd hosts) | cron daemon not running, or `/etc/cron.d/ntp-audit` not deployed | `systemctl status cron` or `systemctl status crond` (distro-dependent); if not running, `systemctl enable --now cron` |
| `ansible-playbook` reports permission denied on `/var/run/chrony.sock` | chrony socket belongs to `chrony` user, script runs as root but can't stat socket (rare edge case) | Check: `ls -la /var/run/chrony.sock`; typically script should be able to stat it. If permission denied, ensure chrony service configured with world-readable socket |

## Testing

### Running tests

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `cd ansible/roles/ntp_audit && molecule test` | After changing variables, script modules, or task logic | Logic correctness, idempotence, config deployment, first run + verify on Arch + Ubuntu |
| Vagrant (cross-platform) | `cd ansible/roles/ntp_audit && molecule test -s vagrant` | After changing OS-specific logic, scheduler config, or service management | Real systemd timer/cron, real packages, full Arch + Ubuntu matrix, real chrony integration |

### Success criteria

- **Molecule output**: All steps complete: `syntax → create → converge → idempotence → verify → destroy`
- **Idempotence**: Second run shows `changed=0` for all tasks (no spurious changes)
- **Verify step**: All assertions pass; no `failed` assertions
- **Final line**: Task summary shows `failed=0`

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Script deployment | `/usr/local/bin/ntp-audit` exists and executable | Verify step: `stat /usr/local/bin/ntp-audit` |
| Log directory | `/var/log/ntp-audit/` exists with correct ownership | Verify step: `stat /var/log/ntp-audit/` |
| Log file | First run populates `/var/log/ntp-audit/audit.log` with valid JSON | Verify step: `tail -1 audit.log \| jq .` succeeds |
| JSON schema | Record contains required keys: `timestamp`, `sync_status`, `stratum`, `ntp_conflict`, `ntp_phc_status` | Verify step: assert all keys present |
| Sync status validation | `sync_status != 'error'` after first run | Verify step: assert sync succeeds (chrony must be installed) |
| Scheduler | systemd timer enabled + active (systemd) OR cron job deployed (non-systemd) | Verify step: `systemctl is-enabled ntp-audit.timer` or `grep ntp-audit /etc/cron.d/` |
| Logrotate | `/etc/logrotate.d/ntp-audit` deployed with correct size limit | Verify step: `grep ntp-audit.log /etc/logrotate.d/ntp-audit` |
| Idempotence | Second converge run produces no changes | Idempotence step: all tasks `ok` with `changed=0` |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `"failed": true` in verify step: `sync_status is 'error'` | chrony not installed or not running in container | Docker images must have chrony installed. Check: `molecule create && docker exec <container> systemctl status chrony` |
| Idempotence failure: task changed on second run | Script rebuild triggered twice, or handler not flushed | Normal if script modules changed. Verify handlers section in verify output shows handler ran exactly once |
| `systemctl is-enabled ntp-audit.timer` fails on Vagrant Arch | Vagrant provisioning issue with systemd caching | Full `molecule destroy && molecule test` required; partial test runs may see stale state |
| `chronyc: command not found` in verify | chrony package not installed in base image | Verify base image has chrony: check `Dockerfile.archlinux` / `Dockerfile.ubuntu` in image repo or molecule prepare.yml |
| Vagrant: `Python not found` during converge | prepare.yml missing or Arch bootstrap skipped | Check `ansible/roles/ntp_audit/molecule/vagrant/prepare.yml` has raw Python install before gather_facts |
| JSON parse error: `jq: parse error` | Log file corrupted or script exited mid-write | Check disk space: `df -h /var/log/ntp-audit/`. If full, logrotate should clean up next run |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `ntp_audit` | Entire role (all tasks) | Full audit role apply |
| `ntp_audit_script` | Script deploy only (`tasks/script.yml`) | Rebuild/redeploy script without reconfiguring scheduler |
| `ntp_audit_verify` | Verification only (`tasks/verify.yml`) | Re-run post-deploy checks without redeploying files |

**Example:**
```bash
# Re-run verification only
ansible-playbook playbook.yml --tags ntp_audit_verify

# Skip entire role
ansible-playbook playbook.yml --skip-tags ntp_audit
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No — override via inventory |
| `tasks/main.yml` | Execution flow orchestrator (preflight, imports, handlers flush) | Only when adding/removing major steps |
| `tasks/script.yml` | Script deployment: Python module templating + zipapp build | When changing script structure or build process |
| `tasks/logrotate.yml` | Logrotate config deployment | When changing rotation policy |
| `tasks/scheduler_systemd.yml` | Systemd timer + service deployment | When changing timer schedule or service config |
| `tasks/scheduler_cron.yml` | Cron fallback for non-systemd hosts | When changing cron schedule or path |
| `tasks/scheduler_assert.yml` | Validate scheduler is active (systemd or cron) | Rarely — only if assertion logic needs adjustment |
| `tasks/alloy.yml` | Grafana Alloy fragment deployment | When changing Alloy config structure or log parsing |
| `tasks/loki.yml` | Loki ruler alert rules deployment | When changing alert rules or thresholds |
| `tasks/first_run.yml` | Execute audit script immediately after deploy | Rarely — only if first-run behavior needs change |
| `tasks/verify.yml` | Post-deploy self-check: script exists, log valid, sync_status not error | When changing verification logic or assertions |
| `handlers/main.yml` | Service restart + script rebuild handlers | Rarely — only if handler logic needs adjustment |
| `templates/ntp-audit/` | Python script modules: `__main__.py`, `chrony.py`, `output.py`, `checkers.py` | When changing audit logic, JSON schema, or chronyc parsing |
| `templates/ntp-audit.service.j2` | Systemd service unit | When changing service config or dependencies |
| `templates/ntp-audit.timer.j2` | Systemd timer unit | When changing timer schedule format |
| `templates/ntp-audit.logrotate.j2` | Logrotate config | When changing rotation size/count |
| `templates/alloy-ntp-audit.alloy.j2` | Grafana Alloy config fragment | When changing log parsing or label extraction |
| `templates/loki-ntp-audit-rules.yaml.j2` | Loki ruler alert rules | When changing alert conditions or thresholds |
| `molecule/default/molecule.yml` | Docker test scenario (fast feedback) | Only when adding/removing test platforms |
| `molecule/vagrant/molecule.yml` | Vagrant test scenario (cross-platform) | Only when adding/removing test platforms |
| `molecule/shared/` | Shared test playbooks (converge, verify) | When changing test logic or verification |

---

## Dependencies

**Requires:**
- `chrony` — NTP daemon, must be installed and running before this role runs
- `logrotate` — for audit log rotation (usually pre-installed)

**Optional:**
- `grafana-alloy` — for log ingestion (set `ntp_audit_alloy_enabled: false` if not in use)
- `loki` with ruler — for alerting (set `ntp_audit_loki_enabled: false` if not in use)

**Not required:**
- The role does not install or configure chrony itself — that is handled by the `ntp` role or external configuration

## Supported platforms

Arch Linux, Debian, Ubuntu (OS families: `Archlinux`, `Debian`)

Both systemd-based. For non-systemd hosts (Void, Alpine, etc.), the role fails during preflight OS assertion (ROLE-003).
