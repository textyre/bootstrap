# ntp

NTP time synchronization via chrony with NTS-enabled servers and full parametrization.

## What this role does

- [x] Installs `chrony` (package name mapped per OS family)
- [x] Disables conflicting time sync daemons (`systemd-timesyncd`, OpenRC `ntpd`, etc.)
- [x] Deploys `/etc/chrony.conf` from Jinja2 template with NTS servers
- [x] Enables and starts `chronyd`
- [x] Verifies chrony responds (`chronyc tracking`) and has at least one source

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ntp_enabled` | `true` | Enable/disable the role |
| `ntp_servers` | Cloudflare, NIST, PTB ×2 | List of `{host, nts, iburst}` objects |
| `ntp_makestep_threshold` | `1.0` | Step clock if offset > N seconds |
| `ntp_makestep_limit` | `3` | Only step in first N updates |
| `ntp_minsources` | `2` | Minimum agreeing sources before adjusting clock |
| `ntp_driftfile` | `/var/lib/chrony/drift` | Clock drift file path |
| `ntp_dumpdir` | `/var/lib/chrony` | Save measurement history on shutdown (fast restart) |
| `ntp_logdir` | `/var/log/chrony` | Log directory (Promtail/Loki reads this) |
| `ntp_rtcsync` | `true` | Sync hardware RTC to system clock |
| `ntp_logchange` | `0.5` | Log clock changes > N seconds to syslog |
| `ntp_log_tracking` | `true` | Write `measurements.log`, `statistics.log`, `tracking.log` |

## Default servers

Three independent providers with NTS (RFC 8915):

| Host | Provider | Stratum |
|------|----------|---------|
| `time.cloudflare.com` | Cloudflare | 3 |
| `time.nist.gov` | NIST (US) | 1 |
| `ptbtime1.ptb.de` | PTB Germany | 1 |
| `ptbtime2.ptb.de` | PTB Germany | 1 |

`minsources: 2` ensures two must agree before the clock is adjusted.

## Supported platforms

Arch Linux, Debian, Ubuntu, RedHat/EL, Alpine, Void Linux

## Tags

`ntp`, `ntp,report`
