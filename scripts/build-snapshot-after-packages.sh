#!/usr/bin/env bash
# DEPRECATED: source VM snapshot mutation is intentionally disabled.
# This script used to rebuild "after-packages" directly on arch-base, which
# conflicts with the immutable clone-only VM architecture.
#
# Do not delete this file yet: it remains as a historical reference until the
# replacement Node.js workflow lands in the Bootstrap Scripts monorepo.

set -euo pipefail

echo "DEPRECATED: scripts/build-snapshot-after-packages.sh is disabled." >&2
echo "Reason: source VM 'arch-base' and its snapshots are immutable." >&2
echo "Use clone-only workflow: create a disposable clone from 'after-packages' and run playbooks on the clone." >&2
exit 1

# Prefer the POSIX toolchain when invoked from PowerShell / Git Bash on Windows.
export PATH="/usr/bin:/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

VM="arch-base"
SNAPSHOT_NAME="after-packages"
BASE_SNAPSHOT_NAME="initial"
LEGACY_BASE_SNAPSHOT_NAME="base"
SSH_KEY="${HOME}/.ssh/id_rsa_127.0.0.1_2222"
SSH_CMD="ssh -p 2222 -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 textyre@127.0.0.1"

FORCE="${1:-}"

resolve_base_snapshot() {
    if VBoxManage snapshot "$VM" showvminfo "$BASE_SNAPSHOT_NAME" >/dev/null 2>&1; then
        printf '%s' "$BASE_SNAPSHOT_NAME"
        return 0
    fi

    if VBoxManage snapshot "$VM" showvminfo "$LEGACY_BASE_SNAPSHOT_NAME" >/dev/null 2>&1; then
        printf '%s' "$LEGACY_BASE_SNAPSHOT_NAME"
        return 0
    fi

    echo "ERROR: Could not find base snapshot '$BASE_SNAPSHOT_NAME' or legacy '$LEGACY_BASE_SNAPSHOT_NAME' on VM '$VM'." >&2
    return 1
}

# Step 1: Compute content hash (roles + venv inputs)
echo "==> Step 1: Computing content hash..."
CONTENT_HASH=$(
    find \
        "$REPO_ROOT/ansible/roles" \
        "$REPO_ROOT/ansible/requirements.txt" \
        "$REPO_ROOT/scripts/setup-venv.sh" \
        "$REPO_ROOT/scripts/install-deps.sh" \
        -type f | sort | xargs sha256sum | sha256sum | awk '{print $1}'
)
echo "    Hash: $CONTENT_HASH"

# Step 2: Check existing snapshot — skip if hash matches
if [[ "$FORCE" != "--force" ]]; then
    echo "==> Step 2: Checking existing snapshot..."
    EXISTING_DESC=$(
        VBoxManage snapshot "$VM" showvminfo "$SNAPSHOT_NAME" 2>/dev/null \
            | grep "Description:" | sed 's/Description:[[:space:]]*//' || true
    )
    if echo "$EXISTING_DESC" | grep -q "content_hash=$CONTENT_HASH"; then
        echo "    Snapshot is up-to-date (hash matches). Use --force to rebuild."
        exit 0
    fi
    echo "    Snapshot missing or hash mismatch — rebuilding."
fi

BASELINE_SNAPSHOT="$(resolve_base_snapshot)"
if [[ "$BASELINE_SNAPSHOT" != "$BASE_SNAPSHOT_NAME" ]]; then
    echo "==> Snapshot alias: using legacy base snapshot '$BASELINE_SNAPSHOT' because '$BASE_SNAPSHOT_NAME' is absent."
fi

# Step 3: Stop VM gracefully if running
echo "==> Step 3: Stopping VM..."
VBoxManage controlvm "$VM" acpipowerbutton 2>/dev/null || true
for i in $(seq 1 30); do
    STATE=$(VBoxManage showvminfo "$VM" --machinereadable \
        | grep "^VMState=" | tr -d '"' | cut -d= -f2)
    [[ "$STATE" == "poweroff" ]] && break
    sleep 2
done

# Step 4: Delete old after-packages snapshot if it exists
echo "==> Step 4: Removing old '$SNAPSHOT_NAME' snapshot (if any)..."
VBoxManage snapshot "$VM" delete "$SNAPSHOT_NAME" 2>/dev/null || true

# Step 5: Restore to clean base state
echo "==> Step 5: Restoring '$BASELINE_SNAPSHOT' snapshot..."
VBoxManage snapshot "$VM" restore "$BASELINE_SNAPSHOT"

# Step 6: Start VM
echo "==> Step 6: Starting VM..."
VBoxManage startvm "$VM" --type headless

# Step 7: Wait for SSH (max 120s)
echo "==> Step 7: Waiting for SSH..."
for i in $(seq 1 24); do
    if $SSH_CMD echo ok 2>/dev/null; then
        echo "    SSH ready."
        break
    fi
    echo "    Attempt $i/24..."
    sleep 5
done
$SSH_CMD echo ok >/dev/null || { echo "ERROR: SSH not available after 120s" >&2; exit 1; }

# Step 8: Sync project to VM
echo "==> Step 8: Syncing project to VM..."
SSH_HOST=arch-127.0.0.1-2222 bash "$SCRIPT_DIR/ssh-scp-to.sh" --project

# Step 9: Install system deps (ansible, go-task, uv) then bootstrap venv+galaxy
echo "==> Step 9: Installing system deps..."
SSH_HOST=arch-127.0.0.1-2222 bash "$SCRIPT_DIR/ssh-run.sh" --bootstrap-secrets \
    "cd ~/bootstrap && bash scripts/install-deps.sh"
echo "==> Step 9: Running bootstrap (venv + galaxy)..."
SSH_HOST=arch-127.0.0.1-2222 bash "$SCRIPT_DIR/ssh-run.sh" --bootstrap-secrets \
    "cd ~/bootstrap && PATH=\$HOME/.local/bin:\$PATH task bootstrap"

# Step 10: Run roles that define the snapshot scope
echo "==> Step 10: Running roles: reflector + package_manager + packages..."
SSH_HOST=arch-127.0.0.1-2222 bash "$SCRIPT_DIR/ssh-run.sh" --bootstrap-secrets \
    "cd ~/bootstrap && PATH=\$HOME/.local/bin:\$PATH task --yes workstation -- --tags reflector,package_manager,packages"

# Step 11: Graceful shutdown via ACPI
echo "==> Step 11: Sending ACPI poweroff..."
VBoxManage controlvm "$VM" acpipowerbutton
echo "    Waiting for VM to power off..."
for i in $(seq 1 60); do
    STATE=$(VBoxManage showvminfo "$VM" --machinereadable \
        | grep "^VMState=" | tr -d '"' | cut -d= -f2)
    [[ "$STATE" == "poweroff" ]] && break
    sleep 2
done
STATE=$(VBoxManage showvminfo "$VM" --machinereadable \
    | grep "^VMState=" | tr -d '"' | cut -d= -f2)
if [[ "$STATE" != "poweroff" ]]; then
    echo "ERROR: VM did not power off after 120s" >&2
    exit 1
fi

# Step 12: Take snapshot with content hash in description
echo "==> Step 12: Taking snapshot '$SNAPSHOT_NAME'..."
VBoxManage snapshot "$VM" take "$SNAPSHOT_NAME" \
    --description "roles: reflector, package_manager, packages | content_hash=$CONTENT_HASH"

echo ""
echo "==> Done. Snapshot '$SNAPSHOT_NAME' ready."
echo "    Hash: $CONTENT_HASH"
