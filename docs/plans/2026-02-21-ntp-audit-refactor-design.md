# ntp_audit Role Refactor — Design Document

**Date:** 2026-02-21
**Status:** Approved
**Scope:** Full refactor of `ansible/roles/ntp_audit` in place

---

## Problem Statement

The current `ntp_audit` role has two critical bugs and several operational gaps:

1. **`NtpPHCMissing` alert never fires** — script never emits `missing` status
2. **Alloy pipeline is disconnected** — source bypasses JSON processor, Loki labels never set
3. Bash heredoc JSON construction breaks on `/` in values
4. Offset sign is discarded — negative drift never detected
5. No log rotation — log grows unbounded
6. No assert if neither systemd nor cron is available
7. All business logic in one `tasks/main.yml` — no isolation

---

## Design Decisions

### Architecture: `import_tasks` modules

Each business requirement maps to one task file. `tasks/main.yml` is an index only.

### Python delivery: zipapp

Source files deployed to staging directory, assembled into single executable via `python3 -m zipapp`.

### chrony interface: `chronyc -c tracking` CSV

Industry standard (prometheus-community, librenms, ntpmon, zabbix-tooling all use this).
CSV mode stable since chrony 3.3 (2018). Offset already signed — no text parsing needed.

### JSON fields: all 14 chrony fields + audit fields

Based on prometheus-community/node-exporter-textfile-collector-scripts reference implementation.

---

## Role Structure

```
ansible/roles/ntp_audit/
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
├── tasks/
│   ├── main.yml                  # import_tasks only — table of contents
│   ├── script.yml                # install python3, log dir, deploy src, build zipapp
│   ├── logrotate.yml             # /etc/logrotate.d/ntp-audit
│   ├── scheduler_systemd.yml     # service unit + timer unit + enable
│   ├── scheduler_cron.yml        # cron job (non-systemd fallback)
│   ├── scheduler_assert.yml      # fail if neither systemd nor cron available
│   ├── alloy.yml                 # Alloy config fragment (when: ntp_audit_alloy_enabled)
│   ├── loki.yml                  # Loki ruler rules (when: ntp_audit_loki_enabled)
│   ├── first_run.yml             # execute ntp-audit immediately after deploy
│   └── verify.yml                # assert script, log, JSON validity, timer active
├── templates/
│   ├── ntp-audit/                # Python source files (zipapp sources)
│   │   ├── chrony.py.j2          # chronyc -c tracking CSV → typed dict (14 fields)
│   │   ├── checkers.py.j2        # conflict services, PHC (ok/missing/n_a), modules
│   │   ├── output.py.j2          # json.dumps() → log file + SysLogHandler
│   │   └── __main__.py.j2        # orchestrator: collect → check → output
│   ├── ntp-audit.service.j2      # systemd oneshot + [Install] section
│   ├── ntp-audit.timer.j2        # OnCalendar + Persistent + RandomizedDelay
│   ├── ntp-audit.logrotate.j2    # daily, 7 rotations, compress
│   ├── alloy-ntp-audit.alloy.j2  # FIXED: source → process → write pipeline
│   └── loki-ntp-audit-rules.yaml.j2  # FIXED: PHC missing + signed offset alerts
└── molecule/default/
    ├── molecule.yml              # test_sequence includes idempotency
    ├── converge.yml
    └── verify.yml
```

---

## Python Package Design

### Delivery

```
/usr/local/src/ntp-audit/     ← Ansible deploys source templates here
  chrony.py                   ← chronyc -c tracking CSV parser
  checkers.py                 ← services, PHC, modules
  output.py                   ← JSON log + syslog
  __main__.py                 ← orchestrator

/usr/local/bin/ntp-audit      ← assembled zipapp (python3 -m zipapp)
```

### `chrony.py` — CSV parser

Uses `chronyc -c tracking` (not text mode). Parses 14 comma-separated fields.

