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

# ── Source Scripts ────────────────────────────────────────
# shellcheck source=scripts/configure.sh
source "${CDSI_ROOT}/scripts/configure.sh"
# shellcheck source=scripts/check-env.sh
source "${CDSI_ROOT}/scripts/check-env.sh"
# shellcheck source=scripts/health.sh
source "${CDSI_ROOT}/scripts/health.sh"
# shellcheck source=scripts/install-nginx.sh
source "${CDSI_ROOT}/scripts/install-nginx.sh"
# shellcheck source=scripts/install-mysql.sh
source "${CDSI_ROOT}/scripts/install-mysql.sh"
# shellcheck source=scripts/install-php.sh
source "${CDSI_ROOT}/scripts/install-php.sh"
# shellcheck source=scripts/install-redis.sh
source "${CDSI_ROOT}/scripts/install-redis.sh"

# ── Installer Metadata ─────────────────────────────────────
readonly CDSI_INSTALLER_VERSION="0.2.0"

# ── Component Registry ─────────────────────────────────────
# Parallel arrays: names, install functions, done flags.
CDSI_COMP_NAMES=("Nginx" "MySQL" "PHP-FPM" "Redis")
CDSI_COMP_DESCS=("HTTP服务" "数据库" "PHP程序" "Redis数据库")
CDSI_COMP_FUNCS=("install_nginx" "install_mysql" "install_php" "install_redis")
CDSI_COMP_DONE=()
for _i in "${!CDSI_COMP_NAMES[@]}"; do
    CDSI_COMP_DONE[$_i]=false
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
# Args: <index 0-based>
cdsi_install_component() {
    local idx="$1"
    local name="${CDSI_COMP_NAMES[$idx]}"
    local func="${CDSI_COMP_FUNCS[$idx]}"

    if [[ "${CDSI_COMP_DONE[$idx]}" == true ]]; then
        log_info "${name} already installed — skipping."
        return 0
    fi

    CDSI_CURRENT_STAGE="INSTALL_${name^^}"
    log_info "Installing ${name}..."
    "$func"
    CDSI_COMP_DONE[$idx]=true
    log_success "${name} installation complete."
    CDSI_CURRENT_STAGE="MENU"
}

# Install all remaining components in order.
cdsi_install_all() {
    local i
    for i in "${!CDSI_COMP_NAMES[@]}"; do
        if [[ "${CDSI_COMP_DONE[$i]}" != true ]]; then
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
        else
            printf "  %b○%b  %s\n" "${CLR_DIM}" "${CLR_RESET}" "$name"
            all_done=false
        fi
    done
    log_separator
    if [[ "$all_done" == true ]]; then
        log_success "All components installed."
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

    # ── Interactive Install Menu ──
    CDSI_CURRENT_STAGE="MENU"

    while true; do
        cdsi_show_menu

        local choice=""
        read -r choice || choice="q"

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
