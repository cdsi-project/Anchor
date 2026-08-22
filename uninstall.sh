#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Anchor — uninstall.sh
# Creator Digital Sovereignty Infrastructure
#
# Reverse installer: removes services that CDSI Anchor provisioned.
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
#   ./uninstall.sh                 # interactive menu
#   ./uninstall.sh nginx           # uninstall a single component
#   ./uninstall.sh all --yes       # non-interactive: remove everything
#   ./uninstall.sh --dry-run all   # show what would be removed
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

# ── Resolve installer root & root/sudo ─────────────────────
CDSI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDSI_ROOT
PASS_DIR="${CDSI_ROOT}/password"

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
    rm -rf "$path" || log_warn "删除失败: $path"
}

# Stop + disable a systemd unit (best-effort).
stop_disable_svc() {
    local svc="$1"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将停止并禁用服务: $svc"
        return 0
    fi
    "${SUDO[@]}" systemctl stop "$svc" 2>/dev/null || true
    "${SUDO[@]}" systemctl disable "$svc" 2>/dev/null || true
}

# Purge a list of explicitly named apt packages (only those installed).
purge_packages() {
    local pkgs=() p
    for p in "$@"; do
        if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
            pkgs+=("$p")
        fi
    done
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log "  (无相关 apt 包已安装，跳过)"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将执行: apt-get purge -y ${pkgs[*]}"
        return 0
    fi
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}" \
        || log_warn "apt-get purge 部分包失败 (继续)"
}

# Purge every *installed* package matching a dpkg glob (e.g. 'nginx*').
# Only packages with status "install ok installed" are touched, so a glob
# never removes unrelated packages that merely exist in the apt cache.
purge_glob() {
    local pattern="$1"
    local pkgs
    pkgs="$(dpkg-query -W -f='${Package} ${Status}\n' "$pattern" 2>/dev/null \
            | awk '$NF=="installed"{print $1}' || true)"
    if [[ -z "$pkgs" ]]; then
        log "  (无匹配 $pattern 的已安装包，跳过)"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将执行: apt-get purge -y $pkgs"
        return 0
    fi
    # shellcheck disable=SC2086
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get purge -y $pkgs \
        || log_warn "apt-get purge 失败 (继续)"
}

# Run apt autoremove --purge to clean orphaned dependencies.
autoremove() {
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "将执行: apt-get autoremove --purge -y"
        return 0
    fi
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true
}

# ── MySQL root helper (reads root password from password file) ─
_mysql_root() {
    local pw=""
    if [[ -f "${PASS_DIR}/mysql.pass" ]]; then
        pw="$(grep '^root:' "${PASS_DIR}/mysql.pass" 2>/dev/null | cut -d: -f2- || true)"
    fi
    if [[ -n "$pw" ]]; then
        mysql -u root -p"$pw" "$@"
    else
        mysql -u root "$@"
    fi
}

# ── Per-component uninstallers ──────────────────────────────

uninstall_nginx() {
    log "── 卸载 Nginx ──"
    local d=""
    d="$(cat "${CDSI_ROOT}/config/domain" 2>/dev/null | head -1 | tr -d '[:space:]')"
    if [[ -d /var/www/wordpress ]] \
       || [[ -f /etc/nginx/sites-enabled/wordpress ]] \
       || { [[ -n "$d" ]] && [[ -f "/etc/nginx/sites-enabled/${d}.conf" ]]; }; then
        log_warn "检测到 WordPress 站点仍在 /etc/nginx，建议先卸载 WordPress (或一并卸载全部)。"
    fi
    stop_disable_svc nginx
    purge_glob 'nginx*'
    log_ok "Nginx 已卸载 (含 nginx-common / nginx-core / 站点配置)。"
}

uninstall_mysql() {
    log "── 卸载 MySQL ──"
    # Drop the CDSI database/user while the server is still up.
    if command -v mysql >/dev/null 2>&1 && _mysql_root -e "SELECT 1" >/dev/null 2>&1; then
        _mysql_root -e "DROP DATABASE IF EXISTS cdsi; DROP USER IF EXISTS 'cdsi'@'localhost';" 2>/dev/null \
            || log_warn "无法删除 cdsi 数据库/用户 (可能已被移除)。"
    fi
    stop_disable_svc mysql
    purge_glob 'mysql-server*'
    purge_glob 'mysql-client*'
    purge_glob 'mysql-common'
    do_rm /var/lib/mysql
    do_rm /etc/mysql
    do_rm "${PASS_DIR}/mysql.pass"
    log_ok "MySQL 已卸载 (数据库 cdsi 与凭据已清理)。"
}

