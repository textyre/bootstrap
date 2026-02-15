#!/usr/bin/env bash
# Install system dependencies: ansible, go-task

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${REPO_ROOT}/ansible"

# Verify Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    echo "ERROR: Arch Linux only." >&2
    exit 1
fi

# Install ansible if missing
if ! command -v ansible-playbook &>/dev/null; then
    echo "==> Installing Ansible..."
    sudo pacman -Syu --needed --noconfirm ansible
else
    echo "==> Ansible already installed"
fi

# Install go-task if missing
if ! command -v task &>/dev/null && ! command -v go-task &>/dev/null; then
    echo "==> Installing go-task..."
    sudo pacman -S --needed --noconfirm go-task
else
    echo "==> go-task already installed"
fi

# Create task symlink if needed
if command -v go-task &>/dev/null && ! command -v task &>/dev/null; then
    mkdir -p ~/.local/bin
    ln -sf /usr/bin/go-task ~/.local/bin/task
    echo "==> Created symlink: task -> go-task"
fi

echo "==> System dependencies ready"
exit 0
