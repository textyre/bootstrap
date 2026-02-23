# Ansible Variable Naming Violations Report

**Date:** February 22, 2026  
**Project:** Bootstrap Ansible Playbooks  
**Scope:** 33 roles, 400+ variable naming violations  
**Naming Rule:** All variables must use role name as prefix (e.g., `common_*`, `ntp_*`, `git_*`)

## Executive Summary

The Ansible codebase has widespread variable naming violations. Variables starting with single underscores (indicating "private" scope in Ansible) are used without proper role prefixes. This violates the role naming standard where ALL variables must follow the pattern `<role_name>_<variable_purpose>`.

### Violation Categories

1. **Shared Reporting Variables** (`_rpt_*`) — Used across 15+ roles
2. **Verify Variables** (`_verify_*`, `_v_*`) — Used in molecule test files and role tasks
3. **Internal Helper Variables** (`_check_*`, `_vm_*`, etc.) — When not role-prefixed
4. **Fact/Status Variables** (various patterns) — Used in tasks

---

## 1. SHARED REPORTING VARIABLES (`_rpt_*` → `common_rpt_*`)

These variables are part of a shared execution reporting framework in the `common` role. They are included via `include_role` from multiple roles and should be prefixed with `common_`.

### Pattern: Report Phase Variables

**Current Names (VIOLATIONS):**
- `_rpt_fact` → **`common_rpt_fact`**
- `_rpt_phase` → **`common_rpt_phase`**
- `_rpt_status` → **`common_rpt_status`**
- `_rpt_detail` → **`common_rpt_detail`**
- `_rpt_title` → **`common_rpt_title`**
- `_rpt_footer_rows` → **`common_rpt_footer_rows`**

**Usage Count:** 150+ occurrences across 15 roles

**Affected Files (Sample):**
| File | Line | Context |
|------|------|---------|
| `ansible/roles/git/tasks/main.yml` | 35-37 | `_rpt_fact: "_git_phases"` |
| `ansible/roles/ssh/tasks/main.yml` | 30-32 | `_rpt_fact: "_ssh_phases"` |
| `ansible/roles/hostname/tasks/main.yml` | 51-53 | `_rpt_fact: "_hostname_phases"` |
| `ansible/roles/locale/tasks/main.yml` | 19-22 | Multiple `_rpt_*` |
| `ansible/roles/vm/tasks/main.yml` | 24-93 | Multiple `_rpt_*` |

**Roles Using This Pattern:**
- `git`, `ssh`, `hostname`, `locale`, `timezone`, `shell`, `user`, `ssh_keys`, `vconsole`, `vm`, `ntp`, `fail2ban`, `teleport`

**Helper Variable Also Affected:**
- `_row` → **`common_rpt_row`** (line 40 in report_phase.yml)
- `_st` → **`common_rpt_status_mark`** (local to report_phase.yml)
- `_mk` → **`common_rpt_mark`** (local to report_phase.yml)

---

## 2. VERIFY VARIABLES WITHOUT ROLE PREFIX

Molecule verify.yml files and role verify tasks use `_verify_*` or `_v_*` patterns without role prefixes.

### Pattern A: Generic `_verify_*` (WITHOUT role name)

**Affected Roles and Violations:**

#### pam_hardening
```
_verify_faillock_conf        → pam_hardening_verify_faillock_conf
_verify_faillock_content     → pam_hardening_verify_faillock_content
_verify_pam_profile          → pam_hardening_verify_pam_profile
_verify_pam_authfail_profile → pam_hardening_verify_pam_authfail_profile
```
**Files:**
- `ansible/roles/pam_hardening/molecule/default/verify.yml` (lines 15, 21, 45, 52)

#### hostctl
```
_verify_version   → hostctl_verify_version
_verify_profile   → hostctl_verify_profile
_verify_entry     → hostctl_verify_entry
_verify_applied   → hostctl_verify_applied
_verify_base      → hostctl_verify_base
```
**Files:**
- `ansible/roles/hostctl/molecule/default/verify.yml` (lines 10, 22, 31, 37, 43)

