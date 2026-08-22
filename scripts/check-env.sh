#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Anchor — Environment Check
# Inspects the server before any installation begins.
# Active preflight used by install.sh; it also remains independently runnable.
# ═══════════════════════════════════════════════════════════════

# Function definitions remain sourceable, while direct execution runs
# check_env_main at the bottom of the file.

# ── Status Constants ───────────────────────────────────────
if [[ -z "${PF_OK+x}" ]]; then
    readonly PF_OK="OK"
fi
if [[ -z "${PF_WARN+x}" ]]; then
    readonly PF_WARN="WARNING"
fi
if [[ -z "${PF_FAIL+x}" ]]; then
    readonly PF_FAIL="ERROR"
fi

# Track overall preflight status.
# 0 = all OK, 1 = has warnings, 2 = has errors.
preflight_overall_status=0

# ── Formatting Helpers ─────────────────────────────────────

# Print a check result line.
# Usage: pf_print_result <label> <value> <status>
pf_print_result() {
    local label="$1"
    local value="$2"
    local status="$3"
    local status_colored

    case "$status" in
        "$PF_OK")
            status_colored="${CLR_GREEN}${status}${CLR_RESET}"
            ;;
        "$PF_WARN")
            status_colored="${CLR_YELLOW}${status}${CLR_RESET}"
            ;;
        "$PF_FAIL")
            status_colored="${CLR_RED}${status}${CLR_RESET}"
            ;;
        *)
            status_colored="${CLR_DIM}${status}${CLR_RESET}"
            ;;
    esac

    printf "  %-20s %-24s %s\n" "$label" "$value" "$status_colored"
}

# Update the overall preflight status (only escalates, never de-escalates).
# Usage: pf_update_status <status>
pf_update_status() {
    local status="$1"
    case "$status" in
        "$PF_WARN")
            [[ "$preflight_overall_status" -lt 1 ]] && preflight_overall_status=1
            ;;
        "$PF_FAIL")
            preflight_overall_status=2
            ;;
    esac
}

# ── Individual Checks ──────────────────────────────────────

pf_check_user() {
    local user value status
    user=$(whoami 2>/dev/null || echo "unknown")
    if check_root; then
        value="${user} (root)"
        status="$PF_OK"
    elif check_sudo; then
        value="${user} (sudo)"
        status="$PF_OK"
    else
        value="${user} (no root/sudo)"
        status="$PF_FAIL"
    fi
    pf_print_result "User" "$value" "$status"
    pf_update_status "$status"
}

pf_check_os() {
    local pretty version status
    pretty=$(get_os_pretty_name)
    version=$(get_os_version)
    if check_os_ubuntu && [[ "$version" == "24.04" || "$version" == "26.04" ]]; then
        status="$PF_OK"
    else
        status="$PF_FAIL"
    fi
    pf_print_result "OS" "$pretty" "$status"
    pf_update_status "$status"
}

pf_check_arch() {
    local arch status
    arch=$(get_arch)
    if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
        status="$PF_OK"
    else
        status="$PF_WARN"
    fi
    pf_print_result "Architecture" "$arch" "$status"
    pf_update_status "$status"
}

pf_check_cpu() {
    local cores status
    cores=$(get_cpu_count)
    if [[ "$cores" -ge "$CDSI_MIN_CPU" ]]; then
        status="$PF_OK"
    else
        status="$PF_FAIL"
    fi
    pf_print_result "CPU" "${cores} Core" "$status"
    pf_update_status "$status"
}

pf_check_memory() {
    local mem_mb status mem_display
    mem_mb=$(get_memory_mb)
    if [[ "$mem_mb" -ge 1024 ]]; then
        mem_display=$(awk "BEGIN{printf \"%.1f GB\", ${mem_mb}/1024}" 2>/dev/null || echo "${mem_mb} MB")
    else
        mem_display="${mem_mb} MB"
    fi
    if [[ "$mem_mb" -ge "$CDSI_MIN_MEMORY_MB" ]]; then
        status="$PF_OK"
    else
        status="$PF_WARN"
    fi
    pf_print_result "Memory" "$mem_display" "$status"
    pf_update_status "$status"
}

pf_check_disk() {
    local free_gb total_gb status
    free_gb=$(get_disk_free_gb)
    total_gb=$(get_disk_total_gb)
    if [[ "$free_gb" -ge "$CDSI_MIN_DISK_GB" ]]; then
        status="$PF_OK"
    else
        status="$PF_WARN"
    fi
    pf_print_result "Disk Free" "${free_gb} GB / ${total_gb} GB" "$status"
    pf_update_status "$status"
}

