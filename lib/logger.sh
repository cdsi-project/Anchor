#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Installer — Logger Library
# Structured logging to both terminal and log file.
# ═══════════════════════════════════════════════════════════════

# Prevent direct execution.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "This file is a library, not meant to be run directly." >&2
    exit 1
}

# Track whether the log file is writable.
CDSI_LOG_WRITABLE=false

# ── Log File Setup ─────────────────────────────────────────
# Ensures the log directory and file exist with correct permissions.
logger_init() {
    if mkdir -p "${CDSI_LOG_DIR}" 2>/dev/null && \
       touch "${CDSI_LOG_FILE}" 2>/dev/null && \
       chmod 600 "${CDSI_LOG_FILE}" 2>/dev/null; then
        CDSI_LOG_WRITABLE=true
    else
        CDSI_LOG_WRITABLE=false
    fi
}

# Internal: write a line to the log file.
# Never writes secrets — callers must not pass sensitive data.
_logger_write_file() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    if [[ "${CDSI_LOG_WRITABLE}" == true ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "${CDSI_LOG_FILE}" 2>/dev/null || true
    fi
}

# Relay component diagnostics in real time and persist only stderr. Component
# stdout can contain credentials intended for the current terminal session.
_logger_relay_component_stderr() {
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line" >&2
        _logger_write_file "COMPONENT" "$line"
    done
}

# Run a component without changing its exit status. stderr is copied to the
# terminal and install log; stdout remains terminal-only to avoid secret leaks.
logger_run_component() {
    local stderr_fd relay_pid
    local rc=0

    if [[ "${CDSI_LOG_WRITABLE}" != true ]]; then
        "$@" || rc=$?
        return "$rc"
    fi

    exec {stderr_fd}> >(_logger_relay_component_stderr)
    relay_pid=$!
    "$@" 2>&"$stderr_fd" || rc=$?
    exec {stderr_fd}>&-
    wait "$relay_pid" || true
    return "$rc"
}

# ── Public Logging Functions ───────────────────────────────

log_info() {
    local msg="$*"
    printf '%b[INFO]%b %s\n' "${CLR_CYAN}" "${CLR_RESET}" "$msg"
    _logger_write_file "INFO" "$msg"
}

log_success() {
    local msg="$*"
    printf '%b[ OK ]%b %s\n' "${CLR_GREEN}" "${CLR_RESET}" "$msg"
    _logger_write_file "OK" "$msg"
}

log_warning() {
    local msg="$*"
    printf '%b[WARN]%b %s\n' "${CLR_YELLOW}" "${CLR_RESET}" "$msg"
    _logger_write_file "WARN" "$msg"
}

log_error() {
    local msg="$*"
    printf '%b[FAIL]%b %s\n' "${CLR_RED}" "${CLR_RESET}" "$msg" >&2
    _logger_write_file "ERROR" "$msg"
}

# Print a separator line (55 chars, matching M0 TODO examples).
log_separator() {
    printf '%s\n' "-------------------------------------------------------"
}

# Print a blank line (terminal only, not logged).
log_blank() {
    printf '\n'
}
