#!/bin/bash
# Automated variable naming refactoring for Ansible roles
# Fixes 246 variable naming violations to follow: <role_name>_<variable>

set -e

BOOTSTRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="$BOOTSTRAP_DIR/ansible"

echo "=== Ansible Variable Naming Refactoring ==="
echo "Working directory: $ANSIBLE_DIR"
echo ""

# ============================================================================
# PHASE 1: Replace _rpt_* → common_rpt_* (150 violations)
# ============================================================================
echo "[PHASE 1] Replacing _rpt_* → common_rpt_* (150 violations)"

echo "  - In all roles/*/tasks/*.yml"
find "$ANSIBLE_DIR/roles" -name "*.yml" -type f -exec sed -i '' \
  -e 's/_rpt_fact:/common_rpt_fact:/g' \
  -e 's/_rpt_phase:/common_rpt_phase:/g' \
  -e 's/_rpt_status:/common_rpt_status:/g' \
  -e 's/_rpt_detail:/common_rpt_detail:/g' \
  -e 's/_rpt_title:/common_rpt_title:/g' \
  -e 's/_rpt_footer_rows:/common_rpt_footer_rows:/g' \
  -e 's/"_rpt_fact"/"common_rpt_fact"/g' \
  -e 's/"_rpt_phase"/"common_rpt_phase"/g' \
  -e 's/"_rpt_status"/"common_rpt_status"/g' \
  -e 's/"_rpt_detail"/"common_rpt_detail"/g' \
  -e 's/"_rpt_title"/"common_rpt_title"/g' \
  -e 's/"_rpt_footer_rows"/"common_rpt_footer_rows"/g' \
  -e "s/'_rpt_fact'/'common_rpt_fact'/g" \
  -e "s/'_rpt_phase'/'common_rpt_phase'/g" \
  -e "s/'_rpt_status'/'common_rpt_status'/g" \
  -e "s/'_rpt_detail'/'common_rpt_detail'/g" \
  -e "s/'_rpt_title'/'common_rpt_title'/g" \
  -e "s/'_rpt_footer_rows'/'common_rpt_footer_rows'/g" \
  -e 's/{{ _rpt_fact }}/{{ common_rpt_fact }}/g' \
  -e 's/{{ _rpt_phase }}/{{ common_rpt_phase }}/g' \
  -e 's/{{ _rpt_status }}/{{ common_rpt_status }}/g' \
  -e 's/{{ _rpt_detail }}/{{ common_rpt_detail }}/g' \
  -e 's/{{ _rpt_title }}/{{ common_rpt_title }}/g' \
  -e 's/{{ _rpt_footer_rows }}/{{ common_rpt_footer_rows }}/g' \
  -e 's/{{ lookup.*_rpt_fact/{{ lookup(\"vars\", \"common_rpt_fact\"/g' \
  -e 's/_row:/_row:/g' \
  -e 's/_st:/_common_rpt_status_mark:/g' \
  -e 's/_mk:/_common_rpt_mark:/g' \
  {} \;

echo "    ✓ _rpt_* variables replaced in all task files"

# ============================================================================
# PHASE 2: Replace _verify_* → <role>_verify_* in molecule/verify.yml
# ============================================================================
echo ""
echo "[PHASE 2] Replacing _verify_* → <role>_verify_* (40+ violations)"

# pam_hardening
echo "  - pam_hardening: _verify_* → pam_hardening_verify_*"
sed -i '' \
  -e 's/_verify_faillock_conf:/pam_hardening_verify_faillock_conf:/g' \
  -e 's/_verify_faillock_content:/pam_hardening_verify_faillock_content:/g' \
  -e 's/_verify_pam_profile:/pam_hardening_verify_pam_profile:/g' \
  -e 's/_verify_pam_authfail_profile:/pam_hardening_verify_pam_authfail_profile:/g' \
  "$ANSIBLE_DIR/roles/pam_hardening/molecule/default/verify.yml"

