# SSH Sync and Remote Directory Scripts Analysis

## Summary

This project contains a comprehensive Windows-based PowerShell and Batch script suite for SSH configuration, key management, and project synchronization to remote Arch Linux servers. The scripts handle SSH key generation, deployment, and rsync/scp-based project synchronization using both Ed25519 keys and secure authentication patterns.

The search identified **7 PowerShell scripts, 2 Batch wrappers, and 1 configuration file** containing SSH and remote sync functionality across the Windows tooling directory.

---

## Files Found

### Primary Sync Script

**File:** `d:\projects\bootstrap\windows\sync\sync_to_server.ps1`
**Lines:** 292
**Purpose:** Main synchronization script using rsync (preferred) or scp fallback
**Key Messages Found:**
- Line 144: `"✓ Используется SSH ключ: $($Global:SSH_KEY)"`
- Line 158: `"Проверяю/создаю удаленную директорию..."`
- Line 160: `"Не удалось создать директорию $($Global:REMOTE_PATH) на сервере."`
- Line 288: `"✗ Синхронизация завершилась с ошибкой"`

**Key Features:**
- Uses SSH key-based authentication with `-i` parameter
- Creates remote directory via SSH with `mkdir -p`
- Supports both rsync (incremental sync) and scp (full copy) modes
- Applies CRLF→LF line ending fixes and chmod +x on remote .sh files
- Excludes: .git, .venv, node_modules, .github, .claude, .vscode, .idea, __pycache__, .molecule, .cache, windows/

---

### SSH Key Management Modules

**File:** `d:\projects\bootstrap\windows\ssh\modules\ssh-keygen.ps1`
**Purpose:** SSH key generation module
**Functions:**
- `New-SSHKey` - Generates Ed25519 SSH key pairs
- Creates `.ssh` directory if missing
- Stores keys with comment format: `{user}@{host}`

---

**File:** `d:\projects\bootstrap\windows\ssh\modules\ssh-copy-id.ps1`
**Purpose:** Public key deployment module
**Functions:**
- `Copy-SSHKey` - Transfers public key to remote server
- `Test-SSHConnection` - Validates passwordless SSH connectivity
- Uses SSH with `-p` for custom port
- Creates `~/.ssh/authorized_keys` and sets permissions (700/600)

---

**File:** `d:\projects\bootstrap\windows\ssh\modules\ssh-config.ps1`
**Purpose:** SSH configuration file management
**Functions:**
- `Update-SSHConfig` - Adds host entries to `~/.ssh/config`
- `Show-SSHHosts` - Lists configured hosts
- Creates host aliases in format: `arch-{host}-{port}`

---

### Setup and Testing Scripts

**File:** `d:\projects\bootstrap\windows\ssh\setup_ssh_key.ps1`
**Purpose:** 3-step orchestration script for SSH setup
**Workflow:**
1. Generate SSH key locally
2. Copy public key to server (prompts for password)
3. Update local SSH config

---

**File:** `d:\projects\bootstrap\windows\ssh\test-connection.ps1`
**Purpose:** Validates SSH connectivity to remote server
**Checks:**
- SSH key existence
- Passwordless connection via BatchMode
- Retrieves `uname -a` for server info verification

---

### Configuration File

**File:** `d:\projects\bootstrap\windows\config\config.ps1`
**Purpose:** Centralized configuration sourced by all scripts
**Key Settings (Port 2222, 127.0.0.1 reference):**
```powershell
$Global:SERVER_USER = "textyre"                      # Remote user
$Global:SERVER_HOST = "127.0.0.1"                    # Remote IP (port 2222 scenario)
$Global:SERVER_PORT = 2222                           # Custom SSH port
$Global:REMOTE_PATH = "/home/textyre/bootstrap"      # Remote deployment path
```

**SSH Key Naming:** `id_rsa_{host}_{port}` (e.g., `id_rsa_127.0.0.1_2222`)

---

### Batch Wrappers

**File:** `d:\projects\bootstrap\windows\sync\sync_to_server.bat`
**Purpose:** Double-click launcher for sync script
**Command:** Launches sync_to_server.ps1 with Bypass execution policy

---

**File:** `d:\projects\bootstrap\windows\ssh\setup_ssh_key.bat`
**Purpose:** Double-click launcher for SSH setup
**Command:** Launches setup_ssh_key.ps1 with Bypass execution policy

---

## Port 2222 and 127.0.0.1 References

### Configuration Usage (Port 2222)

| File | Line | Context |
|------|------|---------|
| `windows/config/config.ps1` | 10 | `$Global:SERVER_PORT = 2222` |
| `windows/README.md` | 147,159-163,170 | Example SSH key naming and alias setup |
| `windows/ssh/README.md` | 20-21, 30-31, 38, 71, 76, 99, 111, 147, 151, 163 | VM port forwarding documentation |

### Documentation References

**File:** `d:\projects\bootstrap\windows\README.md`
- Lines 147, 159-163, 170: Example configuration with port 2222 and 127.0.0.1
- Alias format: `arch-127.0.0.1-2222`
- Example SSH command: `ssh arch-127.0.0.1-2222`

**File:** `d:\projects\bootstrap\windows\ssh\README.md`
- Describes VirtualBox NAT port forwarding setup
- Example: `VBoxManage modifyvm "VM-name" --natpf1 "guestssh,tcp,,2222,,22"`
- Used for local development/testing against virtualized Arch Linux

---

## Script Behavior Analysis

### SSH Authentication Flow

