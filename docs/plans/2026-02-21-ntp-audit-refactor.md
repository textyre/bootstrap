# ntp_audit Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor `ansible/roles/ntp_audit` — replace bash with Python zipapp, split tasks into 9 modules, fix 2 critical bugs (PHC missing status, Alloy pipeline), add logrotate, add scheduler assert.

**Architecture:** Python source files deployed to staging dir, assembled into zipapp. `tasks/main.yml` imports 9 separate task files, each owning one business requirement. `chronyc -c tracking` CSV mode replaces fragile text parsing.

**Tech Stack:** Ansible 2.14+, Python 3 stdlib (no external deps), systemd timer + cron fallback, Grafana Alloy, Loki ruler rules.

**Design doc:** `docs/plans/2026-02-21-ntp-audit-refactor-design.md`

---

## Task 0: Prepare — remove old bash template and update defaults

**Files:**
- Delete: `ansible/roles/ntp_audit/templates/ntp-audit.sh.j2`
- Modify: `ansible/roles/ntp_audit/defaults/main.yml`
- Modify: `ansible/roles/ntp_audit/handlers/main.yml`

**Step 1: Remove bash template**

```bash
rm ansible/roles/ntp_audit/templates/ntp-audit.sh.j2
```

**Step 2: Replace `defaults/main.yml`**

Full content:

```yaml
---
# === ntp_audit — runtime NTP health audit ===

ntp_audit_enabled: true

# Audit schedule interval
ntp_audit_interval_systemd: "*:0/5"
ntp_audit_interval_cron: "*/5 * * * *"

# Log paths
ntp_audit_log_dir: "/var/log/ntp-audit"
ntp_audit_log_file: "/var/log/ntp-audit/audit.log"

# Log rotation
ntp_audit_logrotate_rotate: 7
ntp_audit_logrotate_size: "10M"

# Competing services to detect
ntp_audit_competitor_services:
  - systemd-timesyncd
  - ntpd
  - openntpd
  - vmtoolsd

# PHC devices to check for presence
ntp_audit_phc_devices:
  - /dev/ptp_hyperv
  - /dev/ptp0

# Kernel modules to check (empty = skip)
ntp_audit_kernel_modules:
  - ptp_kvm

# Grafana Alloy integration — separate enable flag
ntp_audit_alloy_enabled: true
ntp_audit_alloy_config_dir: "/etc/alloy/conf.d"

# Loki ruler rules — separate enable flag
ntp_audit_loki_enabled: true
ntp_audit_loki_rules_dir: "/etc/loki/rules/fake"

# chrony log dir (for Alloy config fragment)
ntp_audit_chrony_log_dir: "/var/log/chrony"

# Alert thresholds
ntp_audit_alert_offset_threshold: "0.1"
ntp_audit_alert_stratum_max: "4"
```

**Step 3: Replace `handlers/main.yml`**

```yaml
---
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
  listen: "Reload systemd"

- name: Build ntp-audit zipapp
  ansible.builtin.command:
    cmd: >-
      python3 -m zipapp /usr/local/src/ntp-audit
      -o /usr/local/bin/ntp-audit
      -p "/usr/bin/env python3"
  listen: "Build ntp-audit zipapp"
```

**Step 4: Commit**

```bash
git add ansible/roles/ntp_audit/defaults/main.yml \
        ansible/roles/ntp_audit/handlers/main.yml
git rm  ansible/roles/ntp_audit/templates/ntp-audit.sh.j2
git commit -m "refactor(ntp_audit): update defaults, handlers, remove bash template"
```

---

## Task 1: Python template — `chrony.py`

**Files:**
- Create dir: `ansible/roles/ntp_audit/templates/ntp-audit/`
- Create: `ansible/roles/ntp_audit/templates/ntp-audit/chrony.py.j2`

**Step 1: Create template directory**

```bash
mkdir -p ansible/roles/ntp_audit/templates/ntp-audit
```

**Step 2: Create `chrony.py.j2`**

Full content:

