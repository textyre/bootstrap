# Phase 3: Wiki/Roles Pages Inspection -- Review Results

**Reviewer**: Claudette (destructive-critical review)
**Date**: 2026-02-16
**Files reviewed**: 12/12 wiki role pages
**Verification**: Web search against official documentation performed for Alloy River syntax, Prometheus flags, Loki compactor config, AppArmor on Arch, fail2ban actions/nftables

---

## 1. Critical Issues (blockers)

Issues that would cause failures if implemented as documented.

### CRIT-1: systemd_hardening.md -- ProtectSystem=strict applied to Docker will BREAK Docker

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/systemd_hardening.md`
**Lines**: 16-19, 23

The default configuration applies `ProtectSystem=strict` uniformly to all services in the list, which includes `docker`:

```yaml
systemd_hardening_services:
  - sshd
  - docker    # <-- WILL BREAK
  - caddy
  - nginx
```

`ProtectSystem=strict` makes the entire filesystem read-only except `/dev`, `/proc`, `/sys`. Docker requires write access to `/var/lib/docker`, `/var/run/docker.sock`, `/var/run/docker`, and various overlay mount paths. Applying this directive to `docker.service` will **prevent Docker from starting**.

The page mentions `ReadWritePaths` as an override (line 40), but:
- There is no per-service override mechanism documented -- the same variables apply to ALL listed services
- The default `systemd_hardening_read_write_paths: []` is empty
- No example shows how to exempt Docker from specific directives
- Even with `ReadWritePaths=/var/lib/docker`, Docker also needs namespace creation (`RestrictNamespaces=true` on line 31 will also break Docker, since Docker uses user/PID/network/mount namespaces)

**Additionally**: `RestrictNamespaces=true` (line 31) will prevent Docker from creating containers entirely, since container isolation relies on Linux namespaces.

**Fix required**: Implement a per-service configuration dictionary instead of a flat list. Docker needs fundamentally different hardening than sshd. Example:

```yaml
systemd_hardening_services:
  sshd:
    protect_system: "strict"
    restrict_namespaces: true
  docker:
    protect_system: "full"  # not strict -- Docker needs /var/lib/docker
    restrict_namespaces: false  # Docker requires namespaces
    read_write_paths:
      - /var/lib/docker
      - /var/run/docker
```

### CRIT-2: pam_hardening.md vs base_system QW-5 -- duplicate faillock configuration will CONFLICT

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/pam_hardening.md` (lines 26-32)
**Conflict with**: `wiki/Quick-Wins.md` QW-5, `wiki/Roadmap.md` line 44

Both `pam_hardening` role (Phase 2) and `base_system` QW-5 configure the **exact same file**: `/etc/security/faillock.conf`. Both define `pam_faillock_deny: 3`, `pam_faillock_unlock_time: 900`, etc.

The `pam_hardening` page does NOT document this conflict. Running both will cause:
- Last-write-wins race condition on `/etc/security/faillock.conf`
- Non-idempotent behavior (order-dependent outcome)
- Confusion about which role "owns" faillock configuration

**Fix required**: Either:
1. Remove faillock from `pam_hardening` (since `base_system` QW-5 already handles it), OR
2. Remove faillock from `base_system` QW-5 and consolidate in `pam_hardening`, OR
3. Document the conflict explicitly and add a mutual exclusion flag

### CRIT-3: alloy.md -- Privileged mode is NOT required for journald access

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/alloy.md` (line 94)

```
Privileged: true (requires reading journald)
```

Per the [official Grafana Alloy documentation](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/), Alloy only needs:
- The `alloy` user to be a member of the `adm` and `systemd-journal` groups, OR
- Read-only bind mounts of `/var/log/journal:/var/log/journal:ro`, `/run/log/journal:/run/log/journal:ro`, and `/etc/machine-id:/etc/machine-id:ro`

Running a container as `privileged: true` grants it **full root access to the host** -- all capabilities, all devices, bypass all security (AppArmor, seccomp, etc.). This is a severe security anti-pattern for a log collector.

**Fix required**: Replace `privileged: true` with specific bind mounts and group membership. Example docker-compose:

```yaml
volumes:
  - /var/log/journal:/var/log/journal:ro
  - /run/log/journal:/run/log/journal:ro
  - /etc/machine-id:/etc/machine-id:ro
