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

_CDSI_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F cdsi_platform_init >/dev/null 2>&1; then
    # shellcheck source=platform.sh
    source "${_CDSI_COMMON_LIB_DIR}/platform.sh"
fi
if ! declare -F cdsi_service_active >/dev/null 2>&1; then
    # shellcheck source=services.sh
    source "${_CDSI_COMMON_LIB_DIR}/services.sh"
fi
cdsi_platform_init

# ── CDSI Constants ──────────────────────────────────────────
readonly CDSI_APP_NAME="CDSI"
readonly CDSI_VERSION="0.3.0"

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

# Check if a systemd service is installed.
# Usage: check_service_installed <service>
# Returns: 0 if installed, 1 if not.
check_service_installed() {
    cdsi_service_installed "$1"
}

# Check if a systemd service is currently active.
# Usage: check_service_active <service>
# Returns: 0 if active, 1 if not.
check_service_active() {
    cdsi_service_active "$1"
}

# Check if a TCP port is available (not in use).
# Usage: check_port_available <port>
# Returns: 0 if available, 1 if in use.
check_port_available() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnH 2>/dev/null | awk -v suffix=":${port}" \
            '$4 ~ suffix "$" { found=1 } END { exit found ? 0 : 1 }'; then
            return 1
        fi
    fi
    return 0
}

check_port_listening() {
    ! check_port_available "$1"
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

# Return success for a syntactically valid IPv4 address.
cdsi_is_ipv4() {
    local ip="${1:-}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    local octet
    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
        ((10#$octet <= 255)) || return 1
    done
}

# Return success only for a globally routable IPv4 address.
cdsi_is_public_ipv4() {
    local ip="${1:-}"
    cdsi_is_ipv4 "$ip" || return 1

    local a b c d
    IFS=. read -r a b c d <<< "$ip"

    a=$((10#$a)); b=$((10#$b)); c=$((10#$c)); d=$((10#$d))
    ((a != 0 && a != 10 && a != 127 && a < 224)) || return 1
    ((a != 100 || b < 64 || b > 127)) || return 1
    ((a != 169 || b != 254)) || return 1
    ((a != 172 || b < 16 || b > 31)) || return 1
    ((a != 192 || b != 0 || c != 0)) || return 1
    ((a != 192 || b != 168)) || return 1
    ((a != 192 || b != 0 || c != 2)) || return 1
    ((a != 198 || b < 18 || b > 19)) || return 1
    ((a != 198 || b != 51 || c != 100)) || return 1
    ((a != 203 || b != 0 || c != 113)) || return 1
}

# Get the public IPv4 address of this server.
# Outputs the address, or "unknown" if verified detection fails.
get_public_ip() {
    local ip="" url
    if command -v curl >/dev/null 2>&1; then
        for url in \
            https://ip.3322.net \
            https://api.ipify.org \
            https://ipv4.icanhazip.com \
            https://ifconfig.co/ip \
            https://ifconfig.me/ip; do
            ip="$(curl -fsS --max-time 5 "$url" 2>/dev/null \
                | tr -d '[:space:]' || true)"
            if cdsi_is_public_ipv4 "$ip"; then
                printf '%s\n' "$ip"
                return 0
            fi
        done
    fi
    printf 'unknown\n'
    return 1
}

# Validate a public DNS hostname. IP literals, wildcards, paths, shell
# metacharacters, underscores, and single-label hostnames are rejected.
cdsi_validate_domain() {
    local domain="${1:-}"
    local label
    local -a _cdsi_domain_labels=()

    [[ -n "$domain" && ${#domain} -le 253 ]] || return 1
    [[ "$domain" != *$'\n'* && "$domain" != *$'\r'* && "$domain" != *$'\t'* ]] \
        || return 1
    [[ "$domain" == *.* ]] || return 1
    [[ ! "$domain" =~ ^[0-9.]+$ ]] || return 1
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

    local IFS='.'
    read -r -a _cdsi_domain_labels <<< "$domain"
    for label in "${_cdsi_domain_labels[@]}"; do
        [[ -n "$label" && ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] \
            || return 1
    done
}

# Normalize a comma/space-separated domain list. Outputs a canonical,
# comma-separated lowercase list or returns non-zero without output.
cdsi_normalize_domain_list() {
    local raw="${1:-}"
    local item normalized_item output=""
    local -a items=()

    [[ -n "$raw" ]] || return 1
    [[ "$raw" != *$'\n'* && "$raw" != *$'\r'* && "$raw" != *$'\t'* ]] \
        || return 1
    raw="${raw//,/ }"
    read -r -a items <<< "$raw"
    [[ ${#items[@]} -gt 0 ]] || return 1

    for item in "${items[@]}"; do
        cdsi_validate_domain "$item" || return 1
        normalized_item="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$output" ]]; then
            output="$normalized_item"
        elif [[ ",$output," != *",${normalized_item},"* ]]; then
            output="${output},${normalized_item}"
        fi
    done
    printf '%s\n' "$output"
}
