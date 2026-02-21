# Design: Environment-Aware NTP + ntp_audit Role

**Date:** 2026-02-21
**Status:** Approved

---

## Problem

The current `ntp` role deploys chrony with identical config regardless of environment.
This causes two categories of issues:

1. **Competing discipliners** — on VMs, hypervisor tools (hv_utils, ptp_kvm) also touch the
   system clock. Two agents disciplining the same clock causes erratic timekeeping.
2. **Missed precision** — Hyper-V and KVM expose PTP hardware clocks that chrony can use as
   a high-precision local reference (stratum 2), but the role ignores them.
3. **Incomplete conflict cleanup** — only `systemd-timesyncd` is disabled; `ntpd` and
   `openntpd` are silently ignored.
4. **No runtime audit** — there is no mechanism to detect or log conflicts post-deployment.

---

## Verified Facts (from official documentation)

| Hypervisor | PTP device | Kernel module | Kernel version | chrony integration |
|---|---|---|---|---|
| Hyper-V | `/dev/ptp_hyperv` | `hv_utils` (built-in) | Any | `refclock PHC /dev/ptp_hyperv` |
| KVM | `/dev/ptp0` or `/dev/ptp_kvm` | `ptp_kvm` | 4.11+ (x86) | `refclock PHC /dev/ptp0` |
| VMware (vSphere 7.0 U2+, HW v17+) | `/dev/ptp0` | `ptp_vmw` | 5.7+ | `refclock PHC /dev/ptp0` |
| VirtualBox | None | None | — | Not possible from guest |
| Bare metal | — | — | — | NTS servers only |

Sources: Microsoft Learn, Broadcom KB 313780, LKML ptp_kvm patch (Jan 2017), VirtualBox Manual 7.1.

---

## Solution Overview

Two separate roles with distinct responsibilities:

- **`ntp`** — installs and configures chrony, adapted to detected environment
- **`ntp_audit`** — runtime audit via systemd timer; structured journal output; pre-deployed
  Alloy and Loki configs ready for when the monitoring stack arrives

---

## Part 1: ntp Role Changes

### Environment Detection

The role reads `ansible_facts['virtualization_type']` (available from `gather_facts: true`).
No dependency on the `vm` role. Controlled by `ntp_auto_detect: true`.

### chrony.conf Adaptations per Environment

**Hyper-V:**
```
refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0 stratum 2
makestep 1.0 -1
```
`hv_utils` transitions from discipliner to reference source. NTS servers remain as fallback.

**KVM:**
```
refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0 stratum 2
makestep 1.0 -1
```
Requires `ptp_kvm` kernel module loaded at boot (`/etc/modules-load.d/ptp_kvm.conf`).
`/dev/ptp_kvm` symlink used if present, falls back to `/dev/ptp0`.

**VMware (vSphere 7.0 U2+ with Precision Clock device):**
```
refclock PHC /dev/ptp0 poll 0 delay 0.0004 stratum 1
makestep 1.0 -1
```
Role checks if `/dev/ptp0` exists before adding refclock — presence indicates the
"Precision Clock" device is configured in vSphere. If absent, falls back to NTS only.
Also runs: `vmware-toolbox-cmd timesync disable` (if `vmtoolsd` is active).

**VirtualBox:**
```
# rtcsync removed (RTC managed by host)
makestep 1.0 -1  # unlimited: tolerates jumps from VBoxService on resume/snapshot
```
Cannot integrate with VBoxService from guest. `makestep 1.0 -1` reduces visible
disruption when VBoxService makes a correction. NTS servers remain the only source.

**Bare metal:** No changes to current config.

### Competing Daemon Cleanup

Adds `disable_ntpd.yml` and `disable_openntpd.yml` alongside existing `disable_systemd.yml`.
Pattern: stop + disable, `failed_when` ignores "not found" errors (idempotent on systems
without these daemons).

Discovery via `with_first_found` on `disable_{{ ansible_facts['service_mgr'] }}.yml` already
handles non-systemd init (OpenRC, runit) by skipping gracefully.

### New Variables

```yaml
ntp_auto_detect: true                    # read virtualization_type and adapt config
ntp_refclocks: []                        # manual override: list of raw refclock directives
                                         # populated automatically when ntp_auto_detect: true
ntp_disable_competitors: true            # stop+disable ntpd and openntpd
ntp_vmware_disable_periodic_sync: true   # run vmware-toolbox-cmd timesync disable on VMware
```

### New Files

```
ntp/tasks/
  disable_ntpd.yml
  disable_openntpd.yml
  load_ptp_kvm.yml           # modprobe ptp_kvm + modules-load.d entry
  detect_environment.yml     # sets _ntp_env_* facts from virtualization_type
ntp/vars/
  environments.yml           # mapping: virtualization_type → refclock / rtcsync / makestep
```

---

## Part 2: ntp_audit Role (New)

### Responsibility

Detect and log NTP health and conflicts at runtime. No dependency on any monitoring agent.
Output goes to systemd journal. Pre-deployed configs make Alloy/Loki integration zero-effort.

### Components

```
ntp_audit/
  defaults/main.yml
  tasks/main.yml
  templates/
    ntp-audit.sh.j2           # audit script
    ntp-audit.service.j2      # systemd service unit
    ntp-audit.timer.j2        # systemd timer unit
    alloy-ntp-audit.alloy.j2  # Grafana Alloy config fragment
    loki-ntp-audit-rules.yaml.j2  # Loki ruler alerting rules
```

### Audit Script: What It Checks

Runs as a one-shot systemd service on every timer tick.

