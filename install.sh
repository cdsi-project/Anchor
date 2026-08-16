#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Bootstrap — install.sh
# Creator Digital Sovereignty Infrastructure
#
# Entry point for the CDSI Node installation process.
#
# M1 Scope: Preflight checks only — does NOT install any services.
#           Outputs system inspection results and creates log file.
# ═══════════════════════════════════════════════════════════════

set -Eeuo pipefail

# ── Resolve Bootstrap Root ─────────────────────────────────
CDSI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDSI_ROOT

# ── Source Libraries ───────────────────────────────────────
# shellcheck source=lib/common.sh
source "${CDSI_ROOT}/lib/common.sh"
# shellcheck source=lib/logger.sh
source "${CDSI_ROOT}/lib/logger.sh"
# shellcheck source=lib/system.sh
source "${CDSI_ROOT}/lib/system.sh"

# ── Source Scripts ────────────────────────────────────────
# shellcheck source=scripts/configure.sh
source "${CDSI_ROOT}/scripts/configure.sh"
# shellcheck source=scripts/check-env.sh
source "${CDSI_ROOT}/scripts/check-env.sh"
# shellcheck source=scripts/health.sh
source "${CDSI_ROOT}/scripts/health.sh"

# ── Installer Metadata ─────────────────────────────────────
readonly CDSI_INSTALLER_VERSION="0.1.0"

# ── Error Handling ─────────────────────────────────────────
# Track current stage for error reporting.
CDSI_CURRENT_STAGE="INIT"

# Error trap — fires on any uncaught error under `set -e`.
cdsi_error_handler() {
    local exit_code=$?
    local line="${BASH_LINENO[0]:-unknown}"
    printf '\n'
    printf '%bInstallation failed.%b\n' "${CLR_RED}${CLR_BOLD}" "${CLR_RESET}" >&2
    printf '\n' >&2
    printf '  Stage: %s\n' "$CDSI_CURRENT_STAGE" >&2
    printf '  Error: exit code %s at line %s\n' "$exit_code" "$line" >&2
    printf '  Log:   %s\n' "$CDSI_LOG_FILE" >&2
    printf '\n' >&2
    _logger_write_file "ERROR" "Installation failed at stage ${CDSI_CURRENT_STAGE} (exit code ${exit_code}, line ${line})"
    exit "$exit_code"
}

trap cdsi_error_handler ERR

# ── Banner ─────────────────────────────────────────────────
cdsi_banner() {
    log_blank
    printf "  %bCDSI Installer v%s%b\n" "${CLR_CYAN}${CLR_BOLD}" "$CDSI_INSTALLER_VERSION" "${CLR_RESET}"
    printf "  %bCreator Digital Sovereignty Infrastructure%b\n" "${CLR_CYAN}" "${CLR_RESET}"
    log_blank
}

# ── Main ───────────────────────────────────────────────────
main() {
    # ── Initialize ──
    CDSI_CURRENT_STAGE="INIT"
    logger_init
    log_info "CDSI Installer v${CDSI_INSTALLER_VERSION} started."
    log_info "Log file: ${CDSI_LOG_FILE}"

    cdsi_banner

    # ── Preflight ──
    CDSI_CURRENT_STAGE="PREFLIGHT"
    log_info "Running preflight checks..."

    local pf_status=0
    preflight_run || pf_status=$?

    case "$pf_status" in
        0)
            log_success "All preflight checks passed."
            ;;
        1)
            log_warning "Preflight completed with warnings. Installation can proceed."
            ;;
        2)
            log_error "Preflight failed. Please resolve the errors above before proceeding."
            log_blank
            log_info "Log: ${CDSI_LOG_FILE}"
            exit 1
            ;;
    esac

    # ── M1 Boundary ──
    # M1 only implements preflight. No services are installed.
    log_blank
    log_separator
    log_info "Milestone 1 complete — preflight checks finished."
    log_info "No services were installed (M1 scope: preflight only)."
    log_info "Next milestone: Nginx + PHP + MySQL installation (M2)."
    log_separator
    log_blank

    log_success "CDSI Installer finished."
    log_info "Log: ${CDSI_LOG_FILE}"
}

main "$@"
