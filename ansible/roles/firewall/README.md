# firewall

Minimal nftables-based workstation firewall with default-drop input policy and per-source-IP SSH brute-force rate limiting.

## Execution flow

1. **Preflight** -- asserts OS family is in the supported list (`_firewall_supported_os`). Fails immediately with a clear message if the OS is unsupported.
2. **Install** (`tasks/install-<os_family>.yml`) -- installs the `nftables` package via the OS-specific task file (Arch, Debian, RedHat, Void, Gentoo). Reloads systemd daemon if the init system is systemd.
3. **Configure** (`templates/nftables.conf.j2`) -- deploys `/etc/nftables.conf` from template with default-drop input policy, loopback/established/ICMP rules, optional SSH with per-source-IP rate limiting (IPv4+IPv6), custom TCP/UDP ports, and Docker bridge forwarding. **Triggers handler:** if config changed, nftables will be restarted before verification.
4. **Service** -- enables `nftables.service` at boot and starts it. Checks if the ruleset is already loaded to avoid unnecessary restarts.
5. **Flush handlers** -- applies pending restart (from step 3) so verification runs against the new config.
6. **Verify** (`tasks/verify.yml`) -- checks config file permissions, validates nftables syntax (`nft -c -f`), asserts service is enabled, and verifies the `inet filter` table is loaded at runtime. Skips runtime checks in containers.
7. **Report** -- writes execution report via `common/report_phase.yml` + `report_render.yml` for each phase (install, configure, service, verify).

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `Restart nftables` | Config file change (step 3) | Restarts nftables service via `ansible.builtin.service`. Flushed before verification (step 5). Skipped when `firewall_start_service` is false. |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `firewall_enabled` | `true` | safe | Deploy nftables config and manage service. Set `false` to skip all configuration and service tasks. |
| `firewall_enable_service` | `true` | safe | Enable `nftables.service` at boot |
| `firewall_start_service` | `true` | safe | Start `nftables.service` now |
| `firewall_allow_ssh` | `true` | safe | Allow inbound SSH (TCP 22) |
| `firewall_ssh_rate_limit_enabled` | `true` | careful | Enable per-source-IP SSH rate limiting for IPv4+IPv6 (CRIT-01). Disabling removes brute-force protection. |
| `firewall_ssh_rate_limit` | `"4/minute"` | careful | SSH rate limit per source IP. Lower values increase security but may block legitimate rapid reconnects. |
| `firewall_ssh_rate_limit_burst` | `2` | careful | Burst packets allowed before rate limiting kicks in |
| `firewall_docker_enabled` | `false` | safe | Add Docker bridge forward rules (`docker0`). Enable if Docker publishes ports via nftables DNAT. |
| `firewall_allow_tcp_ports` | `[]` | safe | Extra inbound TCP ports to allow |
| `firewall_allow_udp_ports` | `[]` | safe | Extra inbound UDP ports to allow |

### Internal (`defaults/main.yml`)

| Variable | Description |
|----------|-------------|
| `_firewall_supported_os` | List of supported OS families (Archlinux, Debian, RedHat, Void, Gentoo). Do not override. |

## Examples

### Default secure workstation

```yaml
# In group_vars/all/firewall.yml:
# No configuration needed -- defaults provide a secure baseline with:
# - Default-drop input policy
# - SSH allowed with per-source-IP rate limiting
# - ICMP rate limited
# - All outbound allowed
```

### Docker host with extra ports

```yaml
# In group_vars/docker-hosts/firewall.yml:
firewall_docker_enabled: true
firewall_allow_tcp_ports: [8384, 22000]
firewall_allow_udp_ports: [22000, 21027]
```

### Disabling SSH access

```yaml
# In host_vars/<hostname>/firewall.yml:
firewall_allow_ssh: false
firewall_ssh_rate_limit_enabled: false
```

### Disabling the firewall on a specific host

