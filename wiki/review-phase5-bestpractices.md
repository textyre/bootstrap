# Phase 5: Best Practices Comparison — Research Review

**Date:** 2026-02-17
**Reviewer:** Research synthesis from claudette-researcher output (agent completed research but failed to write file due to context loss)
**Scope:** 6 research questions comparing project against industry best practices + 1 claim verification
**Sources:** 30+ web searches, official documentation, Habr articles index

---

## Executive Summary

The project's approach to hardening is **directionally correct but behind industry standards** in several areas. Key gaps:

1. **dev-sec.io covers significantly more** than the project's current roles (auditd, mount options, login.defs, PAM policies, module loading)
2. **CIS Level 1 coverage is ~35-40%** — strong on network/sysctl, weak on filesystem and access control
3. **Grafana Alloy documentation uses "Alloy syntax"** (not "River") — wiki pages use outdated terminology
4. **Docker Content Trust deprecated** Sept 2025 — project's Docker signing approach needs Sigstore/Notation instead
5. **Ansible Collections recommended** over standalone roles for distribution — project uses standalone roles
6. **No pre-commit hooks or CI/CD pipeline** — industry standard since 2024+

---

## Question 1/6: dev-sec.io Hardening Framework Comparison

### What dev-sec.io Covers

The [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening) provides battle-tested hardening for Linux, SSH, nginx, and MySQL. It implements CIS, DISA STIG, and NIST guidelines.

**Supported OS:** Ubuntu 18.04-22.04, Debian 10-11, RHEL 7-9, CentOS 7-9, Oracle 6-8, OpenSuse 42.

**Key roles:**
- `os_hardening` — filesystem, kernel, PAM, login.defs, auditd, mount options, module loading
- `ssh_hardening` — comprehensive SSH crypto, access control, banner, SFTP
- `docker_hardening` — Docker daemon, image signing, resource limits, network
- `nginx_hardening` — headers, TLS, rate limiting
- `mysql_hardening` — authentication, privileges, logging

### What dev-sec.io Covers That the Project Does NOT

| Area | dev-sec.io | This Project | Gap |
|------|-----------|--------------|-----|
| Filesystem mount options | `/tmp noexec,nosuid`, `/var/log noexec`, `/home nosuid` | Not implemented | **Critical** |
| Module loading restrictions | `install cramfs /bin/true`, blacklist 20+ modules | Not implemented | **Serious** |
| Auditd rules | Full syscall auditing (execve, mount, chmod, etc.) | Planned (Phase 3) but no code | **Serious** |
| `/etc/login.defs` | PASS_MAX_DAYS, PASS_MIN_DAYS, UMASK, SHA_CRYPT_ROUNDS | Not implemented | **Serious** |
| PAM policies | pwquality (minlen, dcredit, ucredit), pam_limits | Only faillock (partial) | **Medium** |
| Banner/MOTD | SSH warning banner, /etc/issue | Not implemented | **Minor** |
| Core dumps | `* hard core 0` in limits.conf + sysctl | Only `fs.suid_dumpable: 0` (partial) | **Medium** |
| AIDE/integrity monitoring | File integrity monitoring | Not planned | **Serious** |

### Verdict

The project re-implements ~30% of what dev-sec.io already provides in a battle-tested, multi-distro format. **Recommendation:** Consider using `devsec.hardening` collection as a dependency rather than reimplementing. At minimum, the project should match dev-sec.io's os_hardening scope before claiming "security hardening."

