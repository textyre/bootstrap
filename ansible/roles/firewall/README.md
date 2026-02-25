# firewall

Minimal nftables-based workstation firewall with default-drop input policy, SSH protection, and per-source-IP brute-force rate limiting (CRIT-01).

## What this role does

- [x] Installs `nftables` (OS-specific: Arch via pacman, Debian/Ubuntu via apt)
- [x] Deploys `/etc/nftables.conf` from Jinja2 template
- [x] Sets default-drop input policy (`type filter hook input priority 0; policy drop;`)
- [x] Allows loopback, established/related connections, and ICMP with rate limiting
- [x] Optionally allows SSH (port 22) with per-source-IP rate limiting (`ssh_ratelimit` dynamic set — CRIT-01)
- [x] Allows additional TCP/UDP ports via variables
- [x] Forward chain allows established/related (Docker bridge compatibility)
- [x] Output chain defaults to accept
- [x] Catch-all log+drop rule for unmatched inbound traffic
- [x] Enables and starts `nftables` service

## Requirements

- Ansible 2.15+
- `become: true` (root required for nftables and systemd)
- Supported OS: Arch Linux, Debian, Ubuntu
- Kernel with `nf_tables` module (standard in all supported distros)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `firewall_enabled` | `true` | Deploy the nftables config and manage the service |
| `firewall_enable_service` | `true` | Enable and start `nftables.service` |
| `firewall_allow_ssh` | `true` | Allow inbound SSH (TCP port 22) |
| `firewall_ssh_rate_limit_enabled` | `true` | Enable per-source-IP SSH rate limiting (brute-force protection) |
| `firewall_ssh_rate_limit` | `"4/minute"` | Rate limit threshold per source IP |
| `firewall_ssh_rate_limit_burst` | `2` | Burst allowance for SSH rate limiting |
| `firewall_allow_tcp_ports` | `[]` | Additional TCP ports to allow inbound |
| `firewall_allow_udp_ports` | `[]` | Additional UDP ports to allow inbound |

## Dependencies

None.

## Example Playbook

Minimal — defaults only (SSH allowed, rate limiting enabled):

```yaml
- hosts: workstations
  become: true
  roles:
    - role: firewall
```

With extra ports (e.g., Syncthing and a custom UDP service):

```yaml
- hosts: workstations
  become: true
  roles:
    - role: firewall
      vars:
        firewall_allow_tcp_ports: [8384, 22000]
        firewall_allow_udp_ports: [22000, 21027]
```

Disable SSH rate limiting (not recommended):

```yaml
- hosts: workstations
  become: true
  roles:
    - role: firewall
      vars:
        firewall_ssh_rate_limit_enabled: false
```

## Tags

| Tag | Effect |
|-----|--------|
| `firewall` | All tasks |
| `firewall,install` | Package installation only |
| `firewall,configure` | Config template deployment only |
| `firewall,service` | Service enable/start only |

## Testing

### Scenarios

| Scenario | Driver | Platforms | Use case |
|----------|--------|-----------|----------|
| `default` | localhost (delegated) | Current host | Fast local syntax + idempotence check |
| `docker` | Docker | `arch-systemd` container | CI — full service test in systemd container |
| `vagrant` | Vagrant (libvirt) | Arch Linux VM, Ubuntu 24.04 VM | Full VM test with real nf_tables kernel |

### Running molecule tests

```bash
# From the role directory
cd ansible/roles/firewall

# --- Default scenario (local, no containers) ---
molecule test -s default

# --- Docker scenario (requires Docker daemon) ---
molecule test -s docker

# --- Vagrant scenario (requires libvirt + vagrant-libvirt) ---
molecule test -s vagrant

# Run only converge (no destroy) for debugging
molecule converge -s docker
molecule verify -s docker
molecule destroy -s docker
```

### What verify checks

The shared `verify.yml` validates:

1. **Package** — `nftables` installed
2. **Config file** — `/etc/nftables.conf` exists, `root:root 0644`
3. **Table structure** — `inet filter` table present, input chain has `policy drop`
4. **Core rules** — loopback accept, established/related accept, `ct state invalid drop`
5. **ICMP** — rate limiting for IPv4 and IPv6
6. **SSH** — accept rule present when `firewall_allow_ssh: true`
7. **CRIT-01 (SSH rate limiting)** — `ssh_ratelimit` dynamic set with `type ipv4_addr`, `flags dynamic`, per-source-IP rule using `add @ssh_ratelimit { ip saddr limit rate over ... }`
8. **Rate limit values** — configured rate and burst match defaults
9. **Chains** — `forward` and `output` chains present
10. **Catch-all** — `log prefix` drop rule exists
11. **Ansible marker** — template-generated marker in config
12. **Service state** — `nftables.service` enabled and active (with `systemctl`)
13. **Runtime rules** — `nft list tables` confirms `inet filter` loaded (skipped gracefully in containers without netfilter)
14. **Runtime CRIT-01** — `nft list set inet filter ssh_ratelimit` confirms dynamic set loaded at runtime

### CRIT-01: SSH per-source-IP rate limiting

A common misconfiguration is using a global rate limit that applies across all source IPs instead of per-source. This role implements per-source-IP rate limiting using a named dynamic set:

```nftables
set ssh_ratelimit {
    type ipv4_addr
    flags dynamic,timeout
    timeout 1m
}

# In input chain:
tcp dport 22 ct state new add @ssh_ratelimit { ip saddr limit rate over 4/minute burst 2 packets } log prefix "[nftables] ssh-rate: " drop
tcp dport 22 ct state new accept
```

This ensures each source IP gets its own rate limit bucket, not a shared counter. The verify playbook treats the absence of this pattern as a test failure (CRIT-01).