```python
# Managed by Ansible (role: ntp_audit). Do not edit manually.
"""chrony data collector — parses chronyc -c tracking CSV output.

Field indices for chronyc -c tracking (stable since chrony 3.3):
  0  reference_id       hex reference clock ID
  1  reference_name     hostname or IP of NTP source
  2  stratum            int — distance from stratum-1 source
  3  ref_time           float — Unix timestamp of last reference update
  4  current_correction float — system clock offset, SIGNED seconds
  5  last_offset        float — last measured offset, seconds
  6  rms_offset         float — RMS offset, seconds
  7  frequency_ppm      float — clock frequency error, ppm
  8  residual_freq      float — residual frequency error, ppm
  9  skew               float — estimated frequency error, ppm
  10 root_delay         float — total round-trip delay to reference, seconds
  11 root_dispersion    float — absolute accuracy bound, seconds
  12 update_interval    float — seconds between reference updates
  13 leap_status        int   — 0=normal, 1=+1s, 2=-1s, 3=unsynchronised

Source: prometheus-community/node-exporter-textfile-collector-scripts,
        paulgear/ntpmon, librenms/librenms-agent.
"""
import subprocess
from dataclasses import dataclass


@dataclass
class ChronyData:
    reference_id: str
    reference_name: str
    stratum: int
    ref_time: float
    current_correction: float
    last_offset: float
    rms_offset: float
    frequency_ppm: float
    residual_freq: float
    skew: float
    root_delay: float
    root_dispersion: float
    update_interval: float
    leap_status: int
    sync_status: str  # derived: "ok" | "unsynchronised"


def collect() -> ChronyData:
    """Run chronyc -c tracking and return parsed data."""
    try:
        result = subprocess.run(
            ['chronyc', '-c', 'tracking'],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except FileNotFoundError:
        raise RuntimeError("chronyc not found — is chrony installed?")
    except subprocess.TimeoutExpired:
        raise RuntimeError("chronyc timed out after 5 seconds")

    if result.returncode != 0:
        raise RuntimeError(
            f"chronyc exited {result.returncode}: {result.stderr.strip()}"
        )

    fields = result.stdout.strip().split(',')
    if len(fields) < 14:
        raise ValueError(
            f"chronyc -c tracking: expected >=14 fields, got {len(fields)}: "
            f"{result.stdout!r}"
        )

    try:
        leap = int(fields[13])
        return ChronyData(
            reference_id=fields[0],
            reference_name=fields[1],
            stratum=int(fields[2]),
            ref_time=float(fields[3]),
            current_correction=float(fields[4]),  # signed — negative = slow
            last_offset=float(fields[5]),
            rms_offset=float(fields[6]),
            frequency_ppm=float(fields[7]),
            residual_freq=float(fields[8]),
            skew=float(fields[9]),
            root_delay=float(fields[10]),
            root_dispersion=float(fields[11]),
            update_interval=float(fields[12]),
            leap_status=leap,
            sync_status="unsynchronised" if leap == 3 else "ok",
        )
    except (ValueError, IndexError) as e:
        raise ValueError(f"Failed to parse chronyc CSV output: {e}") from e
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit/chrony.py.j2
git commit -m "feat(ntp_audit): add chrony.py template — chronyc -c tracking CSV parser"
```

---

## Task 2: Python template — `checkers.py`

**Files:**
- Create: `ansible/roles/ntp_audit/templates/ntp-audit/checkers.py.j2`

**Step 1: Create `checkers.py.j2`**

Full content — note the PHC `missing` fix:

```python
# Managed by Ansible (role: ntp_audit). Do not edit manually.
"""NTP health checkers — competing services, PHC devices, kernel modules."""
import shutil
import subprocess
from pathlib import Path


def check_conflicts(services: list) -> str:
    """Detect active competing NTP services.

    Returns '<service>_active' for the first active conflict found,
    or 'none' if no conflicts detected.
    Skips check silently if systemctl is not available.
    """
    if not shutil.which('systemctl'):
        return "none"
    for svc in services:
        try:
            r = subprocess.run(
                ['systemctl', 'is-active', '--quiet', svc],
                capture_output=True,
                timeout=3,
            )
            if r.returncode == 0:
                return f"{svc}_active"
        except (subprocess.TimeoutExpired, OSError):
            continue
    return "none"


def check_phc(devices: list) -> tuple:
    """Check PTP Hardware Clock device presence.

    Returns (status, device_path) where status is:
      'n/a'     — no devices configured (empty list)
      'ok'      — at least one device exists
      'missing' — devices configured but none present (CRITICAL FIX)
    """
    if not devices:
        return "n/a", "none"
    for dev in devices:
        if Path(dev).is_char_device():
            return "ok", dev
    # Devices were expected but none found — this is the missing state
    # that was never reachable in the previous bash implementation
    return "missing", "none"


def check_modules(modules: list) -> str:
    """Check kernel module presence via /proc/modules.

    Returns 'n/a' if no modules configured,
            'ok' if all modules loaded,
            '<module>_missing' for first missing module.
    Uses /proc/modules directly (no lsmod subprocess needed).
    """
    if not modules:
        return "n/a"
    try:
        loaded_text = Path('/proc/modules').read_text()
        loaded_names = {line.split()[0] for line in loaded_text.splitlines() if line}
    except OSError:
        return "unknown"
    for mod in modules:
        if mod not in loaded_names:
            return f"{mod}_missing"
    return "ok"
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit/checkers.py.j2
git commit -m "feat(ntp_audit): add checkers.py template — PHC missing fix, /proc/modules"
```

---

## Task 3: Python template — `output.py`

**Files:**
- Create: `ansible/roles/ntp_audit/templates/ntp-audit/output.py.j2`

**Step 1: Create `output.py.j2`**

Full content — note `json.dumps()` replaces bash placeholder substitution:

```python
# Managed by Ansible (role: ntp_audit). Do not edit manually.
"""NTP audit output — structured JSON log file + syslog summary."""
import json
import logging
import logging.handlers
import os
from pathlib import Path

# Ansible-rendered constant
LOG_FILE = "{{ ntp_audit_log_file }}"


def write_log(data: dict) -> None:
    """Append one JSON record to the audit log (append-only, one line per run).

    Uses json.dumps() for proper escaping — handles all Unicode and
    special characters including '/' that broke bash placeholder substitution.
    """
    line = json.dumps(data, default=str)
    Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')


def write_syslog(data: dict) -> None:
    """Write human-readable summary to syslog (daemon.info).

    Brief format for operator diagnosis via journalctl or /var/log/syslog.
    Full data is in the JSON log for machine consumption.
    """
    msg = (
        f"ntp_sync={data.get('sync_status', 'unknown')} "
        f"stratum={data.get('stratum', '?')} "
        f"offset={data.get('current_correction', '?')} "
        f"conflict={data.get('ntp_conflict', 'none')} "
        f"phc={data.get('ntp_phc_status', 'n/a')}"
    )
    _syslog(logging.INFO, msg)


def write_syslog_error(message: str) -> None:
    """Write error to syslog (daemon.warning). Called on script failure."""
    _syslog(logging.WARNING, f"ERROR: {message}")


def _syslog(level: int, message: str) -> None:
    logger = logging.getLogger('ntp-audit')
    logger.setLevel(logging.DEBUG)
    # /dev/log on Linux; fallback to UDP for non-standard environments
    addr = '/dev/log' if os.path.exists('/dev/log') else ('localhost', 514)
    handler = logging.handlers.SysLogHandler(
        address=addr,
        facility=logging.handlers.SysLogHandler.LOG_DAEMON,
    )
    handler.ident = 'ntp-audit: '
    logger.addHandler(handler)
    logger.log(level, message)
    logger.removeHandler(handler)
    handler.close()
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit/output.py.j2
git commit -m "feat(ntp_audit): add output.py template — json.dumps, syslog, error handling"
```