pf_check_internet() {
    local status value
    if check_internet; then
        status="$PF_OK"
        value="Connected"
    else
        status="$PF_FAIL"
        value="Not Connected"
    fi
    pf_print_result "Internet" "$value" "$status"
    pf_update_status "$status"
}

pf_check_dns() {
    local status value
    if check_dns_resolution; then
        status="$PF_OK"
        value="Resolving"
    else
        status="$PF_WARN"
        value="Not Resolving"
    fi
    pf_print_result "DNS" "$value" "$status"
    pf_update_status "$status"
}

pf_check_port() {
    local port="$1"
    local status
    if check_port_available "$port"; then
        status="$PF_OK"
        pf_print_result "Port ${port}" "Available" "$status"
    else
        status="$PF_WARN"
        pf_print_result "Port ${port}" "In Use" "$status"
    fi
    pf_update_status "$status"
}

pf_check_apt() {
    local status value
    if check_apt; then
        status="$PF_OK"
        value="Available"
    else
        status="$PF_FAIL"
        value="Not Available"
    fi
    pf_print_result "apt" "$value" "$status"
    pf_update_status "$status"
}

# Check if a service/binary is already installed.
# Not installed = OK (clean environment).
# Installed = WARNING (potential conflict).
# Usage: pf_check_service <command> <display_name>
pf_check_service() {
    local cmd="$1"
    local display_name="$2"
    local status value

    if check_command "$cmd"; then
        value="Installed"
        status="$PF_WARN"
    else
        value="Not Installed"
        status="$PF_OK"
    fi
    pf_print_result "$display_name" "$value" "$status"
    pf_update_status "$status"
}

# ── Main Preflight Function ───────────────────────────────

# Run all preflight checks and output formatted results.
# Returns: 0 if ready, 1 if warnings, 2 if errors.
preflight_run() {
    preflight_overall_status=0

    log_blank
    printf "  %bCDSI Preflight Check%b\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator

    # ── System ──
    pf_check_user
    pf_check_os
    pf_check_arch
    pf_check_cpu
    pf_check_memory
    pf_check_disk

    # ── Network ──
    pf_check_internet
    pf_check_dns
    pf_check_port 80
    pf_check_port 443

    # ── Package Manager ──
    pf_check_apt

    log_separator

    # ── Existing Services ──
    printf "  %bExisting Services%b\n" "${CLR_DIM}" "${CLR_RESET}"
    log_separator

    pf_check_service "nginx"        "Nginx"
    pf_check_service "php"           "PHP"
    pf_check_service "mysql"         "MySQL"
    pf_check_service "redis-server"  "Redis"
    pf_check_service "supervisord"   "Supervisor"

    log_separator
    log_blank

    # ── Summary ──
    case "$preflight_overall_status" in
        0)
            printf "  %b%s%b\n" "${CLR_GREEN}${CLR_BOLD}" "Ready to install CDSI." "${CLR_RESET}"
            _logger_write_file "INFO" "Preflight: all checks passed."
            ;;
        1)
            printf "  %b%s%b\n" "${CLR_YELLOW}${CLR_BOLD}" "Ready to install CDSI (with warnings)." "${CLR_RESET}"
            _logger_write_file "WARN" "Preflight: completed with warnings."
            ;;
        2)
            printf "  %b%s%b\n" "${CLR_RED}${CLR_BOLD}" "Not ready to install CDSI." "${CLR_RESET}"
            _logger_write_file "ERROR" "Preflight: failed."
            ;;
    esac
    log_blank

    return "$preflight_overall_status"
}

# ── Standalone Entry Point ────────────────────────────────

_check_env_load_runtime() {
    local cdsi_root
    cdsi_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # shellcheck source=../lib/common.sh
    source "${cdsi_root}/lib/common.sh"
    # shellcheck source=../lib/logger.sh
    source "${cdsi_root}/lib/logger.sh"
    # shellcheck source=../lib/system.sh
    source "${cdsi_root}/lib/system.sh"
}

check_env_usage() {
    printf 'Usage: bash scripts/check-env.sh\n'
    printf '\n'
    printf 'Run the CDSI preflight checks without starting the installer.\n'
}

check_env_main() {
    case "${1:-}" in
        -h|--help|help)
            check_env_usage
            return 0
            ;;
        '')
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            check_env_usage >&2
            return 2
            ;;
    esac

    logger_init
    preflight_run
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -Eeuo pipefail
    _check_env_load_runtime
    check_env_status=0
    check_env_main "$@" || check_env_status=$?
    exit "$check_env_status"
fi
