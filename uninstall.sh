#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    _cdsi_entry_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
    exec /bin/sh "${_cdsi_entry_dir}/lib/bootstrap.sh" \
        "${_cdsi_entry_dir}/$(basename "$0")" "$@"
fi
# ═══════════════════════════════════════════════════════════════
# CDSI Anchor — uninstall.sh
# Creator Digital Sovereignty Infrastructure
#
# Package/path-based cleanup for the selected Anchor component names.
# It does not track package provenance and is intended for dedicated nodes.
#   • Selective: pick one component from the menu.
#   • Bulk:       "0" removes every CDSI component.
#
# Safety:
#   • Requires root (or sudo).
#   • Asks for confirmation before any destructive action
#     (unless --yes is passed).
#   • --dry-run prints what WOULD be removed without touching anything.
#
# Usage:
#   sudo ./uninstall.sh                 # interactive menu
#   sudo ./uninstall.sh nginx           # uninstall a single component
#   sudo ./uninstall.sh all --yes       # non-interactive: remove everything
#   sudo ./uninstall.sh --dry-run all   # show what would be removed
# ═══════════════════════════════════════════════════════════════

set -Eeuo pipefail

# ── Colors ─────────────────────────────────────────────────
if [[ -t 1 ]]; then
    CLR_RESET=$'\033[0m'; CLR_RED=$'\033[31m'; CLR_GREEN=$'\033[32m'
    CLR_YELLOW=$'\033[33m'; CLR_CYAN=$'\033[34m'; CLR_BOLD=$'\033[1m'; CLR_DIM=$'\033[2m'
else
    CLR_RESET=""; CLR_RED=""; CLR_GREEN=""; CLR_YELLOW=""; CLR_CYAN=""; CLR_BOLD=""; CLR_DIM=""
fi

# ── Logging ────────────────────────────────────────────────
log()      { printf '%b[CDSI]%b %s\n' "$CLR_CYAN" "$CLR_RESET" "$*"; }
log_ok()   { printf '%b[ OK ]%b %s\n' "$CLR_GREEN" "$CLR_RESET" "$*"; }
log_warn() { printf '%b[WARN]%b %s\n' "$CLR_YELLOW" "$CLR_RESET" "$*" >&2; return 0; }
log_fail() { printf '%b[FAIL]%b %s\n' "$CLR_RED" "$CLR_RESET" "$*" >&2; }
log_dry()  { printf '%b[DRY]%b %s\n' "$CLR_DIM" "$CLR_RESET" "$*"; }

cdsi_wp_cli_path() {
    if [[ -x /usr/local/bin/wp ]]; then
        printf '%s\n' /usr/local/bin/wp
        return 0
    fi
    command -v wp 2>/dev/null
}

# ── Resolve installer root & root/sudo ─────────────────────
CDSI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDSI_ROOT
PASS_DIR="${CDSI_ROOT}/password"

# shellcheck source=lib/platform.sh
source "${CDSI_ROOT}/lib/platform.sh"
# shellcheck source=lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"
# shellcheck source=lib/dnf.sh
source "${CDSI_ROOT}/lib/dnf.sh"
# shellcheck source=lib/packages.sh
source "${CDSI_ROOT}/lib/packages.sh"
# shellcheck source=lib/services.sh
source "${CDSI_ROOT}/lib/services.sh"
cdsi_platform_init

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
else
    log_fail "此脚本需要 root 权限或 sudo。"
    exit 1
fi

# ── Flags ──────────────────────────────────────────────────
DRY_RUN=false
ASSUME_YES=false
TARGET=""

# ── Safe destructive helpers (honor --dry-run) ─────────────

# Remove a file or directory (tolerates missing paths).
do_rm() {
    local path="$1"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将删除: $path"
        return 0
    fi
    "${SUDO[@]}" rm -rf -- "$path" || log_warn "删除失败: $path"
}

# Stop + disable a systemd unit (best-effort).
stop_disable_svc() {
    local svc="$1"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将停止并禁用服务: $svc"
        return 0
    fi
    cdsi_service_stop_disable "$svc" 2>/dev/null || true
}

# Remove a list of explicitly named packages (only those installed).
purge_packages() {
    local pkgs=() p
    for p in "$@"; do
        if cdsi_package_installed "$p"; then
            pkgs+=("$p")
        fi
    done
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log "  (无相关系统包已安装，跳过)"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将通过 ${CDSI_PACKAGE_BACKEND} 删除: ${pkgs[*]}"
        return 0
    fi
    cdsi_packages_remove "${pkgs[@]}" \
        || log_warn "部分系统包删除失败 (继续)"
}