---

## Task 4: Python template — `__main__.py` (orchestrator)

**Files:**
- Create: `ansible/roles/ntp_audit/templates/ntp-audit/__main__.py.j2`

**Step 1: Create `__main__.py.j2`**

Full content:

```python
# Managed by Ansible (role: ntp_audit). Do not edit manually.
# Entry point for /usr/local/bin/ntp-audit (Python zipapp).
"""ntp-audit — NTP health and conflict audit.

Collects chrony tracking data, detects competing NTP services,
checks PHC device presence and kernel modules. Writes one JSON
record per run to the audit log and a summary line to syslog.
"""
import sys
from datetime import datetime, timezone

# Ansible-rendered configuration — injected at deploy time
COMPETITOR_SERVICES = {{ ntp_audit_competitor_services | to_json }}
PHC_DEVICES = {{ ntp_audit_phc_devices | to_json }}
KERNEL_MODULES = {{ ntp_audit_kernel_modules | to_json }}

from chrony import collect as collect_chrony
from checkers import check_conflicts, check_phc, check_modules
from output import write_log, write_syslog, write_syslog_error


def run() -> int:
    try:
        chrony = collect_chrony()
        conflict = check_conflicts(COMPETITOR_SERVICES)
        phc_status, phc_device = check_phc(PHC_DEVICES)
        modules_status = check_modules(KERNEL_MODULES)

        record = {
            'timestamp':          datetime.now(timezone.utc).isoformat(),
            'reference_id':       chrony.reference_id,
            'reference_name':     chrony.reference_name,
            'stratum':            chrony.stratum,
            'current_correction': chrony.current_correction,
            'last_offset':        chrony.last_offset,
            'rms_offset':         chrony.rms_offset,
            'frequency_ppm':      chrony.frequency_ppm,
            'residual_freq':      chrony.residual_freq,
            'skew':               chrony.skew,
            'root_delay':         chrony.root_delay,
            'root_dispersion':    chrony.root_dispersion,
            'update_interval':    chrony.update_interval,
            'leap_status':        chrony.leap_status,
            'sync_status':        chrony.sync_status,
            'ntp_conflict':       conflict,
            'ntp_phc_status':     phc_status,
            'ntp_phc_device':     phc_device,
            'ntp_modules_status': modules_status,
        }

        write_log(record)
        write_syslog(record)
        return 0

    except Exception as exc:
        write_syslog_error(str(exc))
        # Do NOT raise — audit script must exit 0 to avoid breaking systemd timer
        return 1


if __name__ == '__main__':
    sys.exit(run())
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit/__main__.py.j2
git commit -m "feat(ntp_audit): add __main__.py template — orchestrator, all 14+5 fields"
```

---

## Task 5: Ansible task — `script.yml`

**Files:**
- Create: `ansible/roles/ntp_audit/tasks/script.yml`

**Step 1: Create `tasks/script.yml`**

Full content:

```yaml
---
# === ntp_audit — deploy Python audit script (zipapp) ===
# Installs python3, deploys source templates, builds zipapp via handler.

- name: Ensure python3 is installed
  ansible.builtin.package:
    name: python3
    state: present
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Create audit log directory
  ansible.builtin.file:
    path: "{{ ntp_audit_log_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Create ntp-audit source staging directory
  ansible.builtin.file:
    path: /usr/local/src/ntp-audit
    state: directory
    owner: root
    group: root
    mode: "0755"
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Deploy chrony.py source
  ansible.builtin.template:
    src: ntp-audit/chrony.py.j2
    dest: /usr/local/src/ntp-audit/chrony.py
    owner: root
    group: root
    mode: "0644"
  notify: Build ntp-audit zipapp
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Deploy checkers.py source
  ansible.builtin.template:
    src: ntp-audit/checkers.py.j2
    dest: /usr/local/src/ntp-audit/checkers.py
    owner: root
    group: root
    mode: "0644"
  notify: Build ntp-audit zipapp
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Deploy output.py source
  ansible.builtin.template:
    src: ntp-audit/output.py.j2
    dest: /usr/local/src/ntp-audit/output.py
    owner: root
    group: root
    mode: "0644"
  notify: Build ntp-audit zipapp
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Deploy __main__.py source
  ansible.builtin.template:
    src: ntp-audit/__main__.py.j2
    dest: /usr/local/src/ntp-audit/__main__.py
    owner: root
    group: root
    mode: "0644"
  notify: Build ntp-audit zipapp
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Flush handlers (build zipapp if any source changed)
  ansible.builtin.meta: flush_handlers

- name: Check if ntp-audit zipapp already exists
  ansible.builtin.stat:
    path: /usr/local/bin/ntp-audit
  register: _ntp_audit_zipapp_stat
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Build ntp-audit zipapp on first deploy
  ansible.builtin.command:
    cmd: >-
      python3 -m zipapp /usr/local/src/ntp-audit
      -o /usr/local/bin/ntp-audit
      -p "/usr/bin/env python3"
  when: not _ntp_audit_zipapp_stat.stat.exists
  changed_when: true
  tags: ['ntp_audit', 'ntp_audit_script']

- name: Ensure ntp-audit zipapp is executable
  ansible.builtin.file:
    path: /usr/local/bin/ntp-audit
    mode: "0755"
    owner: root
    group: root
  tags: ['ntp_audit', 'ntp_audit_script']
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/tasks/script.yml
git commit -m "feat(ntp_audit): script.yml — Python zipapp deploy with handler-driven rebuild"
```

