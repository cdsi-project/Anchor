#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Anchor — Configuration & Secrets
# Manages /etc/cdsi/cdsi.conf and secrets.env.
# Merged from former lib/config.sh + lib/secrets.sh.
# M1: Framework only — actual usage begins in M2.
# ═══════════════════════════════════════════════════════════════

# Function definitions remain sourceable, while direct execution runs
# configure_main at the bottom of the file.

# ── Config Directory ───────────────────────────────────────

# Ensure the CDSI config directory exists with correct permissions.
config_init() {
    mkdir -p "${CDSI_CONFIG_DIR}"
    chmod 755 "${CDSI_CONFIG_DIR}"
}

# ── cdsi.conf Read / Write ─────────────────────────────────

# Check if the main config file exists.
# Returns: 0 if exists, 1 if not.
config_exists() {
    [[ -f "${CDSI_CONF_FILE}" ]]
}

# Read a value from the config file.
# Usage: config_get <key>
# Outputs the value to stdout, or empty if not found.
config_get() {
    local key="$1"
    local value=""
    if config_exists; then
        value=$(grep -E "^${key}=" "${CDSI_CONF_FILE}" 2>/dev/null | tail -1 | cut -d'=' -f2- || true)
    fi
    echo "$value"
}

# Write a key-value pair to the config file.
# Creates the file if it does not exist; updates the key if it does.
# Usage: config_set <key> <value>
config_set() {
    local key="$1"
    local value="$2"
    config_init
    if config_exists && grep -q "^${key}=" "${CDSI_CONF_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${CDSI_CONF_FILE}"
    else
        echo "${key}=${value}" >> "${CDSI_CONF_FILE}"
    fi
}

# ── Secrets Management ─────────────────────────────────────

# Generate a random secret string of the specified length.
# Uses /dev/urandom for cryptographic security.
# Usage: generate_secret [length]
# Default length: 32.
generate_secret() {
    local length="${1:-32}"
    local secret
    secret=$(head -c $(( length * 2 )) /dev/urandom 2>/dev/null | \
             base64 2>/dev/null | \
             tr -dc 'A-Za-z0-9' 2>/dev/null | \
             head -c "${length}" || true)
    echo "${secret}"
}

# Ensure the secrets file exists with restrictive permissions.
secrets_init() {
    config_init
    if [[ ! -f "${CDSI_SECRETS_FILE}" ]]; then
        touch "${CDSI_SECRETS_FILE}"
    fi
    chmod 600 "${CDSI_SECRETS_FILE}"
}

# Write a secret to the secrets file (KEY=VALUE format).
# Usage: secrets_set <key> <value>
secrets_set() {
    local key="$1"
    local value="$2"
    secrets_init
    if grep -q "^${key}=" "${CDSI_SECRETS_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${CDSI_SECRETS_FILE}"
    else
        echo "${key}=${value}" >> "${CDSI_SECRETS_FILE}"
    fi
}

# Read a secret from the secrets file.
# Usage: secrets_get <key>
secrets_get() {
    local key="$1"
    local value=""
    if [[ -f "${CDSI_SECRETS_FILE}" ]]; then
        value=$(grep -E "^${key}=" "${CDSI_SECRETS_FILE}" 2>/dev/null | tail -1 | cut -d'=' -f2- || true)
    fi
    echo "$value"
}

# ── Standalone Entry Point ────────────────────────────────

_configure_load_runtime() {
    local cdsi_root
    cdsi_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # shellcheck source=../lib/common.sh
    source "${cdsi_root}/lib/common.sh"
    # shellcheck source=../lib/logger.sh
    source "${cdsi_root}/lib/logger.sh"
}

configure_usage() {
    printf 'Usage: sudo bash scripts/configure.sh [init]\n'
    printf '\n'
    printf 'Initialize the CDSI configuration directory and secrets file.\n'
}

configure_main() {
    local command="${1:-init}"

    case "$command" in
        -h|--help|help)
            configure_usage
            return 0
            ;;
        init)
            ;;
        *)
            printf 'Unknown command: %s\n' "$command" >&2
            configure_usage >&2
            return 2
            ;;
    esac

    logger_init

    if ! check_root; then
        log_error "Configuration initialization requires root privileges."
        log_info "Run: sudo bash scripts/configure.sh init"
        return 1
    fi

    if ! config_init; then
        log_error "Could not initialize ${CDSI_CONFIG_DIR}."
        return 1
    fi

    if ! secrets_init; then
        log_error "Could not initialize ${CDSI_SECRETS_FILE}."
        return 1
    fi

    log_success "CDSI configuration initialized."
    log_info "Config directory: ${CDSI_CONFIG_DIR}"
    log_info "Secrets file: ${CDSI_SECRETS_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -Eeuo pipefail
    _configure_load_runtime
    configure_status=0
    configure_main "$@" || configure_status=$?
    exit "$configure_status"
fi