# Remove every installed package matching a shell glob (e.g. 'nginx*').
purge_glob() {
    local pattern="$1"
    local p
    local -a pkgs=()
    case "$CDSI_PACKAGE_BACKEND" in
        apt)
            while IFS= read -r p; do
                [[ -n "$p" ]] && pkgs+=("$p")
            done < <(dpkg-query -W -f='${Package} ${Status}\n' "$pattern" 2>/dev/null \
                | awk '$NF=="installed"{print $1}' || true)
            ;;
        dnf)
            while IFS= read -r p; do
                [[ -n "$p" && "$p" == $pattern ]] && pkgs+=("$p")
            done < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null || true)
            ;;
        *)
            log_warn "未知包管理后端，未删除匹配包: $pattern"
            return 1
            ;;
    esac
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log "  (无匹配 $pattern 的已安装包，跳过)"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将通过 ${CDSI_PACKAGE_BACKEND} 删除: ${pkgs[*]}"
        return 0
    fi
    cdsi_packages_remove "${pkgs[@]}" \
        || log_warn "匹配包删除失败 (继续)"
}

# Remove orphaned dependencies through the active package manager.
autoremove() {
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将通过 ${CDSI_PACKAGE_BACKEND} 自动删除孤立依赖"
        return 0
    fi
    cdsi_packages_autoremove 2>/dev/null || true
}

# ── MySQL root helper (reads root password from password file) ─
_mysql_root() {
    local pw=""
    if [[ "$CDSI_DB_FLAVOR" == "mariadb" ]]; then
        "${SUDO[@]}" mysql -u root "$@"
        return
    fi
    if [[ -f "${PASS_DIR}/mysql.pass" ]]; then
        pw="$(grep '^root:' "${PASS_DIR}/mysql.pass" 2>/dev/null | cut -d: -f2- || true)"
    fi
    if [[ -n "$pw" ]]; then
        "${SUDO[@]}" mysql -u root -p"$pw" "$@"
    else
        "${SUDO[@]}" mysql -u root "$@"
    fi
}

# Drop the installer-managed database/user without violating --dry-run.
drop_cdsi_database() {
    command -v mysql >/dev/null 2>&1 || return 0
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将删除 MySQL 数据库 cdsi 和用户 'cdsi'@'localhost'"
        return 0
    fi
    if ! _mysql_root -e "SELECT 1" >/dev/null 2>&1; then
        log_warn "MySQL root 认证失败；未删除 cdsi 数据库/用户。"
        return 1
    fi
    if ! _mysql_root -e "DROP DATABASE IF EXISTS cdsi; DROP USER IF EXISTS 'cdsi'@'localhost';" 2>/dev/null; then
        log_warn "无法删除 cdsi 数据库/用户。"
        return 1
    fi
    return 0
}

read_root_marker() {
    local marker="$1"
    "${SUDO[@]}" cat -- "$marker" 2>/dev/null
}

# Restore only host-security changes that Anchor recorded when it made them.
remove_anchor_firewall_services() {
    local marker="/etc/cdsi/firewall-added-services"
    [[ -f "$marker" ]] || return 0

    local scope service_name marker_entry marker_content failed=0
    marker_content="$(read_root_marker "$marker")" \
        || { log_warn "无法读取 firewalld 记录文件: $marker"; return 1; }

    # Validate the entire marker before changing either firewalld layer.
    while IFS= read -r marker_entry; do
        [[ -n "$marker_entry" ]] || continue
        case "$marker_entry" in
            permanent:http|permanent:https|runtime:http|runtime:https) ;;
            *)
                log_warn "忽略无效的 firewalld 记录: $marker_entry"
                return 1
                ;;
        esac
    done <<< "$marker_content"

    while IFS= read -r marker_entry; do
        [[ -n "$marker_entry" ]] || continue
        scope="${marker_entry%%:*}"
        service_name="${marker_entry#*:}"
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "将删除 Anchor 添加的 firewalld ${scope} 服务: $service_name"
        elif [[ "$scope" == "runtime" ]]; then
            # Runtime rules cease to exist when firewalld is stopped. Never
            # touch the permanent configuration for a runtime-only marker.
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                if ! command -v firewall-cmd >/dev/null 2>&1; then
                    log_warn "firewalld 正在运行但 firewall-cmd 不可用，无法回滚 runtime 服务 ${service_name}。"
                    failed=1
                elif "${SUDO[@]}" firewall-cmd \
                    --query-service="$service_name" >/dev/null 2>&1 \
                    && ! "${SUDO[@]}" firewall-cmd \
                        --remove-service="$service_name" >/dev/null 2>&1; then
                    failed=1
                fi
            fi
        elif systemctl is-active --quiet firewalld 2>/dev/null; then
            if ! command -v firewall-cmd >/dev/null 2>&1; then
                log_warn "firewalld 正在运行但 firewall-cmd 不可用，无法回滚 permanent 服务 ${service_name}。"
                failed=1
            elif "${SUDO[@]}" firewall-cmd --permanent \
                --query-service="$service_name" >/dev/null 2>&1 \
                && ! "${SUDO[@]}" firewall-cmd --permanent \
                    --remove-service="$service_name" >/dev/null 2>&1; then
                failed=1
            fi
        elif command -v firewall-offline-cmd >/dev/null 2>&1; then
            if "${SUDO[@]}" firewall-offline-cmd \
                --query-service="$service_name" >/dev/null 2>&1 \
                && ! "${SUDO[@]}" firewall-offline-cmd \
                    --remove-service="$service_name" >/dev/null 2>&1; then
                failed=1
            fi
        else
            log_warn "无法回滚 firewalld permanent 服务 ${service_name}；保留记录文件。"
            failed=1
        fi
    done <<< "$marker_content"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将删除: $marker"
    elif [[ "$failed" -eq 0 ]]; then
        "${SUDO[@]}" rm -f -- "$marker"
    else
        return 1
    fi
}

