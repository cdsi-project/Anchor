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

# ── OS Information ─────────────────────────────────────────

# Get the Linux distribution name (e.g., "Ubuntu").
get_os_name() {
    local name
    name=$(awk -F'=' '/^NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null || true)
    echo "${name:-unknown}"
}

# Get the OS version ID (e.g., "24.04").
get_os_version() {
    local ver
    ver=$(awk -F'=' '/^VERSION_ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null || true)
    echo "${ver:-unknown}"
}

# Get the full OS pretty name (e.g., "Ubuntu 24.04 LTS").
get_os_pretty_name() {
    local name
    name=$(awk -F'=' '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null || true)
    echo "${name:-unknown}"
}

# Check if the OS is Ubuntu.
# Returns: 0 if Ubuntu, 1 if not.
check_os_ubuntu() {
    local name
    name=$(get_os_name)
    [[ "$name" == "Ubuntu" ]]
}

# ── Hardware Information ───────────────────────────────────

# Get CPU architecture (e.g., "x86_64", "aarch64").
get_arch() {
    uname -m 2>/dev/null || echo "unknown"
}

# Get the number of CPU cores.
get_cpu_count() {
    local cores
    cores=$(nproc 2>/dev/null || echo 1)
    echo "${cores:-1}"
}

# Get total memory in MB.
get_memory_mb() {
    local mem_kb
    mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || true)
    if [[ -n "$mem_kb" && "$mem_kb" =~ ^[0-9]+$ ]]; then
        echo $(( mem_kb / 1024 ))
    else
        echo 0
    fi
}

# Get available disk space in GB for the root filesystem.
get_disk_free_gb() {
    local avail_kb
    avail_kb=$(df -P / 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "$avail_kb" && "$avail_kb" =~ ^[0-9]+$ ]]; then
        echo $(( avail_kb / 1024 / 1024 ))
    else
        echo 0
    fi
}

# Get total disk space in GB for the root filesystem.
get_disk_total_gb() {
    local total_kb
    total_kb=$(df -P / 2>/dev/null | awk 'NR==2{print $2}')
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
    # International sources.
    if curl -s --max-time 5 https://api.ipify.org >/dev/null 2>&1; then
        return 0
    fi
    # China-friendly mirrors.
    if curl -s --max-time 5 https://mirrors.aliyun.com >/dev/null 2>&1; then
        return 0
    fi
    if curl -s --max-time 5 http://mirrors.aliyun.com >/dev/null 2>&1; then
        return 0
    fi
    # Fallback: raw TCP connectivity test.
    if timeout 5 bash -c 'echo > /dev/tcp/mirrors.aliyun.com/443' 2>/dev/null; then
        return 0
    fi
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
