#!/usr/bin/env bash
# Clone arch-base into a disposable test VM.
#
# Usage: bash scripts/clone-test-vm.sh [OPTIONS]
#   --from=<current-snapshot-name>  snapshot to clone from (required)
#   --name=VMNAME                   clone name (default: arch-test-clone)
#   --port=PORT                     SSH host port forwarded to guest:22 (default: 2223)
#   --replace                       delete existing VM with same name before cloning

set -euo pipefail

FROM=""
NAME="arch-test-clone"
PORT="2223"
REPLACE=false

for arg in "$@"; do
    case "$arg" in
        --from=*)  FROM="${arg#--from=}" ;;
        --name=*)  NAME="${arg#--name=}" ;;
        --port=*)  PORT="${arg#--port=}" ;;
        --replace) REPLACE=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "$FROM" ]]; then
    echo "ERROR: --from=<current-snapshot-name> is required." >&2
    echo "Example: bash scripts/clone-test-vm.sh --from=after-packages --replace" >&2
    exit 1
fi

SSH_KEY="${HOME}/.ssh/id_rsa_127.0.0.1_2222"
SSH_CMD="ssh -p $PORT -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 textyre@127.0.0.1"

wait_for_ssh() {
    echo "==> Waiting for SSH on port $PORT..."
    for i in $(seq 1 12); do
        if $SSH_CMD echo ok 2>/dev/null; then
            echo "    SSH ready."
            return 0
        fi
        echo "    Attempt $i/12..."
        sleep 5
    done

    echo "ERROR: SSH not available after 60s on port $PORT" >&2
    exit 1
}

running_kernel_has_matching_modules() {
    $SSH_CMD 'test -d "/usr/lib/modules/$(uname -r)"'
}

echo "==> Clone: arch-base@$FROM → $NAME (SSH port $PORT)"

# Step 1: Remove existing clone if --replace
if $REPLACE; then
    echo "==> Removing existing VM '$NAME'..."
    VBoxManage controlvm "$NAME" acpipowerbutton 2>/dev/null || true
    sleep 3
    VBoxManage controlvm "$NAME" poweroff 2>/dev/null || true
    VBoxManage unregistervm "$NAME" --delete 2>/dev/null || true
fi

# Step 2: Clone from snapshot (linked = fast, ~seconds)
echo "==> Cloning arch-base@$FROM..."
VBoxManage clonevm "arch-base" \
    --snapshot "$FROM" \
    --name "$NAME" \
    --options link \
    --register

# Step 3: Clear any inherited NAT rules, add single rule for requested port
echo "==> Configuring NAT (host $PORT → guest 22)..."
for rule in ssh ssh2222 ssh2223; do
    VBoxManage modifyvm "$NAME" --natpf1 delete "$rule" 2>/dev/null || true
done
VBoxManage modifyvm "$NAME" --natpf1 "ssh,tcp,,$PORT,,22"

# Step 4: Enable 3D + 128 MB VRAM (required for ctOS greeter)
VBoxManage modifyvm "$NAME" --accelerate3d on --vram 128 2>/dev/null || true

# Step 5: Start headless
echo "==> Starting '$NAME' headless..."
VBoxManage startvm "$NAME" --type headless

# Step 6: Wait for SSH (max 60s)
wait_for_ssh

# Step 7: Reboot once if the clone booted on an old kernel without matching modules.
# This can happen on a disposable clone from after-packages when the frozen snapshot
# was captured after package upgrades but before the reboot that activates the new kernel.
if ! running_kernel_has_matching_modules; then
    echo "==> Running kernel has no matching /usr/lib/modules entry; rebooting clone once..."
    VBoxManage controlvm "$NAME" reset
    wait_for_ssh

    if ! running_kernel_has_matching_modules; then
        echo "ERROR: Running kernel still has no matching modules directory after reboot." >&2
        $SSH_CMD 'uname -r; echo ---; ls /usr/lib/modules' 2>/dev/null || true
        exit 1
    fi

    echo "    Rebooted into the installed kernel successfully."
fi

echo ""
echo "Connect: ssh -p $PORT -i $SSH_KEY textyre@127.0.0.1"
