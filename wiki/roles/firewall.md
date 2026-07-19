# Firewall Role

The `firewall` role configures an nftables workstation firewall. Its `inet
filter` table defaults inbound and forwarded traffic to drop, permits
established traffic, preserves required ICMP/ICMPv6 control messages, and
optionally permits SSH, application ports, and Docker bridge forwarding. The
project package layer provides nftables before this role runs.

## Security behavior

| Behavior | Implementation |
|---|---|
| Default deny inbound | `chain input` uses `policy drop` |
| Default deny forwarding | `chain forward` uses `policy drop` |
| SSH brute-force containment | Dynamic IPv4 and IPv6 sets rate-limit each source separately |
| Existing connections | `ct state established,related accept` |
| Invalid packets | `ct state invalid drop` |
| IPv4/IPv6 stability | Required error and IPv6 discovery messages are accepted; only ping requests are rate-limited |
| Dropped traffic visibility | Kernel log prefixes `[nftables] drop:` and `[nftables] ssh-rate:` are limited to 10 messages/second with burst 20 |
| Outbound traffic | Accepted without filtering |

The role replaces only its `inet filter` table. It does not flush the complete
ruleset and therefore does not remove tables maintained by Docker or other
software.

## Operation

The role validates the platform, validates the generated configuration with
`nft -c`, applies a changed ruleset, and keeps the nftables service enabled and
started. Configuration and service failures stop the run instead of being
converted into warnings.

Docker Molecule runs the complete role and nftables service in systemd-based
Arch and Ubuntu containers. Vagrant runs the same contract in Arch and Ubuntu
VMs and confirms that a fresh SSH connection remains possible after the
firewall is active. Both scenarios run the role twice and require an idempotent
second run.

Public variables and examples are documented in
`ansible/roles/firewall/README.md` and `defaults/main.yml`.
