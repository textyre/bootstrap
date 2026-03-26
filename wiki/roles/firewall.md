# Firewall Role

Manages nftables-based firewall configuration for workstation hardening.

## Security Controls

| Setting | CIS Control | Variable |
|---------|-------------|----------|
| Default deny inbound | 3.4.1.1 | `firewall_enabled: true` |
| nftables installed and enabled | 3.4.1.1 | `firewall_enable_service: true` |
| SSH rate limit per-IP | 3.4.1.4 | `firewall_ssh_rate_limit_enabled: true` |
| Ruleset configuration deployed | 3.4.1.4 | `firewall_enabled: true` |

## Audit Events

| Event | Source | Severity | Threshold |
|-------|--------|----------|-----------|
| Dropped packet rate exceeds threshold | nftables log prefix `[nftables] drop:` | WARNING | > 100/min for 5m |
| SSH brute-force rate limit triggered | nftables log prefix `[nftables] ssh-rate:` | CRITICAL | > 10 events/min |
| Ruleset changed outside Ansible | drift detection script | CRITICAL | any change detected |
| nftables service not enabled | systemctl is-enabled | CRITICAL | service disabled |
| inet filter table missing from runtime | nft list tables | CRITICAL | table absent |

## Monitoring Integration

- **Log source:** nftables kernel log messages with `[nftables]` prefix in journald
- **Prometheus metric:** `node_nf_conntrack_entries` (via node_exporter) for connection tracking saturation
- **Alloy pipeline:** scrape journald for `[nftables] drop:` and `[nftables] ssh-rate:` patterns, forward to Loki
- **Alert rules:**
  - `FirewallDropRateHigh` -- dropped packet rate exceeds threshold (WARNING)
  - `FirewallSSHBruteForce` -- SSH rate limit triggered repeatedly (CRITICAL)
  - `FirewallRulesetDrift` -- live ruleset differs from Ansible-managed state (CRITICAL)
  - `FirewallServiceDown` -- nftables service not enabled or inet filter table missing (CRITICAL)

## Drift Detection

When `firewall_drift_detection: true`, the role stores the expected nftables ruleset hash in `{{ firewall_drift_state_dir }}/`. A monitoring script or scheduled task can compare the live ruleset (`nft list ruleset`) against the stored hash to detect out-of-band changes.

**Detection mechanism:**
1. After applying the nftables configuration, store `nft list ruleset | sha256sum` in the state directory
2. Periodic check compares current `nft list ruleset | sha256sum` against stored value
3. Mismatch triggers `FirewallRulesetDrift` alert
