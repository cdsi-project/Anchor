#!/usr/bin/env bash

# Service operations for Ubuntu's systemd.

cdsi_service_installed() {
    local service="$1"
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    systemctl list-unit-files --type=service --no-legend \
        "${service}.service" 2>/dev/null \
        | awk -v unit="${service}.service" \
            '$1 == unit { found=1 } END { exit found ? 0 : 1 }'
}

cdsi_service_active() {
    local service="$1"
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    systemctl is-active --quiet "$service" 2>/dev/null
}

cdsi_service_enabled() {
    local service="$1"
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    systemctl is-enabled --quiet "$service" 2>/dev/null
}

cdsi_service_enable() {
    local service="$1"
    local -a root_cmd=()
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    if [[ "${EUID}" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || return 1
        root_cmd=(sudo)
    fi
    "${root_cmd[@]}" systemctl enable "$service"
}

cdsi_service_start() {
    local service="$1"
    local -a root_cmd=()
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    if [[ "${EUID}" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || return 1
        root_cmd=(sudo)
    fi
    "${root_cmd[@]}" systemctl start "$service"
}

cdsi_service_enable_now() {
    local service="$1"
    cdsi_service_enable "$service" || return
    cdsi_service_enabled "$service" || return 1
    if ! cdsi_service_active "$service"; then
        cdsi_service_start "$service" || return
    fi
    cdsi_service_active "$service"
}

cdsi_service_reload() {
    local service="$1"
    local -a root_cmd=()
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    if [[ "${EUID}" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || return 1
        root_cmd=(sudo)
    fi
    "${root_cmd[@]}" systemctl reload "$service"
}

cdsi_service_restart() {
    local service="$1"
    local -a root_cmd=()
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    if [[ "${EUID}" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || return 1
        root_cmd=(sudo)
    fi
    "${root_cmd[@]}" systemctl restart "$service"
}

cdsi_service_stop_disable() {
    local service="$1"
    local -a root_cmd=()
    cdsi_platform_init
    [[ "$CDSI_SERVICE_BACKEND" == "systemd" ]] || return 1
    if [[ "${EUID}" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || return 1
        root_cmd=(sudo)
    fi
    "${root_cmd[@]}" systemctl disable --now "$service"
}
