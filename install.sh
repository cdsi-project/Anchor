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
# shellcheck source=lib/wordpress-access.sh
source "${CDSI_ROOT}/lib/wordpress-access.sh"

# Scripts under scripts/ are standalone commands. The installer invokes them
# as subprocesses so direct execution and orchestrated execution use the same
# code path and exit-status contract.

# ── Installer Metadata ─────────────────────────────────────
readonly CDSI_INSTALLER_VERSION="0.3.0"
readonly CDSI_COMPONENT_NOT_IMPLEMENTED=3
readonly CDSI_PREFLIGHT_SCRIPT="${CDSI_ROOT}/scripts/check-env.sh"

# ── Component Registry ─────────────────────────────────────
# Parallel arrays: names, descriptions, script paths, done flags.
CDSI_COMP_NAMES=("Nginx" "MySQL" "PHP-FPM" "Certbot" "WordPress")
CDSI_COMP_DESCS=("HTTP服务" "数据库" "PHP程序" "SSL证书" "WordPress站点")
CDSI_COMP_SCRIPTS=(
    "${CDSI_ROOT}/scripts/install-nginx.sh"
    "${CDSI_ROOT}/scripts/install-mysql.sh"
    "${CDSI_ROOT}/scripts/install-php.sh"
    "${CDSI_ROOT}/scripts/install-certbot.sh"
    "${CDSI_ROOT}/scripts/install-wordpress.sh"
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
    clear 2>/dev/null || printf '\033[2J\033[H'
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
    printf "  %bEnter choice:%b " "${CLR_BLINK}" "${CLR_RESET}"
}