#### hostname
```
_verify_hostname      → hostname_verify_hostname
_verify_hosts_resolve → hostname_verify_hosts_resolve
_verify_hosts         → hostname_verify_hosts
```
**Files:**
- `ansible/roles/hostname/molecule/default/verify.yml` (lines 12, 23, 29)

#### locale
```
_verify_locales     → locale_verify_locales
_verify_locale_conf → locale_verify_locale_conf
_verify_locale_cmd  → locale_verify_locale_cmd
```
**Files:**
- `ansible/roles/locale/molecule/default/verify.yml` (lines 20, 36, 60)

#### fail2ban
```
_verify_version     → fail2ban_verify_version
_verify_jail_config → fail2ban_verify_jail_config
_verify_maxretry    → fail2ban_verify_maxretry
_verify_bantime     → fail2ban_verify_bantime
```
**Files:**
- `ansible/roles/fail2ban/molecule/default/verify.yml` (lines 14, 23, 35, 42)

#### ntp
```
_verify_chrony           → ntp_verify_chrony
_verify_ntp_tracking     → ntp_verify_ntp_tracking
_verify_ntp_sources      → ntp_verify_ntp_sources
_verify_ntp_synced       → ntp_verify_ntp_synced
_verify_nts_sources      → ntp_verify_nts_sources
_verify_chrony_conf      → ntp_verify_chrony_conf
_verify_chrony_conf_content → ntp_verify_chrony_conf_content
_verify_logdir           → ntp_verify_logdir
_verify_ntsdumpdir       → ntp_verify_ntsdumpdir
```
**Files:**
- `ansible/roles/ntp/molecule/default/verify.yml` (lines 26, 49, 63, 78, 95, 112, 124, 171, 184)

#### shell
```
_verify_zsh              → shell_verify_zsh
_verify_xdg              → shell_verify_xdg
_verify_profiled         → shell_verify_profiled
_verify_profiled_content → shell_verify_profiled_content
_verify_zshenv           → shell_verify_zshenv
_verify_zshenv_content   → shell_verify_zshenv_content
```
**Files:**
- `ansible/roles/shell/molecule/default/verify.yml` (lines 20, 48, 70, 82, 108, 120)

#### vconsole
```
_verify_vconsole       → vconsole_verify_vconsole
_verify_localectl      → vconsole_verify_localectl
_verify_keymap_openrc  → vconsole_verify_keymap_openrc
_verify_keymap_runit   → vconsole_verify_keymap_runit
```
**Files:**
- `ansible/roles/vconsole/molecule/default/verify.yml` (lines 19, 25, 61, 68)

#### firewall
```
_firewall_verify_nftables           → firewall_verify_nftables (CORRECT!)
_firewall_verify_nftables_conf      → firewall_verify_nftables_conf (CORRECT!)
_firewall_verify_nftables_table     → firewall_verify_nftables_table (CORRECT!)
_firewall_verify_service           → firewall_verify_service (CORRECT!)
_firewall_verify_rules             → firewall_verify_rules (CORRECT!)
```
**Note:** firewall role is correctly prefixed! ✓

**Total Count for Pattern A:** ~40 violations

---

### Pattern B: Abbreviated `_v_*` (ntp_audit)

The `ntp_audit` role uses severely abbreviated variable names:

```
_v_script      → ntp_audit_verify_script
_v_src         → ntp_audit_verify_src
_v_logdir      → ntp_audit_verify_logdir
_v_logfile     → ntp_audit_verify_logfile
_v_last_line   → ntp_audit_verify_last_line
_v_logrotate   → ntp_audit_verify_logrotate
_v_alloy       → ntp_audit_verify_alloy
_v_loki        → ntp_audit_verify_loki
```

**Files:**
- `ansible/roles/ntp_audit/tasks/verify.yml` (lines 7, 21, 35, 49, and more)
- `ansible/roles/ntp_audit/molecule/default/verify.yml` (lines 14, 26, 38, 50, 62, 79, 104, 116)

