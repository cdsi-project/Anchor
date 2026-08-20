#!/usr/bin/env bash

# Shared, bounded retry wrapper for apt-get. Ubuntu may run apt-daily or
# unattended-upgrades immediately after boot, so a fresh install can briefly
# contend for the package-manager locks.

cdsi_apt_log() {
    if declare -F log >/dev/null 2>&1; then
        log "$*"
    else
        printf '[CDSI] %s\n' "$*"
    fi
}

cdsi_apt_log_fail() {
    if declare -F log_fail >/dev/null 2>&1; then
        log_fail "$*"
    else
        printf '[FAIL] %s\n' "$*" >&2
    fi
}

cdsi_apt_get() {
    local attempts="${CDSI_APT_RETRY_ATTEMPTS:-3}"
    local lock_timeout="${CDSI_APT_LOCK_TIMEOUT:-120}"
    local retry_delay="${CDSI_APT_RETRY_DELAY:-10}"

    if [[ ! "$attempts" =~ ^([1-9]|10)$ ]] \
       || [[ ! "$lock_timeout" =~ ^[1-9][0-9]{0,2}$ ]] \
       || [[ ! "$retry_delay" =~ ^(0|[1-9][0-9]?)$ ]]; then
        cdsi_apt_log_fail "Invalid APT retry configuration."
        return 2
    fi
    if ((10#$lock_timeout > 600 || 10#$retry_delay > 60)); then
        cdsi_apt_log_fail "Invalid APT retry configuration."
        return 2
    fi
    if [[ $# -eq 0 ]]; then
        cdsi_apt_log_fail "cdsi_apt_get requires apt-get arguments."
        return 2
    fi

    local -a root_cmd=()
    if [[ "${EUID}" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            cdsi_apt_log_fail "apt-get requires root privileges or sudo."
            return 1
        fi
        root_cmd=(sudo)
    fi

    local attempt exit_code
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "${root_cmd[@]}" env DEBIAN_FRONTEND=noninteractive \
            apt-get \
                -o "DPkg::Lock::Timeout=${lock_timeout}" \
                -o "Acquire::Retries=3" \
                "$@"; then
            return 0
        else
            exit_code=$?
        fi

        if ((attempt == attempts)); then
            cdsi_apt_log \
                "apt-get $1 failed after ${attempts} attempts (exit ${exit_code})."
            return "$exit_code"
        fi

        cdsi_apt_log \
            "apt-get $1 failed (attempt ${attempt}/${attempts}); retrying in ${retry_delay}s..."
        sleep "$retry_delay"
    done
}