# hostctl
echo "  - hostctl: _verify_* → hostctl_verify_*"
sed -i '' \
  -e 's/_verify_version:/hostctl_verify_version:/g' \
  -e 's/_verify_profile:/hostctl_verify_profile:/g' \
  -e 's/_verify_entry:/hostctl_verify_entry:/g' \
  -e 's/_verify_applied:/hostctl_verify_applied:/g' \
  -e 's/_verify_base:/hostctl_verify_base:/g' \
  -e 's/{{ _verify_version }}/{{ hostctl_verify_version }}/g' \
  -e 's/{{ _verify_profile }}/{{ hostctl_verify_profile }}/g' \
  -e 's/{{ _verify_entry }}/{{ hostctl_verify_entry }}/g' \
  -e 's/{{ _verify_applied }}/{{ hostctl_verify_applied }}/g' \
  -e 's/{{ _verify_base }}/{{ hostctl_verify_base }}/g' \
  "$ANSIBLE_DIR/roles/hostctl/molecule/default/verify.yml"

# hostname
echo "  - hostname: _verify_* → hostname_verify_*"
sed -i '' \
  -e 's/_verify_hostname:/hostname_verify_hostname:/g' \
  -e 's/_verify_hosts_resolve:/hostname_verify_hosts_resolve:/g' \
  -e 's/_verify_hosts:/hostname_verify_hosts:/g' \
  -e 's/{{ _verify_hostname }}/{{ hostname_verify_hostname }}/g' \
  -e 's/{{ _verify_hosts_resolve }}/{{ hostname_verify_hosts_resolve }}/g' \
  -e 's/{{ _verify_hosts }}/{{ hostname_verify_hosts }}/g' \
  "$ANSIBLE_DIR/roles/hostname/molecule/default/verify.yml"

# locale
echo "  - locale: _verify_* → locale_verify_*"
sed -i '' \
  -e 's/_verify_locales:/locale_verify_locales:/g' \
  -e 's/_verify_locale_conf:/locale_verify_locale_conf:/g' \
  -e 's/_verify_locale_cmd:/locale_verify_locale_cmd:/g' \
  -e 's/{{ _verify_locales }}/{{ locale_verify_locales }}/g' \
  -e 's/{{ _verify_locale_conf }}/{{ locale_verify_locale_conf }}/g' \
  -e 's/{{ _verify_locale_cmd }}/{{ locale_verify_locale_cmd }}/g' \
  "$ANSIBLE_DIR/roles/locale/molecule/default/verify.yml"

# package_manager
echo "  - package_manager: _verify_* → package_manager_verify_*"
sed -i '' \
  -e 's/_verify_pacman_marker:/package_manager_verify_pacman_marker:/g' \
  -e 's/_verify_pacman_parallel:/package_manager_verify_pacman_parallel:/g' \
  -e 's/_verify_pacman_color:/package_manager_verify_pacman_color:/g' \
  -e 's/_verify_pacman_verbose:/package_manager_verify_pacman_verbose:/g' \
  -e 's/_verify_paccache_timer:/package_manager_verify_paccache_timer:/g' \
  -e 's/_verify_makepkg:/package_manager_verify_makepkg:/g' \
  -e 's/_verify_reflector_conf:/package_manager_verify_reflector_conf:/g' \
  -e 's/_verify_reflector_timer:/package_manager_verify_reflector_timer:/g' \
  -e 's/_verify_yay_binary:/package_manager_verify_yay_binary:/g' \
  -e 's/_verify_yay_sudoers:/package_manager_verify_yay_sudoers:/g' \
  -e 's/_pkgmgr_alpm_user:/package_manager_pkgmgr_alpm_user:/g' \
  "$ANSIBLE_DIR/roles/package_manager/molecule/default/verify.yml"

# power_management
echo "  - power_management: _power_verify_* → power_management_verify_*"
sed -i '' \
  -e 's/_power_verify_/power_management_verify_/g' \
  "$ANSIBLE_DIR/roles/power_management/molecule/default/verify.yml"

# sysctl
echo "  - sysctl: _verify_* → sysctl_verify_*"
sed -i '' \
  -e 's/_sysctl_verify_/sysctl_verify_/g' \
  "$ANSIBLE_DIR/roles/sysctl/molecule/default/verify.yml"
sed -i '' \
  -e 's/_sysctl_verify_security:/sysctl_verify_security:/g' \
  "$ANSIBLE_DIR/roles/sysctl/tasks/verify.yml"