**Sources:**
- [dev-sec.io](https://dev-sec.io/)
- [GitHub: dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening)
- [Ansible Galaxy: devsec.hardening](https://galaxy.ansible.com/ui/repo/published/devsec/hardening/content/)

---

## Question 2/6: CIS Benchmarks Coverage Analysis

### CIS Benchmark Structure (Linux)

Based on CIS Ubuntu Linux 22.04 LTS Benchmark v2.0.0 and general Linux benchmark structure:

| Section | Category | Controls |
|---------|----------|----------|
| 1.x | Filesystem Configuration | Partitions, mount options, module loading, bootloader |
| 2.x | Services | inetd, special-purpose services, service clients |
| 3.x | Network Configuration | IPv4/IPv6 params, firewall, wireless |
| 4.x | Logging and Auditing | rsyslog/journald, auditd, log file permissions |
| 5.x | Access, Authentication | SSH, PAM, password policies, su restriction |
| 6.x | System Maintenance | File permissions, user/group settings |

### Level 1 vs Level 2

- **Level 1**: Practical, minimal disruption, applicable to most environments. ~200+ controls.
- **Level 2**: Maximum security, may impact functionality. ~50+ additional controls on top of Level 1.

### Project Coverage Estimate

| CIS Section | Project Coverage | Assessment |
|-------------|-----------------|------------|
| 1.x Filesystem | **~15%** | No partition separation, no mount options, no module blacklisting, no bootloader password |
| 2.x Services | **~25%** | Docker service managed, but no inetd/xinetd cleanup, no service audit |
| 3.x Network | **~70%** | Strong sysctl coverage, firewall present, but no IPv6 hardening, no egress filtering |
| 4.x Logging | **~20%** | journald planned (Phase 2), auditd planned (Phase 3), no log permissions, no remote logging |
| 5.x Access | **~45%** | SSH hardened (QW-1), PAM faillock (QW-5), sudo (QW-6), but no password policies, no su restriction |
| 6.x Maintenance | **~10%** | No file permission auditing, no user/group cleanup |

**Overall CIS Level 1 Coverage: ~35%** (weighted by control count)

### Critical Gaps for Level 1 Compliance

1. **Filesystem hardening** (Section 1.x) — largest gap, most controls missing
2. **Logging/Auditing** (Section 4.x) — auditd not implemented, only planned
3. **Service cleanup** (Section 2.x) — no unused service removal
4. **System maintenance** (Section 6.x) — no file permission auditing

**Note:** CIS does NOT publish an Arch Linux-specific benchmark. The project must adapt Ubuntu/RHEL benchmarks to Arch, which adds complexity (different package managers, init systems are the same but package names differ).

**Sources:**
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [CIS Ubuntu Linux Benchmarks](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [OpenSCAP CIS Level 1 Server Guide](https://static.open-scap.org/ssg-guides/ssg-ubuntu2204-guide-cis_level1_server.html)
- [LinuxVox: CIS Benchmark for Linux Guide](https://linuxvox.com/blog/cis-benchmark-linux/)
- [Petrosky: Linux VPS Security Checklist CIS](https://petrosky.io/linux-vps-security-checklist-cis/)

---

## Question 3/6: Grafana Alloy Documentation Verification

### Configuration Language

The official Grafana Alloy documentation (v1.x, 2025-2026) refers to the configuration language as **"Alloy syntax"** or **"Alloy configuration syntax"**. The previous name **"River"** was used in early pre-release versions but has been **officially renamed**.

The project's wiki pages (`wiki/roles/alloy.md`) use "River config syntax" — this is **outdated terminology**.

### Component Count

The documentation lists components across categories:
- Discovery (multiple cloud/infrastructure platforms)
- Loki components (source, process, write)
- Prometheus components (scrape, relabel, remote_write)
- OpenTelemetry Collector components (receivers, processors, exporters)
- Mimir components
- Pyroscope (profiling)
- Beyla (eBPF auto-instrumentation)

The exact count of "120+ components" claimed in the wiki is **plausible but not independently verified** from the docs page reviewed. The reference section lists extensive categories.

### OTLP Compatibility

Alloy is described as an "OpenTelemetry Collector distribution with Prometheus pipelines." The "100% OTLP compatible" claim is **approximately correct** — Alloy is built on the OpenTelemetry Collector codebase and supports OTLP natively. However, it is a **distribution**, not a fork, meaning it may not support every single OTel Collector plugin.

### Findings for the Project

| Wiki Claim | Verification | Status |
|------------|-------------|--------|
| "River config syntax" | Now called "Alloy syntax" | **Outdated** |
| "120+ components" | Plausible, not exact-counted | **Approximate** |
| "100% OTLP compatible" | Distribution of OTel Collector, native OTLP | **Approximately correct** |
| `grafana/alloy:latest` Docker tag | Should pin version, not `latest` | **Anti-pattern** |
| Privileged mode for journald | NOT required — group membership sufficient | **Incorrect** (also found in Phase 3) |

**Sources:**
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Grafana Alloy Introduction](https://grafana.com/docs/alloy/latest/introduction/)
- [Grafana Alloy Reference: loki.source.journal](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/)

---

## Question 4/6: Prometheus Best Practices

### Official Recommendations

Based on Prometheus official documentation and community best practices:

| Practice | Recommendation | Project Status |
|----------|---------------|----------------|
| **Recording rules** | Pre-compute expensive queries | Not configured (no recording rules in wiki) |
| **Alerting rules** | Define alerts with `for` duration, severity labels | Mentioned in wiki but no concrete rules |
| **Retention** | 15-90 days local, remote_write for long-term | `prometheus_storage_retention_time: "15d"` — **correct** |
| **Naming conventions** | `<namespace>_<subsystem>_<name>_<unit>` | Not documented in project |
| **Label cardinality** | Keep low (job, instance, env), avoid high (user_id) | Correctly documented in wiki |
| **Scrape interval** | 15s-60s default, per-job overrides | Not configurable in project defaults |
| **Resource limits** | Memory limits for Prometheus container | Not configured |
| **Security** | `--web.enable-admin-api` disabled, basic auth or reverse proxy | No authentication configured |
| **Federation/Remote Write** | For multi-node or long-term storage | Not planned |
| **Docker image tag** | Pin specific version | Uses `prom/prometheus:latest` — **anti-pattern** |

### Key Gap

The project's Prometheus wiki page describes the architecture correctly but lacks **operational best practices**: no recording rules, no alerting rules examples, no resource limits, no authentication. For a security-focused project, running Prometheus without authentication (even behind Caddy) is a gap.

**Sources:**
- [Prometheus Best Practices: Naming](https://prometheus.io/docs/practices/naming/)
- [Prometheus Best Practices: Recording Rules](https://prometheus.io/docs/practices/rules/)
- [Prometheus Best Practices: Alerting](https://prometheus.io/docs/practices/alerting/)
- [Prometheus Storage](https://prometheus.io/docs/prometheus/latest/storage/)

---

## Question 5/6: Docker Security 2025-2026

### Docker Content Trust (DCT) — DEPRECATED

**Critical finding:** Docker Content Trust was **retired starting September 30, 2025**. All DCT data will be permanently deleted by March 31, 2028.

- Fewer than 0.05% of Docker Hub image pulls use DCT
- The upstream Notary v1 codebase is no longer actively maintained
- Microsoft announced DCT deprecation in Azure Container Registry

**Recommended alternatives:**
- **Sigstore** (cosign) — stores signatures in public registries, transparent and auditable
- **Notation** (Notary v2) — specification-driven, supports multiple signatures, integrates with existing PKI

**Impact on project:** The wiki's reference to Docker Content Trust as a security measure is **obsolete**. The project should adopt Sigstore/cosign for image verification.

### Rootless Docker vs userns-remap

The project uses `docker_userns_remap` (disabled by default). Current Docker best practice (2025-2026):

| Approach | Status | Recommendation |
|----------|--------|----------------|
| `userns-remap` | Legacy, still supported | Breaks volume permissions, limited adoption |
| **Rootless Docker** | **Modern recommendation** | Runs entire daemon as non-root, better isolation |
| Docker Desktop | Uses rootless internally | Not applicable to server/workstation |

**Rootless Docker advantages:**
- No root daemon process
- Stronger isolation (entire daemon in user namespace)
- No volume permission issues (unlike userns-remap)
- Supported since Docker 20.10+

**Recommendation:** Replace `docker_userns_remap` with rootless Docker installation option. Add `docker_rootless: false` variable with documentation.

### Docker Bench for Security

[Docker Bench for Security](https://github.com/docker/docker-bench-security) is the standard audit tool. The project does not mention it. Running it as a verification step would validate Docker hardening.

**Sources:**
- [Docker Blog: Retiring Docker Content Trust](https://www.docker.com/blog/retiring-docker-content-trust/)
- [InfoQ: Docker Content Trust Retired](https://www.infoq.com/news/2025/08/docker-content-trust-retired/)
- [Cloudsmith: Migrating from DCT to Sigstore](https://cloudsmith.com/blog/migrating-from-docker-content-trust-to-sigstore)
- [Microsoft: DCT Deprecation in ACR](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-content-trust-deprecation)
- [Docker Docs: Rootless mode](https://docs.docker.com/engine/security/rootless/)

---

## Question 6/6: Ansible Best Practices 2025-2026

### Collections vs Standalone Roles

**Current industry practice:** Collections are the **recommended distribution format**. Standalone roles are not supported in Ansible Automation Hub.

The project uses standalone roles in `ansible/roles/`. This is acceptable for internal use but:
- Makes sharing/reuse harder
- No plugin embedding support (only collections support plugins)
- No version management through Galaxy

**Recommendation:** For a project of this size (~50+ planned roles), consider organizing as a collection: `namespace.bootstrap` with roles inside.

### Testing with Molecule

Molecule provides automated testing with:
- Docker/Podman container-based testing environments
- Multi-platform scenarios (test against multiple distros)
- Built-in idempotency checks
- Test lifecycle: create → converge → idempotence → verify → destroy

**Project status:** Molecule mentioned in AGENTS.md and Taskfile.yml but:
- No `molecule/` directories in any roles
- No CI/CD pipeline to run tests
- No `.yamllint` or `.ansible-lint` configuration files

### Pre-commit Hooks

Industry standard setup for Ansible projects (2025-2026):

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/ansible/ansible-lint.git
    rev: v25.x.x
    hooks:
      - id: ansible-lint
        language_version: python3  # Pin to avoid 3.13 issues
```

**Project status:** No `.pre-commit-config.yaml` exists. No `.ansible-lint` configuration. This is a significant gap for a project claiming security focus — code quality gates should be in place.

**Note:** ansible-lint recently pinned Python to 3.13 in pre-commit hooks. If using older Python, override with `language_version: python3`.

### CI/CD Pipeline

Modern Ansible projects use:
- GitHub Actions or GitLab CI to run Molecule tests on PRs
- ansible-lint as a required check
- Matrix testing across target distributions
- Automatic security scanning (e.g., Trivy for Docker images)

**Project status:** No CI/CD configuration found (`.github/workflows/`, `.gitlab-ci.yml`).

**Sources:**
- [Jeff Geerling: Ansible Best Practices](https://www.jeffgeerling.com/blog/2020/ansible-best-practices-using-project-local-collections-and-roles/)
- [Ansible Docs: Migrating Roles to Collections](https://docs.ansible.com/ansible/latest/dev_guide/migrating_roles.html)
- [Spacelift: 50+ Ansible Best Practices](https://spacelift.io/blog/ansible-best-practices)
- [Roethof.net: CI/CD Pipeline for Ansible Roles](https://roethof.net/posts/2025/04/building-proper-cicd-pipeline-ansible-roles/)
- [Ansible.com: Testing with Molecule and Podman](https://www.ansible.com/blog/developing-and-testing-ansible-roles-with-molecule-and-podman-part-1/)
- [Reinout van Rees: ansible-lint pre-commit](https://reinout.vanrees.org/weblog/2025/11/19/ansible-lint-pre-commit.html)
- [Ansible-lint .pre-commit-hooks.yaml](https://github.com/ansible/ansible-lint/blob/main/.pre-commit-hooks.yaml)

---

## Bonus: "71% of organizations use Prometheus + OTel" Claim Verification

### Source

The claim appears in `wiki/roles/alloy.md` (line 32) and `wiki/roles/prometheus.md` (line 37).

### Verification

**VERIFIED — with nuance.** The Grafana Labs [Observability Survey 2025](https://grafana.com/observability-survey/2025/) (conducted Sept 2024 – Jan 2025) reports:

> "71% of all respondents are using both Prometheus and OpenTelemetry **in some capacity**"

However, the critical qualifier is "in some capacity" which includes:
- Investigating / evaluating
- Building POCs
- In production (some)
- Extensively
- Exclusively

**Only 34% are using both in production** in some capacity.

### Detailed Breakdown

| Tool | Production Usage | All Stages (incl. POC/investigating) |
|------|-----------------|-------------------------------------|
| Prometheus | 67% | 86% |
| OpenTelemetry | 41% | 79% |
| Both together | **34%** (production) | **71%** (any stage) |

### Verdict

The wiki pages cite "71% организаций используют Prometheus + OTel вместе" without the "in some capacity" qualifier. This is **misleading** — it implies 71% use both in production, when the actual production figure is 34%. The wiki should either:
1. Add the qualifier: "71% используют в той или иной степени (включая POC и исследование)"
2. Use the production figure: "34% используют оба в продакшене"

**Sources:**
- [Grafana Labs: Observability Survey 2025 Key Findings](https://grafana.com/observability-survey/2025/)
- [Grafana Labs Blog: State of Observability 2025](https://grafana.com/blog/observability-survey-takeaways/)
- [Grafana Labs Press: 2025 Survey Findings at KubeCon](https://grafana.com/about/press/2025/03/25/grafana-labs-unveils-2025-observability-survey-findings-and-open-source-updates-at-kubecon-europe/)

---

## Summary of Findings

### By Severity

| # | Severity | Finding | Source |
|---|----------|---------|--------|
| 1 | **Critical** | Docker Content Trust deprecated Sept 2025 — project references obsolete technology | Q5 |
| 2 | **Serious** | Only ~35% CIS Level 1 coverage — filesystem hardening (Section 1.x) almost entirely missing | Q2 |
| 3 | **Serious** | dev-sec.io covers 2-3x more hardening areas than project — consider as dependency | Q1 |
| 4 | **Serious** | No pre-commit hooks, no CI/CD pipeline, no Molecule test directories | Q6 |
| 5 | **Serious** | No ansible-lint or yamllint configuration | Q6 |
| 6 | **Medium** | Alloy wiki uses outdated "River" terminology — now "Alloy syntax" | Q3 |
| 7 | **Medium** | Rootless Docker is modern recommendation, project only offers userns-remap | Q5 |
| 8 | **Medium** | Prometheus has no recording rules, alerting rules, or authentication | Q4 |
| 9 | **Medium** | "71% Prometheus+OTel" claim misleading — 34% in production, 71% includes POC/investigating | Bonus |
| 10 | **Medium** | All wiki Docker images use `:latest` tag — should pin versions | Q3, Q4 |
| 11 | **Minor** | Standalone roles instead of Ansible Collection — acceptable but not modern best practice | Q6 |
| 12 | **Minor** | No Docker Bench for Security as validation step | Q5 |
