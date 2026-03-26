# fail2ban

Protects SSH against brute-force attacks with progressive ban escalation.

## Execution flow

1. **Assert OS** (`tasks/main.yml`) -- fails if `ansible_facts['os_family']` is not in `fail2ban_supported_os`
2. **Load OS vars** (`vars/<os_family>.yml`) -- loads package names and service name map for the detected OS family
3. **Install** (`tasks/install.yml`) -- installs fail2ban via `ansible.builtin.package` using OS-specific package list
4. **Configure** (`tasks/configure.yml`) -- deploys `/etc/fail2ban/jail.d/sshd.conf` from Jinja2 template. **Triggers handler:** if config changed, fail2ban will be restarted before verification.
5. **Enable** -- enables fail2ban service (init-agnostic via `ansible.builtin.service`)
6. **Start** -- starts fail2ban service (skipped when `fail2ban_start_service: false`)
7. **Flush handlers** -- applies pending restart (from step 4) so verification runs against new config
8. **Verify** (`tasks/verify.yml`) -- checks fail2ban is running, sshd jail is active, collects journal diagnostics on failure. Container environments get relaxed checks (service may not start due to missing iptables kernel modules).
9. **Report** -- writes execution report via `common/report_phase` + `report_render`

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `restart fail2ban` | Config file change (step 4) | Restarts fail2ban service. Flushed before verification (step 7). |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `fail2ban_enabled` | `true` | safe | Set `false` to skip this role entirely |
| `fail2ban_start_service` | `true` | safe | Set `false` to install and configure without starting the service |
| `fail2ban_sshd_enabled` | `true` | safe | Enable the SSH jail |
| `fail2ban_sshd_port` | `{{ ssh_port \| default(22) }}` | safe | Port to monitor; automatically follows the `ssh` role port |
| `fail2ban_sshd_maxretry` | `5` | safe | Failed attempts within `findtime` before banning |
| `fail2ban_sshd_findtime` | `600` | careful | Window for counting failures in seconds (10 min). Too short misses slow attacks; too long causes false positives |
| `fail2ban_sshd_bantime` | `3600` | safe | Initial ban duration in seconds (1 hour) |
| `fail2ban_sshd_bantime_increment` | `true` | careful | Double ban duration on each repeat offence. Disabling removes progressive escalation |
| `fail2ban_sshd_bantime_maxtime` | `86400` | careful | Maximum ban duration in seconds (24 hours). Only applies when `bantime_increment` is true |
| `fail2ban_sshd_backend` | `auto` | careful | Log backend: `auto`, `systemd`, `pyinotify`, or `polling`. Wrong value causes fail2ban to miss auth failures |
| `fail2ban_sshd_banaction` | `""` | internal | Override ban action (e.g., `iptables-multiport`). Empty uses fail2ban default. Changing requires understanding iptables/nftables backend |
| `fail2ban_ignoreip` | `[127.0.0.1/8, ::1]` | safe | IPs and CIDRs exempt from banning (whitelist) |

### Internal mappings (`vars/`)

These files contain cross-platform mappings. Do not override via inventory -- edit the files directly only when adding new platform or init system support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | Package list (`fail2ban`, `python-systemd`), service name map | Adding Arch-specific dependencies |
| `vars/debian.yml` | Package list (`fail2ban`), service name map | Adding Debian-specific dependencies |
| `vars/redhat.yml` | Package list (`fail2ban`), service name map | Adding RHEL-specific dependencies |
| `vars/void.yml` | Package list (`fail2ban`), service name map | Adding Void-specific dependencies |
| `vars/gentoo.yml` | Package list (`net-analyzer/fail2ban`), service name map | Adding Gentoo-specific dependencies |

## Examples

### Tightening SSH protection

```yaml
# In group_vars/all/fail2ban.yml or host_vars/<hostname>/fail2ban.yml:
fail2ban_sshd_maxretry: 3
fail2ban_sshd_bantime: 1800
fail2ban_sshd_bantime_maxtime: 172800
```

- `maxretry: 3` -- ban after 3 failed attempts (stricter than default 5)
- `bantime: 1800` -- initial 30-minute ban
- `bantime_maxtime: 172800` -- maximum 48-hour ban for repeat offenders

### Whitelisting a management subnet

```yaml
# In group_vars/all/fail2ban.yml:
fail2ban_ignoreip:
  - 127.0.0.1/8
  - "::1"
  - 10.0.0.0/24
```

Keep localhost entries -- removing them can cause fail2ban to ban local processes.

### Using a custom SSH port

```yaml
# In host_vars/<hostname>/fail2ban.yml:
fail2ban_sshd_port: 2222
```