remove_anchor_selinux_state() {
    local fcontext_marker="/etc/cdsi/selinux-wordpress-fcontext"
    local boolean_marker="/etc/cdsi/selinux-httpd-db-boolean"
    local pattern=""

    if [[ -f "$fcontext_marker" ]]; then
        pattern="$(read_root_marker "$fcontext_marker")" \
            || { log_warn "无法读取 SELinux 文件上下文记录。"; return 1; }
        if [[ "$pattern" != "/var/www/wordpress(/.*)?" ]]; then
            log_warn "SELinux 文件上下文记录无效，未自动删除规则。"
            return 1
        elif [[ "$DRY_RUN" == true ]]; then
            log_dry "将删除 Anchor 添加的 SELinux 文件上下文: $pattern"
            log_dry "将删除: $fcontext_marker"
        elif command -v semanage >/dev/null 2>&1; then
            "${SUDO[@]}" semanage fcontext -d "$pattern" \
                || { log_warn "无法删除 SELinux 文件上下文规则。"; return 1; }
            "${SUDO[@]}" rm -f -- "$fcontext_marker"
        else
            log_warn "semanage 不可用，无法回滚 SELinux 文件上下文。"
            return 1
        fi
    fi

    if [[ -f "$boolean_marker" ]]; then
        local boolean_name=""
        boolean_name="$(read_root_marker "$boolean_marker")" \
            || { log_warn "无法读取 SELinux 布尔值记录。"; return 1; }
        if [[ "$boolean_name" != "httpd_can_network_connect_db" ]]; then
            log_warn "SELinux 布尔值记录无效，未自动回滚。"
            return 1
        elif [[ "$DRY_RUN" == true ]]; then
            log_dry "将恢复 SELinux 布尔值: httpd_can_network_connect_db=off"
            log_dry "将删除: $boolean_marker"
        elif command -v setsebool >/dev/null 2>&1; then
            "${SUDO[@]}" setsebool -P httpd_can_network_connect_db off \
                || { log_warn "无法恢复 SELinux 数据库连接布尔值。"; return 1; }
            "${SUDO[@]}" rm -f -- "$boolean_marker"
        else
            log_warn "setsebool 不可用，无法回滚 SELinux 布尔值。"
            return 1
        fi
    fi
}

remove_anchor_epel() {
    local marker="/etc/cdsi/epel-added"
    [[ -f "$marker" ]] || return 0
    local marker_value=""
    marker_value="$(read_root_marker "$marker")" \
        || { log_warn "无法读取 EPEL 记录文件。"; return 1; }
    if [[ "$marker_value" != "epel-release" ]]; then
        log_warn "EPEL 记录内容无效，未自动删除仓库。"
        return 1
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将删除 Anchor 添加的 EPEL 仓库包: epel-release"
        log_dry "将删除: $marker"
        return 0
    fi
    if cdsi_package_installed epel-release; then
        cdsi_packages_remove epel-release \
            || { log_warn "无法删除 Anchor 添加的 EPEL 仓库。"; return 1; }
    fi
    "${SUDO[@]}" rm -f -- "$marker"
}

# ── Per-component uninstallers ──────────────────────────────

read_anchor_domain() {
    local domain_file="${1:-${CDSI_ROOT}/config/domain}"
    [[ -f "$domain_file" ]] || return 0
    head -n1 "$domain_file" 2>/dev/null | tr -d '[:space:]' || true
}

detect_installed_php_version() {
    local version=""
    version="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' \
        2>/dev/null || true)"
    if [[ -z "$version" && "$CDSI_PACKAGE_BACKEND" == "apt" ]]; then
        version="$(dpkg-query -W -f='${Package}\n' 'php*-fpm' 2>/dev/null \
            | head -1 | sed -E 's/^php([0-9]+\.[0-9]+)-fpm$/\1/' || true)"
    fi
    printf '%s' "$version"
}

uninstall_nginx() {
    log "── 卸载 Nginx ──"
    local d=""
    d="$(read_anchor_domain)"
    if [[ -d /var/www/wordpress ]] \
       || [[ -f "${CDSI_NGINX_ENABLED_DIR}/wordpress" ]] \
       || [[ -f "${CDSI_NGINX_ENABLED_DIR}/wordpress.conf" ]] \
       || { [[ -n "$d" ]] && [[ -f "${CDSI_NGINX_ENABLED_DIR}/${d}.conf" ]]; }; then
        log_warn "检测到 WordPress 站点仍在 ${CDSI_NGINX_ENABLED_DIR}，建议先卸载 WordPress (或一并卸载全部)。"
    fi
    remove_anchor_firewall_services \
        || log_warn "部分 Anchor firewalld 状态未能回滚；记录文件已保留。"
    stop_disable_svc "$CDSI_NGINX_SERVICE"
    purge_glob 'nginx*'
    log_ok "Nginx 已卸载 (含 nginx-common / nginx-core / 站点配置)。"
}