uninstall_php() {
    log "── 卸载 PHP-FPM ──"
    # Learn the installed PHP version (default 'php' first, else from php-fpm pkg).
    local ver=""
    ver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
        ver="$(dpkg-query -W -f='${Package}\n' 'php*-fpm' 2>/dev/null | head -1 | sed -E 's/^php([0-9]+\.[0-9]+)-fpm$/\1/')"
    fi
    if [[ -n "$ver" ]]; then
        stop_disable_svc "php${ver}-fpm"
    fi
    # Curated list = exactly what install-php.sh provisions (plus versioned forms).
    # Avoids a broad 'php*' glob that could remove unrelated PHP packages.
    local pkgs=(php-cli php-fpm php-common php-curl php-mbstring php-xml php-zip \
                php-bcmath php-intl php-mysql php-opcache php-redis php-gd php-imagick)
    if [[ -n "$ver" ]]; then
        pkgs+=( "php${ver}-fpm" "php${ver}-cli" "php${ver}-common" "php${ver}-opcache" \
                 "php${ver}-curl" "php${ver}-mbstring" "php${ver}-xml" "php${ver}-zip" \
                 "php${ver}-bcmath" "php${ver}-intl" "php${ver}-mysql" "php${ver}-redis" \
                 "php${ver}-gd" "php${ver}-imagick" )
    fi
    purge_packages "${pkgs[@]}"
    log_ok "PHP 已卸载 (仅移除 CDSI 安装的 php 包)。"
}

uninstall_redis() {
    log "── 卸载 Redis ──"
    stop_disable_svc redis-server
    purge_glob 'redis*'
    do_rm /etc/redis
    do_rm /var/lib/redis
    do_rm "${PASS_DIR}/redis.pass"
    log_ok "Redis 已卸载 (配置与凭据已清理)。"
}

uninstall_supervisor() {
    log "── 卸载 Supervisor ──"
    stop_disable_svc supervisor
    purge_packages supervisor
    do_rm /etc/supervisor
    log_ok "Supervisor 已卸载 (配置已清理)。"
}

# Strip the SSL directives Certbot injected into Nginx site blocks.
_certbot_cleanup_nginx() {
    [[ -d /etc/nginx/sites-available ]] || return 0
    command -v nginx >/dev/null 2>&1 || return 0
    local touched=0
    for f in /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*; do
        [[ -f "$f" ]] || continue
        if grep -q "managed by Certbot" "$f" 2>/dev/null; then
            touched=1
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "将清理 Nginx 中的 Certbot SSL 配置: $f"
                continue
            fi
            "${SUDO[@]}" sed -i '/# managed by Certbot/d' "$f"
            "${SUDO[@]}" sed -i '/if ($scheme != "https") {/d' "$f"
            "${SUDO[@]}" sed -i '/return 301 https:\/\/$host$request_uri;/d' "$f"
        fi
    done
    if [[ "$touched" -eq 1 && "$DRY_RUN" != true ]]; then
        if "${SUDO[@]}" nginx -t 2>/dev/null && "${SUDO[@]}" systemctl reload nginx 2>/dev/null; then
            log "  已移除 Nginx 中的 Certbot SSL 指令并重新加载。"
        else
            log_warn "Nginx 配置校验/重载失败，请手动检查 (可能需一并卸载 Nginx)。"
        fi
    fi
}

uninstall_certbot() {
    log "── 卸载 Certbot (SSL) ──"
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
    _certbot_cleanup_nginx
    purge_packages certbot python3-certbot-nginx
    log_ok "Certbot 已卸载 (证书与 Nginx SSL 指令已清理)。"
}

