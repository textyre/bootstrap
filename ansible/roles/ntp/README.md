# ntp

NTP time synchronization via chrony with NTS-enabled servers and full parametrization.
Supports Arch Linux, Ubuntu/Debian, RedHat/EL, Gentoo, and Void Linux.

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
| `ntp_auto_detect` | `true` | Auto-detect virtualization environment and adjust refclocks/makestep/rtcsync accordingly |
| `ntp_refclocks` | `[]` | Manual refclock directives (list of raw chrony refclock strings). Overrides auto-detect if set. |
| `ntp_disable_competitors` | `true` | Stop and disable ntpd, openntpd, and systemd-timesyncd if found |
| `ntp_vmware_disable_periodic_sync` | `true` | On VMware guests: disable periodic time sync via `vmware-toolbox-cmd`. Has no effect on non-VMware systems. |

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

Arch Linux, Debian, Ubuntu, RedHat/EL, Gentoo, Void Linux

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian |
|--------|-----------|-----------------|
| Service unit | `chronyd.service` | `chrony.service` |
| Config path | `/etc/chrony.conf` | `/etc/chrony/chrony.conf` |
| System user | `chrony` | `_chrony` |
| Package | `chrony` | `chrony` |

These differences are handled by `vars/main.yml` mappings keyed on `ansible_facts['os_family']`.

## Environment Detection

When `ntp_auto_detect: true` (default), the role automatically adapts chrony configuration based on the virtualization environment:

| Environment | Detected Via | Adaptations |
|-------------|--------------|------------|
| **Bare Metal** | No virtualization | Standard refclocks (none by default); normal RTC sync |
| **KVM** | `ansible_facts['virtualization_type'] == 'kvm'` | Load `ptp_kvm` module; refclock PHC on `/dev/ptp0` |
| **VMware** | vSphere/ESXi guest tools | Refclock PHC on VMware precision clock; disable periodic timesync via `vmware-toolbox-cmd` |
| **Hyper-V** | Hyper-V integration services | Refclock PHC (if available); high `makestep_threshold` to prevent constant corrections |
| **Xen** | `ansible_facts['virtualization_type'] == 'xen'` | Conservative `makestep_threshold: 10` due to dom0 time jitter |
| **QEMU/Bochs** | Generic QEMU or Bochs emulator | No special refclocks; high `makestep_threshold` for stability |

To disable auto-detection and use manual refclocks, set:
```yaml
ntp_auto_detect: false
ntp_refclocks:
  - "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0 stratum 2"
```

To override auto-detect for a specific environment:
```yaml
ntp_auto_detect: true
ntp_refclocks:
  - "refclock SHM 0 refid GPS"  # Custom refclock, takes precedence
```

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