uninstall_mysql() {
    log "── 卸载数据库 ──"
    # Drop the CDSI database/user while the server is still up.
    drop_cdsi_database \
        || log_warn "无法单独删除 cdsi 库/用户；数据库数据目录仍将按确认范围清理。"
    stop_disable_svc "$CDSI_DB_SERVICE"
    if cdsi_is_centos_stream; then
        purge_glob 'mysql8.4*'
        do_rm /etc/my.cnf.d/zz-cdsi-anchor.cnf
    elif cdsi_is_debian; then
        # Anchor <= v0.3.0 installed this legacy meta-package.
        purge_glob 'default-mysql-server*'
        purge_glob 'mariadb-server*'
        purge_glob 'mariadb-client*'
        purge_glob 'mariadb-common'
        do_rm /etc/mysql/mariadb.conf.d/99-cdsi-anchor.cnf
    else
        purge_glob 'mysql-server*'
        purge_glob 'mysql-client*'
        purge_glob 'mysql-common'
        do_rm /etc/mysql
    fi
    do_rm /var/lib/mysql
    do_rm "${PASS_DIR}/mysql.pass"
    log_ok "数据库服务已卸载 (数据库 cdsi 与凭据已清理)。"
}

uninstall_php() {
    log "── 卸载 PHP-FPM ──"
    # Learn the installed PHP version (default 'php' first, else from php-fpm pkg).
    local ver=""
    ver="$(detect_installed_php_version)"
    local php_service=""
    php_service="$(cdsi_php_service_name "$ver" 2>/dev/null || true)"
    if [[ -n "$php_service" ]]; then
        stop_disable_svc "$php_service"
    fi
    # Curated list covers current packages plus legacy Imagick packages installed
    # by earlier Anchor releases. Avoid a broad 'php*' glob that could remove
    # unrelated PHP packages.
    local pkgs=()
    if cdsi_is_centos_stream; then
        pkgs=(php php-cli php-fpm php-common php-mbstring php-xml php-bcmath \
              php-intl php-mysqlnd php-process php-opcache php-pecl-redis6 \
              php-gd php-pecl-zip php-pecl-imagick)
    else
        pkgs=(php-cli php-fpm php-common php-curl php-mbstring php-xml php-zip \
              php-bcmath php-intl php-mysql php-opcache php-redis php-gd php-imagick)
    fi
    if cdsi_is_apt_family && [[ -n "$ver" ]]; then
        pkgs+=( "php${ver}-fpm" "php${ver}-cli" "php${ver}-common" "php${ver}-opcache" \
                 "php${ver}-curl" "php${ver}-mbstring" "php${ver}-xml" "php${ver}-zip" \
                 "php${ver}-bcmath" "php${ver}-intl" "php${ver}-mysql" "php${ver}-redis" \
                 "php${ver}-gd" "php${ver}-imagick" )
    fi
    purge_packages "${pkgs[@]}"
    log_ok "PHP 已卸载 (按明确包名移除 PHP-FPM、CLI 与相关扩展)。"
}

uninstall_redis() {
    log "── 卸载 Redis ──"
    if ! cdsi_is_ubuntu; then
        log_warn "Redis 不是 ${CDSI_OS_PRETTY} 的 Anchor 组件，跳过以保护现有服务。"
        return 0
    fi
    stop_disable_svc redis-server
    purge_glob 'redis*'
    do_rm /etc/redis
    do_rm /var/lib/redis
    do_rm "${PASS_DIR}/redis.pass"
    log_ok "Redis 已卸载 (配置与凭据已清理)。"
}

uninstall_supervisor() {
    log "── 卸载 Supervisor ──"
    if ! cdsi_is_ubuntu; then
        log_warn "Supervisor 不是 ${CDSI_OS_PRETTY} 的 Anchor 组件，跳过以保护现有服务。"
        return 0
    fi
    stop_disable_svc supervisor
    purge_packages supervisor
    do_rm /etc/supervisor
    log_ok "Supervisor 已卸载 (配置已清理)。"
}

# Strip the SSL directives and redirect blocks Certbot injected into one Nginx file.
_certbot_strip_nginx_file() {
    local target="$1"
    local filtered
    filtered="$(mktemp "${TMPDIR:-/tmp}/cdsi-nginx-filter.XXXXXX")" \
        || return 1

    # Certbot marks the closing brace of its redirect blocks. Buffer only those
    # candidate blocks so an otherwise identical custom rule remains untouched.
    if ! "${SUDO[@]}" awk '
        function clear_candidate(    i) {
            for (i in candidate) {
                delete candidate[i]
            }
            candidate_lines = 0
            in_candidate = 0
        }

        function flush_candidate(    i) {
            for (i = 1; i <= candidate_lines; i++) {
                print candidate[i]
            }
            clear_candidate()
        }

        function starts_redirect_candidate(line) {
            return line ~ /^[[:space:]]*if[[:space:]]*\(\$host[[:space:]]*=[^)]*\)[[:space:]]*\{[[:space:]]*$/ \
                || line ~ /^[[:space:]]*if[[:space:]]*\(\$scheme[[:space:]]*!=[[:space:]]*"https"[[:space:]]*\)[[:space:]]*\{[[:space:]]*$/
        }

        {
            if (!in_candidate) {
                if (starts_redirect_candidate($0)) {
                    in_candidate = 1
                    candidate[++candidate_lines] = $0
                    next
                }
                if ($0 ~ /#[[:space:]]*managed by Certbot[[:space:]]*$/) {
                    next
                }
                print
                next
            }

            candidate[++candidate_lines] = $0
            if ($0 ~ /^[[:space:]]*}/) {
                if ($0 ~ /#[[:space:]]*managed by Certbot[[:space:]]*$/) {
                    clear_candidate()
                } else {
                    flush_candidate()
                }
            }
        }

        END {
            if (in_candidate) {
                flush_candidate()
            }
        }
    ' "$target" > "$filtered"; then
        rm -f -- "$filtered"
        return 1
    fi

    if ! "${SUDO[@]}" tee "$target" < "$filtered" >/dev/null; then
        rm -f -- "$filtered"
        return 1
    fi
    rm -f -- "$filtered"
}

