#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Installer — System Information Library
# Functions to collect and inspect system state.
# ═══════════════════════════════════════════════════════════════

# Prevent direct execution.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "This file is a library, not meant to be run directly." >&2
    exit 1
}

_CDSI_SYSTEM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F cdsi_platform_init >/dev/null 2>&1; then
    # shellcheck source=platform.sh
    source "${_CDSI_SYSTEM_LIB_DIR}/platform.sh"
fi
cdsi_platform_init

# ── OS Information ─────────────────────────────────────────

# Get the detected Linux distribution name.
get_os_name() {
    case "$CDSI_PLATFORM" in
        ubuntu) printf 'Ubuntu\n' ;;
        centos-stream) printf 'CentOS Stream\n' ;;
        *) printf '%s\n' "${CDSI_PLATFORM:-unknown}" ;;
    esac
}

# Get the OS version ID (e.g., "24.04").
get_os_version() {
    printf '%s\n' "${CDSI_OS_VERSION:-unknown}"
}

# Get the full OS pretty name (e.g., "Ubuntu 24.04 LTS").
get_os_pretty_name() {
    printf '%s\n' "${CDSI_OS_PRETTY:-unknown}"
}

# Check if the OS is Ubuntu.
# Returns: 0 if Ubuntu, 1 if not.
check_os_ubuntu() {
    cdsi_is_ubuntu
}

check_os_supported() {
    cdsi_platform_supported
}

# ── Hardware Information ───────────────────────────────────

# Get CPU architecture (e.g., "x86_64", "aarch64").
get_arch() {
    uname -m 2>/dev/null || echo "unknown"
}

# Get the number of CPU cores.
get_cpu_count() {
    local cores
    cores="$(nproc 2>/dev/null || true)"
    echo "${cores:-1}"
}

# Get total memory in MB.
get_memory_mb() {
    local memory_value
    memory_value="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || true)"
    if [[ "$memory_value" =~ ^[0-9]+$ ]]; then
        echo $(( memory_value / 1024 ))
    else
        echo 0
    fi
}

# Get available disk space in GB for the root filesystem.
get_disk_free_gb() {
    local avail_kb
    avail_kb=$(df -Pk / 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "$avail_kb" && "$avail_kb" =~ ^[0-9]+$ ]]; then
        echo $(( avail_kb / 1024 / 1024 ))
    else
        echo 0
    fi
}

# Get total disk space in GB for the root filesystem.
get_disk_total_gb() {
    local total_kb
    total_kb=$(df -Pk / 2>/dev/null | awk 'NR==2{print $2}')
    if [[ -n "$total_kb" && "$total_kb" =~ ^[0-9]+$ ]]; then
        echo $(( total_kb / 1024 / 1024 ))
    else
        echo 0
    fi
}

# ── Network Checks ─────────────────────────────────────────

# Check if the server has internet connectivity.
# Tries multiple sources including China-friendly mirrors.
# Returns: 0 if connected, 1 if not.
check_internet() {
    local url
    for url in https://api.ipify.org https://mirrors.aliyun.com http://mirrors.aliyun.com; do
        if command -v curl >/dev/null 2>&1 \
            && curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Check if DNS resolution is working.
# Returns: 0 if working, 1 if not.
check_dns_resolution() {
    if getent hosts ubuntu.com >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ── Package Manager ────────────────────────────────────────

# Check if apt-get is available.
# Returns: 0 if available, 1 if not.
check_apt() {
    check_command apt-get
}

check_dnf() {
    check_command dnf
}

check_package_manager() {
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt) check_command apt-get ;;
        dnf) check_command dnf ;;
        *) return 1 ;;
    esac
}