uninstall_wordpress() {
    log "── 卸载 WordPress ──"
    # Remove the Nginx site block — both the legacy 'wordpress' name and the
    # unified <domain>.conf produced by install-wordpress.sh.
    local d=""
    d="$(cat "${CDSI_ROOT}/config/domain" 2>/dev/null | head -1 | tr -d '[:space:]')"
    for n in wordpress "${d}"; do
        [[ -z "$n" ]] && continue
        do_rm "/etc/nginx/sites-available/${n}.conf"
        do_rm "/etc/nginx/sites-enabled/${n}.conf"
        do_rm "/etc/nginx/sites-available/${n}"
        do_rm "/etc/nginx/sites-enabled/${n}"
    done
    if command -v nginx >/dev/null 2>&1 && [[ "$DRY_RUN" != true ]]; then
        "${SUDO[@]}" nginx -t 2>/dev/null && "${SUDO[@]}" systemctl reload nginx 2>/dev/null || true
    fi
    if command -v mysql >/dev/null 2>&1 && _mysql_root -e "SELECT 1" >/dev/null 2>&1; then
        _mysql_root -e "DROP DATABASE IF EXISTS cdsi; DROP USER IF EXISTS 'cdsi'@'localhost';" 2>/dev/null \
            || log_warn "无法删除 cdsi 数据库/用户 (可能已被移除)。"
    fi
    do_rm /var/www/wordpress
    do_rm "${PASS_DIR}/wordpress.pass"
    do_rm "${PASS_DIR}/wordpress-beacon.pass"
    do_rm "${PASS_DIR}/wordpress-atlas.pass"
    do_rm /usr/local/bin/wp
    log_ok "WordPress 已卸载 (站点 / 数据库 / 凭据 / wp-cli 已清理)。"
}

# ── Component registry ─────────────────────────────────────
# Uninstall order matters: dependents first, so dangling configs are
# cleaned before their backing service disappears.
COMP_KEYS=(nginx mysql php redis supervisor certbot wordpress)
COMP_NAMES=(Nginx MySQL "PHP-FPM" Redis Supervisor Certbot WordPress)
COMP_DESCS=("HTTP服务" "数据库" "PHP程序" "Redis数据库" "进程守护" "SSL证书" "WordPress站点")
UNINSTALL_ORDER=(certbot wordpress php redis supervisor nginx mysql)

# Is a component currently installed on this host?
is_installed() {
    case "$1" in
        nginx)     command -v nginx >/dev/null 2>&1 ;;
        mysql)     command -v mysql >/dev/null 2>&1 || systemctl list-unit-files mysql.service >/dev/null 2>&1 ;;
        php)       command -v php-fpm >/dev/null 2>&1 || command -v php >/dev/null 2>&1 ;;
        redis)     command -v redis-server >/dev/null 2>&1 ;;
        supervisor) command -v supervisord >/dev/null 2>&1 ;;
        certbot)   command -v certbot >/dev/null 2>&1 ;;
        wordpress) [[ -d /var/www/wordpress ]] ;;
        *) return 1 ;;
    esac
}

# Short description of what a component's uninstall removes (for prompts).
comp_what() {
    case "$1" in
        nginx)     echo "nginx 包 + /etc/nginx 配置" ;;
        mysql)     echo "mysql-server 包 + /var/lib/mysql 数据 + cdsi 库/用户 + password/mysql.pass" ;;
        php)       echo "php-cli/php-fpm/扩展/php-common 全部包" ;;
        redis)     echo "redis-server 包 + /etc/redis + password/redis.pass" ;;
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
  ./uninstall.sh                交互式菜单 (逐个或卸载全部)
  ./uninstall.sh <组件>         卸载单个组件 (组件: ${COMP_KEYS[*]})
  ./uninstall.sh all            卸载全部组件
  ./uninstall.sh --dry-run all  仅预览将删除的内容，不实际执行
  ./uninstall.sh --yes all      非交互式确认，直接卸载全部

选项:
  --yes       跳过所有确认提示 (适合脚本调用)
  --dry-run   只打印将要执行的操作，不改动系统
  -h, --help  显示此帮助

注意: 卸载会移除 CDSI 安装的 apt 包、服务、生成配置与数据。
       password/*.pass 与 config/domain 等凭据文件也会被清理。
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
        log_fail "交互菜单需要终端。非交互请指定组件，例如: ./uninstall.sh all --yes"
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

main "$@"
