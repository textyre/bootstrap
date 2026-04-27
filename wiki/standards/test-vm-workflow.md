# Test VM Workflow

> Execution model, VM management, playbook testing, and hard rules for automated testing on VirtualBox VMs.

---

## Execution Model

```
┌─────────────────────┐         SSH (port 2223)         ┌─────────────────────┐
│   Windows (local)   │ ──────────────────────────────▶  │   VirtualBox VM     │
│                     │         scp (port 2223)          │   (Arch Linux)      │
│  • Edit files       │ ──────────────────────────────▶  │                     │
│  • git operations   │                                  │  • task workstation │
│  • VBoxManage       │                                  │  • task check       │
│                     │                                  │  • task lint        │
│  d:\projects\       │   scp mirrors to:                │  ~/bootstrap/       │
│    bootstrap\       │ ─────────────────────────────▶   │    ansible/         │
│      ansible\       │                                  │      roles/         │
│        roles\       │                                  │      inventory/     │
│        inventory\   │                                  │      vault-pass.sh  │
│        .local\      │                                  │      task bootstrap │
└─────────────────────┘                                  └─────────────────────┘
     LOCAL actions:                                           VM actions:
     ✅ File editing                                          ✅ task workstation
     ✅ VBoxManage                                            ✅ task check / lint
     ✅ scp to VM (ssh-scp-to.sh)                             ✅ Verification commands
     ✅ SSH to VM                                             ❌ Manual pacman/systemctl
     ✅ git commit/push                                       ❌ Manual file editing
                                                              ❌ Manual venv/pip setup
```

**Key principle:** Ansible runs ON the VM targeting `localhost` with `ansible_connection=local`. The local Windows machine is only for editing, syncing, and VM management.

### Inventory

The VM uses the **default inventory** `ansible/inventory/hosts.yml`:
```yaml
workstations:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
```

The `become_password` (sudo) is stored encrypted in `ansible/inventory/group_vars/all/vault.yml` and decrypted automatically by `vault-pass.sh`.

**NEVER** hardcode `ansible_become_password` in inventory files. **NEVER** create custom inventory on the VM. The default `hosts.yml` + vault is the only correct configuration.

### Vault

```
vault-pass.sh          ← resolver script (consumes BOOTSTRAP_* secret env)
  └─▶ host bootstrap helper
        └─▶ .local/bootstrap/vault-pass.gpg  ← GPG-encrypted local secret
              └─▶ vault.yml                  ← encrypted vars (become_password, secrets)
```

The VM receives `vault-pass.sh`, but not a plaintext vault password file.
Remote bootstrap/task runs that need vault access MUST be started through
`scripts/ssh-run.sh --bootstrap-secrets ...`, which decrypts the local secret on
the host and forwards it ephemerally into the remote shell environment. All
`task` commands still keep the `_check-vault` dependency — they fail
automatically if vault is misconfigured.

**NEVER** use `--ask-vault-pass`. **NEVER** create a plaintext vault password
file manually on the VM.

### Taskfile Commands

All playbook execution goes through the Taskfile. **NEVER** run `ansible-playbook` directly. **NEVER** activate venv manually.

| Command | What it does |
|---------|-------------|
| `task workstation` | Full workstation playbook (`-v` auto) |
| `task workstation -- --skip-tags "x,y"` | Playbook with tag filtering |
| `task check` | Syntax check all playbooks |
| `task lint` | ansible-lint on all roles |
| `task bootstrap` | Install venv + galaxy deps (first-time setup) |

The `task workstation` command has an interactive prompt. Bypass with:
```bash
task --yes workstation -- --skip-tags "..."
```

---

## VM Management

### Snapshot Protocol

The project uses VirtualBox snapshots for clean-state testing.

**Base VM:** `arch-base`. **Sacred snapshot:** `initial` on `arch-base` — NEVER delete, modify, or restore directly. Only clone from it.

### Two Snapshots

`arch-base` has two snapshots for different test scenarios:

| Snapshot | Contents | Use for |
|----------|----------|---------|
| `initial` | Bare Arch install + SSH | Full fresh-install test (all roles) |
| `after-packages` | `initial` + reflector + package_manager + packages | Role tests that assume packages are installed |

The `after-packages` snapshot is built automatically:
```bash
task snapshot:build-after-packages    # skips if content hash matches
task snapshot:rebuild-after-packages  # force rebuild
```

