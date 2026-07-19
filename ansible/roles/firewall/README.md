# firewall

Configures a workstation firewall with nftables. The role deploys a validated
`/etc/nftables.conf`, applies the ruleset, and keeps the nftables service enabled
at boot. Package installation belongs to the project package layer.

## Contract

The managed `inet filter` table provides:

- default-drop input and forward policies;
- loopback and established/related traffic;
- required ICMP/ICMPv6 errors and IPv6 discovery, with rate-limited ping requests;
- optional SSH access with per-source IPv4 and IPv6 rate limiting;
- optional inbound TCP and UDP ports;
- optional forwarding through `docker0` and `br-*` interfaces;
- unrestricted outbound traffic.

Dropped input and SSH rate-limit traffic is logged at no more than 10 messages
per second with a burst of 20. Packet dropping itself is not rate-limited.

The role owns only the `inet filter` table. It does not flush Docker or other
applications' nftables tables. Re-running the role replaces its table with the
same desired ruleset.

## Pipeline

`validate -> configure -> service -> report`

1. Validate the OS family and service manager.
2. Render `/etc/nftables.conf`; `nft -c` rejects invalid generated syntax before deployment.
3. Restart nftables after a ruleset change; otherwise ensure it is enabled and started.
4. Render the execution report.

## Variables

All public variables live in `defaults/main.yml` and are documented there.

| Variable | Default | Meaning |
|---|---:|---|
| `firewall_allow_ssh` | `true` | Allow inbound TCP port 22 |
| `firewall_ssh_rate_limit_enabled` | `true` | Rate-limit new SSH connections per source address |
| `firewall_ssh_rate_limit` | `4/minute` | Sustained SSH connection rate per source |
| `firewall_ssh_rate_limit_burst` | `2` | Additional SSH connection burst |
| `firewall_docker_enabled` | `false` | Permit Docker bridge forwarding |
| `firewall_allow_tcp_ports` | `[]` | Additional inbound TCP ports |
| `firewall_allow_udp_ports` | `[]` | Additional inbound UDP ports |

Project inventory currently enables SSH access, Docker forwarding, and TCP
ports `80` and `443`.

## Platforms

The configuration contract supports Arch Linux, Ubuntu, Fedora, Void, and
Gentoo. The `nft` executable and nftables service must already be provided by
the package layer. Service management is supported with systemd, OpenRC, and
runit. On s6 or dinit the role fails explicitly; no unimplemented init behavior
is assumed.

## Tests

`task test-firewall` runs the Docker scenario on systemd-based Arch and Ubuntu
containers. Test preparation installs nftables because package installation is
outside the role. The scenario runs the complete firewall contract, including
service activation, and then proves idempotence.

The Vagrant scenario runs the same role on Arch and Ubuntu VMs with their own
kernel and network stack. After the default-drop ruleset is active, it closes
the existing Ansible connection and opens a new one, proving that SSH access was
not blocked. Tests do not repeat file, template, package, or service module
checks already guaranteed by the converge and idempotence runs.

Run all Ansible and Molecule operations through the project's remote VM and
Taskfile workflow.