# Strip the SSL directives Certbot injected into Nginx site blocks.
_certbot_cleanup_nginx() {
    [[ -d "$CDSI_NGINX_SITE_DIR" || -d "$CDSI_NGINX_ENABLED_DIR" ]] || return 0
    command -v nginx >/dev/null 2>&1 || return 0
    local touched=0 failed=0 backup_dir=""
    local -a targets=() backups=()
    local f target backup idx
    declare -A seen=()

    for f in "${CDSI_NGINX_SITE_DIR}"/* "${CDSI_NGINX_ENABLED_DIR}"/*; do
        [[ -f "$f" ]] || continue
        if grep -q "managed by Certbot" "$f" 2>/dev/null; then
            touched=1
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "将清理 Nginx 中的 Certbot SSL 配置: $f"
                continue
            fi

            target="$(readlink -f -- "$f" 2>/dev/null || printf '%s' "$f")"
            [[ -f "$target" ]] || continue
            [[ -z "${seen[$target]+x}" ]] || continue
            seen["$target"]=1

            if [[ -z "$backup_dir" ]]; then
                backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/cdsi-nginx-rollback.XXXXXX")" \
                    || { log_warn "无法创建 Nginx 回滚目录。"; return 1; }
            fi
            backup="${backup_dir}/${#targets[@]}.conf"
            if ! "${SUDO[@]}" cp -a -- "$target" "$backup"; then
                log_warn "无法备份 Nginx 配置，停止 Certbot 清理: $target"
                failed=1
                break
            fi
            targets+=("$target")
            backups+=("$backup")

            if ! _certbot_strip_nginx_file "$target"; then
                log_warn "清理 Nginx Certbot 指令失败: $target"
                failed=1
                break
            fi
        fi
    done

    if [[ "$touched" -eq 0 || "$DRY_RUN" == true ]]; then
        return 0
    fi

    if [[ "$failed" -eq 0 ]] \
       && "${SUDO[@]}" nginx -t >/dev/null 2>&1 \
       && cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1; then
        [[ -n "$backup_dir" ]] && "${SUDO[@]}" rm -rf -- "$backup_dir"
        log "  已移除 Nginx 中的 Certbot SSL 指令并重新加载。"
        return 0
    fi

    log_warn "Nginx 配置校验/重载失败，正在恢复清理前配置。"
    local restore_failed=0
    for idx in "${!targets[@]}"; do
        if ! "${SUDO[@]}" cp -a -- "${backups[$idx]}" "${targets[$idx]}"; then
            log_warn "恢复 Nginx 配置失败: ${targets[$idx]}"
            restore_failed=1
        fi
    done

    if [[ "$restore_failed" -ne 0 ]]; then
        log_fail "部分 Nginx 配置未能恢复；回滚备份保留在: $backup_dir"
        return 1
    fi
    if ! "${SUDO[@]}" nginx -t >/dev/null 2>&1; then
        log_fail "恢复后的 Nginx 配置仍未通过校验，请立即手动检查。"
        log_fail "回滚备份保留在: $backup_dir"
        return 1
    fi
    if ! cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1; then
        log_fail "已恢复配置，但 Nginx 重新加载失败。"
        log_fail "回滚备份保留在: $backup_dir"
        return 1
    fi
    [[ -n "$backup_dir" ]] && "${SUDO[@]}" rm -rf -- "$backup_dir"
    return 1
}

_certbot_cleanup_ip_tls() {
    local tls_path="/etc/nginx/cdsi-wordpress-tls/ip.conf"
    local backup=""
    [[ -f "$tls_path" ]] || return 0
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将删除 Anchor IP TLS 配置: ${tls_path}"
        return 0
    fi

    backup="$(mktemp "${TMPDIR:-/tmp}/cdsi-uninstall-ip-tls.XXXXXX")" \
        || return 1
    "${SUDO[@]}" cp -a -- "$tls_path" "$backup" \
        || { rm -f -- "$backup"; return 1; }
    "${SUDO[@]}" rm -f -- "$tls_path" \
        || { rm -f -- "$backup"; return 1; }
    if ! "${SUDO[@]}" nginx -t \
       || ! cdsi_service_reload "$CDSI_NGINX_SERVICE"; then
        "${SUDO[@]}" install -m 0644 "$backup" "$tls_path" 2>/dev/null || true
        "${SUDO[@]}" nginx -t >/dev/null 2>&1 \
            && cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1 || true
        rm -f -- "$backup"
        return 1
    fi
    rm -f -- "$backup"
}

_certbot_restore_wordpress_http_url() {
    local wp_dir="/var/www/wordpress"
    local current_url="" current_siteurl="" http_url="" actual_home="" actual_siteurl=""
    local wp_cli=""
    wp_cli="$(cdsi_wp_cli_path)" || return 0
    [[ -f "${wp_dir}/wp-load.php" ]] || return 0
    current_url="$("${SUDO[@]}" "$wp_cli" --path="$wp_dir" option get home \
        --allow-root 2>/dev/null || true)"
    current_siteurl="$("${SUDO[@]}" "$wp_cli" --path="$wp_dir" option get siteurl \
        --allow-root 2>/dev/null || true)"
    [[ "$current_url" == https://* ]] || return 0
    http_url="http://${current_url#https://}"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将恢复 WordPress HTTP URL: ${http_url}"
        return 0
    fi
    if ! "${SUDO[@]}" "$wp_cli" --path="$wp_dir" option update siteurl "$http_url" \
            --allow-root >/dev/null \
       || ! "${SUDO[@]}" "$wp_cli" --path="$wp_dir" option update home "$http_url" \
            --allow-root >/dev/null; then
        [[ -z "$current_siteurl" ]] || "${SUDO[@]}" "$wp_cli" --path="$wp_dir" option update siteurl "$current_siteurl" --allow-root >/dev/null 2>&1 || true
        [[ -z "$current_url" ]] || "${SUDO[@]}" "$wp_cli" --path="$wp_dir" option update home "$current_url" --allow-root >/dev/null 2>&1 || true
        return 1
    fi
    actual_siteurl="$("${SUDO[@]}" "$wp_cli" --path="$wp_dir" option get siteurl --allow-root 2>/dev/null || true)"
    actual_home="$("${SUDO[@]}" "$wp_cli" --path="$wp_dir" option get home --allow-root 2>/dev/null || true)"
    if [[ "${actual_siteurl%/}" != "${http_url%/}" \
       || "${actual_home%/}" != "${http_url%/}" ]]; then
        [[ -z "$current_siteurl" ]] || "${SUDO[@]}" "$wp_cli" --path="$wp_dir" option update siteurl "$current_siteurl" --allow-root >/dev/null 2>&1 || true
        [[ -z "$current_url" ]] || "${SUDO[@]}" "$wp_cli" --path="$wp_dir" option update home "$current_url" --allow-root >/dev/null 2>&1 || true
        return 1
    fi
}

uninstall_certbot() {
    log "── 卸载 Certbot (SSL) ──"
    if ! _certbot_restore_wordpress_http_url; then
        log_fail "WordPress URL 未能恢复为 HTTP；Certbot 卸载已停止。"
        return 1
    fi
    if ! _certbot_cleanup_nginx; then
        log_fail "Certbot 卸载已停止；Nginx 配置未能安全清理。"
        return 1
    fi
    if ! _certbot_cleanup_ip_tls; then
        log_fail "IP TLS 配置未能安全移除；Certbot 卸载已停止。"
        return 1
    fi
    if command -v certbot >/dev/null 2>&1; then
        for d in /etc/letsencrypt/live/*; do
            [[ -d "$d" ]] || continue
            local name="${d##*/}"
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "将删除证书: $name"
            else
                "${SUDO[@]}" certbot delete --cert-name "$name" --non-interactive 2>/dev/null \
                    || log_warn "certbot delete 失败: $name (继续)"
            fi
        done
        do_rm /etc/letsencrypt
    fi
    stop_disable_svc certbot.timer
    stop_disable_svc certbot-renew.timer
    purge_packages certbot python3-certbot-nginx
    log_ok "Certbot 已卸载 (证书与 Nginx SSL 指令已清理)。"
}