The build script (`scripts/build-snapshot-after-packages.sh`) computes a SHA256 hash of `ansible/roles/`, `requirements.txt`, and venv scripts, stores it in the snapshot description, and skips the rebuild if the hash is unchanged.

### Clone Workflow

```
                    ┌─────────────────────┐
                    │   VM: arch-base      │
                    │   snapshot: initial  │
                    │  (NEVER TOUCH)       │
                    └──────────┬──────────┘
                               │ clone-test-vm.sh --from=initial
                               ▼
                    ┌─────────────────────┐
                    │  "arch-test-clone"   │
                    │  (disposable)        │──── test ──── delete
                    └─────────────────────┘

                    ┌─────────────────────┐
                    │   VM: arch-base      │
                    │ snapshot:            │
                    │  after-packages      │
                    └──────────┬──────────┘
                               │ clone-test-vm.sh --from=after-packages
                               ▼
                    ┌─────────────────────┐
                    │  "arch-test-clone"   │
                    │  packages pre-baked  │──── test ──── delete
                    └─────────────────────┘
```

### Step-by-Step: Create Clone

All `VBoxManage` commands run LOCALLY on Windows, not via SSH.

Use the helper script (preferred):
```bash
# Clone from initial (default) on port 2223
bash scripts/clone-test-vm.sh

# Clone from after-packages, replace if exists
bash scripts/clone-test-vm.sh --from=after-packages --replace

# Custom name and port
bash scripts/clone-test-vm.sh --from=initial --name=arch-test-2 --port=2224
```

Or manually:
```bash
# 1. Stop base VM (to free port 2222) and any previous clone
VBoxManage controlvm "arch-base" poweroff 2>/dev/null || true
VBoxManage controlvm "arch-test-clone" poweroff 2>/dev/null || true
VBoxManage unregistervm "arch-test-clone" --delete 2>/dev/null || true

# 2. Clone from snapshot (linked = fast, ~seconds)
VBoxManage clonevm "arch-base" \
  --snapshot "initial" \
  --name "arch-test-clone" \
  --options link \
  --register

# 3. Configure port forwarding (SSH on 2223)
VBoxManage modifyvm "arch-test-clone" --natpf1 "ssh,tcp,,2223,,22"

# 4. Start clone headless
VBoxManage startvm "arch-test-clone" --type headless

# 5. Wait for SSH (max 60 seconds)
for i in $(seq 1 12); do
  ssh -p 2223 -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    -i ~/.ssh/id_rsa_127.0.0.1_2222 textyre@127.0.0.1 echo ok && break
  sleep 5
done
```

### Step-by-Step: Cleanup

```bash
# Stop and delete clone
VBoxManage controlvm "arch-test-clone" poweroff
VBoxManage unregistervm "arch-test-clone" --delete

# Restart original VM (if it was running before)
VBoxManage startvm "<VM-NAME>" --type headless
```

### SSH Connection

```bash
SSH_CMD="ssh -p 2223 -i ~/.ssh/id_rsa_127.0.0.1_2222 textyre@127.0.0.1"
```

---

## Playbook Testing Workflow

### Pipeline: Sync → Check → Run → Verify → Idempotency

```
┌────────┐    ┌───────┐    ┌───────┐    ┌───────┐    ┌──────────┐    ┌────────┐
│ 1.Sync │───▶│2.Check│───▶│3.Run 1│───▶│4.Verif│───▶│5.Run 2   │───▶│6.Verif │
│ 1.Sync │    │syntax │    │fresh  │    │ state │    │idempotent│    │ final  │
└────────┘    └───────┘    └───────┘    └───────┘    └──────────┘    └────────┘
                              │                          │
                              │ failed?                  │ changed>0?
                              ▼                          ▼
                        Fix role LOCALLY           BUG — no exceptions,
                        sync + RESET VM            changed=0 required for ALL
                        restart from step 1
```

### When to Reset VM

| Scenario | Reset VM? |
|----------|-----------|
| Before Run 1 (fresh install test) | **YES** — always start from clean snapshot clone |
| Before Run 2 (idempotency test) | **NO** — run on same VM as Run 1 |
| After fixing a failed role | **YES** — reset before re-running |
| Switching to a different role scope | **YES** — start clean |

### Step 1: Sync Project to VM

```bash
SSH_HOST=arch-127.0.0.1-2223 bash scripts/ssh-scp-to.sh --project
```

`ssh-scp-to.sh --project` deliberately excludes plaintext vault password files.
Remote bootstrap/task runs must receive the vault secret through
`ssh-run.sh --bootstrap-secrets`, not through synced plaintext artifacts.