```yaml
# In host_vars/<hostname>/firewall.yml:
firewall_enabled: false
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Package | `nftables` | `nftables` | `nftables` | `nftables` | `net-firewall/nftables` |
| Config path | `/etc/nftables.conf` | `/etc/nftables.conf` | `/etc/nftables.conf` | `/etc/nftables.conf` | `/etc/nftables.conf` |
| Service name | `nftables` | `nftables` | `nftables` | `nftables` | `nftables` |
| Install task | `install-archlinux.yml` | `install-debian.yml` (with apt cache) | `install-redhat.yml` | `install-void.yml` | `install-gentoo.yml` |

## Logs

### Log sources

| Source | Location | Contents | Rotation |
|--------|----------|----------|----------|
| nftables drop log | `journalctl -k --grep='nftables'` | Dropped packets matching the catch-all `log prefix "[nftables] drop: "` rule | System journal rotation |
| SSH rate limit log | `journalctl -k --grep='ssh-rate'` | SSH connections exceeding per-source-IP rate limit (`[nftables] ssh-rate:` and `[nftables] ssh6-rate:`) | System journal rotation |
| Ansible execution report | Role output during playbook run | Phase-by-phase execution summary via `common/report_render.yml` | N/A (transient) |

### Reading the logs

- Dropped packets: `journalctl -k --grep='nftables' --since '1 hour ago'` -- shows all firewall drops with source/destination
- SSH brute-force attempts: `journalctl -k --grep='ssh-rate'` -- shows rate-limited SSH connections per source IP
- Current ruleset: `nft list ruleset` -- shows all active rules, sets, and counters
- Drop counter: `nft list chain inet filter input | grep counter` -- shows total dropped packet count

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in `_firewall_supported_os` | Check `ansible_facts['os_family']` matches one of: Archlinux, Debian, RedHat, Void, Gentoo |
| nftables won't start | `journalctl -u nftables -n 50` | Usually config syntax error: run `nft -c -f /etc/nftables.conf` to see the parse error |
| SSH connections refused | `nft list chain inet filter input` -- check if `tcp dport 22` rule exists | Set `firewall_allow_ssh: true` and re-run the role |
| SSH rate limiting too aggressive | `journalctl -k --grep='ssh-rate'` -- frequent hits from legitimate IPs | Increase `firewall_ssh_rate_limit` (e.g., `"10/minute"`) or `firewall_ssh_rate_limit_burst` |
| Docker containers can't reach the network | `nft list chain inet filter forward` -- missing docker0 rules | Set `firewall_docker_enabled: true` and re-run the role |
| Custom port not accessible | `nft list chain inet filter input` -- port rule missing | Add port to `firewall_allow_tcp_ports` or `firewall_allow_udp_ports` and re-run |
| Config deployed but rules not loaded | `nft list tables` returns empty | Restart nftables: `systemctl restart nftables`. If it fails, check syntax first. |

## Testing

### Scenarios

Both scenarios are required. Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Config deployment, idempotence, assertions against config content |
| no_ssh (Docker) | `molecule test -s no_ssh` | After changing SSH-related logic | Negative assertions: SSH rules absent when disabled |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic or service tasks | Real nftables kernel module, Arch + Ubuntu, runtime rule verification |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `ok` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Scenario |
|----------|----------|----------|
| Packages | nftables installed | docker, vagrant |
| Config files | `/etc/nftables.conf` exists with root:root 0644, drop policy, correct chains | docker, vagrant |
| CRIT-01 | `ssh_ratelimit` + `ssh6_ratelimit` dynamic sets, per-source-IP pattern, rate/burst values | docker, vagrant |
| Negative | SSH rules absent when `firewall_allow_ssh: false`, Docker rules absent when disabled | no_ssh |
| Services | nftables enabled + active (or completed successfully for oneshot) | docker, vagrant |
| Runtime | `inet filter` table loaded, dynamic sets exist, full ruleset dump | vagrant only |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `nftables package not found` | Stale package cache in container | Rebuild: `molecule destroy && molecule test -s docker` |
| Idempotence failure on config deploy | Template produces different output on second run | Check for timestamps or random values in template |
| `inet filter table not loaded` | nftables needs kernel nf_tables module | Use vagrant scenario for runtime tests; Docker can only verify config |
| `nftables.service is not enabled` | systemd not running in container | Expected in some Docker setups; vagrant scenario tests this correctly |
| Vagrant: `Python not found` | prepare.yml missing or Arch bootstrap skipped | Check `prepare.yml` has raw Python install |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `firewall` | Entire role | Full apply: `ansible-playbook playbook.yml --tags firewall` |
| `firewall,install` | Package installation only | Reinstall nftables without reconfiguring |
| `firewall,configure` | Config deployment only | Redeploy `/etc/nftables.conf` without reinstalling |
| `firewall,service` | Service enable/start only | Restart nftables without re-deploying config |
| `firewall,report` | Execution report only | Re-generate execution report |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings + supported OS list | No -- override via inventory |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/verify.yml` | Post-deploy self-check (config, syntax, runtime) | When changing verification logic |
| `tasks/install-*.yml` | OS-specific package installation (5 files) | When changing install logic for a distro |
| `templates/nftables.conf.j2` | nftables config template | When changing firewall rules |
| `handlers/main.yml` | Service restart handler | Rarely |
| `meta/main.yml` | Role metadata | When changing dependencies |
| `molecule/` | Test scenarios (default, docker, no_ssh, vagrant) | When changing test coverage |
