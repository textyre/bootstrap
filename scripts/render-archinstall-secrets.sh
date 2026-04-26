#!/usr/bin/env bash
# Render local archinstall JSON files from tracked templates and local secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

bootstrap_require_var "BOOTSTRAP_INSTALL_DISK"
bootstrap_require_var "BOOTSTRAP_INSTALL_HOSTNAME"
bootstrap_require_var "BOOTSTRAP_INSTALL_USERNAME"
bootstrap_require_file "BOOTSTRAP_SSH_PUBLIC_KEY_FILE"

BOOTSTRAP_INSTALL_TIMEZONE="${BOOTSTRAP_INSTALL_TIMEZONE:-UTC}"
BOOTSTRAP_INSTALL_LOCALE="${BOOTSTRAP_INSTALL_LOCALE:-en_US.UTF-8}"
BOOTSTRAP_INSTALL_KEYBOARD_LAYOUT="${BOOTSTRAP_INSTALL_KEYBOARD_LAYOUT:-us}"

bootstrap_mkdir_secure_dir

root_password="$(bootstrap_root_password)"
user_password="$(bootstrap_user_password)"
ssh_public_key="$(tr -d '\r\n' < "${BOOTSTRAP_SSH_PUBLIC_KEY_FILE}")"

export BOOTSTRAP_RENDER_ROOT_PASSWORD="${root_password}"
export BOOTSTRAP_RENDER_USER_PASSWORD="${user_password}"
export BOOTSTRAP_RENDER_SSH_PUBLIC_KEY="${ssh_public_key}"

config_template="${SCRIPT_DIR}/archinstall-config.template.json"
creds_template="${SCRIPT_DIR}/archinstall-creds.template.json"

python3 - "${config_template}" "${BOOTSTRAP_ARCHINSTALL_CONFIG_FILE}" <<'PY'
import json
import os
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
output = pathlib.Path(sys.argv[2])
mapping = {
    "__BOOTSTRAP_INSTALL_DISK__": os.environ["BOOTSTRAP_INSTALL_DISK"],
    "__BOOTSTRAP_INSTALL_HOSTNAME__": os.environ["BOOTSTRAP_INSTALL_HOSTNAME"],
    "__BOOTSTRAP_INSTALL_USERNAME__": os.environ["BOOTSTRAP_INSTALL_USERNAME"],
    "__BOOTSTRAP_INSTALL_TIMEZONE__": os.environ["BOOTSTRAP_INSTALL_TIMEZONE"],
    "__BOOTSTRAP_INSTALL_LOCALE__": os.environ["BOOTSTRAP_INSTALL_LOCALE"],
    "__BOOTSTRAP_INSTALL_KEYBOARD_LAYOUT__": os.environ["BOOTSTRAP_INSTALL_KEYBOARD_LAYOUT"],
    "__BOOTSTRAP_SSH_PUBLIC_KEY__": os.environ["BOOTSTRAP_RENDER_SSH_PUBLIC_KEY"],
}
for token, value in mapping.items():
    template = template.replace(token, json.dumps(value)[1:-1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(template + "\n", encoding="utf-8")
PY

python3 - "${creds_template}" "${BOOTSTRAP_ARCHINSTALL_CREDS_FILE}" <<'PY'
import json
import os
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
output = pathlib.Path(sys.argv[2])
mapping = {
    "__BOOTSTRAP_INSTALL_USERNAME__": os.environ["BOOTSTRAP_INSTALL_USERNAME"],
    "__BOOTSTRAP_INSTALL_ROOT_PASSWORD__": os.environ["BOOTSTRAP_RENDER_ROOT_PASSWORD"],
    "__BOOTSTRAP_INSTALL_USER_PASSWORD__": os.environ["BOOTSTRAP_RENDER_USER_PASSWORD"],
}
for token, value in mapping.items():
    template = template.replace(token, json.dumps(value)[1:-1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(template + "\n", encoding="utf-8")
PY

chmod 600 "${BOOTSTRAP_ARCHINSTALL_CONFIG_FILE}" "${BOOTSTRAP_ARCHINSTALL_CREDS_FILE}" 2>/dev/null || true

unset root_password user_password ssh_public_key
unset BOOTSTRAP_RENDER_ROOT_PASSWORD BOOTSTRAP_RENDER_USER_PASSWORD BOOTSTRAP_RENDER_SSH_PUBLIC_KEY

echo "==> Rendered local archinstall files:"
echo "    ${BOOTSTRAP_ARCHINSTALL_CONFIG_FILE}"
echo "    ${BOOTSTRAP_ARCHINSTALL_CREDS_FILE}"
