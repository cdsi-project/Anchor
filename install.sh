#!/usr/bin/env bash
# Copyright 2026 激怒李维斯
# SPDX-License-Identifier: Apache-2.0
# ═══════════════════════════════════════════════════════════════
# CDSI Bootstrap — install.sh
# Creator Digital Sovereignty Infrastructure
#
# Entry point for the CDSI Node installation process.
# Runs preflight checks, then presents an interactive menu
# for selective component installation.
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

# Scripts under scripts/ are standalone commands. The installer invokes them
# as subprocesses so direct execution and orchestrated execution use the same
# code path and exit-status contract.

# ── Installer Metadata ─────────────────────────────────────
readonly CDSI_INSTALLER_VERSION="0.3.0"
readonly CDSI_COMPONENT_NOT_IMPLEMENTED=3
readonly CDSI_PREFLIGHT_SCRIPT="${CDSI_ROOT}/scripts/check-env.sh"

# ── Component Registry ─────────────────────────────────────
# Parallel arrays: names, descriptions, script paths, done flags.
CDSI_COMP_NAMES=("Nginx" "MySQL" "PHP-FPM" "Redis")
CDSI_COMP_DESCS=("HTTP服务" "数据库" "PHP程序" "Redis数据库")
CDSI_COMP_SCRIPTS=(
    "${CDSI_ROOT}/scripts/install-nginx.sh"
    "${CDSI_ROOT}/scripts/install-mysql.sh"
    "${CDSI_ROOT}/scripts/install-php.sh"
    "${CDSI_ROOT}/scripts/install-redis.sh"
)
CDSI_COMP_DONE=()
CDSI_COMP_UNAVAILABLE=()
for _i in "${!CDSI_COMP_NAMES[@]}"; do
    CDSI_COMP_DONE[$_i]=false
    CDSI_COMP_UNAVAILABLE[$_i]=false
done
unset _i

# ── Error Handling ─────────────────────────────────────────
CDSI_CURRENT_STAGE="INIT"

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

# ── Install Menu ────────────────────────────────────────────

# Print the interactive component-selection menu.
cdsi_show_menu() {
    log_blank
    log_separator
    printf "  %bCDSI Component Installation%b\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator
    log_blank
    printf "  %b0%b  Install All - 安装全部\n" "${CLR_BOLD}" "${CLR_RESET}"
    local i
    for i in "${!CDSI_COMP_NAMES[@]}"; do
        local num=$((i + 1))
        local name="${CDSI_COMP_NAMES[$i]}"
        local desc="${CDSI_COMP_DESCS[$i]}"
        if [[ "${CDSI_COMP_DONE[$i]}" == true ]]; then
            printf "  %b%d%b  %-10s - %-12s %b[installed]%b\n" \
                "${CLR_DIM}" "$num" "${CLR_RESET}" "$name" "$desc" \
                "${CLR_GREEN}" "${CLR_RESET}"
        elif [[ "${CDSI_COMP_UNAVAILABLE[$i]}" == true ]]; then
            printf "  %b%d%b  %-10s - %-12s %b[planned]%b\n" \
                "${CLR_DIM}" "$num" "${CLR_RESET}" "$name" "$desc" \
                "${CLR_YELLOW}" "${CLR_RESET}"
        else
            printf "  %b%d%b  %-10s - %s\n" \
                "${CLR_BOLD}" "$num" "${CLR_RESET}" "$name" "$desc"
        fi
    done
    printf "  %bq%b  Quit - 退出\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator
    printf "  Enter choice: "
}

