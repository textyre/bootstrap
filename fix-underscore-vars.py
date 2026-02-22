#!/usr/bin/env python3
"""
Fix underscore-prefixed Ansible variables across all roles.
This script finds all underscore-prefixed variables and renames them by removing the prefix.
"""

import os
import re
import sys
from pathlib import Path
from collections import defaultdict

def find_var_definitions(file_path):
    """Find all underscore-prefixed variable definitions in a file."""
    vars_found = set()
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Pattern 1: name: _var_name (set_fact, etc.)
    pattern1 = r'^\s*(\w+?):\s*$'
    
    # Pattern 2: - _var_name: (list items)
    pattern2 = r'^\s*-\s+(_[a-z_]+):'
    
    # Pattern 3: _var_name: value
    pattern3 = r'^\s*(_[a-z_]+):\s*(?:.+)?$'
    
    for line in content.split('\n'):
        match = re.search(pattern2, line)
        if match:
            vars_found.add(match.group(1))
        match = re.search(pattern3, line)
        if match:
            vars_found.add(match.group(1))
    
    return vars_found

def find_all_var_occurrences(root_dir, target_var):
    """Find all occurrences of a variable in all YAML files."""
    occurrences = []
    pattern = r'\b' + re.escape(target_var) + r'\b'
    
    for file_path in Path(root_dir).glob('**/*.yml'):
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            
            if re.search(pattern, content):
                for line_no, line in enumerate(content.split('\n'), 1):
                    if re.search(pattern, line):
                        occurrences.append((str(file_path), line_no, line.strip()))
        except Exception as e:
            print(f"Error reading {file_path}: {e}", file=sys.stderr)
    
    return occurrences

def main():
    roles_dir = '/Users/umudrakov/Documents/bootstrap/ansible/roles'
    
    # Collect all underscore-prefixed variables
    all_vars = set()
    var_to_files = defaultdict(set)
    
    print("Scanning for underscore-prefixed variables...")
    for file_path in Path(roles_dir).glob('**/*.yml'):
        vars_in_file = find_var_definitions(str(file_path))
        all_vars.update(vars_in_file)
        for var in vars_in_file:
            var_to_files[var].add(str(file_path))
    
    print(f"Found {len(all_vars)} unique underscore-prefixed variables")
    print("\nVariables to rename:")
    
    replacements = {}
    for var in sorted(all_vars):
        new_var = var.lstrip('_')
        replacements[var] = new_var
        print(f"  {var} → {new_var}")
    
    print(f"\nTotal replacements needed: {len(replacements)}")
    
    # Show a sample of files and occurrences
    print("\nSample occurrences by file:")
    sample_count = 0
    for var, new_var in sorted(replacements.items())[:10]:
        occurrences = find_all_var_occurrences(roles_dir, var)
        print(f"\n{var} → {new_var} ({len(occurrences)} occurrences):")
        for file_path, line_no, line in occurrences[:3]:
            print(f"  {file_path}:{line_no}: {line[:80]}")
        if len(occurrences) > 3:
            print(f"  ... and {len(occurrences) - 3} more")
    
    return replacements

if __name__ == '__main__':
    replacements = main()
