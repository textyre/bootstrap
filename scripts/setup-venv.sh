#!/usr/bin/env bash
# Create Python virtualenv and install pip dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

REPO_ROOT="${BOOTSTRAP_REPO_ROOT}"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VENV_DIR="${ANSIBLE_DIR}/.venv"

if [[ -x "${VENV_DIR}/bin/python" ]] && "${VENV_DIR}/bin/python" -c "import ansible" 2>/dev/null; then
    echo "==> Python venv already exists and working"
    exit 0
fi

# Remove broken/incompatible venv
if [[ -d "${VENV_DIR}" ]]; then
    echo "==> Removing broken venv..."
    rm -rf "${VENV_DIR}"
fi

# Mirror: Aliyun chosen after benchmark (Almaty, KZ, 2026-04-17).
# Tested mirrors (django 8.4 MB download):
#   aliyun  : 2.76 MB/s  (chosen)
#   bfsu    : 2.11 MB/s
#   tuna    : 1.03 MB/s
#   ustc    : 0.93 MB/s
#   huawei  : 0.83 MB/s
#   pypi.org: 0.17 MB/s  (baseline, 16x slower)
# Full pipeline benchmark (ansible+cryptography+jinja2+paramiko+pyyaml):
#   pip + pypi.org : 227s (baseline)
#   pip + tuna     :  49s (4.7x)
#   uv  + pypi.org :  83s (2.7x)
#   uv  + tuna     :  28s (8.2x)
#   uv  + aliyun   :  15s (14.9x, chosen)
# Note: Aliyun (and any CDN) can flap. UV_HTTP_TIMEOUT below handles this.
# If aliyun consistently degrades — manual fallback in priority:
#   bfsu, tuna, ustc, huawei
PYPI_MIRROR="https://mirrors.aliyun.com/pypi/simple/"

# System-wide pip config — any ansible role that invokes pip picks this up.
if [[ ! -f /etc/pip.conf ]] || ! grep -q "${PYPI_MIRROR}" /etc/pip.conf 2>/dev/null; then
    echo "==> Writing /etc/pip.conf (Aliyun mirror)..."
    bootstrap_run_sudo tee /etc/pip.conf > /dev/null <<EOF
[global]
index-url = ${PYPI_MIRROR}
EOF
fi

# Install uv if missing (normally provided by install-deps.sh via pacman).
if ! command -v uv &>/dev/null; then
    if command -v pacman &>/dev/null; then
        echo "==> Installing uv via pacman..."
        bootstrap_run_sudo pacman -Syy --needed --noconfirm uv
    else
        # Fallback for non-Arch systems
        echo "==> Installing uv via astral.sh..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="${HOME}/.local/bin:${PATH}"
    fi
fi

echo "==> Creating Python virtualenv (uv + ${PYPI_MIRROR})..."
export UV_INDEX_URL="${PYPI_MIRROR}"
# uv default HTTP timeout = 30s — too aggressive for 50+ MB wheels
# when any CDN flaps. Aliyun observed 0.87 MB/s → 5.18 MB/s within
# 3 min on 2026-04-17. 300s covers worst observed case (62s for ansible.whl)
# with 5x safety margin. Does NOT slow happy path — only ceiling.
export UV_HTTP_TIMEOUT=300
uv venv "${VENV_DIR}"
uv pip install --python "${VENV_DIR}/bin/python" -r "${ANSIBLE_DIR}/requirements.txt"
echo "==> Python venv ready"
exit 0
