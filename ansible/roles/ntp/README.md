# ntp

NTP time synchronization via chrony with NTS-enabled servers and full parametrization.
Supports Arch Linux, Ubuntu/Debian, RedHat/EL, Alpine, and Void Linux.

## What this role does

- [x] Installs `chrony` (package name mapped per OS family)
- [x] Disables conflicting time sync daemons (`systemd-timesyncd`, OpenRC `ntpd`, etc.)
- [x] Deploys chrony config from Jinja2 template with NTS servers (path per OS family)
- [x] Enables and starts the chrony service (unit name mapped per OS family: `chronyd` on Arch/RH, `chrony` on Debian/Ubuntu)
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

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian |
|--------|-----------|-----------------|
| Service unit | `chronyd.service` | `chrony.service` |
| Config path | `/etc/chrony.conf` | `/etc/chrony/chrony.conf` |
| System user | `chrony` | `_chrony` |
| Package | `chrony` | `chrony` |

These differences are handled by `vars/main.yml` mappings keyed on `ansible_facts['os_family']`.

## Testing

Four Molecule scenarios:

| Scenario | Driver | Platform(s) | Coverage |
|----------|--------|-------------|----------|
| `default` | localhost | Arch Linux (host) | Smoke — config deploy, service start |
| `docker` | docker | Arch Linux (container) | Offline assertions — package, service, config, directories |
| `vagrant` | vagrant (libvirt) | Arch Linux VM + Ubuntu 24.04 VM | Cross-platform offline assertions + idempotence |
| `integration` | localhost | Arch Linux (host) | Live NTP sync, NTS authentication, KVM refclock |

```bash
# Arch container test (fast, CI-friendly)
cd ansible/roles/ntp
molecule test -s docker

# Cross-platform KVM VMs (requires libvirt + vagrant)
molecule test -s vagrant

# Live sync verification (requires outbound NTS connectivity)
molecule test -s integration
```

The `vagrant` scenario runs `shared/verify.yml` (offline assertions only) against both
Arch and Ubuntu VMs, covering the service name and config path differences.
The `integration` scenario verifies live sync and NTS authentication and is
intended to run on real infrastructure.

## Tags

`ntp`, `ntp:state` (service enable/start only), `ntp,report`

Use `--tags ntp:state` to restart chronyd without re-applying full configuration.
