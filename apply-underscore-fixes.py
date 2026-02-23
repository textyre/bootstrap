#!/usr/bin/env python3
"""
Fix all underscore-prefixed Ansible variables across all roles.
"""

import re
from pathlib import Path

# All underscore-prefixed variables to fix
VARS_TO_FIX = {
    '_available_list': 'available_list',
    '_border': 'border',
    '_changed': 'changed',
    '_chezmoi_user_home': 'chezmoi_user_home',
    '_common_rpt_status_mark': 'common_rpt_status_mark',
    '_detail': 'detail',
    '_failed': 'failed',
    '_git_lfs_package': 'git_lfs_package',
    '_git_packages': 'git_packages',
    '_gpu_drivers_has_amd': 'gpu_drivers_has_amd',
    '_gpu_drivers_has_intel': 'gpu_drivers_has_intel',
    '_gpu_drivers_has_nvidia': 'gpu_drivers_has_nvidia',
    '_gpu_drivers_initramfs_tool': 'gpu_drivers_initramfs_tool',
    '_greeter_ssh_fp_hash': 'greeter_ssh_fp_hash',
    '_header': 'header',
    '_hostctl_arch_map': 'hostctl_arch_map',
    '_hostname_hosts_line': 'hostname_hosts_line',
    '_hostname_strategy': 'hostname_strategy',
    '_locale_normalized': 'locale_normalized',
    '_locale_skip': 'locale_skip',
    '_locale_skip_reason': 'locale_skip_reason',
    '_locale_supported_os_families': 'locale_supported_os_families',
    '_locale_verify_missing': 'locale_verify_missing',
    '_locale_verify_ok': 'locale_verify_ok',
    '_ntp_active_refclocks': 'ntp_active_refclocks',
    '_ntp_env': 'ntp_env',
    '_ntp_env_defaults': 'ntp_env_defaults',
    '_ntp_env_map': 'ntp_env_map',
    '_ntp_package': 'ntp_package',
    '_ntp_service': 'ntp_service',
    '_ntp_user': 'ntp_user',
    '_ntp_virt_type': 'ntp_virt_type',
    '_packages_all': 'packages_all',
    '_pm_current_governor': 'pm_current_governor',
    '_pm_drift_previous': 'pm_drift_previous',
    '_pm_fact_governor': 'pm_fact_governor',
    '_pm_hibernate_in_use': 'pm_hibernate_in_use',
    '_power_management_cpu_is_amd': 'power_management_cpu_is_amd',
    '_power_management_cpu_is_intel': 'power_management_cpu_is_intel',
    '_power_management_init': 'power_management_init',
    '_power_management_is_laptop': 'power_management_is_laptop',
    '_reflector_latest_backup': 'reflector_latest_backup',
    '_reflector_mirrorlist_changed': 'reflector_mirrorlist_changed',
    '_row': 'row',
    '_shell_bin': 'shell_bin',
    '_shell_packages': 'shell_packages',
    '_shell_supported_os': 'shell_supported_os',
    '_shell_supported_types': 'shell_supported_types',
    '_shell_user_home': 'shell_user_home',
    '_ssh_packages': 'ssh_packages',
    '_ssh_service_name': 'ssh_service_name',
    '_ssh_svc': 'ssh_svc',
    '_teleport_arch': 'teleport_arch',
    '_teleport_install_method': 'teleport_install_method',
    '_teleport_major_version': 'teleport_major_version',
    '_teleport_packages': 'teleport_packages',
    '_teleport_service_name': 'teleport_service_name',
    '_test_lc_overrides': 'test_lc_overrides',
    '_test_locale': 'test_locale',
    '_test_locales': 'test_locales',
    '_test_timezone': 'test_timezone',
    '_tz_cron_service': 'tz_cron_service',
    '_umask_user': 'umask_user',
    '_umask_value': 'umask_value',
    '_user_packages': 'user_packages',
    '_vaultwarden_admin_token': 'vaultwarden_admin_token',
    '_vconsole_supported_inits': 'vconsole_supported_inits',
    '_vconsole_value': 'vconsole_value',
    '_verify_shell_type': 'verify_shell_type',
    '_vm_hyperv_packages': 'vm_hyperv_packages',
    '_vm_hypervisor': 'vm_hypervisor',
    '_vm_is_container': 'vm_is_container',
    '_vm_is_guest': 'vm_is_guest',
    '_vm_kvm_packages': 'vm_kvm_packages',
    '_vm_mod_label': 'vm_mod_label',
    '_vm_mod_list': 'vm_mod_list',
    '_vm_notify_handler': 'vm_notify_handler',
    '_vm_pkg_label': 'vm_pkg_label',
    '_vm_pkg_list': 'vm_pkg_list',
    '_vm_reboot_condition': 'vm_reboot_condition',
    '_vm_reboot_label': 'vm_reboot_label',
    '_vm_reboot_required': 'vm_reboot_required',
    '_vm_rpt_pkg_rows': 'vm_rpt_pkg_rows',
    '_vm_rpt_svc_rows': 'vm_rpt_svc_rows',
    '_vm_service_manager': 'vm_service_manager',
    '_vm_svc_label': 'vm_svc_label',
    '_vm_svc_list': 'vm_svc_list',
    '_vm_timesync_label': 'vm_timesync_label',
    '_vm_timesync_service': 'vm_timesync_service',
    '_vm_vbox_guest_ver': 'vm_vbox_guest_ver',
    '_vm_vbox_host_ver': 'vm_vbox_host_ver',
    '_vm_vbox_iso_installed': 'vm_vbox_iso_installed',
    '_vm_vbox_lts_kernel_support': 'vm_vbox_lts_kernel_support',
    '_vm_vbox_service_name': 'vm_vbox_service_name',
    '_vm_ver_command': 'vm_ver_command',
    '_vm_ver_extra_commands': 'vm_ver_extra_commands',
    '_vm_ver_extra_result': 'vm_ver_extra_result',
    '_vm_ver_label': 'vm_ver_label',
    '_vm_x11_paths': 'vm_x11_paths',
    '_greeter_dist_stat': 'greeter_dist_stat',
    '_greeter_ssh_fp_raw': 'greeter_ssh_fp_raw',
    '_greeter_wallpaper_stat': 'greeter_wallpaper_stat',
    '_ntp_audit_zipapp_stat': 'ntp_audit_zipapp_stat',
    '_teleport_supported_os': 'teleport_supported_os',
    '_teleport_user_ca': 'teleport_user_ca',
}

def fix_variables_in_file(file_path):
    """Fix all underscore-prefixed variables in a file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return False
    
    original_content = content
    
    # Replace all variables using word boundaries to avoid partial matches
    for old_var, new_var in VARS_TO_FIX.items():
        # Use word boundaries to match only whole variable names
        pattern = r'\b' + re.escape(old_var) + r'\b'
        content = re.sub(pattern, new_var, content)
    
    # Only write if content changed
    if content != original_content:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return True
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            return False
    
    return False

def main():
    roles_dir = Path('/Users/umudrakov/Documents/bootstrap/ansible/roles')
    
    modified_files = []
    
    print(f"Fixing {len(VARS_TO_FIX)} variables in {roles_dir}...")
    
    for file_path in sorted(roles_dir.glob('**/*.yml')):
        if fix_variables_in_file(file_path):
            modified_files.append(file_path)
            print(f"  ✓ {file_path.relative_to(roles_dir.parent.parent)}")
    
    print(f"\nTotal files modified: {len(modified_files)}")
    return len(modified_files)

if __name__ == '__main__':
    count = main()
    exit(0 if count >= 0 else 1)