```

### CRIT-4: apparmor.md -- Incorrect kernel parameter syntax for Arch Linux

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/apparmor.md` (line 49)

```
Kernel parameter: apparmor=1 security=apparmor in /etc/default/grub -> grub-mkconfig
```

Per the [Arch Wiki AppArmor page](https://wiki.archlinux.org/title/AppArmor), the **current correct syntax** uses the `lsm=` kernel parameter:

```
lsm=landlock,lockdown,yama,integrity,apparmor,bpf
```

The old `apparmor=1 security=apparmor` syntax is **deprecated**. The modern kernel uses the `lsm=` parameter to set the initialization order, and `apparmor` must be the first "major" module in the list.

Additionally, the page does NOT mention the dependency on the `bootloader` role for modifying GRUB configuration. Modifying `/etc/default/grub` and running `grub-mkconfig` is the `bootloader` role's responsibility.

**Fix required**: Update to `lsm=` syntax, add `bootloader` as a dependency.

### CRIT-5: Loki retention requires limits_config AND compactor AND delete_request_store -- wiki only documents compactor

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/loki.md` (lines 37-38, 52-54)

The wiki documents:
```yaml
loki_retention_enabled: true
loki_retention_period: "720h"
```

But per [Grafana Loki retention documentation](https://grafana.com/docs/loki/latest/operations/storage/retention/), retention requires **three** configuration sections working together:

1. `compactor.retention_enabled: true` -- documented
2. `limits_config.retention_period: 720h` -- **NOT documented** (the variable exists but the wiki doesn't show which YAML section it maps to)
3. `compactor.delete_request_store` -- **NOT documented** (required when retention is enabled)
4. Index period must be `24h` -- **NOT documented**

Without ALL of these, retention silently does nothing -- old logs accumulate indefinitely. This is a storage exhaustion risk.

---

## 2. Serious Gaps (high impact)

### GAP-1: All Docker images use `:latest` tag -- supply chain risk and reproducibility failure

**Affected files** (every Docker-based role):

| File | Variable | Image |
|------|----------|-------|
| `alloy.md` | `alloy_docker_image` | `grafana/alloy:latest` |
| `prometheus.md` | `prometheus_docker_image` | `prom/prometheus:latest` |
| `loki.md` | `loki_docker_image` | `grafana/loki:latest` |
| `grafana.md` | `grafana_docker_image` | `grafana/grafana:latest` |
| `node_exporter.md` | `node_exporter_docker_image` | `prom/node-exporter:latest` |
| `cadvisor.md` | `cadvisor_docker_image` | `gcr.io/cadvisor/cadvisor:latest` |
| `watchtower.md` | (in docker-compose example) | `containrrr/watchtower:latest` |

Using `:latest` tags means:
- **Non-reproducible**: same playbook produces different results on different days
- **Supply chain risk**: a compromised image pushed as `latest` is automatically pulled
- **Breaking changes**: major version bumps (Loki 2.x -> 3.x, Grafana 10 -> 11) pulled without warning
- **No rollback path**: you don't know what version you were running

**Additional concern for Watchtower**: The `containrrr/watchtower` repository was **archived on Dec 17, 2025**. The project is no longer maintained. The latest release is v1.7.1. The wiki should:
1. Pin to `containrrr/watchtower:1.7.1`
2. Document that the project is archived/EOL
3. Suggest alternatives (e.g., Renovate Bot, Diun)

### GAP-2: Watchtower auto-updates entire monitoring stack simultaneously -- cascading failure risk

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/watchtower.md`

The default configuration (`watchtower_scope: ""`) means Watchtower updates ALL running containers. If Prometheus, Loki, Alloy, Grafana, and cAdvisor are all updated simultaneously at 03:00:
- The entire observability stack goes down
- Any logs generated during the update are LOST (Alloy -> Loki pipeline broken)
- If any updated container fails to start, there is no monitoring to detect the failure
- Rolling restarts (`watchtower_rolling_restart: false` by default) are disabled

The page mentions label filtering in the notes section but does NOT flag this as a risk in the main configuration. The default should either:
1. Enable label filtering by default (`WATCHTOWER_LABEL_ENABLE=true`)
2. Enable `monitor_only` mode as default
3. Document the cascading failure scenario prominently

### GAP-3: grafana.md -- admin password defaults to "admin" with no security warning

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/grafana.md` (line 59)

```yaml
grafana_admin_password: "{{ vault_grafana_admin_password | default('admin') }}"
```

The `| default('admin')` fallback means if vault is not configured (common for initial setup), Grafana launches with `admin/admin` credentials. The page does NOT:
- Flag this as a security risk
- Recommend generating a random password
- Warn that Grafana is exposed via Caddy (`https://grafana.local/`) with default credentials
- Suggest using `GF_SECURITY_ADMIN_PASSWORD__FILE` for secrets management

### GAP-4: auditd.md -- `space_left_action: email` requires MTA that does not exist

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/auditd.md` (line 21)

```yaml
auditd_space_left_action: email
```

On a fresh Arch Linux (or minimal Debian) install, there is no configured MTA (Mail Transfer Agent). The `email` action requires `sendmail` or equivalent. When disk space runs low:
- auditd attempts to send email
- Email fails silently (no MTA)
- No alert is generated
- System continues without admin notification

**Fix required**: Default to `syslog` (which actually works) and document email as optional with MTA dependency.

### GAP-5: fail2ban.md -- nftables backend not properly documented

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/fail2ban.md` (lines 42-43)

The page mentions "integration with nftables" for Arch but does not provide the actual configuration needed. fail2ban defaults to `iptables` banaction. To use nftables, the jail.local must include:

```ini
[DEFAULT]
banaction = nftables
banaction_allports = nftables[type=allports]
```

The page also does not document:
- Whether the `firewall` role (nftables) creates the expected chains/tables that fail2ban-nftables expects
- Whether `fail2ban_action: action_` conflicts with the nftables banaction (they are different configuration layers)
- The specific nftables table/chain names fail2ban creates

---

## 3. Medium Issues

### MED-1: alloy.md -- loki.write endpoint URL syntax incomplete

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/alloy.md` (lines 105-109)

The example config shows:
```hcl
loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

Per [official Alloy loki.write docs](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/), this is syntactically correct. However, the wiki's `loki.source.journal` block is missing the recommended `relabel_rules` for extracting journal fields (unit name, priority, etc.). Without relabeling, all journal entries arrive in Loki with only internal `__journal_*` labels that are dropped, making logs very difficult to query.

### MED-2: prometheus.md -- `--storage.tsdb.retention.size` not shown in Docker command

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/prometheus.md` (line 106)

The Docker command only shows:
```
--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=15d
```

But the variable `prometheus_storage_retention_size: "10GB"` (line 54) is defined without being used in the command. The `--storage.tsdb.retention.size=10GB` flag is missing from the Docker command example.

`prometheus_query_max_concurrency: 20` (line 77) -- This IS a valid Prometheus flag (`--query.max-concurrency`), confirmed in official docs. Default Prometheus value is 20, so this is technically redundant but not wrong.

### MED-3: apparmor.md -- No mention of SELinux alternative for Fedora/RHEL

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/apparmor.md`

AppArmor is standard on Debian/Ubuntu, available on Arch (official repos, not AUR -- confirmed via Arch Wiki), but Fedora/RHEL use **SELinux** as their MAC system. The page has no mention of:
- SELinux as an alternative for Fedora/RHEL
- Whether the role should be skipped on SELinux-based distros
- The `systemd_hardening.md` page lists Fedora/RHEL in its distro sections, creating an implicit expectation of Fedora support

### MED-4: journald.md -- rate_limit_burst: 10000 tradeoff not discussed

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/journald.md` (line 64)

```yaml
journald_rate_limit_burst: 10000  # 10000 messages per 30s = ~333 msg/sec
```

For a desktop workstation, 333 messages/second is very high (normal desktop generates < 10 msg/sec). However, Docker containers logging to journald can easily exceed this under error conditions (crash loops, debug logging). The page does not discuss:
- When to increase vs decrease this value
- The relationship between this limit and the Alloy -> Loki pipeline (dropped journald messages = lost logs)
- That Docker's `--log-opt max-size` is a separate rate limit layer

### MED-5: certificates.md -- trust_anchors_path is Arch-only in variable definition

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/certificates.md` (lines 35-36)

```yaml
certificates_trust_anchors_path: /etc/ca-certificates/trust-source/anchors  # Arch
# certificates_trust_anchors_path: /usr/local/share/ca-certificates          # Debian
```

The Debian path is **commented out** in the defaults. This means the actual implementation must use `ansible_os_family` conditionals. However, the wiki only shows a comment, not how the conditional works. If implemented as-is (uncommented Arch line, commented Debian line), it will fail on Debian/Ubuntu because `/etc/ca-certificates/trust-source/anchors` does not exist there.

### MED-6: Structural inconsistency -- not all pages have Architecture section

Pages with Architecture diagram: `alloy.md`, `prometheus.md`, `loki.md`, `grafana.md`, `journald.md`, `node_exporter.md`, `cadvisor.md`

Pages WITHOUT Architecture section: `fail2ban.md`, `auditd.md`, `apparmor.md`, `systemd_hardening.md`, `certificates.md`, `watchtower.md`, `pam_hardening.md`

Some pages have "Notes" sections, others don't. The structural template is not consistently applied.

---

## 4. Minor Issues (low)

### MIN-1: "71% organizations" claim used 3 times without direct URL

**Appears in**:
- `alloy.md` (line 32): "71% organizations use Prometheus + OTel together"
- `prometheus.md` (line 37): "71% organizations use Prometheus + OTel together"
- `Roadmap.md` (line 177): "71% organizations use Prometheus + OTel together"

This claim IS verifiable -- it comes from the [Grafana Labs Observability Survey 2025](https://grafana.com/observability-survey/2025/). However:
- None of the three pages provide the source URL
- The statistic is "71% of respondents" (survey respondents, not all organizations globally)
- The wiki says "71% organizations" which omits the sampling bias (Grafana Labs survey audience is already skewed toward Prometheus/OTel users)
- The wording "Grafana Labs Survey 2025" is attributed but never linked

### MIN-2: "100% OTLP compatible, 120+ components" -- marketing language

**File**: `alloy.md` (line 7, 27-29), `Roadmap.md` (line 99, 177)

The [Grafana Alloy GitHub repository](https://github.com/grafana/alloy) and [official marketing page](https://grafana.com/oss/alloy-opentelemetry-collector/) do use these phrases. However:
- "100% OTLP compatible" is marketing language -- Alloy is an OTel Collector *distribution*, which means it supports OTLP by design. The "100%" adds nothing technical.
- "120+ components" is accurate per documentation but changes with releases. Consider "100+ components" or citing a specific version.

### MIN-3: fail2ban_action: action_ -- correct but non-obvious

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/fail2ban.md` (line 18)

`action_` is indeed a valid fail2ban action (ban only, no mail). However, the fail2ban convention uses `%(action_)s`, `%(action_mw)s`, `%(action_mwl)s`. The wiki stores it as `action_` without the `%()s` wrapper. The template that consumes this variable must add the wrapper -- this is not documented.

### MIN-4: watchtower.md -- port conflict with cAdvisor

**File**: `/Users/umudrakov/Documents/bootstrap/wiki/roles/watchtower.md` (line 48)

```yaml
watchtower_http_api_port: 8080
```

cAdvisor also uses port 8080 (`cadvisor.md` line 51). If both Watchtower HTTP API and cAdvisor are enabled, there will be a port conflict. The default `watchtower_http_api: false` prevents this, but it's not documented as a known conflict.

### MIN-5: Tag naming inconsistency

- `systemd_hardening.md`: tags are `systemd`, `hardening`, `security`, `sandboxing` (4 tags as bullet list)
- `fail2ban.md`: tags are `fail2ban`, `security`, `ips` (3 tags inline)
- `watchtower.md`: tags are `docker`, `autodeploy`, `containers`, `watchtower` (4 tags as bullet list)
- Most other pages use inline comma-separated format

Some pages use markdown bullet lists for tags, others use inline format. This makes automation (tag parsing) unreliable.

---

## 5. Missing Roles (gap analysis)

### Documented in Roadmap but no wiki page

| Role | Phase | Status |
|------|-------|--------|
| `logrotate` | 8 | Listed in Roadmap Phase 8 (line 97) but no wiki page exists in `wiki/roles/` |
| `network` | 5 | Listed in Roadmap Phase 5 but no wiki page |
| `dns` | 5 | Listed in Roadmap Phase 5 but no wiki page |
| `vpn` | 5 | Listed in Roadmap Phase 5 but no wiki page |

### Referenced as dependencies but no wiki page

| Role | Referenced from | Context |
|------|----------------|---------|
| `firewall` | `fail2ban.md` | "fail2ban adds rules to active firewall" -- but what role manages nftables? |
| `ssh` | `fail2ban.md`, `auditd.md` | Referenced as dependency; exists as existing role but no wiki page in `wiki/roles/` |

### Roles that should exist based on architecture

| Role | Reason |
|------|--------|
| `alertmanager` | `prometheus.md` references `alertmanager:9093` endpoint but no role exists to deploy it |
| `docker_logging` | The logging pipeline assumes Docker uses journald log driver, but the Docker role must configure `--log-driver=journald`. This is mentioned in `journald.md` but there is no clear role ownership documentation |

---

## 6. Architecture Questions

### AQ-1: Resource Budget -- Is the full observability stack realistic for a 16GB workstation?

Estimated RAM consumption of the full Phase 8 stack running simultaneously:

| Service | Expected RAM (idle) | Expected RAM (load) | Docker image |
|---------|-------------------|---------------------|--------------|
| Prometheus | 200-500 MB | 1-2 GB (high cardinality queries) | prom/prometheus:latest |
| Loki | 200-400 MB | 500 MB - 1 GB (during ingestion) | grafana/loki:latest |
| Alloy | 100-200 MB | 300-500 MB (with WAL) | grafana/alloy:latest |
| Grafana | 100-200 MB | 300-500 MB (dashboard rendering) | grafana/grafana:latest |
| cAdvisor | 100-200 MB | 200-400 MB | gcr.io/cadvisor/cadvisor:latest |
| node_exporter | 20-50 MB | 50-100 MB | prom/node-exporter:latest |
| Watchtower | 20-50 MB | 50-100 MB | containrrr/watchtower:latest |
| **TOTAL (idle)** | **~740 MB - 1.6 GB** | | |
| **TOTAL (load)** | | **~2.4 - 4.6 GB** | |

On a 16 GB workstation also running:
- Desktop environment (GNOME/KDE: 500 MB - 1.5 GB)
- Browser (2-6 GB with tabs)
- IDE (1-3 GB)
- Docker development containers (variable)
- The services being monitored (Caddy, Vaultwarden, etc.)

**Realistic assessment**: At idle, the observability stack uses ~1 GB which is acceptable. Under load (complex Grafana dashboards, Loki queries over 30 days of data, Prometheus PromQL with high cardinality), it can spike to 3-5 GB. Combined with normal workstation usage (8-12 GB), the system may encounter memory pressure.

**Recommendation**: Document memory limits in docker-compose (`deploy.resources.limits.memory`) and recommend disabling cAdvisor and node_exporter when not actively monitoring, or set Prometheus retention to 7d instead of 15d on <16 GB systems.

### AQ-2: Cascading failure mode -- log pipeline during outages

The logging pipeline is: Docker -> journald -> Alloy -> Loki -> Grafana

If Loki goes down:
1. Alloy buffers logs in WAL (`/opt/alloy/data`) -- size is unbounded in the wiki config
2. If WAL fills disk, Alloy may crash
3. journald continues storing locally (bounded by `journald_system_max_use: 1G`)
4. No logs are queryable in Grafana

If Alloy goes down:
1. journald continues storing locally
2. Logs generated while Alloy is down are NOT retroactively forwarded (Alloy reads from current journal position)
3. Gap in Loki data

None of these failure modes are documented in any wiki page.

### AQ-3: Docker network topology unclear

All Docker services use `docker_network: "proxy"`. This means Prometheus, Loki, Grafana, Alloy, cAdvisor, node_exporter, and Watchtower all share the same Docker network. While this enables inter-service communication, it also means:
- Any compromised container can reach all other containers on the network
- No network segmentation between monitoring stack and application containers
- The "proxy" network is named for Caddy reverse proxy but is being used as a general-purpose service mesh

### AQ-4: Service discovery inconsistency

- `prometheus.md` uses static configs: `node_exporter:9100`, `cadvisor:8080` (Docker DNS names)
- `alloy.md` connects to `loki:3100` (Docker DNS name)
- `grafana.md` connects to `loki:3100` and `prometheus:9090` (Docker DNS names)

This only works if all services are on the same Docker network AND use specific container names. But each role deploys its own `docker-compose.yml` in a separate directory (`/opt/prometheus/`, `/opt/loki/`, etc.). Separate docker-compose files create separate default networks unless explicitly connected to the shared "proxy" network.

The wiki does not document the requirement that ALL docker-compose files must include:
```yaml
networks:
  proxy:
    external: true
```

Without this, Docker DNS resolution between services will fail.

---

## 7. Recommendations

Prioritized by impact (highest first).

### P0 -- Must fix before implementation

| # | File | Fix |
|---|------|-----|
| 1 | `systemd_hardening.md` | Redesign to use per-service configuration dictionary. Remove `docker` from default service list OR add per-service override mechanism with documented Docker-safe defaults |
| 2 | `pam_hardening.md` | Add "Conflict with base_system QW-5" section. Decide ownership of faillock.conf. Only one role should manage it |
| 3 | `alloy.md` | Replace `Privileged: true` with read-only bind mounts and group membership. Document bind mount approach as primary, privileged as deprecated fallback |
| 4 | `apparmor.md` | Update kernel parameter from `apparmor=1 security=apparmor` to `lsm=landlock,lockdown,yama,integrity,apparmor,bpf`. Add `bootloader` dependency |
| 5 | `loki.md` | Document full retention chain: compactor + limits_config + delete_request_store + 24h index period requirement |
| 6 | ALL Docker roles | Pin image versions: `grafana/alloy:v1.5`, `prom/prometheus:v2.53`, `grafana/loki:3.4`, `grafana/grafana:11.4`, `containrrr/watchtower:1.7.1` (adjust to current stable) |

### P1 -- Should fix before implementation

| # | File | Fix |
|---|------|-----|
| 7 | `watchtower.md` | Default to label-based filtering (`WATCHTOWER_LABEL_ENABLE=true`). Document cascading failure risk. Note project is archived/EOL since Dec 2025 |
| 8 | `grafana.md` | Remove `| default('admin')` fallback. Require vault password or fail with clear error. Add security warning about HTTPS exposure with default credentials |
| 9 | `auditd.md` | Change `space_left_action` default to `syslog`. Document MTA requirement for `email` action |
| 10 | `fail2ban.md` | Add explicit nftables backend configuration: `banaction = nftables`, `banaction_allports = nftables[type=allports]`. Document interaction with firewall role |
| 11 | `certificates.md` | Replace commented-out Debian path with proper `ansible_os_family` conditional documentation |
| 12 | ALL Docker roles | Document `networks: proxy: external: true` requirement for inter-service DNS resolution |

### P2 -- Nice to have

| # | File | Fix |
|---|------|-----|
| 13 | `alloy.md` | Add `relabel_rules` example for extracting journal fields (unit, priority) |
| 14 | `prometheus.md` | Add `--storage.tsdb.retention.size=10GB` to Docker command example |
| 15 | `apparmor.md` | Add note about SELinux on Fedora/RHEL |
| 16 | `journald.md` | Add section discussing rate_limit_burst tradeoffs for Docker workloads |
| 17 | ALL pages | Standardize structure: every page should have Purpose, Architecture, Variables, What it configures, Dependencies, Tags sections |
| 18 | `alloy.md`, `prometheus.md`, `Roadmap.md` | Add source URL for "71% organizations" claim: https://grafana.com/observability-survey/2025/ |
| 19 | ALL pages | Add estimated RAM usage to each Docker-based role page |
| 20 | ALL Docker roles | Add `deploy.resources.limits.memory` recommendations in docker-compose examples |

---

## Appendix: Verification Sources

- Grafana Alloy loki.source.journal: https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
- Prometheus CLI flags: https://prometheus.io/docs/prometheus/latest/command-line/prometheus/
- Loki retention docs: https://grafana.com/docs/loki/latest/operations/storage/retention/
- AppArmor on Arch: https://wiki.archlinux.org/title/AppArmor
- fail2ban nftables: https://wiki.archlinux.org/title/Fail2ban
- Grafana Labs Observability Survey 2025: https://grafana.com/observability-survey/2025/
- Watchtower GitHub (archived): https://github.com/containrrr/watchtower
- systemd ProtectSystem docs: https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html
