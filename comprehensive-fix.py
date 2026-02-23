#!/usr/bin/env python3
"""
Comprehensive fix for Ansible variable naming violations.
Dynamically identifies register names and removes underscore prefixes from references.
"""
import os
import re
import glob

def fix_file_comprehensive(filepath):
    """
    Fix a single file by:
    1. Finding all register names (they don't have underscores)
    2. Finding all references with underscore prefixes
    3. Replacing underscore references with non-underscore versions where applicable
    """
    with open(filepath, 'r') as f:
        original_content = f.read()
    
    content = original_content
    fixed_something = False
    
    # Find all register names
    register_pattern = r'register:\s+([a-z_][a-z0-9_]*)'
    registers = set()
    for match in re.finditer(register_pattern, content):
        reg_name = match.group(1)
        registers.add(reg_name)
    
    # For each register that contains verify/check patterns, find its underscore version and fix it
    for register_name in list(registers):
        # Skip if it's already underscore-prefixed (shouldn't happen but be safe)
        if register_name.startswith('_'):
            continue
        
        # Create potential underscore version
        underscore_version = '_' + register_name
        
        # Count occurrences of underscore version
        underscore_count = content.count(underscore_version)
        
        if underscore_count > 0:
            # Replace underscore version with non-underscore version
            # Use careful replacements to avoid partial replacements
            # Pattern: _variablename followed by . or [ or whitespace/newline
            pattern = re.escape(underscore_version) + r'(?=[.\[\s\n\)])'
            content = re.sub(pattern, register_name, content)
            fixed_something = True
    
    if fixed_something:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    
    return False

# Find all verify.yml files
verify_files = sorted(glob.glob('ansible/roles/*/molecule/*/verify.yml') + 
                     glob.glob('ansible/roles/*/tasks/verify.yml'))

fixed_count = 0
fixed_files = []

for filepath in verify_files:
    try:
        if fix_file_comprehensive(filepath):
            fixed_count += 1
            fixed_files.append(filepath)
    except Exception as e:
        print(f"✗ {filepath}: {e}")

# Print results
if fixed_files:
    print("Fixed files:")
    for f in fixed_files:
        print(f"  ✓ {f}")

print(f"\nTotal files fixed: {fixed_count}/{len(verify_files)}")
