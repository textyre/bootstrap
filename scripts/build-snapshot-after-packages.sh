#!/usr/bin/env bash
# Build the "after-packages" snapshot on arch-base.
# Idempotent: skips rebuild when content hash matches the existing snapshot.
#
# Usage: bash scripts/build-snapshot-after-packages.sh [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

VM="arch-base"
SNAPSHOT_NAME="after-packages"
SSH_KEY="${HOME}/.ssh/id_rsa_127.0.0.1_2222"
SSH_CMD="ssh -p 2222 -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 textyre@127.0.0.1"

FORCE="${1:-}"

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

# Step 5: Restore to initial clean state
echo "==> Step 5: Restoring 'initial' snapshot..."
VBoxManage snapshot "$VM" restore "initial"

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
$SSH_CMD "cd ~/bootstrap && bash scripts/install-deps.sh"
echo "==> Step 9: Running bootstrap (venv + galaxy)..."
$SSH_CMD "cd ~/bootstrap && PATH=\$HOME/.local/bin:\$PATH task bootstrap"

# Step 10: Run roles that define the snapshot scope
echo "==> Step 10: Running roles: reflector + package_manager + packages..."
$SSH_CMD "cd ~/bootstrap && PATH=\$HOME/.local/bin:\$PATH task --yes workstation -- --tags reflector,package_manager,packages"

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
