#!/usr/bin/env bash
# ═══════════════════════════════════════════════════
# CDSI Bootstrap — WordPress Installer
# Downloads the latest WordPress, provisions it against the
# existing `cdsi` MySQL database (credentials from password/mysql.pass),
# and creates an admin user `cdsi` with a random 10-char password.
# The admin username/password are saved to password/wordpress.pass. A separate
# WordPress Application Password for CDSI Atlas is saved to
# password/wordpress-atlas.pass so it can be revoked independently.
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
# shellcheck source=../lib/wordpress-access.sh
source "${CDSI_ROOT}/lib/wordpress-access.sh"
PASS_DIR="${CDSI_ROOT}/password"
MYSQL_PASS_FILE="${PASS_DIR}/mysql.pass"
WP_PASS_FILE="${PASS_DIR}/wordpress.pass"
WP_ATLAS_PASS_FILE="${PASS_DIR}/wordpress-atlas.pass"
CHECKSUM_FILE="${CDSI_ROOT}/SHA256SUMS"

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
    SERVER_IP="$(cdsi_resolve_wordpress_server_ip)"
    [[ -n "$SERVER_IP" ]] || fail "Could not determine the server IP. Set CDSI_SERVER_IP and run again."
    WP_URL="http://${SERVER_IP}"
fi
WP_TITLE="CDSI Node"
WP_ADMIN_USER="cdsi"
WP_ADMIN_EMAIL="admin@cdsi.local"
WP_ATLAS_APP_NAME="CDSI Atlas"
# Stable UUIDv5 for the canonical CDSI Atlas application URL.
WP_ATLAS_APP_ID="3549dd9a-23b7-5dbb-a9ef-78f9537c69ac"

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

