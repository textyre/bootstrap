# firewall

Minimal nftables-based workstation firewall with default-drop input policy, SSH
protection, and per-source-IP brute-force rate limiting for **both IPv4 and IPv6**
(CRIT-01).

## What this role does

- [x] Installs `nftables` using `ansible.builtin.package` (OS-specific task files)
- [x] Deploys `/etc/nftables.conf` from Jinja2 template
- [x] Sets default-drop input policy (`type filter hook input priority 0; policy drop;`)
- [x] Allows loopback, established/related connections, and ICMP with rate limiting
- [x] Optionally allows SSH (port 22) with per-source-IP rate limiting for **IPv4 and IPv6** (`ssh_ratelimit` + `ssh6_ratelimit` dynamic sets — CRIT-01)
- [x] Allows additional TCP/UDP ports via variables
- [x] Forward chain allows established/related; optional Docker bridge support
- [x] Output chain defaults to accept
- [x] Catch-all log+drop rule for unmatched inbound traffic
- [x] Enables and optionally starts `nftables` service
- [x] Emits execution report via `common` role (`report_phase.yml` + `report_render.yml`)

## Requirements

- Ansible 2.15+
- `become: true` (root required for nftables and service management)
- Supported OS in role tasks: Arch Linux, Debian/Ubuntu, Fedora/RHEL, Void Linux, Gentoo
- Kernel with `nf_tables` module

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `firewall_enabled` | `true` | Deploy nftables config and manage service |
| `firewall_enable_service` | `true` | Enable `nftables.service` at boot |
| `firewall_start_service` | `true` | Start `nftables.service` now |
| `firewall_allow_ssh` | `true` | Allow inbound SSH (TCP 22) |
| `firewall_ssh_rate_limit_enabled` | `true` | Enable per-source-IP SSH rate limiting for IPv4+IPv6 |
| `firewall_ssh_rate_limit` | `"4/minute"` | SSH rate limit per source IP |
| `firewall_ssh_rate_limit_burst` | `2` | Burst packets for SSH limiter |
| `firewall_docker_enabled` | `false` | Add Docker bridge forward rules (`docker0`) |
| `firewall_allow_tcp_ports` | `[]` | Extra inbound TCP ports |
| `firewall_allow_udp_ports` | `[]` | Extra inbound UDP ports |

## Dependencies

No external role dependencies. Reporting uses `common` role from this repository.

## Example Playbook

```yaml
- hosts: workstations
  become: true
  roles:
    - role: firewall
```

With Docker and extra ports:

```yaml
- hosts: workstations
  become: true
  roles:
    - role: firewall
      vars:
        firewall_docker_enabled: true
        firewall_allow_tcp_ports: [8384, 22000]
        firewall_allow_udp_ports: [22000, 21027]
```

SSH disabled:

```yaml
- hosts: workstations
  become: true
  roles:
    - role: firewall
      vars:
        firewall_allow_ssh: false
        firewall_ssh_rate_limit_enabled: false
```

## Tags

| Tag | Effect |
|-----|--------|
| `firewall` | All tasks |
| `firewall,install` | Package installation |
| `firewall,configure` | Config deployment |
| `firewall,service` | Service enable/start |
| `firewall,report` | Execution report |

## Testing

### Scenarios

| Scenario | Driver | Platforms | Use case |
|----------|--------|-----------|----------|
| `default` | localhost (delegated) | Current host | Fast local syntax checks |
| `docker` | Docker | Arch systemd container | CI smoke test for converge+verify |
| `no_ssh` | Docker | Arch systemd container | Negative SSH assertions |
| `vagrant` | Vagrant (libvirt) | Arch Linux VM, Ubuntu VM | Full VM test with real kernel |

### Running molecule tests

```bash
cd ansible/roles/firewall

molecule test -s docker
molecule test -s no_ssh
molecule test -s vagrant
```

### What verify checks

`docker/shared/verify.yml` checks:
1. package installed
2. config exists with owner/group/mode
3. core chains and drop policy
4. ICMP rate limiting (IPv4+IPv6)
5. SSH allow rule + CRIT-01 sets/rules for IPv4 and IPv6
6. configured rate + burst values
7. expected custom TCP/UDP ports are present
8. Docker forward rules presence/absence based on config
9. service enabled
10. runtime checks skipped in Docker with explicit notice

`no_ssh/verify.yml` checks:
1. `tcp dport 22` absent
2. `ssh_ratelimit` and `ssh6_ratelimit` absent
3. core protection rules remain present
4. service enabled
