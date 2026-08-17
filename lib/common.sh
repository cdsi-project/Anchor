#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Installer — Common Library
# Shared constants, color definitions, and safe command wrappers.
# ═══════════════════════════════════════════════════════════════

# Prevent direct execution.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "This file is a library, not meant to be run directly." >&2
    exit 1
}

# ── CDSI Constants ──────────────────────────────────────────
readonly CDSI_APP_NAME="CDSI"
readonly CDSI_VERSION="0.1.0"

readonly CDSI_CONFIG_DIR="/etc/cdsi"
readonly CDSI_APP_DIR="/var/www/cdsi"
readonly CDSI_LOG_DIR="/var/log/cdsi"
readonly CDSI_LOG_FILE="${CDSI_LOG_DIR}/install.log"
readonly CDSI_SECRETS_FILE="${CDSI_CONFIG_DIR}/secrets.env"
readonly CDSI_CONF_FILE="${CDSI_CONFIG_DIR}/cdsi.conf"

# Minimum system requirements.
readonly CDSI_MIN_CPU=1
readonly CDSI_MIN_MEMORY_MB=1024
readonly CDSI_MIN_DISK_GB=10

# ── Colors ─────────────────────────────────────────────────
if [[ -t 1 ]]; then
    readonly CLR_RESET=$'\033[0m'
    readonly CLR_RED=$'\033[31m'
    readonly CLR_GREEN=$'\033[32m'
    readonly CLR_YELLOW=$'\033[33m'
    readonly CLR_CYAN=$'\033[36m'
    readonly CLR_BOLD=$'\033[1m'
    readonly CLR_DIM=$'\033[2m'
    readonly CLR_BLINK=$'\033[5m'
else
    readonly CLR_RESET=""
    readonly CLR_RED=""
    readonly CLR_GREEN=""
    readonly CLR_YELLOW=""
    readonly CLR_CYAN=""
    readonly CLR_BOLD=""
    readonly CLR_DIM=""
    readonly CLR_BLINK=""
fi

# ── Safe Command Wrappers ─────────────────────────────────
# These helpers work correctly under `set -Eeuo pipefail`.
# They prevent probe commands from aborting the script.

# Run a command, capture its exit code without aborting the script.
# Usage: run_check <command> [args...]
# Returns: the exit code of the command.
run_check() {
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    return "$rc"
}

# Check if a command/binary exists on PATH.
# Usage: check_command <name>
# Returns: 0 if found, 1 if not.
check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if a systemd service unit is installed.
# Usage: check_service_installed <service>
# Returns: 0 if installed, 1 if not.
check_service_installed() {
    if systemctl list-unit-files "$1.service" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if a systemd service is currently active.
# Usage: check_service_active <service>
# Returns: 0 if active, 1 if not.
check_service_active() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Check if a TCP port is available (not in use).
# Usage: check_port_available <port>
# Returns: 0 if available, 1 if in use.
check_port_available() {
    if ss -tlnH 2>/dev/null | grep -q ":$1 "; then
        return 1
    fi
    return 0
}

# Check if the current user is root.
# Returns: 0 if root, 1 if not.
check_root() {
    [[ "${EUID}" -eq 0 ]]
}

# Check if the current user has passwordless sudo privileges.
# Returns: 0 if yes, 1 if no.
check_sudo() {
    if check_root; then
        return 0
    fi
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    return 1
}

# Get the public IP address of this server.
# Outputs the IP to stdout, or "unknown" if detection fails.
get_public_ip() {
    local ip=""
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || true)
    fi
    if [[ -z "$ip" ]]; then
        echo "unknown"
    else
        echo "$ip"
    fi
}
