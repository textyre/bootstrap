#!/usr/bin/env bash
# =============================================================================
# Arch Linux Workstation Bootstrap
# =============================================================================
# Единственная точка входа. Устанавливает Ansible и запускает playbook.
#
# Использование:
#   ./bootstrap.sh                        # Полная настройка
#   ./bootstrap.sh --tags packages        # Только пакеты
#   ./bootstrap.sh --tags "docker,ssh"    # Docker + SSH
#   ./bootstrap.sh --check                # Dry-run
#   ./bootstrap.sh --skip-tags firewall   # Пропустить firewall
#
# Все аргументы передаются напрямую в ansible-playbook.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/scripts/bootstrap/ansible"
VAULT_PASS_FILE="${HOME}/.vault-pass"

# --- Step 1: Verify Arch Linux ---
if [[ ! -f /etc/arch-release ]]; then
    echo "ERROR: This bootstrap is for Arch Linux only." >&2
    exit 1
fi

# --- Step 2: Install Ansible if missing ---
if ! command -v ansible-playbook &>/dev/null; then
    echo "==> Installing Ansible..."
    sudo pacman -Sy --needed --noconfirm ansible
fi

# --- Step 3: Install go-task if missing ---
if ! command -v task &>/dev/null && ! command -v go-task &>/dev/null; then
    echo "==> Installing go-task..."
    sudo pacman -S --needed --noconfirm go-task

    # Create symlink: task -> go-task
    if command -v go-task &>/dev/null && ! command -v task &>/dev/null; then
        mkdir -p ~/.local/bin
        ln -sf /usr/bin/go-task ~/.local/bin/task
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi

# --- Step 4: Vault password setup ---
if [[ ! -f "${VAULT_PASS_FILE}" ]]; then
    echo "Vault password file not found at ${VAULT_PASS_FILE}"
    read -s -r -p "Enter Ansible vault password: " vault_pass
    echo
    echo "${vault_pass}" > "${VAULT_PASS_FILE}"
    chmod 600 "${VAULT_PASS_FILE}"
    unset vault_pass
    echo "==> Vault password saved (chmod 600)"
fi

# --- Step 5: Setup Python venv for molecule/lint tooling ---
if [[ ! -d "${ANSIBLE_DIR}/.venv" ]]; then
    echo "==> Setting up Python virtualenv..."
    python -m venv "${ANSIBLE_DIR}/.venv"
    "${ANSIBLE_DIR}/.venv/bin/pip" install --upgrade pip
    "${ANSIBLE_DIR}/.venv/bin/pip" install -r "${ANSIBLE_DIR}/requirements.txt"
fi

# --- Step 6: Run workstation playbook ---
echo "==> Running workstation playbook..."
cd "${ANSIBLE_DIR}"
ansible-playbook playbooks/workstation.yml -v "$@"

echo "==> Bootstrap complete!"