# Run a single component install by index.
# Executes the component's install script as a subprocess.
# Args: <index 0-based>
cdsi_install_component() {
    local idx="$1"
    local name="${CDSI_COMP_NAMES[$idx]}"
    local script="${CDSI_COMP_SCRIPTS[$idx]}"
    local rc=0

    if [[ "${CDSI_COMP_DONE[$idx]}" == true ]]; then
        log_info "${name} already installed — skipping."
        return 0
    fi

    if [[ "${CDSI_COMP_UNAVAILABLE[$idx]}" == true ]]; then
        log_warning "${name} installation is planned for a later milestone."
        return 0
    fi

    if [[ ! -f "$script" ]]; then
        log_error "Install script not found: $script"
        return 1
    fi

    CDSI_CURRENT_STAGE="INSTALL_${name^^}"
    log_info "Installing ${name}..."
    if bash "$script"; then
        CDSI_COMP_DONE[$idx]=true
        log_success "${name} installation complete."
        CDSI_CURRENT_STAGE="MENU"
        return 0
    else
        rc=$?
        if [[ "$rc" -eq "$CDSI_COMPONENT_NOT_IMPLEMENTED" ]]; then
            CDSI_COMP_UNAVAILABLE[$idx]=true
            log_warning "${name} installation is not implemented in the current milestone."
            CDSI_CURRENT_STAGE="MENU"
            return 0
        fi
        log_error "${name} installation failed (exit code ${rc})."
        return "$rc"
    fi
}

# Install all remaining components in order.
cdsi_install_all() {
    local i
    for i in "${!CDSI_COMP_NAMES[@]}"; do
        if [[ "${CDSI_COMP_DONE[$i]}" != true && "${CDSI_COMP_UNAVAILABLE[$i]}" != true ]]; then
            cdsi_install_component "$i"
        fi
    done
}

# Print installation summary.
cdsi_summary() {
    log_blank
    log_separator
    printf "  %bInstallation Summary%b\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator
    local i all_done=true
    for i in "${!CDSI_COMP_NAMES[@]}"; do
        local name="${CDSI_COMP_NAMES[$i]}"
        if [[ "${CDSI_COMP_DONE[$i]}" == true ]]; then
            printf "  %b✓%b  %s\n" "${CLR_GREEN}" "${CLR_RESET}" "$name"
        elif [[ "${CDSI_COMP_UNAVAILABLE[$i]}" == true ]]; then
            printf "  %b○%b  %s (planned)\n" "${CLR_YELLOW}" "${CLR_RESET}" "$name"
        else
            printf "  %b○%b  %s\n" "${CLR_DIM}" "${CLR_RESET}" "$name"
            all_done=false
        fi
    done
    log_separator
    if [[ "$all_done" == true ]]; then
        log_success "All available components installed."
    else
        log_info "Some components were not installed. Re-run to install them."
    fi
    log_info "Log: ${CDSI_LOG_FILE}"
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
    if bash "$CDSI_PREFLIGHT_SCRIPT"; then
        pf_status=0
    else
        pf_status=$?
    fi

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
        *)
            log_error "Preflight script failed unexpectedly (exit code ${pf_status})."
            log_blank
            log_info "Log: ${CDSI_LOG_FILE}"
            exit "$pf_status"
            ;;
    esac

    # ── Interactive Install Menu ──
    CDSI_CURRENT_STAGE="MENU"

    # Require an interactive terminal for the selection menu.
    if [[ ! -t 0 ]]; then
        log_error "Interactive terminal required for component selection."
        log_info  "If running via SSH, use:  ssh -t user@host 'cd /path && ./install.sh'"
        log_info  "Log: ${CDSI_LOG_FILE}"
        exit 1
    fi

    while true; do
        cdsi_show_menu

        local choice=""
        if ! read -r choice; then
            log_blank
            log_info "Input closed. Exiting installer menu."
            break
        fi

        case "$choice" in
            0)
                log_info "Installing all components..."
                cdsi_install_all
                break
                ;;
            [1-9])
                # Validate against component count
                if [[ "$choice" -le "${#CDSI_COMP_NAMES[@]}" ]]; then
                    local idx=$((choice - 1))
                    cdsi_install_component "$idx"
                else
                    log_warning "Invalid choice: $choice"
                fi
                ;;
            [qQ])
                break
                ;;
            *)
                log_warning "Invalid choice: '$choice'"
                ;;
        esac
    done

    # ── Summary ──
    cdsi_summary
    log_blank
    log_success "CDSI Installer finished."
}

main "$@"
