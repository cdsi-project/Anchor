#!/usr/bin/env bash
# Shared WordPress access-summary helpers. This file is intended to be sourced.

cdsi_resolve_wordpress_server_ip() {
    local server_ip="${CDSI_SERVER_IP:-}"

    if [[ -z "$server_ip" ]] && command -v curl >/dev/null 2>&1; then
        server_ip="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    fi
    if [[ -z "$server_ip" ]]; then
        server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    printf '%s' "$server_ip"
}

cdsi_resolve_wordpress_url() {
    local wordpress_dir="${1:-/var/www/wordpress}"
    local domain="${2:-}"
    local fallback_url="${3:-}"
    local site_url=""

    domain="$(printf '%s' "$domain" | awk -F'[, ]' '{print $1}')"

    if [[ -n "$domain" ]]; then
        if [[ -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
            site_url="https://${domain}"
        else
            site_url="http://${domain}"
        fi
    elif command -v wp >/dev/null 2>&1 && [[ -f "${wordpress_dir}/wp-load.php" ]]; then
        site_url="$(wp --path="$wordpress_dir" option get home --allow-root 2>/dev/null || true)"
    fi

    if [[ -z "$site_url" ]]; then
        site_url="$fallback_url"
    fi

    printf '%s' "${site_url%/}"
}

cdsi_print_wordpress_access() {
    local site_url="${1%/}"
    local credentials_file="$2"
    local default_user="${3:-cdsi}"
    local atlas_credentials_file="${4:-${credentials_file%/*}/wordpress-atlas.pass}"
    local atlas_domain="${5:-}"
    local username=""
    local password=""
    local atlas_username=""
    local atlas_name=""
    local atlas_password=""
    local admin_url=""

    if [[ -r "$credentials_file" ]]; then
        username="$(grep '^user:' "$credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
        password="$(grep '^pass:' "$credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
    fi
    if [[ -r "$atlas_credentials_file" ]]; then
        atlas_username="$(grep '^user:' "$atlas_credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
        atlas_name="$(grep '^name:' "$atlas_credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
        atlas_password="$(grep '^pass:' "$atlas_credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
    fi

    [[ -n "$username" ]] || username="$default_user"
    [[ -n "$atlas_username" ]] || atlas_username="$username"
    [[ -n "$atlas_name" ]] || atlas_name="CDSI Atlas"
    atlas_domain="$(printf '%s' "$atlas_domain" | awk -F'[, ]' '{print $1}')"
    if [[ -n "$site_url" ]]; then
        admin_url="${site_url}/wp-admin/"
    else
        site_url="<unavailable>"
        admin_url="<unavailable>"
    fi

    # Use printf directly so credentials are not sent to the persistent logger.
    printf '\n'
    printf '  WordPress 网站与登录信息 / Site & Login\n'
    printf '  -------------------------------------------------------\n'
    printf '  网站地址 / Site URL:     %s\n' "$site_url"
    printf '  后台地址 / Admin URL:    %s\n' "$admin_url"
    printf '  登录用户 / Username:     %s\n' "$username"
    if [[ -n "$password" ]]; then
        printf '  登录密码 / Password:     %s\n' "$password"
    else
        printf '  登录密码 / Password:     <unavailable; see %s>\n' "$credentials_file"
    fi
    printf '  凭据文件 / Credentials:  %s (mode 600)\n' "$credentials_file"
    printf '\n'
    printf '  CDSI Atlas OpenWeb 配置 / Atlas Configuration\n'
    if [[ -n "$atlas_domain" && "$site_url" == https://* ]]; then
        printf '  源站域名 / Origin Domain: %s\n' "$atlas_domain"
    else
        printf '  源站域名 / Origin Domain: <requires a domain with valid HTTPS>\n'
        printf '  Atlas 状态 / Status:      暂不可用；请先配置域名和有效 HTTPS\n'
    fi
    printf '  登录用户 / Username:     %s\n' "$atlas_username"
    printf '  应用名称 / Application:  %s\n' "$atlas_name"
    if [[ -n "$atlas_password" ]]; then
        printf '  应用密码 / App Password: %s\n' "$atlas_password"
    else
        printf '  应用密码 / App Password: <unavailable; see %s>\n' "$atlas_credentials_file"
    fi
    printf '  Atlas 凭据 / Credentials: %s (mode 600)\n' "$atlas_credentials_file"
    printf '  -------------------------------------------------------\n'
}
