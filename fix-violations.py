#!/usr/bin/env python3
import os
import glob

# Find all verify.yml files
verify_files = sorted(glob.glob('ansible/roles/*/molecule/*/verify.yml') + glob.glob('ansible/roles/*/tasks/verify.yml'))

# Replacement pairs (old_pattern -> new_pattern)
replacements = [
    # Role-specific patterns with underscore prefix
    ('_git_verify_', 'git_verify_'),
    ('_ssh_verify_', 'ssh_verify_'),
    ('_chezmoi_verify_', 'chezmoi_verify_'),
    ('_caddy_verify_', 'caddy_verify_'),
    ('_lightdm_verify_', 'lightdm_verify_'),
    ('_vaultwarden_verify_', 'vaultwarden_verify_'),
    ('_docker_verify_', 'docker_verify_'),
    ('_gpu_verify_', 'gpu_verify_'),
    ('_firewall_verify_', 'firewall_verify_'),
    ('_greeter_verify_', 'greeter_verify_'),
    ('_teleport_verify_', 'teleport_verify_'),
    ('_sysctl_verify_', 'sysctl_verify_'),
    ('_zen_verify_', 'zen_verify_'),
    ('_yay_verify_', 'yay_verify_'),
    ('_xorg_verify_', 'xorg_verify_'),
    ('_hostname_verify_', 'hostname_verify_'),
    ('_power_management_verify_', 'power_management_verify_'),
    ('_fail2ban_verify_', 'fail2ban_verify_'),
    ('_reflector_verify_', 'reflector_verify_'),
    ('_ssh_keys_verify_', 'ssh_keys_verify_'),
    ('_locale_verify_', 'locale_verify_'),
    ('_timezone_verify_', 'timezone_verify_'),
    ('_user_verify_', 'user_verify_'),
    ('_vm_verify_', 'vm_verify_'),
    ('_vconsole_verify_', 'vconsole_verify_'),
    ('_packages_verify_', 'packages_verify_'),
    # Generic patterns without role prefix  
    ('_verify_pacman_marker', 'pkgmgr_verify_pacman_marker'),
    ('_verify_pacman_parallel', 'pkgmgr_verify_pacman_parallel'),
    ('_verify_pacman_color', 'pkgmgr_verify_pacman_color'),
    ('_verify_pacman_verbose', 'pkgmgr_verify_pacman_verbose'),
    ('_verify_paccache_timer', 'pkgmgr_verify_paccache_timer'),
    ('_verify_makepkg', 'pkgmgr_verify_makepkg'),
    ('_verify_reflector_conf', 'pkgmgr_verify_reflector_conf'),
    ('_verify_reflector_timer', 'pkgmgr_verify_reflector_timer'),
    ('_verify_yay_binary', 'pkgmgr_verify_yay_binary'),
    ('_verify_yay_sudoers', 'pkgmgr_verify_yay_sudoers'),
    ('_verify_key_content', 'ssh_keys_verify_key_content'),
    ('_verify_lsmod', 'ntp_verify_lsmod'),
]

fixed_count = 0
for filepath in verify_files:
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        original = content
        for old, new in replacements:
            content = content.replace(old, new)
        
        if content != original:
            with open(filepath, 'w') as f:
                f.write(content)
            fixed_count += 1
            print(f"✓ {filepath}")
    except Exception as e:
        print(f"✗ {filepath}: {e}")

print(f"\nTotal files fixed: {fixed_count}/{len(verify_files)}")
