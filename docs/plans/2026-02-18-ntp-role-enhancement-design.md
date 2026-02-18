# Design: NTP Role Enhancement — chrony.conf Management

**Date:** 2026-02-18
**Role:** `ansible/roles/ntp`
**Status:** Approved

## Goal

Extend the existing `ntp` role to manage `chrony.conf` via a Jinja2 template with full
parametrization: NTS-enabled servers, clock correction parameters, dumpdir for fast
post-reboot sync, and detailed logging for Loki ingestion.

## Context

The existing role installs chrony, disables `systemd-timesyncd`, and starts/enables
`chronyd`, but leaves `/etc/chrony.conf` untouched (package default). This means:
- No NTS (Network Time Security) — servers are unauthenticated
- No control over `minsources`, `makestep`, `driftfile` without editing templates
- No consistent logging for observability

## Decision: Approach B — Full Parametrization

Every significant chrony parameter becomes an Ansible variable with a sensible default
in `defaults/main.yml`. This follows the established pattern of `ssh`, `sysctl`, and
`docker` roles in this project.

Rejected alternatives:
- **A (minimal patch):** `makestep` and `minsources` hardcoded — violates project conventions
- **C (extra_config):** Arbitrary config string is unpredictable and hard to test

## New Variables (`defaults/main.yml`)

```yaml
# NTP servers — list of {host, nts, iburst}
ntp_servers:
  - { host: "time.cloudflare.com",  nts: true, iburst: true }
  - { host: "time.nist.gov",        nts: true, iburst: true }
  - { host: "ptbtime1.ptb.de",      nts: true, iburst: true }
  - { host: "ptbtime2.ptb.de",      nts: true, iburst: true }

# Clock correction on start
ntp_makestep_threshold: 1.0   # step if offset > N seconds
ntp_makestep_limit: 3         # only in first N updates

# Minimum agreeing sources required to update system clock
ntp_minsources: 2

# File paths
ntp_driftfile: "/var/lib/chrony/drift"
ntp_dumpdir: "/var/lib/chrony"    # save measurement history on shutdown
ntp_logdir: "/var/log/chrony"

# RTC hardware clock sync
ntp_rtcsync: true

# Log large clock changes to syslog
ntp_logchange: 0.5

# Detailed measurement logging (for Loki ingestion)
ntp_log_tracking: true
```

### Server selection rationale

| Server | Provider | Stratum | NTS |
|--------|----------|---------|-----|
| time.cloudflare.com | Cloudflare | 3 | Yes |
| time.nist.gov | NIST (US) | 1 | Yes |
| ptbtime1.ptb.de | PTB Germany | 1 | Yes |
| ptbtime2.ptb.de | PTB Germany | 1 | Yes |

3 independent providers + `minsources: 2` ensures two must agree before the clock
is adjusted, protecting against a single compromised or malfunctioning source.

### `ntp_dumpdir` rationale

User reboots frequently. `dumpdir` saves measurement history (per-server offset,
local clock drift) on chrony shutdown. On restart without the `-r` flag, chrony
re-calibrates from scratch (few minutes). With history saved, drift correction
is applied immediately. Note: the `-r` flag (sysconfig/service level) is out of
scope for this iteration — `dumpdir` directive is added to the config.

### `ntp_log_tracking: true` rationale

User plans Loki-based observability. With this enabled, chrony writes three files
to `ntp_logdir`:
- `measurements.log` — raw NTP round-trip measurements per source
- `statistics.log` — per-source offset/frequency statistics
- `tracking.log` — system clock offset/frequency over time

Promtail reads these files and ships to Loki. Log rotation is handled by the
`chrony` package's bundled logrotate config (`/etc/logrotate.d/chrony`).

## Template: `templates/chrony.conf.j2`

```jinja2
# Managed by Ansible — do not edit manually
# Role: ntp | Template: chrony.conf.j2

{% for server in ntp_servers %}
server {{ server.host }}{% if server.iburst | default(true) %} iburst{% endif %}{% if server.nts | default(false) %} nts{% endif %}

{% endfor %}
# Clock stability
driftfile {{ ntp_driftfile }}
{% if ntp_dumpdir %}
dumpdir {{ ntp_dumpdir }}
{% endif %}
makestep {{ ntp_makestep_threshold }} {{ ntp_makestep_limit }}
minsources {{ ntp_minsources }}

{% if ntp_rtcsync %}
# Sync hardware RTC to system clock
rtcsync
{% endif %}

# Leap seconds from system timezone database
leapsectz right/UTC

# Logging
logdir {{ ntp_logdir }}
logchange {{ ntp_logchange }}
{% if ntp_log_tracking %}
log measurements statistics tracking
{% endif %}
```

### Example rendered output (defaults)

```
server time.cloudflare.com iburst nts
server time.nist.gov iburst nts
server ptbtime1.ptb.de iburst nts
server ptbtime2.ptb.de iburst nts

driftfile /var/lib/chrony/drift
dumpdir /var/lib/chrony
makestep 1.0 3
minsources 2

rtcsync

leapsectz right/UTC

logdir /var/log/chrony
logchange 0.5
log measurements statistics tracking
```

### Intentionally excluded

| Directive | Reason |
|-----------|--------|
| `lock_all` | mlockall() prevents swap — chrony uses ~3MB, never swapped on workstation |
| `allow` / `local stratum` | Client-only mode; no NTP server functionality needed |
| `keyfile` | NTS replaces symmetric key auth; keyfile only needed for legacy NTP auth |

## Task Changes (`tasks/main.yml`)

One new task added after package installation, before service start:

```yaml
- name: Deploy chrony configuration
  ansible.builtin.template:
    src: chrony.conf.j2
    dest: /etc/chrony.conf
    owner: root
    group: root
    mode: "0644"
  notify: restart ntp
```

Handler (`handlers/main.yml`) already has `listen: "restart ntp"` — no changes needed.

## Molecule Test Additions

```yaml
- name: Verify chrony.conf deployed
  ansible.builtin.stat:
    path: /etc/chrony.conf
  register: conf_file

- name: Assert chrony.conf exists and is a file
  ansible.builtin.assert:
    that:
      - conf_file.stat.exists
      - conf_file.stat.isreg

- name: Verify NTS flag present in config
  ansible.builtin.command: grep -c "nts" /etc/chrony.conf
  changed_when: false
  register: nts_count

- name: Assert at least one NTS server configured
  ansible.builtin.assert:
    that: nts_count.stdout | int >= 1

- name: Verify minsources directive present
  ansible.builtin.command: grep "minsources" /etc/chrony.conf
  changed_when: false

- name: Verify driftfile directive present
  ansible.builtin.command: grep "driftfile" /etc/chrony.conf
  changed_when: false
```

## Files Changed

| File | Action |
|------|--------|
| `defaults/main.yml` | Add 9 new variables |
| `templates/chrony.conf.j2` | Create (new file) |
| `tasks/main.yml` | Add 1 task (deploy template) |
| `handlers/main.yml` | No changes |
| `meta/main.yml` | No changes |
| `molecule/default/verify.yml` | Add 6 assertions |

## Out of Scope (v2)

- `-r` flag via sysconfig/systemd drop-in (enables reading saved `dumpdir` history on boot)
- `chrony_exporter` for Prometheus metrics (separate role)
- NTP server mode (`allow`, `local stratum`)
