# Relative Paths Analysis - Ansible Directory

**Date:** 2026-01-31
**Scope:** Full ansible/ directory recursive scan + Taskfile.yml root-level references
**Status:** Complete inventory of all relative paths needing conversion to absolute paths

---

## Executive Summary

The ansible infrastructure contains **4 critical relative path definitions** in `ansible.cfg` and multiple relative path constructions in role defaults that use Ansible's `role_path` variable for fallback resolution. Additionally, `Taskfile.yml` contains references to the ansible directory using relative path variables.

### Key Findings:

1. **ansible.cfg** - 3 relative path configurations that should be absolute
2. **Role defaults (chezmoi, lightdm, xorg)** - Use fallback relative paths via `role_path`
3. **system.yml** - Uses Ansible special variable `inventory_dir` with relative path navigation
4. **Taskfile.yml** - Uses task variables `{{.ANSIBLE_DIR}}` with relative paths
5. **vault-pass.sh** - Referenced with relative path in ansible.cfg

---

## Detailed Findings

### 1. ansible.cfg - Critical Absolute Path Candidates

**File:** `d:\projects\bootstrap\ansible\ansible.cfg`

#### Finding 1.1
- **Line:** 2
- **Current Value:** `./roles:./playbooks/roles:~/.ansible/roles:/usr/share/ansible/roles`
- **Key:** `roles_path`
- **Type:** Configuration file path
- **References:** Multiple role directories for Ansible role loading
- **Issue:** Relative paths `.` and `./` depend on current working directory (CWD). Must be absolute or use Ansible variables.
- **Impact:** If executed from outside `ansible/` directory, role discovery fails.

#### Finding 1.2
- **Line:** 3
- **Current Value:** `./inventory/hosts.ini`
- **Key:** `inventory`
- **Type:** Configuration file path
- **References:** Inventory file for hosts/groups
- **Issue:** Relative path depends on CWD. If Ansible is run from project root instead of `ansible/`, path resolution fails.
- **Impact:** Inventory not found → playbook execution fails.

#### Finding 1.3
- **Line:** 9
- **Current Value:** `./vault-pass.sh`
- **Key:** `vault_password_file`
- **Type:** Script path
- **References:** Vault password helper script
- **Issue:** Relative path depends on CWD. Breaks if script executed outside `ansible/` directory.
- **Impact:** Cannot decrypt vault-encrypted variables.

---

### 2. system.yml - Relative Navigation via inventory_dir

**File:** `d:\projects\bootstrap\ansible\inventory\group_vars\all\system.yml`

#### Finding 2.1
- **Line:** 16
- **Current Value:** `{{ inventory_dir }}/../../dotfiles`
- **Key:** `dotfiles_base_dir`
- **Type:** Directory path construction
- **References:** dotfiles/ directory at repository root
- **Issue:** Uses `../../` relative navigation from `inventory_dir`. While `inventory_dir` is an Ansible magic variable, this is still a relative path construction.
- **Current:** Works because `inventory_dir` is absolute (`d:\projects\bootstrap\ansible\inventory`), so result is: `d:\projects\bootstrap\ansible\inventory/../../dotfiles` → `d:\projects\bootstrap\dotfiles`
- **Recommendation:** Can remain as-is since it resolves to absolute, but could be more explicit using Ansible's `playbook_dir` or explicit absolute path construction.

**Current Behavior (Acceptable):**
```yaml
dotfiles_base_dir: "{{ inventory_dir }}/../../dotfiles"
# Resolves to: d:\projects\bootstrap\dotfiles (absolute)
```

---

### 3. Role Defaults - Fallback Relative Paths

These use `role_path` (Ansible magic variable) for fallback, but default to relative `.` construction.

#### Finding 3.1: chezmoi role
**File:** `d:\projects\bootstrap\ansible\roles\chezmoi\defaults\main.yml`