1. **Configuration Loading:** All scripts source `config.ps1` for server credentials
2. **Key Verification:** Checks for SSH key at `$Global:SSH_KEY` path
3. **Fallback:** If key missing, prompts user to continue with password auth
4. **SSH Command Construction:**
   - With key: `ssh -i "path\to\key" -p 2222 user@host`
   - Without key: `ssh -p 2222 user@host`

### Rsync vs SCP Logic

```powershell
# sync_to_server.ps1 logic
if (rsync available AND not -ForceScp) {
    # Use rsync -avz --delete with SSH transport
    # Only syncs changes, removes deleted files remotely
} else {
    # Use scp -r for full directory copy
    # Fallback when rsync unavailable
}
```

### Remote Directory Creation

**Source:** Lines 156-162 in sync_to_server.ps1
```powershell
$remotePathLiteral = ConvertTo-PosixLiteral -Value $Global:REMOTE_PATH
Write-Host "Проверяю/создаю удаленную директорию..." -ForegroundColor Cyan
if ((Invoke-SSHCommand -Command ("mkdir -p {0}" -f $remotePathLiteral)) -ne 0) {
    throw "Не удалось создать директорию $($Global:REMOTE_PATH) на сервере."
}
```

- Uses `mkdir -p` via SSH to create directory path
- Escapes special characters in path via `ConvertTo-PosixLiteral`
- Throws exception if creation fails (exit code ≠ 0)

### Post-Sync Permissions Fix

**Source:** Lines 248-261 in sync_to_server.ps1
```powershell
# Normalizes CRLF → LF in shell scripts and sets execute bit
$findCommand = "if command -v sed >/dev/null 2>&1; then
    find {0} -type f -name '*.sh' -exec sed -i 's/\r$//' {{}} +;
fi;
find {0} -type f -name '*.sh' -exec chmod +x {{}} +"
```

- Replaces Windows line endings (CRLF) with Unix (LF)
- Sets executable bit on all .sh files
- Uses sed if available, otherwise skipped gracefully

---

## Potential Issues and Edge Cases

### 1. **POSIX Path Escaping**
- Function `ConvertTo-PosixLiteral` (lines 20-28) escapes quotes, backslashes, dollar signs for shell safety
- Critical for paths with special characters

### 2. **SSH Command Escaping**
- Function `Format-CommandPart` (lines 30-41) quotes values containing whitespace
- Important for rsync `-e` transport argument construction

### 3. **Rsync Transport String Building**
- Function `Get-RsyncTransport` (lines 81-94) manually constructs SSH command
- Example: `ssh -i "key" -p 2222`
- Nested quoting required for spaces in key paths

### 4. **File Exclusions**
- Both rsync and scp skip: .git/, .github/, .venv/, windows/, .claude/, .vscode/, .idea/, __pycache__/, .molecule/, .cache/
- Python bytecode excluded: *.pyc, *.pyo

### 5. **Missing Dependencies**
- Gracefully falls back scp if rsync unavailable
- Fails if neither rsync nor scp available
- Requires OpenSSH Client installed on Windows

### 6. **Configuration Validation**
- `Test-Config` validates SERVER_USER, SERVER_HOST, SERVER_PORT (1-65535), REMOTE_PATH
- All scripts abort if validation fails

---

## Security Considerations

### Key Management
- Uses Ed25519 (modern, 256-bit)
- Generated without passphrase (for automation)
- Stored in `%USERPROFILE%\.ssh\id_rsa_{host}_{port}`
- Private key permissions: Windows ACL (equiv. to Unix 600)

### SSH Options Used
- `StrictHostKeyChecking accept-new` - Auto-accept new host keys
- `IdentitiesOnly yes` - Use only specified key file
- `BatchMode yes` - No interactive prompts (test mode)

### Remote Directory Permissions
- `mkdir -p` creates hierarchy safely
- `chmod 700 ~/.ssh` - Directory readable/writable only by owner
- `chmod 600 ~/.ssh/authorized_keys` - Key file writable only by owner

---

## Usage Summary

### 1. Initial SSH Setup
```powershell
.\windows\ssh\setup_ssh_key.ps1
# or
.\windows\ssh\setup_ssh_key.bat  # double-click
```

### 2. Test Connection
```powershell
.\windows\ssh\test-connection.ps1
```

### 3. Synchronize Project
```powershell
.\windows\sync\sync_to_server.ps1
# or with rsync bypass
.\windows\sync\sync_to_server.ps1 -ForceScp
# or without permission fixes
.\windows\sync\sync_to_server.ps1 -SkipPermissions
```

### 4. Manual SSH Commands
```powershell
# Using configured key and port
ssh -i "C:\Users\user\.ssh\id_rsa_127.0.0.1_2222" -p 2222 textyre@127.0.0.1
# or via SSH config alias
ssh arch-127.0.0.1-2222
```

---

## File Size Reference

| File | Lines |
|------|-------|
| sync_to_server.ps1 | 292 |
| setup_ssh_key.ps1 | 126 |
| ssh-keygen.ps1 | 74 |
| ssh-copy-id.ps1 | 99 |
| ssh-config.ps1 | 107 |
| test-connection.ps1 | 68 |
| config.ps1 | 78 |
| sync_to_server.bat | 16 |
| setup_ssh_key.bat | 17 |

---

## References to Documentation

- `d:\projects\bootstrap\windows\README.md` - SSH setup and VM networking
- `d:\projects\bootstrap\windows\ssh\README.md` - Detailed SSH configuration guide
- `d:\projects\bootstrap\docs\CONFIG.txt` - Legacy configuration reference

