#!/usr/bin/env bash

# Shared, bounded retry wrapper for DNF operations on CentOS Stream.

cdsi_dnf_log() {
    if declare -F log >/dev/null 2>&1; then
        log "$*"
    else
        printf '[CDSI] %s\n' "$*"
    fi
}

cdsi_dnf_log_fail() {
    if declare -F log_fail >/dev/null 2>&1; then
        log_fail "$*"
    else
        printf '[FAIL] %s\n' "$*" >&2
    fi
}

cdsi_dnf() {
    local attempts="${CDSI_DNF_RETRY_ATTEMPTS:-3}"
    local command_timeout="${CDSI_DNF_COMMAND_TIMEOUT:-900}"
    local retry_delay="${CDSI_DNF_RETRY_DELAY:-10}"

    if [[ ! "$attempts" =~ ^([1-9]|10)$ ]] \
       || [[ ! "$command_timeout" =~ ^[1-9][0-9]{1,3}$ ]] \
       || [[ ! "$retry_delay" =~ ^(0|[1-9][0-9]?)$ ]]; then
        cdsi_dnf_log_fail "Invalid DNF retry configuration."
        return 2
    fi
    if ((10#$command_timeout < 30 || 10#$command_timeout > 1800 \
        || 10#$retry_delay > 60)); then
        cdsi_dnf_log_fail "Invalid DNF retry configuration."
        return 2
    fi
    if [[ $# -eq 0 ]]; then
        cdsi_dnf_log_fail "cdsi_dnf requires DNF arguments."
        return 2
    fi
    if ! command -v dnf >/dev/null 2>&1 \
       || ! command -v timeout >/dev/null 2>&1; then
        cdsi_dnf_log_fail "DNF and timeout are required."
        return 127
    fi

    local -a root_cmd=()
    if [[ "${EUID}" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            cdsi_dnf_log_fail "DNF requires root privileges or sudo."
            return 1
        fi
        root_cmd=(sudo)
    fi

    local attempt exit_code
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "${root_cmd[@]}" timeout --foreground "$command_timeout" \
            dnf --setopt=retries=3 --setopt=timeout=30 "$@"; then
            return 0
        else
            exit_code=$?
        fi

        if ((attempt == attempts)); then
            cdsi_dnf_log \
                "dnf $1 failed after ${attempts} attempts (exit ${exit_code})."
            return "$exit_code"
        fi

        cdsi_dnf_log \
            "dnf $1 failed (attempt ${attempt}/${attempts}); retrying in ${retry_delay}s..."
        sleep "$retry_delay"
    done
}

# Metadata probes must be bounded as well, but use a shorter retry budget than
# package mutations so an unavailable optional package does not stall install.
cdsi_dnf_query() {
    CDSI_DNF_RETRY_ATTEMPTS="${CDSI_DNF_QUERY_RETRY_ATTEMPTS:-2}" \
    CDSI_DNF_COMMAND_TIMEOUT="${CDSI_DNF_QUERY_TIMEOUT:-120}" \
    CDSI_DNF_RETRY_DELAY="${CDSI_DNF_QUERY_RETRY_DELAY:-2}" \
        cdsi_dnf "$@"
}