- **Line:** 9
- **Current Value:** `{{ dotfiles_base_dir | default(role_path ~ '/../../../dotfiles') }}`
- **Key:** `chezmoi_source_dir`
- **Type:** Directory path (fallback relative)
- **Issue:** Fallback uses `role_path ~ '/../../../dotfiles'` which is relative navigation
- **When Used:** Only if `dotfiles_base_dir` is not defined (shouldn't happen in normal flow since it comes from system.yml)
- **Recommendation:** The pattern is defensive but still contains relative path fallback. Should convert to absolute path construction.

#### Finding 3.2: lightdm role
**File:** `d:\projects\bootstrap\ansible\roles\lightdm\defaults\main.yml`

- **Line:** 6
- **Current Value:** `{{ dotfiles_base_dir | default(role_path ~ '/../../../dotfiles') }}`
- **Key:** `lightdm_source_dir`
- **Type:** Directory path (fallback relative)
- **Same Issue:** Identical to Finding 3.1

#### Finding 3.3: xorg role
**File:** `d:\projects\bootstrap\ansible\roles\xorg\defaults\main.yml`

- **Line:** 6
- **Current Value:** `{{ dotfiles_base_dir | default(role_path ~ '/../../../dotfiles') }}`
- **Key:** `xorg_source_dir`
- **Type:** Directory path (fallback relative)
- **Same Issue:** Identical to Findings 3.1 and 3.2

---

### 4. Taskfile.yml - Task Variables with Relative Paths

**File:** `d:\projects\bootstrap\Taskfile.yml` (root level)

#### Finding 4.1
- **Line:** 4
- **Current Value:** `ANSIBLE_DIR: ansible`
- **Type:** Task variable (relative directory)
- **Usage Pattern:** `{{.ANSIBLE_DIR}}` throughout file
- **Example Uses:**
  - Line 5: `VENV: '{{.ANSIBLE_DIR}}/.venv'` → resolves to `ansible/.venv`
  - Line 6: `PREFIX: 'env PATH="{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"'` (uses TASKFILE_DIR - absolute)
  - Line 33, 43, 45: `dir: '{{.ANSIBLE_DIR}}'` → changes to relative directory
  - Line 253: `dir: '{{.ANSIBLE_DIR}}'` in preconditions

- **Current Behavior:** Acceptable because Task sets `dir: '{{.ANSIBLE_DIR}}'` to change working directory before execution
- **Recommendation:** Can remain as-is because Task tool changes directory. However, paths could be more explicit using `{{.TASKFILE_DIR}}/ansible`

#### Finding 4.2
- **Line:** 8
- **Current Value:** `PLAYBOOK: playbooks/workstation.yml`
- **Type:** Task variable (relative playbook path)
- **Usage:** `"{{.ANSIBLE}} {{.PLAYBOOK}}"` in commands
- **Example:** Line 207, 216, 225

- **Current Behavior:** Works because execution is always `dir: '{{.ANSIBLE_DIR}}'`, so playbooks/ is found
- **Recommendation:** Could use absolute: `PLAYBOOK: '{{.TASKFILE_DIR}}/{{.ANSIBLE_DIR}}/playbooks/workstation.yml'`

---

### 5. Other Files - No Problematic Relative Paths Found

**Files Checked (no problematic relative paths):**
- `d:\projects\bootstrap\ansible\playbooks\workstation.yml` - Uses role references (no path refs)
- `d:\projects\bootstrap\ansible\playbooks\mirrors-update.yml` - Uses role references (no path refs)
- `d:\projects\bootstrap\ansible\inventory\hosts.ini` - Inventory format (no relative paths)
- `d:\projects\bootstrap\ansible\inventory\group_vars\all\packages.yml` - Package lists (no paths)
- `d:\projects\bootstrap\ansible\requirements.txt` - Version pins (no paths)
- `d:\projects\bootstrap\ansible\requirements.yml` - Galaxy collections (no paths)
- All role tasks, handlers, templates - Use ansible built-in paths or absolute paths

**Example of Good Practices Found:**
- `d:\projects\bootstrap\ansible\roles\chezmoi\tasks\main.yml` - Uses `{{ chezmoi_source_dir }}` (variable)
- `d:\projects\bootstrap\ansible\roles\firewall\tasks\main.yml` - Uses `src: nftables.conf.j2` (role template, relative but correct)
- All `path:` keys in tasks use absolute or variable-based paths (e.g., `/etc/locale.gen`, `{{ _chezmoi_user_home }}`)

---

## Directory Structure Reference

```
d:\projects\bootstrap/
├── Taskfile.yml                          (root)
├── ansible/                              (relative: ./ansible or ansible)
│   ├── ansible.cfg                       (CRITICAL - 3 relative paths)
│   ├── vault-pass.sh                     (referenced by ansible.cfg)
│   ├── playbooks/
│   │   ├── workstation.yml
│   │   └── mirrors-update.yml
│   ├── roles/
│   │   ├── roles/
│   │   ├── playbooks/roles/              (referenced in ansible.cfg)
│   │   └── ... (13 roles)
│   ├── inventory/
│   │   ├── hosts.ini                     (referenced by ansible.cfg)
│   │   └── group_vars/
│   │       └── all/
│   │           ├── system.yml            (uses inventory_dir + ../../)
│   │           ├── packages.yml
│   │           └── vault.yml (encrypted)
│   ├── requirements.txt
│   └── requirements.yml
└── dotfiles/                             (relative: ../../dotfiles from inventory_dir)
```

---

## Impact Analysis

### Critical (ansible.cfg)
**Risk Level:** HIGH
**Affected Operations:**
1. Ansible playbook execution from any directory other than `ansible/`
2. Ansible-galaxy, ansible-lint, ansible-vault commands
3. Vault password decryption

**Symptoms of Failure:**
- Error: `[WARNING]: Unable to parse d:\projects\bootstrap/./inventory/hosts.ini as an inventory source`
- Error: `[WARNING]: Unable to parse ./roles as an inventory source`
- Error: `Vault password (--vault-password-file) not found`

---

### Medium (Role Defaults)
**Risk Level:** MEDIUM
**Affected Operations:**
1. Only if `dotfiles_base_dir` is not set in `group_vars/all/system.yml`
2. Only in chezmoi, lightdm, xorg roles

**Symptoms of Failure:**
- Error: `Директория с дотфайлами не найдена: /path/to/role/../../../dotfiles`
- Unlikely in normal flow since `system.yml` is always loaded

---

### Low (Taskfile.yml)
**Risk Level:** LOW
**Affected Operations:**
1. Only affects Task tool execution
2. Works correctly because Task changes directory first

**Recommendation:** Optional improvement for consistency

---

## Conversion Recommendations

### Priority 1: Fix ansible.cfg (CRITICAL)

Convert from relative to absolute paths. Options:

**Option A: Use Ansible default_location magic variable (if available in ansible.cfg context)**
```ini
[defaults]
roles_path = /path/to/bootstrap/ansible/roles:/path/to/bootstrap/ansible/playbooks/roles:~/.ansible/roles:/usr/share/ansible/roles
inventory = /path/to/bootstrap/ansible/inventory/hosts.ini
vault_password_file = /path/to/bootstrap/ansible/vault-pass.sh
```

**Option B: Determine absolute path at runtime (ansible.cfg doesn't support vars)**
```bash
# ansible.cfg itself doesn't support variable interpolation,
# so must be hardcoded or set via environment variables
```

**Option C: Use environment variables (RECOMMENDED)**
```ini
[defaults]
roles_path = $ANSIBLE_ROLES_PATH
inventory = $ANSIBLE_INVENTORY
vault_password_file = $ANSIBLE_VAULT_PASSWORD_FILE
```

Then set in bootstrap.sh:
```bash
export ANSIBLE_ROLES_PATH="$ANSIBLE_DIR/roles:$ANSIBLE_DIR/playbooks/roles:~/.ansible/roles:/usr/share/ansible/roles"
export ANSIBLE_INVENTORY="$ANSIBLE_DIR/inventory/hosts.ini"
export ANSIBLE_VAULT_PASSWORD_FILE="$ANSIBLE_DIR/vault-pass.sh"
```

---

### Priority 2: Update Role Defaults (MEDIUM)

**For chezmoi, lightdm, xorg defaults (safer fallback):**

```yaml
# OLD: Relative path fallback
chezmoi_source_dir: "{{ dotfiles_base_dir | default(role_path ~ '/../../../dotfiles') }}"

# NEW: Absolute path construction
chezmoi_source_dir: "{{ dotfiles_base_dir | default(playbook_dir ~ '/../../dotfiles') }}"
```

**Explanation:** `playbook_dir` is the directory of the main playbook being executed, which is `ansible/playbooks/`, so `../../` reaches repo root → `dotfiles/`.

---

### Priority 3: Update Taskfile.yml (LOW - Optional)

**Optional improvement for consistency:**

```yaml
vars:
  ANSIBLE_DIR: "{{ .TASKFILE_DIR }}/ansible"  # If Task supports this
  # OR keep as-is since dir: changes context
```

---

## Testing Recommendations

After implementing changes, verify:

1. **From project root:**
   ```bash
   cd d:\projects\bootstrap
   task check
   task lint
   ```

2. **From ansible directory:**
   ```bash
   cd d:\projects\bootstrap\ansible
   ansible-playbook playbooks/workstation.yml --syntax-check
   ```

3. **From arbitrary directory:**
   ```bash
   cd /tmp
   ansible-playbook /path/to/bootstrap/ansible/playbooks/workstation.yml --syntax-check
   ```

4. **Verify vault decryption:**
   ```bash
   ANSIBLE_VAULT_PASSWORD_FILE=/path/to/bootstrap/ansible/vault-pass.sh ansible-vault view /path/to/bootstrap/ansible/inventory/group_vars/all/vault.yml
   ```

---

## Files Referenced in This Analysis

1. `d:\projects\bootstrap\ansible\ansible.cfg` - PRIMARY SOURCE (3 relative paths)
2. `d:\projects\bootstrap\Taskfile.yml` - SECONDARY SOURCE (relative vars)
3. `d:\projects\bootstrap\ansible\inventory\group_vars\all\system.yml` - SECONDARY (relative nav)
4. `d:\projects\bootstrap\ansible\roles\chezmoi\defaults\main.yml` - SECONDARY (fallback)
5. `d:\projects\bootstrap\ansible\roles\lightdm\defaults\main.yml` - SECONDARY (fallback)
6. `d:\projects\bootstrap\ansible\roles\xorg\defaults\main.yml` - SECONDARY (fallback)
7. `d:\projects\bootstrap\ansible\vault-pass.sh` - REFERENCED BY ansible.cfg

**All role tasks reviewed:** No additional problematic relative paths found (all use absolute or variables)

---

## Summary Table

| File | Line | Key | Current Value | Type | Priority | Impact |
|------|------|-----|---------------|------|----------|--------|
| `ansible.cfg` | 2 | `roles_path` | `./roles:./playbooks/roles:...` | Config | CRITICAL | Role discovery fails if CWD ≠ ansible/ |
| `ansible.cfg` | 3 | `inventory` | `./inventory/hosts.ini` | Config | CRITICAL | Inventory not found, playbook fails |
| `ansible.cfg` | 9 | `vault_password_file` | `./vault-pass.sh` | Config | CRITICAL | Vault decryption fails |
| `system.yml` | 16 | `dotfiles_base_dir` | `{{ inventory_dir }}/../../dotfiles` | Var | LOW | Works currently (inventory_dir is absolute) |
| `chezmoi/defaults` | 9 | `chezmoi_source_dir` | `role_path ~ '/../../../dotfiles'` | Fallback | MEDIUM | Only if dotfiles_base_dir undefined |
| `lightdm/defaults` | 6 | `lightdm_source_dir` | `role_path ~ '/../../../dotfiles'` | Fallback | MEDIUM | Only if dotfiles_base_dir undefined |
| `xorg/defaults` | 6 | `xorg_source_dir` | `role_path ~ '/../../../dotfiles'` | Fallback | MEDIUM | Only if dotfiles_base_dir undefined |
| `Taskfile.yml` | 4 | `ANSIBLE_DIR` | `ansible` | Var | LOW | Works fine with `dir:` context switch |
| `Taskfile.yml` | 8 | `PLAYBOOK` | `playbooks/workstation.yml` | Var | LOW | Works fine with `dir:` context switch |

---

## Conclusion

**Immediate Action Required:**
Fix `ansible.cfg` relative paths using environment variables to ensure Ansible can be executed from any directory.

**Recommended Timeline:**
1. Implement ansible.cfg fix immediately (critical)
2. Update role defaults in next maintenance (defensive)
3. Improve Taskfile.yml clarity (optional, nice-to-have)