uninstall_wordpress() {
    log "── 卸载 WordPress ──"
    local db_status="数据库已删除或不存在"
    # Remove the Nginx site block — both the legacy 'wordpress' name and the
    # unified <domain>.conf produced by install-wordpress.sh.
    local d=""
    d="$(read_anchor_domain)"
    for n in wordpress "${d}"; do
        [[ -z "$n" ]] && continue
        do_rm "${CDSI_NGINX_SITE_DIR}/${n}.conf"
        do_rm "${CDSI_NGINX_ENABLED_DIR}/${n}.conf"
        do_rm "${CDSI_NGINX_SITE_DIR}/${n}"
        do_rm "${CDSI_NGINX_ENABLED_DIR}/${n}"
    done
    if command -v nginx >/dev/null 2>&1 && [[ "$DRY_RUN" != true ]]; then
        "${SUDO[@]}" nginx -t 2>/dev/null \
            && cdsi_service_reload "$CDSI_NGINX_SERVICE" 2>/dev/null || true
    fi
    if ! drop_cdsi_database; then
        db_status="数据库/用户可能仍保留，请手动核对"
    fi
    do_rm /var/www/wordpress
    do_rm "${PASS_DIR}/wordpress.pass"
    do_rm "${PASS_DIR}/wordpress-beacon.pass"
    do_rm "${PASS_DIR}/wordpress-atlas.pass"
    do_rm /usr/local/bin/wp
    remove_anchor_selinux_state \
        || log_warn "部分 Anchor SELinux 状态未能回滚；记录文件已保留。"
    log_ok "WordPress 文件、站点配置、凭据与 wp-cli 已清理；${db_status}。"
}