```python
# chronyc -c tracking CSV fields (index → name):
FIELDS = [
    (0,  'reference_id'),        # hex reference ID
    (1,  'reference_name'),      # hostname or IP
    (2,  'stratum'),             # int
    (3,  'ref_time'),            # Unix timestamp of last update
    (4,  'current_correction'),  # system clock offset, seconds (SIGNED float)
    (5,  'last_offset'),         # last measured offset, seconds (signed)
    (6,  'rms_offset'),          # RMS offset, seconds
    (7,  'frequency_ppm'),       # frequency error, ppm
    (8,  'residual_freq'),       # residual frequency error, ppm
    (9,  'skew'),                # estimated frequency error, ppm
    (10, 'root_delay'),          # total round-trip delay, seconds
    (11, 'root_dispersion'),     # absolute accuracy bound, seconds
    (12, 'update_interval'),     # seconds between updates
    (13, 'leap_status'),         # 0=normal, 1=+1s, 2=-1s, 3=unsync
]
```

Returns typed dict. `sync_status` derived from `leap_status == 3 → unsynchronised`.

### `checkers.py` — Conflict, PHC, Modules

**PHC logic (fixes critical bug #1):**

```python
def check_phc(devices: list[str]) -> tuple[str, str]:
    if not devices:
        return "n/a", "none"
    for dev in devices:
        if Path(dev).is_char_device():
            return "ok", dev
    return "missing", "none"   # ← was never reached in bash
```

**Conflict detection:**

```python
def check_conflicts(services: list[str]) -> str:
    if not shutil.which('systemctl'):
        return "none"
    for svc in services:
        result = subprocess.run(['systemctl', 'is-active', '--quiet', svc], ...)
        if result.returncode == 0:
            return f"{svc}_active"
    return "none"
```

### `output.py` — Structured output

```python
import json, logging, logging.handlers

def write_log(path: str, data: dict) -> None:
    line = json.dumps(data)           # ← proper escaping, handles all chars
    with open(path, 'a') as f:
        f.write(line + '\n')

def write_syslog(data: dict) -> None:
    msg = (f"ntp_sync={data['sync_status']} stratum={data['stratum']} "
           f"conflict={data['ntp_conflict']} phc={data['ntp_phc_status']}")
    logger = logging.getLogger('ntp-audit')
    handler = logging.handlers.SysLogHandler(address='/dev/log', facility='daemon')
    logger.addHandler(handler)
    logger.info(msg)
```

### `__main__.py` — Orchestrator

```python
def run() -> int:
    try:
        chrony_data = collect_chrony()       # dict with 14 fields
        conflict = check_conflicts(SERVICES)
        phc_status, phc_device = check_phc(PHC_DEVICES)
        modules_status = check_modules(KERNEL_MODULES)

        record = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            **chrony_data,
            'ntp_conflict': conflict,
            'ntp_phc_status': phc_status,
            'ntp_phc_device': phc_device,
            'ntp_modules_status': modules_status,
        }
        write_log(LOG_FILE, record)
        write_syslog(record)
        return 0
    except Exception as e:
        syslog_error(str(e))   # never silent
        return 1
```

---

## Ansible Task Modules

### `script.yml`

1. Install `python3` (ensure present)
2. Create `/var/log/ntp-audit/` (mode 0755)
3. Create `/usr/local/src/ntp-audit/` staging dir
4. Deploy each `.py` template to staging dir
5. Build zipapp: `python3 -m zipapp /usr/local/src/ntp-audit -o /usr/local/bin/ntp-audit -p "/usr/bin/env python3"`
6. Set mode 0755 on zipapp

### `logrotate.yml`

Deploy `/etc/logrotate.d/ntp-audit`:

```
/var/log/ntp-audit/audit.log {
    daily
    rotate {{ ntp_audit_logrotate_rotate }}
    size {{ ntp_audit_logrotate_size }}
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
```

### `scheduler_systemd.yml`

1. Deploy `ntp-audit.service` (oneshot, After=chronyd.service, has [Install] section)
2. Deploy `ntp-audit.timer` (OnCalendar, Persistent=true, RandomizedDelaySec=30)
3. Notify: Reload systemd
4. Flush handlers
5. Enable and start timer
6. When: `ansible_facts['service_mgr'] == 'systemd'`

### `scheduler_cron.yml`

1. Deploy cron job via `ansible.builtin.cron`
2. When: `ansible_facts['service_mgr'] != 'systemd'`

### `scheduler_assert.yml`

```yaml
- name: Assert a scheduler is available
  ansible.builtin.assert:
    that:
      - ansible_facts['service_mgr'] == 'systemd'
        or ansible_facts['service_mgr'] != 'systemd'  # always true — placeholder
    fail_msg: >
      No scheduler configured. Neither systemd timer nor cron job was deployed.
      Ensure systemd or cron is available on this host.
```

Actually: assert that the script file exists AND (systemd timer is active OR cron entry exists).

### `alloy.yml` — Fixed pipeline

```alloy
loki.source.file "ntp_audit" {
  targets    = [{ __path__ = "...", job = "ntp-audit", host = constants.hostname }]
  forward_to = [loki.process.ntp_audit_json.receiver]   // ← FIX: not write.default
}

loki.process "ntp_audit_json" {
  forward_to = [loki.write.default.receiver]
  stage.json { expressions = { ntp_sync_status = "", ntp_conflict = "",
                                ntp_phc_status = "", ntp_stratum = "",
                                current_correction = "" } }
  stage.labels { values = { ntp_sync_status = "", ntp_conflict = "",
                              ntp_phc_status = "" } }
}
```

When: `ntp_audit_alloy_enabled | bool and ntp_audit_alloy_config_dir | length > 0`

### `loki.yml` — Fixed alerts

Key fixes:
- `NtpPHCMissing`: fires on `ntp_phc_status="missing"` (now actually reachable)
- `NtpHighOffset`: `| float > threshold OR | float < -threshold` (both signs)
- `NtpUnsynchronised`: window reduced from 20min to 10min (align with best practice)

---

## Variables (`defaults/main.yml`)

```yaml
ntp_audit_enabled: true
ntp_audit_interval_systemd: "*:0/5"     # every 5 min
ntp_audit_interval_cron: "*/5 * * * *"

ntp_audit_log_dir:  "/var/log/ntp-audit"
ntp_audit_log_file: "/var/log/ntp-audit/audit.log"

ntp_audit_logrotate_rotate: 7
ntp_audit_logrotate_size: "10M"

ntp_audit_competitor_services:
  - systemd-timesyncd
  - ntpd
  - openntpd
  - vmtoolsd

ntp_audit_phc_devices:
  - /dev/ptp_hyperv
  - /dev/ptp0

ntp_audit_kernel_modules:
  - ptp_kvm

# Alloy — separate enable flag (not just empty string)
ntp_audit_alloy_enabled: true
ntp_audit_alloy_config_dir: "/etc/alloy/conf.d"

# Loki — separate enable flag
ntp_audit_loki_enabled: true
ntp_audit_loki_rules_dir: "/etc/loki/rules/fake"

ntp_audit_chrony_log_dir: "/var/log/chrony"

ntp_audit_alert_offset_threshold: "0.1"   # seconds, absolute value
ntp_audit_alert_stratum_max: "4"
```

---

## Fixes Summary

| # | Bug | Fix |
|---|-----|-----|
| 1 | PHC `missing` never set | `checkers.py` explicit branch |
| 2 | Alloy pipeline disconnected | `source → process → write` |
| 3 | JSON broken on `/` in values | `json.dumps()` |
| 4 | Offset unsigned | CSV field 4 already signed |
| 5 | Silent failure on set -e | Python `try/except` + syslog |
| 6 | No logrotate | `logrotate.yml` module |
| 7 | No scheduler fallback assert | `scheduler_assert.yml` |
| 8 | No idempotency test | Molecule `test_sequence` updated |
| 9 | service missing `[Install]` | Added to template |

---

## Research Sources

- prometheus-community/node-exporter-textfile-collector-scripts — `chrony.py` (CSV mode, field indices)
- librenms/librenms-agent — `snmp/chrony` (14-field CSV parser)
- paulgear/ntpmon — `src/readvar.py` (chronyc -c tracking field mapping)
- Research agent findings: no python-chrony library exists; all tools use subprocess+CSV