# vm
echo "  - vm: _verify_* → vm_verify_*"
sed -i '' \
  -e 's/_verify_/vm_verify_/g' \
  "$ANSIBLE_DIR/roles/vm/molecule/default/verify.yml"

echo "    ✓ _verify_* variables replaced in molecule verify.yml files"

# ============================================================================
# PHASE 3: Replace _v_* → ntp_audit_verify_* (16 violations)
# ============================================================================
echo ""
echo "[PHASE 3] Replacing _v_* → ntp_audit_verify_* (16 violations)"

sed -i '' \
  -e 's/_v_script:/ntp_audit_verify_script:/g' \
  -e 's/_v_src:/ntp_audit_verify_src:/g' \
  -e 's/_v_logdir:/ntp_audit_verify_logdir:/g' \
  -e 's/_v_logfile:/ntp_audit_verify_logfile:/g' \
  -e 's/_v_last_line:/ntp_audit_verify_last_line:/g' \
  -e 's/_v_logrotate:/ntp_audit_verify_logrotate:/g' \
  -e 's/_v_alloy:/ntp_audit_verify_alloy:/g' \
  -e 's/_v_loki:/ntp_audit_verify_loki:/g' \
  -e 's/_cron_list:/ntp_audit_verify_cron_list:/g' \
  -e 's/{{ _v_/{{ ntp_audit_verify_/g' \
  "$ANSIBLE_DIR/roles/ntp_audit"/**/*.yml 2>/dev/null || true

echo "    ✓ _v_* variables replaced in ntp_audit role"

# ============================================================================
# PHASE 4: Replace _check_internet_* → common_check_internet_*
# ============================================================================
echo ""
echo "[PHASE 4] Replacing _check_internet_* → common_check_internet_*"

sed -i '' \
  -e 's/_check_internet_host:/common_check_internet_host:/g' \
  -e 's/_check_internet_port:/common_check_internet_port:/g' \
  -e 's/_check_internet_timeout:/common_check_internet_timeout:/g' \
  -e 's/_common_internet_check:/common_check_internet_result:/g' \
  -e 's/{{ _check_internet_host }}/{{ common_check_internet_host }}/g' \
  -e 's/{{ _check_internet_port }}/{{ common_check_internet_port }}/g' \
  -e 's/{{ _check_internet_timeout }}/{{ common_check_internet_timeout }}/g' \
  "$ANSIBLE_DIR/roles/common/tasks/check_internet.yml"

echo "    ✓ _check_internet_* variables replaced"

# ============================================================================
# PHASE 5: Remaining role-specific variables
# ============================================================================
echo ""
echo "[PHASE 5] Fixing remaining role-specific variables"

# Fix _ssh_keys_* in ssh_keys role
sed -i '' -e 's/_ssh_keys_supported_os:/ssh_keys_supported_os:/g' \
  "$ANSIBLE_DIR/roles/ssh_keys/defaults/main.yml"

# Fix _user_packages in user role
sed -i '' -e 's/_user_packages:/user_packages:/g' \
  "$ANSIBLE_DIR/roles/user/tasks/"*.yml

# Fix _fail2ban_* in fail2ban role
sed -i '' \
  -e 's/_fail2ban_packages:/fail2ban_packages:/g' \
  -e 's/_fail2ban_service_name:/fail2ban_service_name:/g' \
  "$ANSIBLE_DIR/roles/fail2ban"/**/*.yml

echo "    ✓ Remaining role-specific variables fixed"

echo ""
echo "=== Refactoring Complete ==="
echo ""
echo "Summary:"
echo "  - PHASE 1: _rpt_* → common_rpt_* (150 violations)"
echo "  - PHASE 2: _verify_* → <role>_verify_* (40+ violations)"
echo "  - PHASE 3: _v_* → ntp_audit_verify_* (16 violations)"
echo "  - PHASE 4: _check_* → common_check_* (10 violations)"
echo "  - PHASE 5: Role-specific _* → <role>_* (30+ violations)"
echo ""
echo "Next steps:"
echo "  1. Review changes with: git diff"
echo "  2. Run ansible-lint to verify: cd ansible && ansible-lint roles/"
echo "  3. Commit with: git add -A && git commit 'm \"refactor: fix all 246 variable naming violations\"'"
echo ""