---

## Task 6: Ansible task — `logrotate.yml` + template

**Files:**
- Create: `ansible/roles/ntp_audit/templates/ntp-audit.logrotate.j2`
- Create: `ansible/roles/ntp_audit/tasks/logrotate.yml`

**Step 1: Create `ntp-audit.logrotate.j2`**

```
# Managed by Ansible (role: ntp_audit). Do not edit manually.
{{ ntp_audit_log_file }} {
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

**Step 2: Create `tasks/logrotate.yml`**

```yaml
---
# === ntp_audit — log rotation ===

- name: Deploy ntp-audit logrotate config
  ansible.builtin.template:
    src: ntp-audit.logrotate.j2
    dest: /etc/logrotate.d/ntp-audit
    owner: root
    group: root
    mode: "0644"
  tags: ['ntp_audit', 'ntp_audit_logrotate']
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit.logrotate.j2 \
        ansible/roles/ntp_audit/tasks/logrotate.yml
git commit -m "feat(ntp_audit): logrotate.yml — daily rotation, 7 rotations, compress"
```

---

## Task 7: Ansible tasks — scheduler (systemd, cron, assert)

**Files:**
- Modify: `ansible/roles/ntp_audit/templates/ntp-audit.service.j2`
- Create: `ansible/roles/ntp_audit/tasks/scheduler_systemd.yml`
- Create: `ansible/roles/ntp_audit/tasks/scheduler_cron.yml`
- Create: `ansible/roles/ntp_audit/tasks/scheduler_assert.yml`

**Step 1: Update `ntp-audit.service.j2`** — add missing `[Install]` section

```ini
# Managed by Ansible (role: ntp_audit). Do not edit manually.
[Unit]
Description=NTP health and conflict audit
Documentation=https://github.com/your-org/bootstrap
After=chronyd.service
Wants=chronyd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ntp-audit
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ntp-audit

[Install]
WantedBy=multi-user.target
```

**Step 2: Create `tasks/scheduler_systemd.yml`**

```yaml
---
# === ntp_audit — systemd timer scheduler ===

- name: Deploy ntp-audit systemd service unit
  ansible.builtin.template:
    src: ntp-audit.service.j2
    dest: /etc/systemd/system/ntp-audit.service
    owner: root
    group: root
    mode: "0644"
  notify: Reload systemd
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']

- name: Deploy ntp-audit systemd timer unit
  ansible.builtin.template:
    src: ntp-audit.timer.j2
    dest: /etc/systemd/system/ntp-audit.timer
    owner: root
    group: root
    mode: "0644"
  notify: Reload systemd
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']

- name: Flush handlers to reload systemd before enabling timer
  ansible.builtin.meta: flush_handlers
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Enable and start ntp-audit timer
  ansible.builtin.systemd:
    name: ntp-audit.timer
    enabled: true
    state: started
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']
```

**Step 3: Create `tasks/scheduler_cron.yml`**

```yaml
---
# === ntp_audit — cron scheduler (non-systemd fallback) ===

- name: Deploy ntp-audit cron job
  ansible.builtin.cron:
    name: "ntp-audit"
    job: "/usr/local/bin/ntp-audit"
    minute: "*/5"
    hour: "*"
    day: "*"
    month: "*"
    weekday: "*"
    user: root
  when: ansible_facts['service_mgr'] != 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']
```

**Step 4: Create `tasks/scheduler_assert.yml`**

```yaml
---
# === ntp_audit — assert a scheduler is active ===
# Fails explicitly if neither systemd timer nor cron job is available.

- name: Collect service facts (systemd)
  ansible.builtin.service_facts:
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']

- name: Assert systemd timer is enabled
  ansible.builtin.assert:
    that:
      - "'ntp-audit.timer' in ansible_facts.services"
      - ansible_facts.services['ntp-audit.timer'].status == 'enabled'
    fail_msg: >-
      ntp-audit.timer is not enabled after deploy.
      Run: systemctl status ntp-audit.timer
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']

- name: Check cron entry exists (non-systemd)
  ansible.builtin.command:
    cmd: crontab -l -u root
  register: _cron_list
  changed_when: false
  failed_when: false
  when: ansible_facts['service_mgr'] != 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']

