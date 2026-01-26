#!/usr/bin/env bash
#
# Bootstrap script for fresh Arch Linux installation
# This script installs minimal dependencies and delegates to Task
#

set -e

echo "==> Bootstrap Ansible Testing Environment"
echo ""

# Fix directory permissions to prevent Ansible security warnings
# Ansible ignores ansible.cfg in world-writable directories
echo "==> Fixing directory permissions..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod 755 "$SCRIPT_DIR"
echo "✓ Directory permissions fixed"
echo ""

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    echo "ERROR: This script is designed for Arch Linux"
    exit 1
fi

# Update mirrorlist first (fix 404 errors)
echo "==> Updating package database..."
sudo pacman -Syy

# Install Task if not present
if ! command -v task &> /dev/null && ! command -v go-task &> /dev/null; then
    echo "==> Installing Task (go-task)..."
    sudo pacman -S --needed --noconfirm go-task
    echo "✓ Task installed from official repos"
else
    echo "✓ Task is already installed"
fi

# In Arch, the binary is called 'go-task', create alias
if command -v go-task &> /dev/null && ! command -v task &> /dev/null; then
    echo "==> Creating 'task' alias for 'go-task'..."

    # Create symlink in ~/.local/bin
    mkdir -p ~/.local/bin
    ln -sf /usr/bin/go-task ~/.local/bin/task

    # Add to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"

    # Add to shell config if not already there
    SHELL_CONFIG="$HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    fi

    if ! grep -q '$HOME/.local/bin' "$SHELL_CONFIG" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_CONFIG"
        echo "✓ Added ~/.local/bin to PATH in $SHELL_CONFIG"
    fi

    echo "✓ Created symlink: task -> go-task"
fi

# Verify Task is available
if ! command -v task &> /dev/null && ! command -v go-task &> /dev/null; then
    echo "ERROR: Task installation failed"
    exit 1
fi

# Delegate to Taskfile
echo "==> Running task bootstrap..."
if command -v task &> /dev/null; then
    task bootstrap
else
    go-task bootstrap
fi

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "Available commands (use 'task' or 'go-task'):"
echo "  task         - Show all available tasks"
echo "  task check   - Validate syntax"
echo "  task lint    - Check best practices"
echo "  task test    - Run tests"
echo "  task all     - Run all checks"
echo "  task run     - Apply playbook (real changes)"
echo ""
echo "Note: You may need to reload shell or run: source ~/.bashrc"
echo ""
echo "Start with: task check"