```
chronyc tracking --json       offset, stratum, reference ID, leap status
chronyc sources -v            per-source state, reach, last sample
systemctl is-active           ntpd openntpd systemd-timesyncd vmtoolsd
test -c /dev/ptp_hyperv       PHC device present (Hyper-V)
test -c /dev/ptp0             PHC device present (KVM/VMware)
lsmod | grep ptp_kvm          ptp_kvm module loaded (KVM)
```

### Journal Output Format

Every run emits one structured entry via `systemd-cat`:

```
SYSLOG_IDENTIFIER=ntp-audit
NTP_STRATUM=2
NTP_REFERENCE=PHC0
NTP_OFFSET_S=0.000012
NTP_FREQ_ERROR_PPM=1.4
NTP_ROOT_DELAY_S=0.000031
NTP_ROOT_DISPERSION_S=0.000045
NTP_LEAP_STATUS=Normal
NTP_SYNC_STATUS=ok             # ok | unsynchronised
NTP_CONFLICT=none              # none | ntpd_active | openntpd_active | timesyncd_active | vmtoolsd_active
NTP_PHC_STATUS=ok              # ok | missing | n/a
NTP_PHC_DEVICE=/dev/ptp_hyperv # or /dev/ptp0 or none
NTP_PTP_KVM_MODULE=loaded      # loaded | not_loaded | n/a
```

These journal fields become Loki labels/values when Alloy scrapes the journal.
`journalctl -o json` can query them immediately without any additional tooling.

### Alloy Config Fragment

Deployed to `{{ ntp_audit_alloy_config_dir }}/ntp-audit.alloy`
(default: `/etc/alloy/conf.d/ntp-audit.alloy`).

Activated automatically when an Alloy role installs Alloy and loads `conf.d/`.

```hcl
// NTP audit — journal events
loki.source.journal "ntp_audit" {
  matches    = "_SYSLOG_IDENTIFIER=ntp-audit"
  forward_to = [loki.write.default.receiver]
  labels     = { job = "ntp-audit" }
}

// NTP quality logs — chrony structured logs
loki.source.file "chrony_logs" {
  targets = [{
    __path__ = "/var/log/chrony/*.log",
    job      = "chrony",
  }]
  forward_to = [loki.write.default.receiver]
}

// NTP kernel metrics — adjtimex via node_exporter
prometheus.exporter.unix "ntp_timex" {
  enable_collectors = ["timex"]
}

prometheus.scrape "ntp_timex" {
  targets    = prometheus.exporter.unix.ntp_timex.targets
  forward_to = [prometheus.remote_write.default.receiver]
}
```

### Loki Alert Rules

Deployed to `{{ ntp_audit_loki_rules_dir }}/ntp-audit-rules.yaml`
(default: `/etc/loki/rules/fake/ntp-audit-rules.yaml`).

```yaml
groups:
  - name: ntp-audit
    interval: 5m
    rules:
      - alert: NtpCompetingDaemon
        expr: |
          count_over_time(
            {job="ntp-audit"} |= "NTP_CONFLICT" != `NTP_CONFLICT=none` [10m]
          ) > 0
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Competing time sync daemon detected alongside chrony"
          description: "{{ $labels.host }}: NTP_CONFLICT={{ $labels.NTP_CONFLICT }}"

      - alert: NtpPHCMissing
        expr: |
          count_over_time(
            {job="ntp-audit"} |= `NTP_PHC_STATUS=missing` [10m]
          ) > 0
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "PTP hardware clock device disappeared on VM"
          description: "{{ $labels.host }}: PHC device expected but not found"

      - alert: NtpUnsynchronised
        expr: |
          count_over_time(
            {job="ntp-audit"} |= `NTP_SYNC_STATUS=unsynchronised` [15m]
          ) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "chrony is not synchronised"

      - alert: NtpHighOffset
        expr: |
          {job="ntp-audit"}
            | json
            | NTP_OFFSET_S > 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "NTP offset exceeds 100ms"
          description: "Offset: {{ $labels.NTP_OFFSET_S }}s"

      - alert: NtpClockStep
        expr: |
          count_over_time(
            {job="chrony"} |= "System clock was stepped" [5m]
          ) > 0
        for: 0m
        labels:
          severity: info
        annotations:
          summary: "chrony performed a clock step (time jump)"
```

### ntp_audit Variables

```yaml
ntp_audit_enabled: true
ntp_audit_interval: "5min"                         # systemd timer OnCalendar interval
ntp_audit_alloy_config_dir: "/etc/alloy/conf.d"   # where Alloy fragment is deployed
ntp_audit_loki_rules_dir: "/etc/loki/rules/fake"  # where Loki ruler rules are deployed
ntp_audit_phc_devices:                            # PHC devices to check (auto-set by ntp role)
  - /dev/ptp_hyperv
  - /dev/ptp0
```

### Playbook Integration

```yaml
- role: ntp
  tags: [system, ntp]
  when: ntp_enabled | default(true)

- role: ntp_audit
  tags: [system, ntp, ntp_audit]
  when: ntp_enabled | default(true) and ntp_audit_enabled | default(true)
```

---

## What Is NOT in Scope

- Installing Grafana Alloy (separate role, future)
- Installing Loki (separate role, future)
- Grafana dashboards (future, after Alloy/Loki exist)
- chrony_exporter (Prometheus path — future, if Prometheus added)

---

## Alloy Integration Path (when Alloy role arrives)

1. Alloy role installs Alloy and loads all files from `/etc/alloy/conf.d/`
2. `ntp-audit.alloy` is already there — zero additional config needed
3. Loki ruler rules at `/etc/loki/rules/` are picked up by Loki automatically
4. Full alerting active on first Alloy run