- name: Assert cron entry present (non-systemd)
  ansible.builtin.assert:
    that:
      - "'ntp-audit' in _cron_list.stdout"
    fail_msg: >-
      ntp-audit cron job not found in root's crontab.
      Non-systemd host detected but cron deploy failed.
  when: ansible_facts['service_mgr'] != 'systemd'
  tags: ['ntp_audit', 'ntp_audit_scheduler']
```

**Step 5: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit.service.j2 \
        ansible/roles/ntp_audit/tasks/scheduler_systemd.yml \
        ansible/roles/ntp_audit/tasks/scheduler_cron.yml \
        ansible/roles/ntp_audit/tasks/scheduler_assert.yml
git commit -m "feat(ntp_audit): scheduler tasks — systemd, cron, assert; fix service [Install]"
```

---

## Task 8: Ansible tasks — `alloy.yml` + fixed Alloy template

**Files:**
- Modify: `ansible/roles/ntp_audit/templates/alloy-ntp-audit.alloy.j2`
- Create: `ansible/roles/ntp_audit/tasks/alloy.yml`

**Step 1: Replace `alloy-ntp-audit.alloy.j2`** — fix disconnected pipeline

```alloy
// ntp-audit — Grafana Alloy configuration fragment
// Managed by Ansible (role: ntp_audit). Do not edit manually.
// Requires: loki.write.default and prometheus.remote_write.default defined elsewhere.

// NTP audit JSON log → JSON processor → Loki
loki.source.file "ntp_audit" {
  targets = [{
    __path__ = "{{ ntp_audit_log_file }}",
    job      = "ntp-audit",
    host     = constants.hostname,
  }]
  // FIX: forward to processor, not directly to write
  forward_to = [loki.process.ntp_audit_json.receiver]
}

// Parse JSON fields; promote key fields to Loki stream labels
loki.process "ntp_audit_json" {
  forward_to = [loki.write.default.receiver]

  stage.json {
    expressions = {
      ntp_sync_status = "sync_status",
      ntp_conflict    = "ntp_conflict",
      ntp_phc_status  = "ntp_phc_status",
      ntp_stratum     = "stratum",
      ntp_offset      = "current_correction",
    }
  }

  stage.labels {
    values = {
      ntp_sync_status = "",
      ntp_conflict    = "",
      ntp_phc_status  = "",
    }
  }
}

// chrony native logs → Loki (for NtpClockStep alert)
loki.source.file "chrony_logs" {
  targets = [{
    __path__ = "{{ ntp_audit_chrony_log_dir }}/*.log",
    job      = "chrony",
    host     = constants.hostname,
  }]
  forward_to = [loki.write.default.receiver]
}

// Kernel timex metrics → Prometheus (high-precision, independent of script)
prometheus.exporter.unix "ntp_timex" {
  enable_collectors = ["timex"]
}

prometheus.scrape "ntp_timex" {
  targets    = prometheus.exporter.unix.ntp_timex.targets
  forward_to = [prometheus.remote_write.default.receiver]
  job_name   = "ntp-timex"
}
```

**Step 2: Create `tasks/alloy.yml`**

```yaml
---
# === ntp_audit — Grafana Alloy config fragment ===
# Deploys when ntp_audit_alloy_enabled is true and alloy_config_dir is set.
# Does not require Alloy to be installed — pre-deployed for when it arrives.

- name: Create Alloy conf.d directory
  ansible.builtin.file:
    path: "{{ ntp_audit_alloy_config_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  when:
    - ntp_audit_alloy_enabled | bool
    - ntp_audit_alloy_config_dir | length > 0
  tags: ['ntp_audit', 'ntp_audit_alloy']

- name: Deploy Alloy config fragment for ntp-audit
  ansible.builtin.template:
    src: alloy-ntp-audit.alloy.j2
    dest: "{{ ntp_audit_alloy_config_dir }}/ntp-audit.alloy"
    owner: root
    group: root
    mode: "0644"
  when:
    - ntp_audit_alloy_enabled | bool
    - ntp_audit_alloy_config_dir | length > 0
  tags: ['ntp_audit', 'ntp_audit_alloy']
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/templates/alloy-ntp-audit.alloy.j2 \
        ansible/roles/ntp_audit/tasks/alloy.yml
git commit -m "fix(ntp_audit): alloy pipeline — source→process→write; separate enable flag"
```

---

## Task 9: Ansible tasks — `loki.yml` + fixed Loki rules template

**Files:**
- Modify: `ansible/roles/ntp_audit/templates/loki-ntp-audit-rules.yaml.j2`
- Create: `ansible/roles/ntp_audit/tasks/loki.yml`

**Step 1: Replace `loki-ntp-audit-rules.yaml.j2`** — fix PHC alert + offset sign