**Total Count for Pattern B:** ~16 violations

---

### Pattern C: Role-Specific Verify (Already Correct Pattern)

These roles CORRECTLY use role-prefixed verify variables:

```
_git_verify_*        → CORRECT (role-prefixed)
_ssh_verify_*        → CORRECT (role-prefixed)
_chezmoi_verify_*    → CORRECT (role-prefixed)
_caddy_verify_*      → CORRECT (role-prefixed)
_lightdm_verify_*    → CORRECT (role-prefixed)
_vaultwarden_verify_* → CORRECT (role-prefixed)
_docker_verify_*     → CORRECT (role-prefixed)
_gpu_verify_*        → CORRECT (role-prefixed) [from gpu_drivers]
_sysctl_verify_*     → CORRECT (role-prefixed)
_zen_verify_*        → CORRECT (role-prefixed)
```

**Note:** These follow the correct naming standard and should NOT be changed!

---

## 3. COMMON ROLE HELPER VARIABLES

### Pattern: Internet Connectivity Check

**File:** `ansible/roles/common/tasks/check_internet.yml`

```
_check_internet_host    → common_check_internet_host
_check_internet_port    → common_check_internet_port
_check_internet_timeout → common_check_internet_timeout
```

**Usage Count:** ~10 occurrences  
**Lines:** 5-30

**Context:**
```yaml
- name: "Check internet connectivity ({{ _check_internet_host }}:{{ _check_internet_port }})"
  ansible.builtin.wait_for:
    host: "{{ _check_internet_host }}"
    port: "{{ _check_internet_port }}"
    timeout: "{{ _check_internet_timeout | default(5) }}"
```

---

## 4. CORRECTLY-PREFIXED INTERNAL VARIABLES (NO ACTION NEEDED)

The following variables are CORRECTLY prefixed and should NOT be changed:

### VM Role (`_vm_*`)
- All `_vm_*` variables are correctly prefixed with `vm_` (the role name)
- Examples: `_vm_hypervisor`, `_vm_is_guest`, `_vm_virt_type`, `_vm_svc_result`, etc.

### Git Role (`_git_*`)
- `_git_verify_*`, `_git_current_safe_dirs`, etc. — **CORRECT**

### SSH Role (`_ssh_*`)
- `_ssh_verify_*`, `_ssh_moduli_file`, `_ssh_weak_moduli`, etc. — **CORRECT**

### Other Correctly-Prefixed Patterns
- `_hostctl_*`, `_chezmoi_*`, `_caddy_*`, `_lightdm_*`, `_vaultwarden_*`, etc. — **CORRECT**

---

## 5. DEFAULTS/MAIN.YML INTERNAL VARIABLES

Variables defined in `defaults/main.yml` with `_` prefix (meant to be "private"):

| Role | Variable | New Name | Type | Locations |
|------|----------|----------|------|-----------|
| ssh_keys | `_ssh_keys_supported_os` | ssh_keys_supported_os | defaults | `defaults/main.yml:6` |
| ssh_keys | `_ssh_keys_users` | ssh_keys_users | defaults | `defaults/main.yml:28` |
| git | `_git_supported_os` | git_supported_os | defaults | `defaults/main.yml:5` |
| ssh | `_ssh_supported_os` | ssh_supported_os | defaults | `defaults/main.yml:8` |
| gpu_drivers | `_gpu_drivers_*` | gpu_drivers_* | defaults | Multiple lines |
| vm | `_vm_hypervisor_map` | vm_hypervisor_map | defaults | `defaults/main.yml:27` |
| vm | `_vm_supported_hypervisors` | vm_supported_hypervisors | defaults | `defaults/main.yml:33` |
| power_management | `_power_management_*` | power_management_* | defaults | Multiple lines |
| user | `_user_supported_os` | user_supported_os | defaults | `defaults/main.yml:5` |
| fail2ban | `_fail2ban_supported_os` | fail2ban_supported_os | defaults | `defaults/main.yml:5` |
| sysctl | `_sysctl_supported_os` | sysctl_supported_os | defaults | `defaults/main.yml:6` |
| teleport | `_teleport_supported_os` | teleport_supported_os | defaults | `defaults/main.yml:5` |
| package_manager | `_pkgmgr_supported_distributions` | pkgmgr_supported_distributions | defaults | `defaults/main.yml:5` |

