# ntp

NTP time synchronization via chrony with NTS-enabled servers and full parametrization.

## What this role does

- [x] Installs `chrony` (package name mapped per OS family)
- [x] Disables conflicting time sync daemons (`systemd-timesyncd`, OpenRC `ntpd`, etc.)
- [x] Deploys `/etc/chrony.conf` from Jinja2 template with NTS servers
- [x] Enables and starts `chronyd`
- [x] Verifies chrony responds (`chronyc tracking`) and has at least one source
- [x] Verifies internet connectivity before sync checks (requires outbound TCP 123 to `time.cloudflare.com`)
- [x] Validates input variables (`ntp_servers`/`ntp_pools` non-empty, `ntp_minsources` in range)
- [x] Creates required directories (`ntp_logdir`, `ntp_dumpdir`, `ntp_ntsdumpdir`) with correct ownership

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
| `ntp_pools` | `[]` | Pool-type sources (`pool` directive). Objects: `{host, iburst, maxsources}` |
| `ntp_allow` | `[]` | ACL for NTP server mode. Empty = client-only. Example: `["192.168.1.0/24"]` |
| `ntp_ntsdumpdir` | `/var/lib/chrony/nts-data` | NTS cookie cache — speeds up NTS re-handshake after restart |

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

`ntp`, `ntp:state` (service enable/start only), `ntp,report`

Use `--tags ntp:state` to restart chronyd without re-applying full configuration.