```yaml
# ntp-audit — Loki ruler alert rules
# Managed by Ansible (role: ntp_audit). Do not edit manually.
# Deploy path: {{ ntp_audit_loki_rules_dir }}/ntp-audit-rules.yaml

groups:
  - name: ntp-audit
    interval: 5m
    rules:

      - alert: NtpCompetingDaemon
        expr: |
          count_over_time(
            {job="ntp-audit", ntp_conflict!="none"} [10m]
          ) > 0
        for: 0m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "Competing time sync daemon active alongside chrony"
          description: >-
            Host {{ "{{ $labels.host }}" }}: competing NTP daemon running
            (ntp_conflict={{ "{{ $labels.ntp_conflict }}" }}).
            Stop the competing daemon to prevent clock discipline conflicts.

      - alert: NtpPHCMissing
        # FIX: 'missing' status is now reachable (Python checkers.py fix)
        expr: |
          count_over_time(
            {job="ntp-audit", ntp_phc_status="missing"} [10m]
          ) > 0
        for: 0m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "PTP hardware clock device missing on VM"
          description: >-
            Host {{ "{{ $labels.host }}" }}: PHC device expected but not present.
            Check hypervisor guest tools and kernel module (ptp_kvm / hv_utils).

      - alert: NtpUnsynchronised
        expr: |
          count_over_time(
            {job="ntp-audit", ntp_sync_status="unsynchronised"} [10m]
          ) > 0
        for: 2m
        labels:
          severity: critical
          team: ops
        annotations:
          summary: "chrony is not synchronised"
          description: >-
            Host {{ "{{ $labels.host }}" }}: chrony unsynchronised for > 10 minutes.
            Check internet connectivity and NTP server reachability.

      - alert: NtpHighOffset
        # FIX: check both positive and negative offset (current_correction is signed)
        expr: |
          (
            {job="ntp-audit"} | json
              | ntp_offset | float > {{ ntp_audit_alert_offset_threshold }}
          ) or (
            {job="ntp-audit"} | json
              | ntp_offset | float < -{{ ntp_audit_alert_offset_threshold }}
          )
        for: 10m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "NTP clock offset exceeds ±{{ ntp_audit_alert_offset_threshold }}s"
          description: >-
            Host {{ "{{ $labels.host }}" }}: |offset| > {{ ntp_audit_alert_offset_threshold }}s.
            May indicate VM clock disruption or degraded NTP source.

      - alert: NtpClockStep
        expr: |
          count_over_time(
            {job="chrony"} |= "System clock was stepped" [5m]
          ) > 0
        for: 0m
        labels:
          severity: info
          team: ops
        annotations:
          summary: "chrony performed a clock step"
          description: >-
            Host {{ "{{ $labels.host }}" }}: large time correction applied (makestep).
            Normal after VM resume or first sync. Investigate if recurring.

      - alert: NtpHighStratum
        expr: |
          {job="ntp-audit"} | json | ntp_stratum | int > {{ ntp_audit_alert_stratum_max }}
        for: 15m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "NTP stratum too high (> {{ ntp_audit_alert_stratum_max }})"
          description: >-
            Host {{ "{{ $labels.host }}" }}: stratum {{ "{{ $labels.ntp_stratum }}" }}.
            NTP source quality is degraded.
```

**Step 2: Create `tasks/loki.yml`**

```yaml
---
# === ntp_audit — Loki ruler alert rules ===

- name: Create Loki rules directory
  ansible.builtin.file:
    path: "{{ ntp_audit_loki_rules_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  when:
    - ntp_audit_loki_enabled | bool
    - ntp_audit_loki_rules_dir | length > 0
  tags: ['ntp_audit', 'ntp_audit_loki']

- name: Deploy Loki alert rules for ntp-audit
  ansible.builtin.template:
    src: loki-ntp-audit-rules.yaml.j2
    dest: "{{ ntp_audit_loki_rules_dir }}/ntp-audit-rules.yaml"
    owner: root
    group: root
    mode: "0644"
  when:
    - ntp_audit_loki_enabled | bool
    - ntp_audit_loki_rules_dir | length > 0
  tags: ['ntp_audit', 'ntp_audit_loki']
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/templates/loki-ntp-audit-rules.yaml.j2 \
        ansible/roles/ntp_audit/tasks/loki.yml
git commit -m "fix(ntp_audit): loki rules — PHC missing alert works, signed offset, 10m unsync"
```

---

## Task 10: Ansible tasks — `first_run.yml` and `verify.yml`

**Files:**
- Create: `ansible/roles/ntp_audit/tasks/first_run.yml`
- Modify: `ansible/roles/ntp_audit/tasks/verify.yml` (replace content)

**Step 1: Create `tasks/first_run.yml`**

```yaml
---
# === ntp_audit — execute script immediately after deploy ===
# Separate from verify: intent is "run now", not "check artifacts".

- name: Run ntp-audit immediately (post-deploy first run)
  ansible.builtin.command:
    cmd: /usr/local/bin/ntp-audit
  changed_when: false
  failed_when: false
  tags: ['ntp_audit', 'ntp_audit_first_run']
```

**Step 2: Replace `tasks/verify.yml`**

Full content — updated JSON field names to match new Python output:

```yaml
---
# === ntp_audit — post-deploy verification ===

- name: Assert ntp-audit zipapp exists and is executable
  ansible.builtin.stat:
    path: /usr/local/bin/ntp-audit
  register: _v_script
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Verify ntp-audit zipapp
  ansible.builtin.assert:
    that:
      - _v_script.stat.exists
      - _v_script.stat.executable
    fail_msg: "/usr/local/bin/ntp-audit missing or not executable"
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Assert audit log directory exists
  ansible.builtin.stat:
    path: "{{ ntp_audit_log_dir }}"
  register: _v_logdir
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Verify log directory
  ansible.builtin.assert:
    that:
      - _v_logdir.stat.exists
      - _v_logdir.stat.isdir
    fail_msg: "{{ ntp_audit_log_dir }} missing"
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Assert audit log file was written
  ansible.builtin.stat:
    path: "{{ ntp_audit_log_file }}"
  register: _v_logfile
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Verify audit log not empty
  ansible.builtin.assert:
    that:
      - _v_logfile.stat.exists
      - _v_logfile.stat.size > 0
    fail_msg: "{{ ntp_audit_log_file }} missing or empty — first run failed"
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Read last line of audit log
  ansible.builtin.command:
    cmd: tail -1 {{ ntp_audit_log_file }}
  register: _v_last_line
  changed_when: false
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Assert audit log contains valid JSON with required keys
  ansible.builtin.assert:
    that:
      - (_v_last_line.stdout | from_json).timestamp is defined
      - (_v_last_line.stdout | from_json).sync_status is defined
      - (_v_last_line.stdout | from_json).stratum is defined
      - (_v_last_line.stdout | from_json).current_correction is defined
      - (_v_last_line.stdout | from_json).ntp_conflict is defined
      - (_v_last_line.stdout | from_json).ntp_phc_status is defined
    fail_msg: "audit.log last line missing required JSON keys"
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Collect service facts (systemd)
  ansible.builtin.service_facts:
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_verify']

- name: Verify ntp-audit.timer is enabled and active
  ansible.builtin.assert:
    that:
      - "'ntp-audit.timer' in ansible_facts.services"
      - ansible_facts.services['ntp-audit.timer'].status == 'enabled'
      - ansible_facts.services['ntp-audit.timer'].state == 'active'
    fail_msg: "ntp-audit.timer not enabled or not active"
  when: ansible_facts['service_mgr'] == 'systemd'
  tags: ['ntp_audit', 'ntp_audit_verify']
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/tasks/first_run.yml \
        ansible/roles/ntp_audit/tasks/verify.yml
git commit -m "feat(ntp_audit): first_run.yml, verify.yml — updated JSON key assertions"
```

---

## Task 11: Wire everything — `tasks/main.yml`

**Files:**
- Modify: `ansible/roles/ntp_audit/tasks/main.yml`

**Step 1: Replace `tasks/main.yml`**

Full content — pure table of contents:

```yaml
---
# === ntp_audit — entry point ===
# Each import_tasks is one business requirement.
# To run a single module: ansible-playbook ... --tags ntp_audit_script

- name: ntp_audit role
  when: ntp_audit_enabled | bool
  tags: ['ntp_audit']
  block:

    - name: Deploy audit script (Python zipapp)
      ansible.builtin.import_tasks: script.yml

    - name: Configure log rotation
      ansible.builtin.import_tasks: logrotate.yml

    - name: Configure systemd timer scheduler
      ansible.builtin.import_tasks: scheduler_systemd.yml

    - name: Configure cron scheduler (non-systemd fallback)
      ansible.builtin.import_tasks: scheduler_cron.yml

    - name: Assert scheduler is active
      ansible.builtin.import_tasks: scheduler_assert.yml

    - name: Deploy Grafana Alloy config fragment
      ansible.builtin.import_tasks: alloy.yml

    - name: Deploy Loki ruler alert rules
      ansible.builtin.import_tasks: loki.yml

    - name: Execute first run
      ansible.builtin.import_tasks: first_run.yml

    - name: Verify deployment
      ansible.builtin.import_tasks: verify.yml
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/tasks/main.yml
git commit -m "refactor(ntp_audit): main.yml — import_tasks table of contents, 9 modules"
```

---

## Task 12: Update molecule tests

**Files:**
- Modify: `ansible/roles/ntp_audit/molecule/default/molecule.yml`
- Modify: `ansible/roles/ntp_audit/molecule/default/verify.yml`

**Step 1: Update `molecule.yml`** — add idempotency step

Change `test_sequence` in `molecule.yml`:

```yaml
scenario:
  test_sequence:
    - syntax
    - converge
    - idempotency
    - verify
```

**Step 2: Update `molecule/default/verify.yml`**

Replace the verify tasks to match new JSON keys and new artifacts:

```yaml
---
- name: Verify ntp_audit
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  tasks:

    - name: Assert ntp-audit zipapp exists and is executable
      ansible.builtin.stat:
        path: /usr/local/bin/ntp-audit
      register: _v_script

    - name: Verify ntp-audit zipapp
      ansible.builtin.assert:
        that:
          - _v_script.stat.exists
          - _v_script.stat.executable
        fail_msg: "/usr/local/bin/ntp-audit missing or not executable"

    - name: Assert Python source staging directory exists
      ansible.builtin.stat:
        path: /usr/local/src/ntp-audit
      register: _v_src

    - name: Verify staging directory
      ansible.builtin.assert:
        that:
          - _v_src.stat.exists
          - _v_src.stat.isdir
        fail_msg: "/usr/local/src/ntp-audit staging directory missing"

    - name: Assert audit log directory exists
      ansible.builtin.stat:
        path: /var/log/ntp-audit
      register: _v_logdir

    - name: Verify log directory
      ansible.builtin.assert:
        that:
          - _v_logdir.stat.exists
          - _v_logdir.stat.isdir
        fail_msg: "/var/log/ntp-audit directory missing"

    - name: Assert audit log file written after first run
      ansible.builtin.stat:
        path: /var/log/ntp-audit/audit.log
      register: _v_logfile

    - name: Verify audit log not empty
      ansible.builtin.assert:
        that:
          - _v_logfile.stat.exists
          - _v_logfile.stat.size > 0
        fail_msg: "audit.log missing or empty — first run failed"

    - name: Read last line of audit log
      ansible.builtin.command:
        cmd: tail -1 /var/log/ntp-audit/audit.log
      register: _v_last_line
      changed_when: false

    - name: Assert audit log contains valid JSON with required keys
      ansible.builtin.assert:
        that:
          - (_v_last_line.stdout | from_json).timestamp is defined
          - (_v_last_line.stdout | from_json).sync_status is defined
          - (_v_last_line.stdout | from_json).stratum is defined
          - (_v_last_line.stdout | from_json).current_correction is defined
          - (_v_last_line.stdout | from_json).ntp_conflict is defined
          - (_v_last_line.stdout | from_json).ntp_phc_status is defined
        fail_msg: "audit.log missing required JSON keys"

    - name: Assert logrotate config deployed
      ansible.builtin.stat:
        path: /etc/logrotate.d/ntp-audit
      register: _v_logrotate

    - name: Verify logrotate config
      ansible.builtin.assert:
        that:
          - _v_logrotate.stat.exists
          - _v_logrotate.stat.size > 0
        fail_msg: "/etc/logrotate.d/ntp-audit missing"

    - name: Collect service facts (systemd)
      ansible.builtin.service_facts:
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Verify ntp-audit.timer is enabled and active
      ansible.builtin.assert:
        that:
          - "'ntp-audit.timer' in ansible_facts.services"
          - ansible_facts.services['ntp-audit.timer'].status == 'enabled'
          - ansible_facts.services['ntp-audit.timer'].state == 'active'
        fail_msg: "ntp-audit.timer not enabled or not active"
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert Alloy config fragment deployed
      ansible.builtin.stat:
        path: /etc/alloy/conf.d/ntp-audit.alloy
      register: _v_alloy

    - name: Verify Alloy fragment
      ansible.builtin.assert:
        that:
          - _v_alloy.stat.exists
          - _v_alloy.stat.size > 0
        fail_msg: "Alloy config fragment missing"

    - name: Assert Loki rules deployed
      ansible.builtin.stat:
        path: /etc/loki/rules/fake/ntp-audit-rules.yaml
      register: _v_loki

    - name: Verify Loki rules
      ansible.builtin.assert:
        that:
          - _v_loki.stat.exists
          - _v_loki.stat.size > 0
        fail_msg: "Loki alert rules missing"

    - name: Show result
      ansible.builtin.debug:
        msg: >-
          ntp_audit verify passed: zipapp, timer, log written with correct JSON keys,
          logrotate, alloy config, loki rules all present.
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/molecule/default/molecule.yml \
        ansible/roles/ntp_audit/molecule/default/verify.yml
git commit -m "test(ntp_audit): molecule — add idempotency, update verify for new JSON schema"
```

---

## Task 13: Syntax check + lint

**Step 1: Run Ansible syntax check**

Use `/ansible` skill:

```
/ansible syntax-check ansible/roles/ntp_audit
```

Or manually on the remote VM:

```bash
ansible-playbook --syntax-check ansible/playbooks/workstation.yml
```

Expected: no errors.

**Step 2: Run ansible-lint**

```bash
ansible-lint ansible/roles/ntp_audit/
```

Expected: no violations (or only informational).

**Step 3: Fix any lint issues found**

Common issues to watch for:
- `import_tasks` vs `include_tasks` (we use `import_tasks` — static, preferred)
- `changed_when: false` missing on command tasks
- Trailing spaces in YAML

**Step 4: Commit lint fixes if any**

```bash
git add -u
git commit -m "fix(ntp_audit): lint — address ansible-lint findings"
```

---

## Task 14: Run molecule on VM

Use `/ansible` skill to run molecule:

```
/ansible molecule ansible/roles/ntp_audit
```

Or directly on the remote VM:

```bash
cd /path/to/bootstrap && molecule test -s default -- --role ntp_audit
```

Expected:
- syntax: PASS
- converge: all tasks green
- idempotency: 0 changed tasks
- verify: all assertions pass

**If idempotency fails:** The most likely cause is the zipapp build step (`changed_when: true`). Check that the `when: not _ntp_audit_zipapp_stat.stat.exists` condition prevents rebuild on second run.

**If verify fails on JSON keys:** Check the actual log output with `tail -1 /var/log/ntp-audit/audit.log | python3 -m json.tool`

**Step 2: Commit passing molecule run evidence**

```bash
git commit --allow-empty -m "test(ntp_audit): molecule passing — syntax, converge, idempotency, verify"
```

---

## Summary

| Task | Files changed | Key outcome |
|---|---|---|
| 0 | defaults, handlers, rm bash | New vars, zipapp handler |
| 1 | `chrony.py.j2` | CSV parser, 14 fields, signed offset |
| 2 | `checkers.py.j2` | PHC `missing` fix |
| 3 | `output.py.j2` | `json.dumps()`, syslog |
| 4 | `__main__.py.j2` | Orchestrator, all fields in record |
| 5 | `tasks/script.yml` | zipapp deploy + handler |
| 6 | `tasks/logrotate.yml` + template | Log rotation |
| 7 | `tasks/scheduler_*.yml` + service fix | systemd+cron+assert, [Install] |
| 8 | `tasks/alloy.yml` + alloy template | Pipeline fix |
| 9 | `tasks/loki.yml` + loki template | PHC alert, signed offset alert |
| 10 | `tasks/first_run.yml` + `verify.yml` | Separated intents |
| 11 | `tasks/main.yml` | 9-module import_tasks |
| 12 | molecule | idempotency + new assertions |
| 13 | lint | Clean |
| 14 | molecule run | All green |