# ── Component registry ─────────────────────────────────────
# Uninstall order matters: dependents first, so dangling configs are
# cleaned before their backing service disappears.
COMP_KEYS=(nginx mysql php redis supervisor certbot wordpress)
if [[ "$CDSI_DB_FLAVOR" == "mariadb" ]]; then
    DATABASE_COMPONENT_NAME="MariaDB"
else
    DATABASE_COMPONENT_NAME="MySQL"
fi
COMP_NAMES=(Nginx "$DATABASE_COMPONENT_NAME" "PHP-FPM" Redis Supervisor Certbot WordPress)
COMP_DESCS=("HTTP服务" "数据库" "PHP程序" "Redis数据库" "进程守护" "SSL证书" "WordPress站点")
UNINSTALL_ORDER=(certbot wordpress php redis supervisor nginx mysql)

# Is a component currently installed on this host?
is_installed() {
    case "$1" in
        nginx)     command -v nginx >/dev/null 2>&1 ;;
        mysql)     command -v mysql >/dev/null 2>&1 || cdsi_service_installed "$CDSI_DB_SERVICE" ;;
        php)       command -v php-fpm >/dev/null 2>&1 || command -v php >/dev/null 2>&1 ;;
        redis)     cdsi_is_ubuntu && command -v redis-server >/dev/null 2>&1 ;;
        supervisor) cdsi_is_ubuntu && command -v supervisord >/dev/null 2>&1 ;;
        certbot)   command -v certbot >/dev/null 2>&1 ;;
        wordpress) [[ -d /var/www/wordpress ]] ;;
        *) return 1 ;;
    esac
}

# Short description of what a component's uninstall removes (for prompts).
comp_what() {
    case "$1" in
        nginx)     echo "nginx 包 + /etc/nginx 配置" ;;
        mysql)
            if cdsi_is_centos_stream; then
                echo "${CDSI_DB_PACKAGE} 包 + Anchor 配置 /etc/my.cnf.d/zz-cdsi-anchor.cnf + /var/lib/mysql 数据 + cdsi 库/用户 + password/mysql.pass"
            elif cdsi_is_debian; then
                echo "${CDSI_DB_PACKAGE} 包 + Anchor 配置 /etc/mysql/mariadb.conf.d/99-cdsi-anchor.cnf + /var/lib/mysql 数据 + cdsi 库/用户 + password/mysql.pass"
            else
                echo "${CDSI_DB_PACKAGE} 包 + /etc/mysql 配置 + /var/lib/mysql 数据 + cdsi 库/用户 + password/mysql.pass"
            fi
            ;;
        php)       echo "php-cli/php-fpm/扩展/php-common 全部包" ;;
        redis)     echo "所有已安装 redis* 包 + /etc/redis + /var/lib/redis + password/redis.pass" ;;
        supervisor) echo "supervisor 包 + /etc/supervisor" ;;
        certbot)   echo "certbot/python3-certbot-nginx 包 + /etc/letsencrypt 证书 + Nginx SSL 指令" ;;
        wordpress) echo "/var/www/wordpress + Nginx 站点块 + cdsi 库 + WordPress/Beacon 凭据 + wp-cli" ;;
    esac
}

# ── Confirmation ───────────────────────────────────────────
confirm() {
    local prompt="$1"
    [[ "$ASSUME_YES" == true ]] && return 0
    printf '%b%s%b [y/N]: ' "$CLR_BOLD" "$prompt" "$CLR_RESET"
    local ans=""
    read -r ans || ans=""
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# ── Dispatch ───────────────────────────────────────────────
uninstall_one() {
    local key="$1"
    local skip="${2:-}"
    local idx=-1 name=""
    for i in "${!COMP_KEYS[@]}"; do
        if [[ "${COMP_KEYS[$i]}" == "$key" ]]; then idx=$i; name="${COMP_NAMES[$i]}"; break; fi
    done
    if [[ "$idx" -lt 0 ]]; then
        log_fail "未知组件: $key"
        return 1
    fi
    if [[ "$skip" != "skip_confirm" ]]; then
        if ! confirm "确认卸载 ${name}？将移除: $(comp_what "$key")"; then
            log "已取消 ${name} 的卸载。"
            return 0
        fi
    fi
    case "$key" in
        nginx)     uninstall_nginx ;;
        mysql)     uninstall_mysql ;;
        php)       uninstall_php ;;
        redis)     uninstall_redis ;;
        supervisor) uninstall_supervisor ;;
        certbot)   uninstall_certbot ;;
        wordpress) uninstall_wordpress ;;
    esac
}