# ── Checksum-verified artifact downloads ───────────────────
checksum_for_artifact() {
    local artifact="$1"
    local -a matches=()

    if [[ ! -r "$CHECKSUM_FILE" ]]; then
        log_fail "Checksum file not found: ${CHECKSUM_FILE}"
        return 1
    fi
    mapfile -t matches < <(
        awk -v artifact="$artifact" '$2 == artifact { print tolower($1) }' \
            "$CHECKSUM_FILE"
    )
    if [[ ${#matches[@]} -ne 1 ]]; then
        log_fail "Expected exactly one SHA-256 entry for ${artifact} in ${CHECKSUM_FILE}."
        return 1
    fi
    if [[ ! "${matches[0]}" =~ ^[0-9a-f]{64}$ ]]; then
        log_fail "Invalid SHA-256 entry for ${artifact} in ${CHECKSUM_FILE}."
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}

download_verified_artifact() {
    local destination="$1"
    local artifact="$2"
    shift 2

    command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required."

    local expected actual url
    if ! expected="$(checksum_for_artifact "$artifact")"; then
        return 1
    fi
    if ! rm -f -- "$destination"; then
        log_fail "Could not prepare the download path for ${artifact}."
        return 1
    fi
    local partial
    if ! partial="$(mktemp "${destination}.part.XXXXXX")"; then
        log_fail "Could not create a secure temporary file for ${artifact}."
        return 1
    fi

    for url in "$@"; do
        log "Downloading ${artifact} from ${url}..."
        if curl -fsSL --retry 2 --connect-timeout 15 --max-time 900 \
            --speed-limit 1024 --speed-time 60 \
            -o "$partial" "$url" 2>/dev/null; then
            if ! actual="$(sha256sum "$partial" 2>/dev/null | awk '{print tolower($1)}')"; then
                log_fail "Could not calculate SHA-256 for ${artifact} from ${url}."
                continue
            fi
            if [[ "$actual" == "$expected" ]]; then
                if ! mv -f -- "$partial" "$destination"; then
                    log_fail "Could not finalize the verified ${artifact} download."
                    rm -f -- "$partial" 2>/dev/null || true
                    return 1
                fi
                log_ok "SHA-256 verified for ${artifact}."
                return 0
            fi
            log_fail "SHA-256 mismatch for ${artifact} from ${url}; rejecting download."
        else
            log_fail "Download failed for ${artifact} from ${url}."
        fi
    done

    rm -f -- "$partial" 2>/dev/null || true
    return 1
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
    log "Installing checksum-verified wp-cli..."
    # The domestic CDN is intentionally HTTP; SHA256SUMS pins the trusted bytes.
    # HTTPS mirrors remain available when the CDN cannot be reached.
    local urls=(
        "http://cdn.aicsi.cn/packages/wp-cli.phar"
        "https://cdn.jsdelivr.net/gh/wp-cli/builds@gh-pages/phar/wp-cli.phar"
        "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
    )
    local download_dir downloaded_phar
    download_dir="$(mktemp -d "${TMPDIR:-/tmp}/cdsi-wpcli.XXXXXX")" \
        || fail "Could not create a secure wp-cli download directory."
    downloaded_phar="${download_dir}/wp-cli.phar"
    if ! download_verified_artifact "$downloaded_phar" wp-cli.phar "${urls[@]}"; then
        rm -rf -- "$download_dir"
        fail "Failed to download a checksum-verified wp-cli phar."
    fi
    if ! ${SUDO} install -m 0755 "$downloaded_phar" /usr/local/bin/wp; then
        rm -rf -- "$download_dir"
        fail "wp-cli install failed."
    fi
    if ! rm -rf -- "$download_dir"; then
        log_fail "Could not remove the temporary wp-cli download directory: ${download_dir}"
    fi
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
WP_PACKAGE_NAME="wordpress-7.0.4-zh_CN.zip"
WP_PACKAGE_URLS=(
    "http://cdn.aicsi.cn/packages/${WP_PACKAGE_NAME}"
    "https://cn.wordpress.org/${WP_PACKAGE_NAME}"
)

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

    log "Downloading checksum-verified WordPress (zh_CN) package..."
    local download_dir archive extract_dir
    download_dir="$(mktemp -d "${TMPDIR:-/tmp}/cdsi-wordpress.XXXXXX")" \
        || fail "Could not create a secure WordPress download directory."
    archive="${download_dir}/${WP_PACKAGE_NAME}"
    extract_dir="${download_dir}/extracted"
    if ! mkdir "$extract_dir"; then
        rm -rf -- "$download_dir"
        fail "Could not create the WordPress extraction directory."
    fi
    if ! download_verified_artifact "$archive" "$WP_PACKAGE_NAME" \
        "${WP_PACKAGE_URLS[@]}"; then
        rm -rf -- "$download_dir"
        fail "Failed to download a checksum-verified WordPress package."
    fi
    if ! unzip -q -o "$archive" -d "$extract_dir"; then
        rm -rf -- "$download_dir"
        fail "Failed to extract WordPress zip package."
    fi
    if ! ${SUDO} mkdir -p "$WEB_ROOT" "$WP_DIR"; then
        rm -rf -- "$download_dir"
        fail "Failed to prepare the WordPress web root."
    fi

    # Most WordPress builds (including the official one) nest files under a
    # 'wordpress/' directory; fall back to the flat layout if not present.
    if [[ -d "${extract_dir}/wordpress" ]]; then
        if ! ${SUDO} cp -a "${extract_dir}/wordpress/." "$WP_DIR"/; then
            rm -rf -- "$download_dir"
            fail "Failed to copy WordPress files to ${WP_DIR}."
        fi
    else
        if ! ${SUDO} cp -a "${extract_dir}/." "$WP_DIR"/; then
            rm -rf -- "$download_dir"
            fail "Failed to copy WordPress files to ${WP_DIR}."
        fi
    fi

    if ! rm -rf -- "$download_dir"; then
        log_fail "Could not remove the temporary WordPress download directory: ${download_dir}"
    fi
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
    if ${SUDO} wp --path="$WP_DIR" core is-installed --allow-root >/dev/null 2>&1; then
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
# 5) CDSI Atlas Application Password
# ══════════════════════════════════════════════════════════
read_atlas_credential() {
    local key="$1"
    [[ -f "$WP_ATLAS_PASS_FILE" ]] || return 0
    ${SUDO} awk -v prefix="${key}:" \
        'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' \
        "$WP_ATLAS_PASS_FILE" 2>/dev/null || true
}

write_atlas_credentials() {
    local application_uuid="$1"
    local application_password="$2"
    local temp_file=""
    local destination_temp=""
    local credential_owner=""

    credential_owner="$(id -u):$(id -g)"

    if ! temp_file="$(mktemp)"; then
        return 1
    fi
    if ! chmod 600 "$temp_file"; then
        rm -f "$temp_file" || true
        return 1
    fi
    if ! {
        printf 'user:%s\n' "$WP_ADMIN_USER"
        printf 'name:%s\n' "$WP_ATLAS_APP_NAME"
        printf 'app_id:%s\n' "$WP_ATLAS_APP_ID"
        printf 'uuid:%s\n' "$application_uuid"
        printf 'pass:%s\n' "$application_password"
    } > "$temp_file"; then
        rm -f "$temp_file" || true
        return 1
    fi

    if ! ${SUDO} mkdir -p "$PASS_DIR"; then
        rm -f "$temp_file" || true
        return 1
    fi
    if ! destination_temp="$(${SUDO} mktemp "${WP_ATLAS_PASS_FILE}.tmp.XXXXXX")"; then
        rm -f "$temp_file" || true
        return 1
    fi
    if ! ${SUDO} install -m 600 "$temp_file" "$destination_temp"; then
        rm -f "$temp_file" || true
        ${SUDO} rm -f "$destination_temp" || true
        return 1
    fi
    if ! ${SUDO} chown "$credential_owner" "$destination_temp"; then
        rm -f "$temp_file" || true
        ${SUDO} rm -f "$destination_temp" || true
        return 1
    fi
    if ! ${SUDO} mv -f -- "$destination_temp" "$WP_ATLAS_PASS_FILE"; then
        rm -f "$temp_file" || true
        ${SUDO} rm -f "$destination_temp" || true
        return 1
    fi

    rm -f "$temp_file" || true
    return 0
}

revoke_atlas_application_password() {
    local application_uuid="$1"
    [[ -n "$application_uuid" ]] || return 1
    ${SUDO} wp --path="$WP_DIR" user application-password delete \
        "$WP_ADMIN_USER" "$application_uuid" --allow-root >/dev/null 2>&1
}

ensure_atlas_application_password() {
    local stored_user=""
    local stored_name=""
    local stored_app_id=""
    local stored_uuid=""
    local stored_password=""
    local actual_uuid=""
    local actual_name=""
    local application_password=""
    local application_password_valid=false
    local uuid_output=""
    local fallback_uuid=""
    local -a matching_uuids=()

    ${SUDO} wp --path="$WP_DIR" user get "$WP_ADMIN_USER" --field=ID --allow-root \
        >/dev/null 2>&1 || fail "WordPress admin user '${WP_ADMIN_USER}' was not found."

    if ! uuid_output="$(${SUDO} wp --path="$WP_DIR" user application-password list \
        "$WP_ADMIN_USER" --app_id="$WP_ATLAS_APP_ID" --field=uuid \
        --allow-root --no-color)"; then
        fail "Failed to inspect existing WordPress Application Passwords."
    fi
    while IFS= read -r actual_uuid; do
        [[ -n "$actual_uuid" ]] && matching_uuids+=("$actual_uuid")
    done <<< "$uuid_output"

    (( ${#matching_uuids[@]} <= 1 )) \
        || fail "Multiple WordPress Application Passwords use the CDSI Atlas app_id. Refusing to choose or rotate automatically."

    if (( ${#matching_uuids[@]} == 1 )); then
        actual_uuid="${matching_uuids[0]}"
        actual_name="$(${SUDO} wp --path="$WP_DIR" user application-password get \
            "$WP_ADMIN_USER" "$actual_uuid" --field=name --allow-root 2>/dev/null || true)"
        stored_user="$(read_atlas_credential user)"
        stored_name="$(read_atlas_credential name)"
        stored_app_id="$(read_atlas_credential app_id)"
        stored_uuid="$(read_atlas_credential uuid)"
        stored_password="$(read_atlas_credential pass)"

        if [[ -z "$stored_password" || -z "$stored_uuid" ]]; then
            fail "Application Password '${WP_ATLAS_APP_NAME}' already exists, but its plaintext credentials are missing from ${WP_ATLAS_PASS_FILE}. WordPress cannot recover them; explicitly rotate the credential, then re-run."
        fi
        if [[ "$actual_name" != "$WP_ATLAS_APP_NAME" \
            || "$stored_user" != "$WP_ADMIN_USER" \
            || "$stored_name" != "$WP_ATLAS_APP_NAME" \
            || "$stored_app_id" != "$WP_ATLAS_APP_ID" \
            || "$stored_uuid" != "$actual_uuid" ]]; then
            fail "Stored CDSI Atlas credentials do not match the existing WordPress Application Password. Refusing to rotate it automatically."
        fi

        log "CDSI Atlas Application Password already exists; keeping stored credentials."
        return 0
    fi

    if ${SUDO} wp --path="$WP_DIR" user application-password exists \
        "$WP_ADMIN_USER" "$WP_ATLAS_APP_NAME" --allow-root >/dev/null 2>&1; then
        fail "An Application Password named '${WP_ATLAS_APP_NAME}' already exists with a different app_id. Refusing to replace it automatically."
    fi

    log "Creating WordPress Application Password for ${WP_ATLAS_APP_NAME}..."
    if ! application_password="$(${SUDO} wp --path="$WP_DIR" user application-password create \
        "$WP_ADMIN_USER" "$WP_ATLAS_APP_NAME" --app-id="$WP_ATLAS_APP_ID" \
        --porcelain --allow-root --no-color)"; then
        fail "Failed to create the CDSI Atlas Application Password."
    fi
    if [[ "$application_password" =~ ^[A-Za-z0-9]{24}$ ]]; then
        application_password_valid=true
    fi

    matching_uuids=()
    if uuid_output="$(${SUDO} wp --path="$WP_DIR" user application-password list \
        "$WP_ADMIN_USER" --app_id="$WP_ATLAS_APP_ID" --field=uuid \
        --allow-root --no-color)"; then
        while IFS= read -r actual_uuid; do
            [[ -n "$actual_uuid" ]] && matching_uuids+=("$actual_uuid")
        done <<< "$uuid_output"
    fi
    if (( ${#matching_uuids[@]} != 1 )); then
        fallback_uuid="$(${SUDO} wp --path="$WP_DIR" user application-password list \
            "$WP_ADMIN_USER" --name="$WP_ATLAS_APP_NAME" --field=uuid \
            --allow-root 2>/dev/null | head -n1 || true)"
        if [[ -n "$fallback_uuid" ]] \
            && revoke_atlas_application_password "$fallback_uuid"; then
            fail "The new CDSI Atlas Application Password could not be verified and was revoked."
        fi
        fail "The new CDSI Atlas Application Password could not be verified or revoked automatically. Revoke '${WP_ATLAS_APP_NAME}' manually before re-running."
    fi
    actual_uuid="${matching_uuids[0]}"

    if [[ "$application_password_valid" != true ]]; then
        if revoke_atlas_application_password "$actual_uuid"; then
            fail "WordPress returned an invalid Application Password value; the new credential was revoked."
        fi
        fail "WordPress returned an invalid Application Password value, and UUID ${actual_uuid} could not be revoked automatically. Revoke it manually before re-running."
    fi

    if ! write_atlas_credentials "$actual_uuid" "$application_password"; then
        if revoke_atlas_application_password "$actual_uuid"; then
            fail "Failed to save CDSI Atlas credentials to ${WP_ATLAS_PASS_FILE}; the new Application Password was revoked."
        fi
        fail "Failed to save CDSI Atlas credentials, and the new Application Password could not be revoked automatically. Revoke UUID ${actual_uuid} manually."
    fi

    log_ok "CDSI Atlas Application Password saved to: ${WP_ATLAS_PASS_FILE} (mode 600)"
}

# ══════════════════════════════════════════════════════════
# 6) Nginx server block → php-fpm
# ══════════════════════════════════════════════════════════
configure_nginx() {
    local phpver sock site_name conf_path enabled_path tmpl_file
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

    # Use the site template from config/ — variables substituted at install
    # time. Template uses {{WP_DOMAIN}}/{{WP_DIR}}/{{PHP_SOCK}} placeholders
    # (not $VAR, to avoid clashing with nginx's own $uri/$args variables).
    tmpl_file="${CDSI_ROOT}/config/nginx-site.conf.template"
    if [[ ! -f "$tmpl_file" ]]; then
        fail "Nginx site template not found: ${tmpl_file}"
    fi
    log "  Using site template: ${tmpl_file}"
    sed -e "s|{{WP_DOMAIN}}|${WP_DOMAIN:-_}|g" \
        -e "s|{{WP_DIR}}|${WP_DIR}|g" \
        -e "s|{{PHP_SOCK}}|${sock}|g" \
        "$tmpl_file" | ${SUDO} tee "$conf_path" >/dev/null
    ${SUDO} ln -sf "$conf_path" "$enabled_path"

    # Disable the stock 'default' site once our domain block is enabled. The
    # default site ships with a catch-all server_name (_) and, if certbot ever
    # injected a TLS block into it, a duplicate server_name <domain> would
    # cause "conflicting server name ... ignored" and break the domain config.
    # Removing it keeps this block the sole handler for the domain.
    if [[ "$(basename "$enabled_path")" != "default" ]]; then
        ${SUDO} rm -f /etc/nginx/sites-enabled/default
    fi

    ${SUDO} nginx -t || fail "nginx -t failed; server block has errors."
    ${SUDO} systemctl reload nginx || fail "Failed to reload nginx."
    log_ok "Nginx reloaded with WordPress server block (${site_name}.conf)."
}

# ── Align WordPress site URL with the configured WP_URL ──
set_site_url() {
    if ${SUDO} wp --path="$WP_DIR" core is-installed --allow-root >/dev/null 2>&1; then
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
    # Pass the domain + admin email through so a re-run does not hang on the
    # interactive email prompt (install-certbot.sh also self-skips if a live
    # cert for this domain already exists).
    if CDSI_DOMAIN="${WP_DOMAIN}" CDSI_CERT_EMAIL="${CDSI_CERT_EMAIL:-}" bash "$cert_script"; then
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
    if [[ -f "${WP_DIR}/wp-config.php" ]]; then
        ${SUDO} chmod 600 "${WP_DIR}/wp-config.php" \
            || fail "Failed to secure ${WP_DIR}/wp-config.php."
    fi
}

# ── Main ───────────────────────────────────────────────────
log "=== CDSI WordPress Installer ==="

provision_php
download_wordpress
write_wp_config
install_core
ensure_atlas_application_password
set_site_url
configure_nginx
fix_ownership
maybe_issue_cert

# ── Summary ────────────────────────────────────────────────
log_ok "WordPress installation complete."
FINAL_WP_URL="$(cdsi_resolve_wordpress_url "$WP_DIR" "$WP_DOMAIN" "$WP_URL")"
log "  Version:   $(${SUDO} wp --path="$WP_DIR" core version --allow-root 2>/dev/null || echo unknown)"
log "  URL:       ${FINAL_WP_URL}"
[[ -n "${WP_DOMAIN:-}" ]] && log "  Domain:    ${WP_DOMAIN} (Certbot SSL attempted)"
log "  Web root:  ${WP_DIR}"
log "  DB:        ${DB_NAME} (user ${DB_USER})"
log "  Admin:     ${WP_ADMIN_USER}"
log "  WP pass:   ${WP_PASS_FILE} (mode 600)"
log "  Atlas:     ${WP_ATLAS_PASS_FILE} (mode 600)"
log "  Login:     ${FINAL_WP_URL}/wp-admin/"

# The full install prints this once in its final verification report. Standalone
# and single-component runs print it here as their final step.
if [[ "${CDSI_INSTALL_CONTEXT:-standalone}" != "all" ]]; then
    cdsi_print_wordpress_access "$FINAL_WP_URL" "$WP_PASS_FILE" \
        "$WP_ADMIN_USER" "$WP_ATLAS_PASS_FILE" "$WP_DOMAIN"
fi

exit 0
