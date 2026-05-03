#!/usr/bin/env bash
# Install system dependencies: ansible, go-task

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

refresh_pacman_mirrorlist() {
    echo "==> Refreshing pacman mirrorlist..."
    bootstrap_run_sudo tee /etc/pacman.d/mirrorlist > /dev/null <<'EOF'
# Managed by bootstrap install-deps.sh.
# Use Arch's CDN-backed Fastly mirror to avoid partial-sync 404s during bootstrap.
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
EOF
}

refresh_archlinux_keyring() {
    echo "==> Refreshing Arch Linux keyring..."

    local temp_config
    local rc
    temp_config="$(mktemp "${TMPDIR:-/tmp}/bootstrap-pacman-conf.XXXXXX")"

    {
        sed 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf > "${temp_config}"
        bootstrap_run_sudo pacman -Sy --needed --noconfirm --config "${temp_config}" archlinux-keyring
        bootstrap_run_sudo pacman-key --populate archlinux
    }
    rc=$?

    rm -f -- "${temp_config}"
    return "${rc}"
}

# Verify Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    echo "ERROR: Arch Linux only." >&2
    exit 1
fi

# Install ansible and dependencies if missing.
# uv: 10x faster pip alternative (parallel downloads + Rust resolver).
# Used by setup-venv.sh for venv creation and dependency install.
# See setup-venv.sh for benchmark data and mirror choice rationale.
if ! command -v ansible-playbook &>/dev/null; then
    refresh_pacman_mirrorlist
    refresh_archlinux_keyring
    echo "==> Installing Ansible..."
    bootstrap_run_sudo pacman -Syu --needed --noconfirm ansible python-rich uv
else
    echo "==> Ansible already installed"
fi

# Ensure python-rich is installed (required by callback plugin)
if ! python3 -c "import rich" &>/dev/null; then
    echo "==> Installing python-rich..."
    bootstrap_run_sudo pacman -S --needed --noconfirm python-rich
fi

# Install go-task if missing
if ! command -v task &>/dev/null && ! command -v go-task &>/dev/null; then
    echo "==> Installing go-task..."
    bootstrap_run_sudo pacman -S --needed --noconfirm go-task
else
    echo "==> go-task already installed"
fi

# Create task symlink if needed
if command -v go-task &>/dev/null && ! command -v task &>/dev/null; then
    bootstrap_run_sudo ln -sf /usr/bin/go-task /usr/local/bin/task
    echo "==> Created symlink: /usr/local/bin/task -> go-task"

    TARGET_USER="${SUDO_USER:-${USER}}"
    TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
    if [[ -z "${TARGET_HOME}" ]]; then
        TARGET_HOME="${HOME}"
    fi
    mkdir -p "${TARGET_HOME}/.local/bin"
    ln -sf /usr/bin/go-task "${TARGET_HOME}/.local/bin/task"
    echo "==> Created symlink for ${TARGET_USER}: task -> go-task"
fi

echo "==> System dependencies ready"
exit 0