### Step 2: Syntax Check

```bash
$SSH_CMD "cd ~/bootstrap && task check"
```

### Step 3: Run Playbook (Run 1)

Full playbook from beginning through a specific role using `--skip-tags`:

```bash
$SSH_CMD "cd ~/bootstrap && task --yes workstation -- \
  --skip-tags 'git,shell,docker,firewall,caddy,vaultwarden,xorg,lightdm,greeter,zen_browser,chezmoi'"
```

**Scope reference** — roles in `playbooks/workstation.yml` order:

| Stop after | Skip tags |
|------------|-----------|
| fail2ban | `git,shell,docker,firewall,caddy,vaultwarden,xorg,lightdm,greeter,zen_browser,chezmoi` |
| ssh | `teleport,fail2ban,git,shell,docker,firewall,caddy,vaultwarden,xorg,lightdm,greeter,zen_browser,chezmoi` |
| packages | `user,ssh_keys,ssh,teleport,fail2ban,git,shell,docker,firewall,caddy,vaultwarden,xorg,lightdm,greeter,zen_browser,chezmoi` |
| full playbook | *(no skip)* |

**If a role fails:**
1. Record the full error output
2. Identify root cause (not symptoms)
3. Fix the role LOCALLY (file:line:change)
4. RESET VM to clean state (clone workflow above)
5. rsync and restart from Step 1

**NEVER** fix issues manually on the VM. **NEVER** continue from the failure point. **NEVER** skip the failed role. Reset and re-run from scratch.

### Step 4: Verification

After Run 1 succeeds (`failed=0`), verify system state via SSH:

```bash
$SSH_CMD "
  echo '=== fail2ban ===' && sudo systemctl status fail2ban --no-pager | head -5;
  echo '=== sysctl ===' && sysctl vm.swappiness;
  echo '=== root ===' && sudo passwd -S root;
  echo '=== faillock ===' && faillock --user textyre;
  echo '=== yay ===' && which yay && yay --version;
"
```

Adapt verification commands to the roles being tested.

### Step 5: Idempotency Run (Run 2)

Run the EXACT SAME command as Step 3 on the SAME VM (**no reset**).

**Expected result:** `changed=0` for ALL roles. No exceptions.

Any role with `changed > 0` on Run 2 is a **BUG** that must be fixed. This includes `reflector` and `package_manager` — both must be idempotent.

### Step 6: Final Verification

Repeat Step 4 to confirm idempotency run didn't break anything.

---

## Hard Rules

### 1. No Manual Actions on VM

The VM is a **target**, not a workbench. Every system change MUST come through Ansible roles.

**FORBIDDEN on VM:**
- `pacman -S`, `pacman -Syu`, `pacman -Rns` — manual package management
- `systemctl start/stop/enable/disable` — manual service management (except `status` for verification)
- `vim`, `nano`, `sed`, `echo >` — manual file editing
- `reflector`, `curl`, `wget` — manual downloads
- Manual venv creation, `pip install`, `ansible-galaxy install`
- Writing inventory files or vault files manually
- `ansible-playbook` directly (use `task` commands)

**ALLOWED on VM (via SSH):**
- `task` commands (`workstation`, `check`, `lint`, `bootstrap`)
- Read-only verification commands (`systemctl status`, `cat`, `sysctl`, `which`, `passwd -S`, etc.)

### 2. Fix Roles, Not Systems

```
WRONG: SSH to VM → manually fix the issue → re-run
RIGHT: Identify root cause → fix role locally → rsync → reset VM → re-run from scratch
```

The fix must be **in the role code**, not in the VM state. Every manual fix is lost on the next VM reset.

### 3. Evidence Rule

Every claim about system state MUST include the command and its verbatim output.

- "It works" without evidence = not verified
- "The service is running" without `systemctl status` output = unproven
- "The fix is applied" without `cat -n file:lines` = unconfirmed

### 4. Portability Rule

Roles support 5 distros: Arch, Ubuntu, Fedora, Void, Gentoo. Any fix that hardcodes a distro-specific path or command without an `ansible_facts['os_family']` guard is a bug.

### 5. No Shortcuts

- **NEVER** use `--ask-vault-pass` — vault-pass.sh handles it
- **NEVER** use `--skip-tags` to work around a broken role — fix the role
- **NEVER** use `ignore_errors: true` to hide failures
- **NEVER** continue from failure point — reset and re-run from scratch
- **NEVER** amend the snapshot — it's the immutable baseline