# Run a single component install by index.
# Executes the component's install script as a subprocess.
# Args: <index 0-based> [install context]
cdsi_install_component() {
    local idx="$1"
    local install_context="${2:-single}"
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
    if env CDSI_INSTALL_CONTEXT="$install_context" bash "$script"; then
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
            cdsi_install_component "$i" all
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

# Post-install verification report: service status, site URLs, frontend
# reachability, and credentials. Printed after a full install, then the
# installer exits. Robust to missing services / unset domain.
cdsi_post_install_report() {
    log_blank
    log_separator
    printf "  %b安装完成验收报告 / Post-Install Verification%b\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator

    # ── 1. Service status ──
    printf "\n  %b服务状态 / Service Status%b\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    local svc state
    local -a svc_list=()
    svc_list+=( "nginx" )

    # Detect the PHP-FPM service name (version-dependent).
    local fpm_svc=""
    if command -v php >/dev/null 2>&1; then
        fpm_svc="php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)-fpm"
    fi
    if [[ -z "$fpm_svc" ]]; then
        fpm_svc="$(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null \
            | awk '{print $1}' | grep -m1 'php[0-9].*-fpm\.service' | sed 's/\.service$//' || true)"
    fi
    if [[ -n "$fpm_svc" ]]; then
        svc_list+=( "$fpm_svc" )
    fi

    # MySQL or MariaDB (whichever is installed) — detect by active/enabled
    # status rather than grepping list-unit-files (more robust across shells).
    local db_svc=""
    for cand in mysql mariadb mysqld; do
        if systemctl is-active --quiet "$cand" 2>/dev/null || systemctl is-enabled --quiet "$cand" 2>/dev/null; then
            db_svc="$cand"
            break
        fi
    done
    [[ -n "$db_svc" ]] && svc_list+=( "$db_svc" )
    for svc in "${svc_list[@]}"; do
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                state="${CLR_GREEN}● active${CLR_RESET}"
            elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                state="${CLR_YELLOW}○ inactive${CLR_RESET}"
            else
                state="${CLR_DIM}· not installed${CLR_RESET}"
            fi
        else
            state="${CLR_DIM}· unknown${CLR_RESET}"
        fi
        printf "    %-18s %b\n" "$svc" "$state"
    done

    # Resolve the final site URL once for reachability and the final access block.
    local domain="${CDSI_DOMAIN:-}"
    if [[ -z "$domain" && -f "${CDSI_ROOT}/config/domain" ]]; then
        domain="$(head -1 "${CDSI_ROOT}/config/domain" 2>/dev/null | tr -d '[:space:]')"
    fi
    local site_url server_ip="" fallback_url=""
    if [[ -z "$domain" ]]; then
        server_ip="$(cdsi_resolve_wordpress_server_ip)"
        if [[ -n "$server_ip" ]]; then
            fallback_url="http://${server_ip}"
        fi
    fi
    site_url="$(cdsi_resolve_wordpress_url "/var/www/wordpress" "$domain" "$fallback_url")"

    # ── 2. Frontend reachability ──
    printf "\n  %b前台访问检查 / Frontend Check%b\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    local http_code
    http_code="$(curl -sL -o /dev/null -m 12 -w '%{http_code}' "$site_url" 2>/dev/null || echo '000')"
    if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
        printf "    %b可访问 OK%b  (HTTP %s)\n" "${CLR_GREEN}" "${CLR_RESET}" "$http_code"
    else
        printf "    %b未能访问%b  (HTTP %s) — 请检查 Nginx / DNS / 防火墙\n" "${CLR_YELLOW}" "${CLR_RESET}" "$http_code"
    fi

    # ── 3. Database credentials ──
    printf "\n  %b数据库凭据 / Database Credentials%b\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    local mysql_pass="${CDSI_ROOT}/password/mysql.pass"
    if [[ -f "$mysql_pass" ]]; then
        local rootpw
        rootpw="$(grep '^root:' "$mysql_pass" 2>/dev/null | cut -d: -f2- || true)"
        printf "    %bMySQL 数据库 / Database%b\n" "${CLR_BOLD}" "${CLR_RESET}"
        printf "        root 密码: %s\n" "${rootpw:-<见 password/mysql.pass>}"
    else
        printf "    %bMySQL 凭据文件未找到：%s%b\n" "${CLR_YELLOW}" "$mysql_pass" "${CLR_RESET}"
    fi

    # ── 4. WordPress access details (keep this as the final result block) ──
    local wp_pass="${CDSI_ROOT}/password/wordpress.pass"
    local wp_atlas_pass="${CDSI_ROOT}/password/wordpress-atlas.pass"
    cdsi_print_wordpress_access "$site_url" "$wp_pass" "cdsi" \
        "$wp_atlas_pass" "$domain"

    log_blank
    log_info "以上凭据仅显示在当前终端，并保存在 password/ 目录（mode 600）；请勿提交到版本库。"
    log_separator
}

# ── Top-level Menu ────────────────────────────────────────

# Print the top-level menu shown after preflight checks pass.
cdsi_show_main_menu() {
    clear 2>/dev/null || printf '\033[2J\033[H'
    log_blank
    log_separator
    printf "  %bCDSI 主菜单 / Main Menu%b\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator
    log_blank
    printf "  %b1%b  安装服务 - Install services\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  %b2%b  卸载服务 - Uninstall services\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  %b3%b  查看密码 - View passwords\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  %bq%b  退出     - Quit\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator
    printf "  %bEnter choice:%b " "${CLR_BLINK}" "${CLR_RESET}"
}

# Display all stored component credentials (password/*.pass, mode 600).
cdsi_view_passwords() {
    local pass_dir="${CDSI_ROOT}/password"
    log_blank
    log_separator
    printf "  %b查看密码 / View Passwords%b\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_separator
    if [[ ! -d "$pass_dir" ]] || [[ -z "$(ls -A "$pass_dir" 2>/dev/null)" ]]; then
        log_info "No password files found at ${pass_dir}."
        log_info "Install components first to generate credentials."
        return 0
    fi
    local f
    for f in "${pass_dir}"/*.pass; do
        [[ -f "$f" ]] || continue
        printf "\n  %b%s%b\n" "${CLR_CYAN}${CLR_BOLD}" "$(basename "$f")" "${CLR_RESET}"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                printf "    %s\n" "$line"
            fi
        done < "$f"
    done
    log_blank
    log_info "These files are mode 600 — keep them secure and never commit them."
}

# Domain prompt + interactive install menu (top-level option 1).
cdsi_run_install_flow() {
    CDSI_CURRENT_STAGE="MENU"

    # Domain prompt (optional) — drives the WordPress URL and the Certbot cert.
    # Saved to config/domain so standalone component runs also pick it up.
    local CDSI_DOMAIN_FILE="${CDSI_ROOT}/config/domain"
    if [[ -z "${CDSI_DOMAIN:-}" ]] && [[ -f "$CDSI_DOMAIN_FILE" ]]; then
        CDSI_DOMAIN="$(cat "$CDSI_DOMAIN_FILE" 2>/dev/null | head -1 | tr -d '[:space:]')"
    fi

    if [[ -n "${CDSI_DOMAIN:-}" ]]; then
        log_info "Using existing domain: ${CDSI_DOMAIN}"
    else
        printf "  %b域名%b (Domain, optional — for WordPress URL + SSL; leave empty to use the server IP): " "${CLR_BLINK}" "${CLR_RESET}"
        local _domain_input=""
        if ! read -r _domain_input; then
            _domain_input=""
        fi
        if [[ -n "$_domain_input" ]]; then
            CDSI_DOMAIN="$(printf '%s' "$_domain_input" | tr -d '[:space:]')"
            mkdir -p "${CDSI_ROOT}/config"
            printf '%s\n' "$CDSI_DOMAIN" > "$CDSI_DOMAIN_FILE"
            log_info "Domain set: ${CDSI_DOMAIN} (saved to config/domain)"
        fi
    fi
    # Cert email: defaults to admin@<domain> (used by certbot for the ACME
    # account). Override with CDSI_CERT_EMAIL=you@example.com if needed.
    if [[ -z "${CDSI_CERT_EMAIL:-}" ]] && [[ -n "${CDSI_DOMAIN:-}" ]]; then
        CDSI_CERT_EMAIL="admin@${CDSI_DOMAIN}"
    fi
    export CDSI_DOMAIN CDSI_CERT_EMAIL

    while true; do
        cdsi_show_menu

        local choice=""
        if ! read -r choice; then
            log_blank
            log_info "Input closed. Returning to main menu."
            break
        fi

        # Select → clear → output: wipe the menu, then run the chosen action
        # so its output starts on a clean screen.
        clear 2>/dev/null || printf '\033[2J\033[H'

        case "$choice" in
            0)
                log_info "Installing all components..."
                cdsi_install_all
                cdsi_summary
                cdsi_post_install_report
                log_success "全部服务安装完成，验收报告已输出。安装程序即将退出。"
                exit 0
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

    cdsi_summary
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

    # ── Interactive gate ──
    if [[ ! -t 0 ]]; then
        log_error "Interactive terminal required for the installer menu."
        log_info  "If running via SSH, use:  ssh -t user@host 'cd /path && ./install.sh'"
        log_info  "Log: ${CDSI_LOG_FILE}"
        exit 1
    fi

    # Normalize the terminal erase character so the Backspace key works in the
    # menu. Some terminals send ^H (BS) while the remote `stty erase` defaults
    # to ^? (DEL), which makes Backspace echo garbage instead of deleting.
    # This matches Backspace → ^H. Switch to '^?' if your terminal sends DEL.
    stty erase '^H' 2>/dev/null || true

    # ── Press any key to continue (after preflight) ──
    printf "  %bPreflight 检查完成，按任意键继续...%b" "${CLR_BLINK}" "${CLR_RESET}"
    local _anykey=""
    if read -r -n1 -s _anykey; then
        echo
    fi
    unset _anykey

    # ── Top-level menu loop ──
    CDSI_CURRENT_STAGE="MENU"
    while true; do
        cdsi_show_main_menu

        local choice=""
        if ! read -r choice; then
            log_blank
            log_info "Input closed. Exiting installer."
            break
        fi

        # Select → clear → output: wipe the menu, then run the chosen action
        # so its output starts on a clean screen.
        clear 2>/dev/null || printf '\033[2J\033[H'

        case "$choice" in
            1)
                cdsi_run_install_flow
                ;;
            2)
                CDSI_CURRENT_STAGE="UNINSTALL"
                if [[ -f "${CDSI_ROOT}/uninstall.sh" ]]; then
                    bash "${CDSI_ROOT}/uninstall.sh"
                else
                    log_error "uninstall.sh not found at ${CDSI_ROOT}/uninstall.sh"
                fi
                CDSI_CURRENT_STAGE="MENU"
                ;;
            3)
                cdsi_view_passwords
                # Keep the credentials on screen until the user dismisses them,
                # otherwise the next menu render would clear them instantly.
                printf "  %b按任意键返回主菜单...%b" "${CLR_BLINK}" "${CLR_RESET}"
                local _back=""
                if read -r -n1 -s _back 2>/dev/null; then
                    echo
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

    log_blank
    log_success "CDSI Installer finished."
}

main "$@"
