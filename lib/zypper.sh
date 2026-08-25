#!/usr/bin/env bash

# Shared, bounded retry wrapper for Zypper operations on openSUSE Leap.

cdsi_zypper_log() {
    if declare -F log >/dev/null 2>&1; then
        log "$*"
    else
        printf '[CDSI] %s\n' "$*"
    fi
}

cdsi_zypper_log_fail() {
    if declare -F log_fail >/dev/null 2>&1; then
        log_fail "$*"
    else
        printf '[FAIL] %s\n' "$*" >&2
    fi
}

cdsi_zypper() {
    local attempts="${CDSI_ZYPPER_RETRY_ATTEMPTS:-3}"
    local command_timeout="${CDSI_ZYPPER_COMMAND_TIMEOUT:-900}"
    local retry_delay="${CDSI_ZYPPER_RETRY_DELAY:-10}"

    if [[ ! "$attempts" =~ ^([1-9]|10)$ ]] \
       || [[ ! "$command_timeout" =~ ^[1-9][0-9]{1,3}$ ]] \
       || [[ ! "$retry_delay" =~ ^(0|[1-9][0-9]?)$ ]]; then
        cdsi_zypper_log_fail "Invalid Zypper retry configuration."
        return 2
    fi
    if ((10#$command_timeout < 30 || 10#$command_timeout > 1800 \
        || 10#$retry_delay > 60)); then
        cdsi_zypper_log_fail "Invalid Zypper retry configuration."
        return 2
    fi
    if [[ $# -eq 0 ]]; then
        cdsi_zypper_log_fail "cdsi_zypper requires Zypper arguments."
        return 2
    fi
    if ! command -v zypper >/dev/null 2>&1 \
       || ! command -v timeout >/dev/null 2>&1; then
        cdsi_zypper_log_fail "Zypper and timeout are required."
        return 127
    fi

    local -a root_cmd=()
    if [[ "${EUID}" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            cdsi_zypper_log_fail "Zypper requires root privileges or sudo."
            return 1
        fi
        root_cmd=(sudo)
    fi

    local attempt exit_code
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "${root_cmd[@]}" timeout --foreground "$command_timeout" \
            zypper --non-interactive "$@"; then
            return 0
        else
            exit_code=$?
        fi

        if ((attempt == attempts)); then
            cdsi_zypper_log \
                "zypper $1 failed after ${attempts} attempts (exit ${exit_code})."
            return "$exit_code"
        fi

        cdsi_zypper_log \
            "zypper $1 failed (attempt ${attempt}/${attempts}); retrying in ${retry_delay}s..."
        sleep "$retry_delay"
    done
}

# Availability probes use the existing solver cache and a shorter retry budget.
cdsi_zypper_query() {
    CDSI_ZYPPER_RETRY_ATTEMPTS="${CDSI_ZYPPER_QUERY_RETRY_ATTEMPTS:-2}" \
    CDSI_ZYPPER_COMMAND_TIMEOUT="${CDSI_ZYPPER_QUERY_TIMEOUT:-120}" \
    CDSI_ZYPPER_RETRY_DELAY="${CDSI_ZYPPER_QUERY_RETRY_DELAY:-2}" \
        cdsi_zypper --no-refresh "$@"
}