If the `ssh` role is also applied, `fail2ban_sshd_port` defaults to `ssh_port` automatically -- no override needed.

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/fail2ban.yml:
fail2ban_enabled: false
```

## Progressive ban escalation

With `fail2ban_sshd_bantime_increment: true`, repeat offenders receive exponentially longer bans:

| Offence | Ban duration |
|---------|-------------|
| 1st ban | 1 hour (`bantime`) |
| 2nd ban | 2 hours |
| 3rd ban | 4 hours |
| ... | doubles each time |
| Maximum | 24 hours (`bantime_maxtime`) |

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Package | `fail2ban` | `fail2ban` | `fail2ban` | `fail2ban` | `net-analyzer/fail2ban` |
| Extra packages | `python-systemd` | -- | -- | -- | -- |
| Service name | `fail2ban` | `fail2ban` | `fail2ban` | `fail2ban` | `fail2ban` |
| Jail config path | `/etc/fail2ban/jail.d/sshd.conf` | `/etc/fail2ban/jail.d/sshd.conf` | `/etc/fail2ban/jail.d/sshd.conf` | `/etc/fail2ban/jail.d/sshd.conf` | `/etc/fail2ban/jail.d/sshd.conf` |

Arch Linux requires `python-systemd` for the `systemd` log backend to function.

## Logs

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| fail2ban log | `/var/log/fail2ban.log` | Ban/unban events, jail start/stop, filter matches | logrotate (distro default) |
| syslog / journal | `journalctl -u fail2ban` | Service start/stop, configuration errors | system journal rotation |
| auth log | `/var/log/auth.log` (Debian) or journal | SSH authentication failures that fail2ban monitors | system default |

### Reading the logs

- Currently banned IPs: `fail2ban-client status sshd` -- look at "Banned IP list"
- Recent bans: `grep 'Ban' /var/log/fail2ban.log | tail -20`
- Total bans since last restart: `fail2ban-client status sshd` -- "Currently banned" + "Total banned"
- Filter matches: `grep 'Found' /var/log/fail2ban.log | tail -20` -- shows detected auth failures

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| fail2ban won't start | `journalctl -u fail2ban -n 50` | Usually bad jail config: check `/etc/fail2ban/jail.d/sshd.conf` for syntax errors |
| Service starts but sshd jail not active | `fail2ban-client status` -- is `sshd` listed? | Check `fail2ban_sshd_enabled: true`. Check backend matches system: use `systemd` on systemd hosts |
| Legitimate users getting banned | `fail2ban-client status sshd` -- check banned IPs | Add their IP/subnet to `fail2ban_ignoreip`. Unban immediately: `fail2ban-client set sshd unbanip <IP>` |
| Ban not working (attackers not blocked) | `iptables -L f2b-sshd` or `nft list chain inet f2b-sshd` | Check iptables/nftables is installed and kernel modules are loaded. In Docker, host kernel modules required |
| Role fails at "Assert supported operating system" | Read the `fail_msg` | Running on unsupported OS family. Only Archlinux, Debian, RedHat, Void, Gentoo are supported |
| Idempotence failure on jail config | Template produces different output on second run | Check for dynamic values in template variables. Config should be deterministic |
| fail2ban not detecting SSH failures | `fail2ban-client get sshd logpath` | Verify log path matches actual auth log. On systemd, set `fail2ban_sshd_backend: systemd` |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| `default` | `molecule test` | After changing variables or task logic | Localhost smoke test on Arch |
| `docker` | `molecule test -s docker` | After changing templates or config logic | Package, config, permissions in Arch systemd container |
| `vagrant` | `molecule test -s vagrant` | After changing OS-specific logic | Real systemd, Arch + Ubuntu VMs, cross-platform |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Packages | fail2ban installed, `fail2ban-client --version` works | TEST-008 |
| Config files | `/etc/fail2ban/jail.d/sshd.conf` exists, root:root 0644 | TEST-008 |
| Config content | All template directives present (maxretry, bantime, findtime, backend, ignoreip, bantime.increment) | TEST-008 |
| Services | fail2ban enabled + active (relaxed in Docker) | TEST-008 |
| Runtime | `fail2ban-client status sshd` reports jail active (non-Docker only) | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `fail2ban package not found` | Stale package cache in container | Rebuild: `molecule destroy && molecule test` |
| fail2ban service not active in Docker | Missing iptables kernel modules in container | Expected -- verify.yml warns but does not fail |
| Idempotence failure on config deploy | Template produces different output on second run | Check for timestamps or random values in template |
| `maxretry not set to N` in verify | Verify vars out of sync with converge vars | Check `molecule/shared/vars.yml` matches converge overrides |
| Vagrant: `Python not found` | prepare.yml missing or Arch bootstrap skipped | Check `prepare.yml` has raw Python install |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `fail2ban` | Entire role | Full apply: `ansible-playbook playbook.yml --tags fail2ban` |
| `fail2ban`, `install` | Package installation only | Reinstall packages without reconfiguring |
| `fail2ban`, `service` | Service enable/start only | Restart fail2ban without redeploying config: `ansible-playbook playbook.yml --tags fail2ban,service` |
| `fail2ban`, `report` | Execution report only | Regenerate report |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No -- override via inventory |
| `vars/archlinux.yml` | Arch package list + service name map | Only when adding Arch-specific dependencies |
| `vars/debian.yml` | Debian package list + service name map | Only when adding Debian-specific dependencies |
| `vars/redhat.yml` | RHEL package list + service name map | Only when adding RHEL-specific dependencies |
| `vars/void.yml` | Void package list + service name map | Only when adding Void-specific dependencies |
| `vars/gentoo.yml` | Gentoo package list + service name map | Only when adding Gentoo-specific dependencies |
| `templates/jail_sshd.conf.j2` | SSH jail config template | When changing jail config structure |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/install.yml` | Package installation | When changing install logic |
| `tasks/configure.yml` | Jail config deployment | When changing config deployment |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `handlers/main.yml` | Service restart handler | Rarely |
| `molecule/` | Test scenarios | When changing test coverage |
