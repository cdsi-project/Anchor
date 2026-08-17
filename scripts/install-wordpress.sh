#!/usr/bin/env bash
# ═══════════════════════════════════════════════════
# CDSI Bootstrap — WordPress Installer
# Downloads the latest WordPress, provisions it against the
# existing `cdsi` MySQL database (credentials from password/mysql.pass),
# and creates an admin user `cdsi` with a random 10-char password.
# The admin username and password are both saved to password/wordpress.pass
# (format: user:<name> / pass:<password>).
#
# Also wires the LEMP stack so the site is reachable:
#   • installs php-fpm + php-mysql + wp-cli if missing
#   • adds an Nginx server block for the chosen URL
#
# Reads from password/mysql.pass (lines: root:<pw>  cdsi:<pw>).
#
# Can be called by install.sh or run directly:
#   bash scripts/install-wordpress.sh
# ═══════════════════════════════════════════════════

set -Eeuo pipefail

# ── Logging ────────────────────────────────────────────────
log()     { printf "\033[1;34m[CDSI]\033[0m %s\n" "$*"; }
log_ok()  { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
log_fail(){ printf "\033[1;31m[FAIL]\033[0m %s\n" "$*" >&2; }

fail() {
    log_fail "$*"
    exit 1
}

# ── Root Check ─────────────────────────────────────────────
if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    fail "This script requires root privileges or sudo."
fi

# ── Paths / Config ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS_DIR="${CDSI_ROOT}/password"
MYSQL_PASS_FILE="${PASS_DIR}/mysql.pass"
WP_PASS_FILE="${PASS_DIR}/wordpress.pass"

WEB_ROOT="/var/www"
WP_DIR="${WEB_ROOT}/wordpress"
# Nginx site-block path is computed inside configure_nginx() as <domain>.conf
# (falls back to 'wordpress.conf' when no domain is set), so the file name is
# unified as the domain instead of a generic 'wordpress'.

DB_NAME="cdsi"
DB_USER="cdsi"

# ── Resolve site domain (optional) ──────────────────────
# Precedence: CDSI_DOMAIN env → config/domain file → none (fall back to IP).
# When set, the site is served at http://<domain>, Nginx server_name points
# at it, and Certbot is triggered to issue a TLS certificate.
if [[ -z "${CDSI_DOMAIN:-}" ]] && [[ -f "${CDSI_ROOT}/config/domain" ]]; then
    CDSI_DOMAIN="$(cat "${CDSI_ROOT}/config/domain" 2>/dev/null | head -1 | tr -d '[:space:]')"
fi
if [[ -n "${CDSI_DOMAIN:-}" ]]; then
    WP_DOMAIN="$(printf '%s' "${CDSI_DOMAIN}" | awk -F'[, ]' '{print $1}')"
    WP_URL="http://${WP_DOMAIN}"
    log "Domain provided: ${WP_DOMAIN} (site URL → ${WP_URL})"
else
    WP_DOMAIN=""
    WP_URL="http://8.140.192.151"
fi
WP_TITLE="CDSI Node"
WP_ADMIN_USER="cdsi"
WP_ADMIN_EMAIL="admin@cdsi.local"

# ── Read cdsi DB password from password/mysql.pass ────────
[[ -f "$MYSQL_PASS_FILE" ]] || fail "MySQL credential file not found: ${MYSQL_PASS_FILE}. Run install-mysql.sh first."
DB_PASSWORD="$(grep '^cdsi:' "$MYSQL_PASS_FILE" 2>/dev/null | cut -d: -f2-)"
[[ -n "$DB_PASSWORD" ]] || fail "cdsi password not found in ${MYSQL_PASS_FILE}."

# ── Password Generation (10-char alphanumeric) ─────────────
generate_password() {
    local pw
    pw="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || true)"
    [[ ${#pw} -eq 10 ]] || fail "Failed to generate 10-char password."
    echo "$pw"
}

# ── Detect PHP-FPM version installed ──────────────────────
detect_php_fpm() {
    # echoes the php-fpm service/bin version prefix, e.g. "8.5", or ""
    local v
    v="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"
    echo "$v"
}

# ══════════════════════════════════════════════════════════
# 1) Provision PHP runtime (php-fpm + php-mysql + wp-cli)
# ══════════════════════════════════════════════════════════
# ── Install wp-cli (with mirror fallback + integrity check) ─
install_wpcli() {
    if command -v wp >/dev/null 2>&1 && wp --info >/dev/null 2>&1; then
        log "wp-cli already present."
        return 0
    fi
    log "Installing wp-cli from CDN..."
    # No bundled phar is shipped; always fetch over the network. Primary mirror:
    # cdn.aicsi.cn (reliable in CN regions). jsDelivr kept as a secondary
    # fallback in case the CDN is unreachable.
    local urls=(
        "http://cdn.aicsi.cn/packages/wp-cli.phar"
        "https://cdn.jsdelivr.net/gh/wp-cli/builds@gh-pages/phar/wp-cli.phar"
    )
    local ok=0
    for u in "${urls[@]}"; do
        if ${SUDO} curl -fsSL --retry 3 -o /tmp/wp-cli.phar "$u" 2>/dev/null \
           && [[ -s /tmp/wp-cli.phar ]] \
           && [[ $(wc -c < /tmp/wp-cli.phar) -gt 1000000 ]]; then
            ok=1
            break
        fi
        ${SUDO} rm -f /tmp/wp-cli.phar
    done
    [[ $ok -eq 1 ]] || fail "Failed to download a valid wp-cli phar."
    ${SUDO} cp /tmp/wp-cli.phar /usr/local/bin/wp
    ${SUDO} chmod +x /usr/local/bin/wp
    command -v wp >/dev/null 2>&1 || fail "wp-cli install failed."
    log_ok "wp-cli installed."
}

provision_php() {
    local phpver
    phpver="$(detect_php_fpm)"
    [[ -n "$phpver" ]] || fail "Could not determine PHP version from 'php'."
    PHP_FPM_VER="$phpver"

    if command -v "php-fpm${phpver}" >/dev/null 2>&1 \
       && systemctl is-active --quiet "php${phpver}-fpm" \
       && command -v wp >/dev/null 2>&1 \
       && php -m | grep -qi mysqli; then
        log "PHP-FPM ${phpver} and wp-cli already present and active."
        return 0
    fi

    log "Installing PHP-FPM, MySQL driver and wp-cli..."
    ${SUDO} apt-get update -qq || log "apt-get update had warnings, continuing..."

    # Install php-fpm + common extensions. Use the PHP reported by `php`.
    DEBIAN_FRONTEND=noninteractive ${SUDO} apt-get install -y -qq \
        "php${phpver}-fpm" "php${phpver}-mysql" "php${phpver}-cli" \
        "php${phpver}-curl" "php${phpver}-gd" "php${phpver}-mbstring" \
        "php${phpver}-xml" "php${phpver}-zip" || fail "PHP package installation failed."

    install_wpcli

    # Start php-fpm service (name: php{ver}-fpm)
    ${SUDO} systemctl enable "php${phpver}-fpm" >/dev/null 2>&1 || true
    ${SUDO} systemctl start  "php${phpver}-fpm" || fail "Failed to start php${phpver}-fpm."
    ${SUDO} systemctl is-active --quiet "php${phpver}-fpm" || fail "php${phpver}-fpm is not active."

    log_ok "PHP-FPM ${phpver} + wp-cli ready."
}

# ══════════════════════════════════════════════════════════
# 2) Download WordPress package (zh_CN build) from the CDN and unzip
# ══════════════════════════════════════════════════════════
WP_PACKAGE_URL="http://cdn.aicsi.cn/packages/wordpress-7.0.4-zh_CN.zip"

download_wordpress() {
    if [[ -f "${WP_DIR}/wp-load.php" ]]; then
        log "WordPress files already present at ${WP_DIR}."
        return 0
    fi

    # unzip is required to extract the package
    if ! command -v unzip >/dev/null 2>&1; then
        log "Installing unzip (required to extract the package)..."
        ${SUDO} apt-get update -qq || true
        DEBIAN_FRONTEND=noninteractive ${SUDO} apt-get install -y -qq unzip \
            || fail "Failed to install unzip."
    fi

    log "Downloading WordPress (zh_CN) package from CDN: ${WP_PACKAGE_URL}"
    ${SUDO} mkdir -p "$WEB_ROOT"
    ${SUDO} rm -rf /tmp/wp-latest
    ${SUDO} mkdir -p /tmp/wp-latest
    ${SUDO} curl -fsSL --retry 3 -o /tmp/wp-latest/wordpress.zip "${WP_PACKAGE_URL}" \
        || fail "Failed to download WordPress package from ${WP_PACKAGE_URL}."
    ${SUDO} unzip -q -o /tmp/wp-latest/wordpress.zip -d /tmp/wp-latest \
        || fail "Failed to extract WordPress zip package."

    # Most WordPress builds (including the official one) nest files under a
    # 'wordpress/' directory; fall back to the flat layout if not present.
    if [[ -d /tmp/wp-latest/wordpress ]]; then
        ${SUDO} cp -a /tmp/wp-latest/wordpress/. "$WP_DIR"/
    else
        ${SUDO} cp -a /tmp/wp-latest/. "$WP_DIR"/
    fi

    ${SUDO} rm -rf /tmp/wp-latest
    [[ -f "${WP_DIR}/wp-load.php" ]] || fail "WordPress extraction did not produce wp-load.php."
    log_ok "WordPress files placed at ${WP_DIR}."
}

# ══════════════════════════════════════════════════════════
# 3) wp-config.php (DB + auth salts)
# ══════════════════════════════════════════════════════════
write_wp_config() {
    local cfg="${WP_DIR}/wp-config.php"
    if [[ -f "$cfg" ]]; then
        log "wp-config.php already exists."
        return 0
    fi
    log "Generating wp-config.php (with auth salts)..."
    ${SUDO} wp --path="$WP_DIR" config create \
        --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASSWORD" --dbhost=localhost \
        --allow-root || fail "wp config create failed."
    log_ok "wp-config.php written (DB=${DB_NAME}, user=${DB_USER})."
}

# ══════════════════════════════════════════════════════════
# 4) wp core install (DB tables + admin user)
# ══════════════════════════════════════════════════════════
install_core() {
    # Already installed?
    if wp --path="$WP_DIR" core is-installed --allow-root >/dev/null 2>&1; then
        log "WordPress is already installed (core is-installed)."
        return 0
    fi

    WP_ADMIN_PASSWORD="$(generate_password)"
    log "Running wp core install (admin user: ${WP_ADMIN_USER})..."
    ${SUDO} wp --path="$WP_DIR" core install \
        --url="$WP_URL" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email --allow-root \
        || fail "wp core install failed."

    # Save admin credentials (username + password), format matches password/mysql.pass
    #   user:cdsi
    #   pass:<random-10-char>
    ${SUDO} mkdir -p "$PASS_DIR"
    {
        echo "user:${WP_ADMIN_USER}"
        echo "pass:${WP_ADMIN_PASSWORD}"
    } > "$WP_PASS_FILE"
    ${SUDO} chmod 600 "$WP_PASS_FILE"
    log_ok "Admin credentials saved to: ${WP_PASS_FILE} (mode 600)"
}

# ══════════════════════════════════════════════════════════
# 5) Nginx server block → php-fpm
# ══════════════════════════════════════════════════════════
configure_nginx() {
    local phpver sock site_name conf_path enabled_path conf
    phpver="$(detect_php_fpm)"
    sock="/run/php/php${phpver}-fpm.sock"

    # Unified site-block file name: <domain>.conf (or 'wordpress.conf' when no
    # domain is provided). Migrate away any legacy 'wordpress' block so the
    # name is consistent and there is exactly one WordPress server block.
    site_name="${WP_DOMAIN:-wordpress}"
    conf_path="/etc/nginx/sites-available/${site_name}.conf"
    enabled_path="/etc/nginx/sites-enabled/${site_name}.conf"
    if [[ "${site_name}" != "wordpress" ]]; then
        ${SUDO} rm -f /etc/nginx/sites-available/wordpress \
                     /etc/nginx/sites-enabled/wordpress
    fi

    log "Configuring Nginx server block (${site_name}.conf) → ${WP_DIR} (php-fpm ${phpver})..."

    conf="$(cat <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${WP_DOMAIN:-_};

    root ${WP_DIR};
    index index.php index.html index.htm;

    access_log /var/log/nginx/wordpress.access.log;
    error_log  /var/log/nginx/wordpress.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${sock};
    }

    location ~ /\\.(ht|git|env) {
        deny all;
    }
}
EOF
)"
    printf '%s\n' "$conf" | ${SUDO} tee "$conf_path" >/dev/null
    ${SUDO} ln -sf "$conf_path" "$enabled_path"

    ${SUDO} nginx -t || fail "nginx -t failed; server block has errors."
    ${SUDO} systemctl reload nginx || fail "Failed to reload nginx."
    log_ok "Nginx reloaded with WordPress server block (${site_name}.conf)."
}

# ── Align WordPress site URL with the configured WP_URL ──
set_site_url() {
    if wp --path="$WP_DIR" core is-installed --allow-root >/dev/null 2>&1; then
        ${SUDO} wp --path="$WP_DIR" option update siteurl "$WP_URL" --allow-root 2>/dev/null || true
        ${SUDO} wp --path="$WP_DIR" option update home    "$WP_URL" --allow-root 2>/dev/null || true
        log_ok "WordPress site URL set to ${WP_URL}."
    fi
}

# ── Issue a TLS certificate via Certbot when a domain is set ─
maybe_issue_cert() {
    [[ -n "${WP_DOMAIN:-}" ]] || return 0
    local cert_script="${CDSI_ROOT}/scripts/install-certbot.sh"
    [[ -f "$cert_script" ]] || return 0
    log "Requesting TLS certificate for ${WP_DOMAIN} via Certbot..."
    if bash "$cert_script"; then
        log_ok "Certbot configuration complete for ${WP_DOMAIN}."
    else
        log_fail "Certbot failed to obtain a certificate for ${WP_DOMAIN}."
        log_fail "Ensure the domain DNS A record points to this server and port 80 is"
        log_fail "reachable from the internet (ACME HTTP-01 challenge), then re-run:"
        log_fail "  bash scripts/install-certbot.sh"
    fi
}

# ── Permissions ───────────────────────────────────────────
fix_ownership() {
    ${SUDO} chown -R www-data:www-data "$WP_DIR" 2>/dev/null || true
    ${SUDO} find "$WP_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    ${SUDO} find "$WP_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
}

# ── Main ───────────────────────────────────────────────────
log "=== CDSI WordPress Installer ==="

provision_php
download_wordpress
write_wp_config
install_core
set_site_url
configure_nginx
fix_ownership
maybe_issue_cert

# ── Summary ────────────────────────────────────────────────
log_ok "WordPress installation complete."
log "  Version:   $(wp --path="$WP_DIR" core version --allow-root 2>/dev/null || echo unknown)"
log "  URL:       ${WP_URL}"
[[ -n "${WP_DOMAIN:-}" ]] && log "  Domain:    ${WP_DOMAIN} (Certbot SSL attempted)"
log "  Web root:  ${WP_DIR}"
log "  DB:        ${DB_NAME} (user ${DB_USER})"
log "  Admin:     ${WP_ADMIN_USER}"
log "  WP pass:   ${WP_PASS_FILE} (mode 600)"
log "  Login:     ${WP_URL}/wp-admin/"

exit 0
