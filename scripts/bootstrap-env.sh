#!/usr/bin/env bash
# Shared bootstrap environment and secret resolution helpers.

set -euo pipefail

if [[ -n "${BOOTSTRAP_ENV_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

BOOTSTRAP_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_REPO_ROOT="$(dirname "${BOOTSTRAP_HELPER_DIR}")"

: "${BOOTSTRAP_SECURE_DIR:=${BOOTSTRAP_REPO_ROOT}/.local/bootstrap}"
: "${BOOTSTRAP_ENV_FILE:=${BOOTSTRAP_SECURE_DIR}/bootstrap.env}"

if [[ -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${BOOTSTRAP_ENV_FILE}"
    set +a
fi

: "${BOOTSTRAP_ARCHINSTALL_DIR:=${BOOTSTRAP_SECURE_DIR}/archinstall}"
: "${BOOTSTRAP_ARCHINSTALL_CONFIG_FILE:=${BOOTSTRAP_ARCHINSTALL_DIR}/archinstall-config.json}"
: "${BOOTSTRAP_ARCHINSTALL_CREDS_FILE:=${BOOTSTRAP_ARCHINSTALL_DIR}/archinstall-creds.json}"
: "${BOOTSTRAP_SSH_PUBLIC_KEY_FILE:=${BOOTSTRAP_ARCHINSTALL_DIR}/authorized_key.pub}"
: "${BOOTSTRAP_ROOT_PASSWORD_FILE:=${BOOTSTRAP_ARCHINSTALL_DIR}/root-password}"
: "${BOOTSTRAP_USER_PASSWORD_FILE:=${BOOTSTRAP_ARCHINSTALL_DIR}/user-password}"
: "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE:=${BOOTSTRAP_SECURE_DIR}/vault-pass.gpg}"
: "${BOOTSTRAP_VAULT_PASSWORD_FILE:=}"
: "${BOOTSTRAP_SUDO_PASSWORD_GPG_FILE:=${BOOTSTRAP_SECURE_DIR}/sudo-password.gpg}"
: "${BOOTSTRAP_SUDO_PASSWORD_FILE:=}"
: "${BOOTSTRAP_VAULT_GPG_RECIPIENT:=}"

export BOOTSTRAP_REPO_ROOT
export BOOTSTRAP_SECURE_DIR
export BOOTSTRAP_ENV_FILE
export BOOTSTRAP_ARCHINSTALL_DIR
export BOOTSTRAP_ARCHINSTALL_CONFIG_FILE
export BOOTSTRAP_ARCHINSTALL_CREDS_FILE
export BOOTSTRAP_SSH_PUBLIC_KEY_FILE
export BOOTSTRAP_ROOT_PASSWORD_FILE
export BOOTSTRAP_USER_PASSWORD_FILE
export BOOTSTRAP_VAULT_PASSWORD_GPG_FILE
export BOOTSTRAP_VAULT_PASSWORD_FILE
export BOOTSTRAP_SUDO_PASSWORD_GPG_FILE
export BOOTSTRAP_SUDO_PASSWORD_FILE
export BOOTSTRAP_VAULT_GPG_RECIPIENT
export BOOTSTRAP_ENV_LOADED=1

bootstrap_require_var() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        echo "ERROR: Required environment variable ${var_name} is not set." >&2
        return 1
    fi
}

bootstrap_require_file() {
    local var_name="$1"
    bootstrap_require_var "${var_name}"
    if [[ ! -f "${!var_name}" ]]; then
        echo "ERROR: File referenced by ${var_name} does not exist: ${!var_name}" >&2
        return 1
    fi
}

bootstrap_secret_value() {
    local value_var="$1"
    local file_var="$2"
    local label="$3"

    if [[ -n "${!value_var:-}" ]]; then
        printf '%s' "${!value_var}"
        return 0
    fi

    if [[ -n "${!file_var:-}" ]]; then
        if [[ ! -f "${!file_var}" ]]; then
            echo "ERROR: ${label} file not found: ${!file_var}" >&2
            return 1
        fi
        cat "${!file_var}"
        return 0
    fi

    echo "ERROR: Provide ${label} via ${value_var} or ${file_var}." >&2
    return 1
}

bootstrap_secret_from_gpg_file() {
    local file_path="$1"
    local label="$2"

    if ! command -v gpg >/dev/null 2>&1; then
        echo "ERROR: gpg is required to decrypt ${label}: ${file_path}" >&2
        return 1
    fi

    gpg --quiet --batch --decrypt -- "${file_path}"
}

bootstrap_default_gpg_recipient() {
    if ! command -v gpg >/dev/null 2>&1; then
        return 1
    fi

    gpg --list-secret-keys --with-colons --fingerprint 2>/dev/null | \
        awk -F: '/^fpr:/ { print $10; exit }'
}

bootstrap_vault_password() {
    if [[ -n "${BOOTSTRAP_VAULT_PASSWORD:-}" ]]; then
        printf '%s' "${BOOTSTRAP_VAULT_PASSWORD}"
        return 0
    fi

    if [[ -n "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE:-}" && -f "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}" ]]; then
        bootstrap_secret_from_gpg_file "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}" "vault password"
        return 0
    fi

    if [[ -n "${BOOTSTRAP_VAULT_PASSWORD_FILE:-}" && -f "${BOOTSTRAP_VAULT_PASSWORD_FILE}" ]]; then
        cat -- "${BOOTSTRAP_VAULT_PASSWORD_FILE}"
        return 0
    fi

    echo "ERROR: Provide vault password via BOOTSTRAP_VAULT_PASSWORD, ${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}, or BOOTSTRAP_VAULT_PASSWORD_FILE." >&2
    return 1
}

bootstrap_sudo_password() {
    if [[ -n "${BOOTSTRAP_SUDO_PASSWORD:-}" ]]; then
        printf '%s' "${BOOTSTRAP_SUDO_PASSWORD}"
        return 0
    fi

    if [[ -n "${BOOTSTRAP_SUDO_PASSWORD_GPG_FILE:-}" && -f "${BOOTSTRAP_SUDO_PASSWORD_GPG_FILE}" ]]; then
        bootstrap_secret_from_gpg_file "${BOOTSTRAP_SUDO_PASSWORD_GPG_FILE}" "sudo password"
        return 0
    fi

    if [[ -n "${BOOTSTRAP_SUDO_PASSWORD_FILE:-}" && -f "${BOOTSTRAP_SUDO_PASSWORD_FILE}" ]]; then
        cat -- "${BOOTSTRAP_SUDO_PASSWORD_FILE}"
        return 0
    fi

    bootstrap_vault_password
}

bootstrap_root_password() {
    bootstrap_secret_value "BOOTSTRAP_INSTALL_ROOT_PASSWORD" "BOOTSTRAP_ROOT_PASSWORD_FILE" "root install password"
}

bootstrap_user_password() {
    bootstrap_secret_value "BOOTSTRAP_INSTALL_USER_PASSWORD" "BOOTSTRAP_USER_PASSWORD_FILE" "user install password"
}

bootstrap_mkdir_secure_dir() {
    mkdir -p "${BOOTSTRAP_SECURE_DIR}" "${BOOTSTRAP_ARCHINSTALL_DIR}"
    chmod 700 "${BOOTSTRAP_SECURE_DIR}" "${BOOTSTRAP_ARCHINSTALL_DIR}" 2>/dev/null || true
}

bootstrap_run_sudo() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
        return
    fi

    local sudo_pass
    local askpass_script
    local askpass_script_quoted
    sudo_pass="$(bootstrap_sudo_password)"
    askpass_script="$(mktemp "${TMPDIR:-/tmp}/bootstrap-askpass.XXXXXX")"
    printf -v askpass_script_quoted '%q' "${askpass_script}"
    trap "rm -f -- ${askpass_script_quoted}" RETURN

    cat > "${askpass_script}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${BOOTSTRAP_ASKPASS_VALUE:?}"
EOF
    chmod 700 "${askpass_script}"

    BOOTSTRAP_ASKPASS_VALUE="${sudo_pass}" \
    SUDO_ASKPASS="${askpass_script}" \
    sudo -A -p '' -- "$@"
}
