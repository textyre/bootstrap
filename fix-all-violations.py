#!/usr/bin/env python3
"""
Fix Ansible variable naming violations by removing underscore prefixes.
"""
import os
import glob

def fix_underscore_references(content):
    """Remove underscore prefixes from variable references where registers don't have them."""
    original = content
    
    # List of known patterns to fix: replace _var with var when var is registered
    patterns_to_fix = [
        # git
        ('_git_verify_', 'git_verify_'),
        # ssh
        ('_ssh_verify_', 'ssh_verify_'),
        # chezmoi
        ('_chezmoi_verify_', 'chezmoi_verify_'),
        # docker
        ('_docker_verify_', 'docker_verify_'),
        # firewall
        ('_firewall_verify_', 'firewall_verify_'),
        # gpu_drivers
        ('_gpu_verify_', 'gpu_verify_'),
        # greeter  
        ('_greeter_verify_', 'greeter_verify_'),
        # lightdm
        ('_lightdm_verify_', 'lightdm_verify_'),
        # vaultwarden
        ('_vaultwarden_verify_', 'vaultwarden_verify_'),
        # fail2ban
        ('_fail2ban_verify_', 'fail2ban_verify_'),
        # ssh_keys
        ('_ssh_keys_verify_', 'ssh_keys_verify_'),
        # hostname
        ('_hostname_verify_', 'hostname_verify_'),
        # locale
        ('_locale_verify_', 'locale_verify_'),
        # timezone
        ('_timezone_verify_', 'timezone_verify_'),
        # sysctl
        ('_sysctl_verify_', 'sysctl_verify_'),
        # zen_browser
        ('_zen_verify_', 'zen_verify_'),
        # yay
        ('_yay_verify_', 'yay_verify_'),
        # xorg
        ('_xorg_verify_', 'xorg_verify_'),
        # power_management
        ('_power_management_verify_', 'power_management_verify_'),
        # reflector
        ('_reflector_verify_', 'reflector_verify_'),
        # user
        ('_user_verify_', 'user_verify_'),
        # vm
        ('_vm_verify_', 'vm_verify_'),
        # vconsole
        ('_vconsole_verify_', 'vconsole_verify_'),
        # packages
        ('_packages_verify_', 'packages_verify_'),
        # pkgmgr
        ('_verify_pacman_', 'pkgmgr_verify_pacman_'),
        ('_verify_paccache_', 'pkgmgr_verify_paccache_'),
        ('_verify_makepkg', 'pkgmgr_verify_makepkg'),
        ('_verify_reflector_', 'pkgmgr_verify_reflector_'),
        ('_verify_yay_', 'pkgmgr_verify_yay_'),
        # ntp
        ('_verify_lsmod', 'ntp_verify_lsmod'),
        ('_verify_chrony_conf_text', 'ntp_verify_chrony_conf_text'),
        # ssh_keys
        ('_verify_key_content', 'ssh_keys_verify_key_content'),
        # pam_hardening
        ('_verify_faillock_', 'pam_hardening_verify_faillock_'),
        ('_verify_pam_', 'pam_hardening_verify_pam_'),
    ]
    
    for old, new in patterns_to_fix:
        content = content.replace(old, new)
    
    return content, content != original

# Find all verify.yml files
verify_files = sorted(glob.glob('ansible/roles/*/molecule/*/verify.yml') + 
                     glob.glob('ansible/roles/*/tasks/verify.yml'))

fixed_count = 0  
for filepath in verify_files:
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        new_content, changed = fix_underscore_references(content)
        
        if changed:
            with open(filepath, 'w') as f:
                f.write(new_content)
            fixed_count += 1
            print(f"✓ {filepath}")
    except Exception as e:
        print(f"✗ {filepath}: {e}")

print(f"\nTotal files fixed: {fixed_count}/{len(verify_files)}")