uninstall_all() {
    if ! confirm "确认卸载全部 CDSI 组件？此操作不可逆，将移除 Nginx / MySQL / PHP-FPM / Redis / Supervisor / Certbot / WordPress 及其所有数据"; then
        log "已取消。"
        return 0
    fi
    for key in "${UNINSTALL_ORDER[@]}"; do
        uninstall_one "$key" skip_confirm
    done
    autoremove
    remove_anchor_epel \
        || log_warn "Anchor 添加的 EPEL 仓库未能移除；记录文件已保留。"
    log_ok "全部 CDSI 组件已卸载。"
}

# ── Interactive menu ────────────────────────────────────────
show_menu() {
    printf '\n'
    printf '%s\n' "-------------------------------------------------------"
    printf '  %bCDSI 组件卸载%b\n' "$CLR_BOLD" "$CLR_RESET"
    printf '%s\n' "-------------------------------------------------------"
    printf '  %b0%b  卸载全部 - Uninstall All\n' "$CLR_BOLD" "$CLR_RESET"
    local i
    for i in "${!COMP_KEYS[@]}"; do
        local num=$((i + 1)) key="${COMP_KEYS[$i]}" name="${COMP_NAMES[$i]}" desc="${COMP_DESCS[$i]}"
        if is_installed "$key"; then
            printf '  %b%d%b  %-10s - %-12s %b[已安装]%b\n' "$CLR_BOLD" "$num" "$CLR_RESET" "$name" "$desc" "$CLR_GREEN" "$CLR_RESET"
        else
            printf '  %b%d%b  %-10s - %-12s %b[未安装]%b\n' "$CLR_DIM" "$num" "$CLR_RESET" "$name" "$desc" "$CLR_DIM" "$CLR_RESET"
        fi
    done
    printf '  %bq%b  退出 - Quit\n' "$CLR_BOLD" "$CLR_RESET"
    printf '%s\n' "-------------------------------------------------------"
    printf '  输入选择: '
}

show_help() {
    cat <<EOF
CDSI Anchor uninstall.sh

用法:
  sudo ./uninstall.sh                交互式菜单 (逐个或卸载全部)
  sudo ./uninstall.sh <组件>         卸载单个组件 (组件: ${COMP_KEYS[*]})
  sudo ./uninstall.sh all            卸载全部组件
  sudo ./uninstall.sh --dry-run all  仅预览将删除的内容，不实际执行
  sudo ./uninstall.sh --yes all      非交互式确认，直接卸载全部

选项:
  --yes       跳过所有确认提示 (适合脚本调用)
  --dry-run   只打印将要执行的操作，不改动系统
  -h, --help  显示此帮助

注意: 卸载器不跟踪系统包或证书由谁安装；它会按组件名清理全局包、
       服务、配置与数据，只适用于专用 Anchor 节点。所选组件对应的
       password/*.pass 会被清理；config/domain 与 /etc/cdsi 会保留。
EOF
}

# ── Argument parsing ────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --yes|--assume-yes) ASSUME_YES=true ;;
        --dry-run)          DRY_RUN=true ;;
        -h|--help)          show_help; exit 0 ;;
        nginx|mysql|php|redis|supervisor|certbot|wordpress|all) TARGET="$arg" ;;
        *)
            log_fail "未知参数: $arg"
            show_help
            exit 1
            ;;
    esac
done

# ── Main ────────────────────────────────────────────────────
main() {
    if ! cdsi_platform_supported; then
        log_fail "不支持的操作系统: ${CDSI_OS_PRETTY}。卸载器未做任何修改。"
        log "Anchor 支持 Ubuntu Server 24.04/26.04 LTS、Debian 13 和 CentOS Stream 10。"
        return 3
    fi
    log "CDSI Uninstaller 启动。"
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY-RUN 模式：仅预览，不会修改系统。"
    fi

    # Non-interactive path: a target was given on the command line.
    if [[ -n "$TARGET" ]]; then
        if [[ "$TARGET" == "all" ]]; then
            uninstall_all
        else
            uninstall_one "$TARGET"
        fi
        log_ok "CDSI Uninstaller 完成。"
        return 0
    fi

    # Interactive path: require a terminal for the menu.
    if [[ ! -t 0 ]]; then
        log_fail "交互菜单需要终端。非交互请指定组件，例如: sudo ./uninstall.sh all --yes"
        exit 1
    fi

    # Normalize Backspace → ^H (see install.sh note).
    stty erase '^H' 2>/dev/null || true

    while true; do
        show_menu
        local choice=""
        if ! read -r choice; then
            printf '\n'
            log "输入已关闭，退出。"
            break
        fi
        case "$choice" in
            0)
                uninstall_all
                break
                ;;
            [1-9])
                if [[ "$choice" -le "${#COMP_KEYS[@]}" ]]; then
                    uninstall_one "${COMP_KEYS[$((choice - 1))]}"
                else
                    log_warn "无效选择: $choice"
                fi
                ;;
            [qQ]) break ;;
            *) log_warn "无效选择: '$choice'" ;;
        esac
    done

    log_ok "CDSI Uninstaller 完成。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