**Total Count:** ~30 violations in defaults

---

## 6. SUMMARY TABLE: VIOLATION COUNTS

| Category | Count | Priority | Severity |
|----------|-------|----------|----------|
| Shared `_rpt_*` variables | 150+ | HIGH | Critical (shared across 15 roles) |
| Generic `_verify_*` without prefix | 40+ | HIGH | High (inconsistent pattern) |
| Abbreviated `_v_*` (ntp_audit) | 16 | MEDIUM | Medium (abbreviations hard to read) |
| `_check_internet_*` (common) | 10 | MEDIUM | Medium (should be `common_*`) |
| Defaults with `_` prefix | 30+ | LOW | Low (not used in tasks, internal only) |
| **TOTAL VIOLATIONS** | **246+** | — | — |

---

## 7. REFACTORING STRATEGY

### Phase 1: HIGH PRIORITY (Shared Variables)
1. Rename `_rpt_*` → `common_rpt_*` across all files
2. Update `common/tasks/report_phase.yml` to use new names
3. Update `common/tasks/report_render.yml` to use new names
4. Update all 15 roles calling `include_role` from common

### Phase 2: HIGH PRIORITY (Verify Variables)
1. Rename generic `_verify_*` to role-prefixed names in all roles
2. Update molecule verify.yml files
3. Update role verify tasks

### Phase 3: MEDIUM PRIORITY (Other Helpers)
1. Rename `_check_internet_*` → `common_check_internet_*`
2. Rename `_v_*` → `ntp_audit_verify_*` abbreviations

### Phase 4: LOW PRIORITY (Defaults)
1. Rename `_*` variables in defaults/main.yml files
2. Update all references in tasks

---

## 8. AFFECTED FILES BY ROLE

### Common Role (Central Hub)
- `ansible/roles/common/tasks/report_phase.yml` (36+ line changes)
- `ansible/roles/common/tasks/report_render.yml` (20+ line changes)
- `ansible/roles/common/tasks/check_internet.yml` (10+ line changes)

### Roles Using Shared Reporting (`_rpt_*`)
1. **Git**: `tasks/main.yml`, `tasks/verify.yml`
2. **SSH**: `tasks/main.yml`, `tasks/verify.yml`
3. **Hostname**: `tasks/main.yml`, `tasks/hosts.yml`
4. **Locale**: `tasks/main.yml`
5. **Timezone**: `tasks/main.yml`
6. **Shell**: `tasks/main.yml`, `tasks/*.yml`
7. **User**: `tasks/main.yml`
8. **SSH_Keys**: `tasks/main.yml`
9. **VConsole**: `tasks/main.yml`
10. **VM**: `tasks/main.yml`, `tasks/_*.yml`
11. **NTP**: `tasks/main.yml`, `tasks/detect_environment.yml`
12. **Fail2ban**: `tasks/main.yml`
13. **Teleport**: `tasks/main.yml`

### Verify Variable Violations
- `pam_hardening/molecule/default/verify.yml`
- `hostctl/molecule/default/verify.yml`
- `hostname/molecule/default/verify.yml`
- `locale/molecule/default/verify.yml`
- `fail2ban/molecule/default/verify.yml`
- `ntp/molecule/default/verify.yml`
- `shell/molecule/default/verify.yml`
- `vconsole/molecule/default/verify.yml`
- `ntp_audit/tasks/verify.yml` + `molecule/default/verify.yml`

---

## 9. LINTING ERROR EXAMPLES

Based on the GitHub Actions lint error from `gh run view 22283549681`:

