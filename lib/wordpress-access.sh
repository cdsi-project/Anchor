#!/usr/bin/env bash
# Shared WordPress access-summary helpers. This file is intended to be sourced.

cdsi_resolve_wordpress_server_ip() {
    local server_ip="${CDSI_SERVER_IP:-}"
    local wordpress_dir="${1:-/var/www/wordpress}"
    local existing_url="" existing_host="" candidate="" url=""

    if [[ -n "$server_ip" ]]; then
        cdsi_is_ipv4 "$server_ip" || return 1
        printf '%s' "$server_ip"
        return 0
    fi

    if command -v wp >/dev/null 2>&1 \
       && [[ -f "${wordpress_dir}/wp-load.php" ]]; then
        existing_url="$(wp --path="$wordpress_dir" option get home \
            --allow-root 2>/dev/null || true)"
        case "$existing_url" in
            http://*|https://*)
                existing_host="${existing_url#*://}"
                existing_host="${existing_host%%/*}"
                existing_host="${existing_host%%:*}"
                if cdsi_is_public_ipv4 "$existing_host"; then
                    printf '%s' "$existing_host"
                    return 0
                fi
                ;;
        esac
    fi

    if declare -F get_public_ip >/dev/null 2>&1; then
        server_ip="$(get_public_ip 2>/dev/null || true)"
        [[ "$server_ip" != "unknown" ]] || server_ip=""
    fi
    if [[ -z "$server_ip" ]] && command -v curl >/dev/null 2>&1; then
        for url in \
            https://ip.3322.net \
            https://api.ipify.org \
            https://ipv4.icanhazip.com \
            https://ifconfig.co/ip \
            https://ifconfig.me/ip; do
            candidate="$(curl -fsS --max-time 5 "$url" 2>/dev/null \
                | tr -d '[:space:]' || true)"
            if cdsi_is_public_ipv4 "$candidate"; then
                server_ip="$candidate"
                break
            fi
        done
    fi
    if [[ -z "$server_ip" ]]; then
        for candidate in $(hostname -I 2>/dev/null || true); do
            if cdsi_is_public_ipv4 "$candidate"; then
                server_ip="$candidate"
                break
            fi
        done
    fi
    if [[ -z "$server_ip" && "${CDSI_ALLOW_PRIVATE_IP:-false}" == true ]]; then
        for candidate in $(hostname -I 2>/dev/null || true); do
            if cdsi_is_ipv4 "$candidate"; then
                server_ip="$candidate"
                break
            fi
        done
    fi

    printf '%s' "$server_ip"
}

cdsi_resolve_wordpress_url() {
    local wordpress_dir="${1:-/var/www/wordpress}"
    local domain="${2:-}"
    local fallback_url="${3:-}"
    local site_url=""
    local certbot_config_dir="${CDSI_CERTBOT_CONFIG_DIR:-}"

    [[ -n "$certbot_config_dir" ]] || certbot_config_dir="/etc/letsencrypt"

    domain="$(printf '%s' "$domain" | awk -F'[, ]' '{print $1}')"

    if [[ -n "$domain" ]]; then
        if [[ -s "${certbot_config_dir}/live/${domain}/fullchain.pem" ]] \
           && command -v openssl >/dev/null 2>&1 \
           && openssl x509 -checkend 86400 -noout \
                -in "${certbot_config_dir}/live/${domain}/fullchain.pem" \
                >/dev/null 2>&1; then
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
    local beacon_credentials_file="${4:-${credentials_file%/*}/wordpress-beacon.pass}"
    local beacon_domain="${5:-}"
    local username=""
    local password=""
    local beacon_username=""
    local beacon_name=""
    local beacon_password=""
    local admin_url=""

    if [[ -r "$credentials_file" ]]; then
        username="$(grep '^user:' "$credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
        password="$(grep '^pass:' "$credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
    fi
    if [[ -r "$beacon_credentials_file" ]]; then
        beacon_username="$(grep '^user:' "$beacon_credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
        beacon_name="$(grep '^name:' "$beacon_credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
        beacon_password="$(grep '^pass:' "$beacon_credentials_file" 2>/dev/null | head -n1 | cut -d: -f2- || true)"
    fi

    [[ -n "$username" ]] || username="$default_user"
    [[ -n "$beacon_username" ]] || beacon_username="$username"
    [[ -n "$beacon_name" ]] || beacon_name="CDSI Beacon"
    beacon_domain="$(printf '%s' "$beacon_domain" | awk -F'[, ]' '{print $1}')"
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
    printf '  CDSI Beacon OpenWeb 配置 / Beacon Configuration\n'
    if [[ -n "$beacon_domain" && "$site_url" == https://* ]]; then
        printf '  源站域名 / Origin Domain: %s\n' "$beacon_domain"
    else
        printf '  源站域名 / Origin Domain: <requires a domain with valid HTTPS>\n'
        printf '  Beacon 状态 / Status:      暂不可用；请先配置域名和有效 HTTPS\n'
    fi
    printf '  登录用户 / Username:     %s\n' "$beacon_username"
    printf '  应用名称 / Application:  %s\n' "$beacon_name"
    if [[ -n "$beacon_password" ]]; then
        printf '  应用密码 / App Password: %s\n' "$beacon_password"
    else
        printf '  应用密码 / App Password: <unavailable; see %s>\n' "$beacon_credentials_file"
    fi
    printf '  Beacon 凭据 / Credentials: %s (mode 600)\n' "$beacon_credentials_file"
    printf '  -------------------------------------------------------\n'
}