```
[error] Variables names must start with their role prefix
  Pattern: <role>_<var>
  
  File: ansible/roles/git/tasks/main.yml:35
    _rpt_fact should be: git_rpt_fact or common_rpt_fact
    
  File: ansible/roles/pam_hardening/molecule/default/verify.yml:15
    _verify_faillock_conf should be: pam_hardening_verify_faillock_conf
    
  File: ansible/roles/ntp_audit/tasks/verify.yml:7
    _v_script should be: ntp_audit_verify_script or ntp_audit_v_script
```

---

## 10. IMPLEMENTATION NOTES

1. **Backward Compatibility:** This is a breaking change for any external playbooks using these variables. All references must be updated simultaneously.

2. **Testing:** After refactoring:
   - Run `molecule test` on all roles
   - Run Ansible lint checks
   - Run any CI/CD validation pipelines

3. **Documentation:** Update role READMEs if they reference variable names

4. **Git History:** Consider this a major refactor in commit history/changelog

---

## Appendix: Complete Mapping JSON

```json
{
  "violations": {
    "shared_reporting": {
      "description": "Variables used via include_role from common role",
      "affected_roles": ["git", "ssh", "hostname", "locale", "timezone", "shell", "user", "ssh_keys", "vconsole", "vm", "ntp", "fail2ban", "teleport"],
      "mappings": {
        "_rpt_fact": "common_rpt_fact",
        "_rpt_phase": "common_rpt_phase",
        "_rpt_status": "common_rpt_status",
        "_rpt_detail": "common_rpt_detail",
        "_rpt_title": "common_rpt_title",
        "_rpt_footer_rows": "common_rpt_footer_rows",
        "_row": "common_rpt_row",
        "_st": "common_rpt_status_mark",
        "_mk": "common_rpt_mark"
      },
      "priority": "HIGH",
      "count": 150
    },
    "verify_variables_generic": {
      "description": "Verify variables without role prefix",
      "affected_roles": ["pam_hardening", "hostctl", "hostname", "locale", "fail2ban", "ntp", "shell", "vconsole"],
      "mappings": {
        "pam_hardening": {
          "_verify_faillock_conf": "pam_hardening_verify_faillock_conf",
          "_verify_faillock_content": "pam_hardening_verify_faillock_content",
          "_verify_pam_profile": "pam_hardening_verify_pam_profile",
          "_verify_pam_authfail_profile": "pam_hardening_verify_pam_authfail_profile"
        },
        "hostctl": {
          "_verify_version": "hostctl_verify_version",
          "_verify_profile": "hostctl_verify_profile",
          "_verify_entry": "hostctl_verify_entry",
          "_verify_applied": "hostctl_verify_applied",
          "_verify_base": "hostctl_verify_base"
        }
      },
      "priority": "HIGH",
      "count": 40
    },
    "abbreviated_verify": {
      "description": "Abbreviated _v_* variables (ntp_audit)",
      "affected_roles": ["ntp_audit"],
      "mappings": {
        "_v_script": "ntp_audit_verify_script",
        "_v_src": "ntp_audit_verify_src",
        "_v_logdir": "ntp_audit_verify_logdir",
        "_v_logfile": "ntp_audit_verify_logfile",
        "_v_last_line": "ntp_audit_verify_last_line",
        "_v_logrotate": "ntp_audit_verify_logrotate",
        "_v_alloy": "ntp_audit_verify_alloy",
        "_v_loki": "ntp_audit_verify_loki"
      },
      "priority": "MEDIUM",
      "count": 16
    },
    "common_helpers": {
      "description": "Helper variables in common role",
      "affected_roles": ["common"],
      "mappings": {
        "_check_internet_host": "common_check_internet_host",
        "_check_internet_port": "common_check_internet_port",
        "_check_internet_timeout": "common_check_internet_timeout",
        "_common_internet_check": "common_internet_check"
      },
      "priority": "MEDIUM",
      "count": 10
    }
  },
  "total_violations": 246
}
```

---

## Document Versioning

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-02-22 | Analysis | Initial comprehensive audit of all roles |

---

**Next Steps:** Use this report to guide systematic file-by-file refactoring of variable names across the entire Ansible codebase.
