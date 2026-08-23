#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    _cdsi_script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
    exec /bin/sh "${_cdsi_script_dir}/../../lib/bootstrap.sh" \
        "${_cdsi_script_dir}/$(basename "$0")" "$@"
fi
# ═══════════════════════════════════════════════════
# CDSI Anchor — WordPress Installer
# Downloads the latest WordPress, provisions it against the
# existing `cdsi` MySQL database (credentials from password/mysql.pass),
# and creates an admin user `cdsi` with a random 10-char password.
# The admin username/password are saved to password/wordpress.pass. A separate
# WordPress Application Password for CDSI Beacon is saved to
# password/wordpress-beacon.pass so it can be revoked independently. Existing
# password/wordpress-atlas.pass credentials remain supported after the rename.
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
CDSI_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../lib/platform.sh
source "${CDSI_ROOT}/lib/platform.sh"
# shellcheck source=../../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"
# shellcheck source=../../lib/dnf.sh
source "${CDSI_ROOT}/lib/dnf.sh"
# shellcheck source=../../lib/packages.sh
source "${CDSI_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/services.sh
source "${CDSI_ROOT}/lib/services.sh"
# shellcheck source=../../lib/common.sh
source "${CDSI_ROOT}/lib/common.sh"
# shellcheck source=../../lib/wordpress-access.sh
source "${CDSI_ROOT}/lib/wordpress-access.sh"
# shellcheck source=../../lib/domain.sh
source "${CDSI_ROOT}/lib/domain.sh"
cdsi_platform_init
cdsi_platform_supported \
    || fail "Unsupported operating system. Anchor supports Ubuntu 24.04/26.04 LTS and CentOS Stream 10."
PASS_DIR="${CDSI_ROOT}/password"
MYSQL_PASS_FILE="${PASS_DIR}/mysql.pass"
WP_PASS_FILE="${PASS_DIR}/wordpress.pass"
WP_BEACON_PASS_FILE="${PASS_DIR}/wordpress-beacon.pass"
WP_LEGACY_ATLAS_PASS_FILE="${PASS_DIR}/wordpress-atlas.pass"
if [[ ! -f "$WP_BEACON_PASS_FILE" && -f "$WP_LEGACY_ATLAS_PASS_FILE" ]]; then
    WP_BEACON_PASS_FILE="$WP_LEGACY_ATLAS_PASS_FILE"
fi
CHECKSUM_FILE="${CDSI_ROOT}/SHA256SUMS"
CDSI_DOMAIN_FILE="${CDSI_DOMAIN_FILE:-${CDSI_ROOT}/config/domain}"
CDSI_PENDING_DOMAIN_FILE="${CDSI_PENDING_DOMAIN_FILE:-${CDSI_ROOT}/config/domain.pending}"

WEB_ROOT="/var/www"
WP_DIR="${CDSI_WORDPRESS_DIR:-${WEB_ROOT}/wordpress}"
# Nginx site-block path is computed inside configure_nginx() as <domain>.conf
# (falls back to 'wordpress.conf' when no domain is set), so the file name is
# unified as the domain instead of a generic 'wordpress'.

DB_NAME="cdsi"
DB_USER="cdsi"

# ── Resolve site domain (optional) ──────────────────────
# Precedence: CDSI_DOMAIN env → verified config/domain file → IP fallback.
# When set, Nginx server_name points at it and Certbot can issue TLS.
DOMAIN_FROM_ACTIVE_STATE=false
if [[ "${CDSI_FORCE_IP:-false}" == true ]]; then
    CDSI_DOMAIN=""
fi
if [[ "${CDSI_FORCE_IP:-false}" != true \
   && -z "${CDSI_DOMAIN:-}" && -f "$CDSI_DOMAIN_FILE" ]]; then
    CDSI_DOMAIN="$(cdsi_domain_state_read "$CDSI_DOMAIN_FILE" 2>/dev/null || true)"
    DOMAIN_FROM_ACTIVE_STATE=true
fi
SITE_SCHEME="${CDSI_SITE_SCHEME:-}"
if [[ -n "${CDSI_DOMAIN:-}" ]]; then
    CDSI_DOMAIN="$(cdsi_normalize_domain_list "$CDSI_DOMAIN")" \
        || fail "Invalid CDSI_DOMAIN. Use DNS hostnames only; paths, wildcards, IP addresses, and shell characters are not allowed."
    WP_DOMAIN="$(printf '%s' "${CDSI_DOMAIN}" | awk -F'[, ]' '{print $1}')"
    SERVER_IP="$(cdsi_resolve_wordpress_server_ip "$WP_DIR" || true)"
    [[ -n "$SERVER_IP" ]] || fail "Could not determine the server IP. Set CDSI_SERVER_IP and run again."
    if [[ "${CDSI_DNS_VERIFIED:-false}" != true \
       && "$DOMAIN_FROM_ACTIVE_STATE" != true ]]; then
        cdsi_ensure_dns_tools \
            || fail "Could not install the system DNS query tool required for domain validation."
        if cdsi_domain_dns_ready "$CDSI_DOMAIN" "$SERVER_IP"; then
            CDSI_DNS_VERIFIED=true
        elif [[ "${CDSI_WORDPRESS_CONFIGURE_ONLY:-false}" == true \
             || -f "${WP_DIR}/wp-load.php" ]]; then
            fail "${CDSI_DNS_MESSAGE} The existing site was not changed."
        else
            cdsi_domain_state_write "$CDSI_PENDING_DOMAIN_FILE" "$CDSI_DOMAIN" \
                || fail "${CDSI_DNS_MESSAGE} The pending domain could not be saved."
            log_fail "${CDSI_DNS_MESSAGE} Saved as pending; continuing in IP mode."
            CDSI_DOMAIN=""
            WP_DOMAIN=""
        fi
    fi
fi
if [[ -n "${WP_DOMAIN:-}" ]]; then
    TARGET_HOST="$WP_DOMAIN"
else
    WP_DOMAIN=""
    SERVER_IP="${SERVER_IP:-$(cdsi_resolve_wordpress_server_ip "$WP_DIR" || true)}"
    [[ -n "$SERVER_IP" ]] || fail "Could not determine the server IP. Set CDSI_SERVER_IP and run again."
    TARGET_HOST="$SERVER_IP"
fi
if [[ -z "$SITE_SCHEME" ]]; then
    SITE_SCHEME="http"
    if command -v wp >/dev/null 2>&1 && [[ -f "${WP_DIR}/wp-load.php" ]]; then
        EXISTING_WP_URL="$(${SUDO} wp --path="$WP_DIR" option get home \
            --allow-root 2>/dev/null || true)"
        if [[ "$EXISTING_WP_URL" == https://* ]]; then
            EXISTING_WP_HOST="${EXISTING_WP_URL#https://}"
            EXISTING_WP_HOST="${EXISTING_WP_HOST%%/*}"
            EXISTING_WP_HOST="${EXISTING_WP_HOST%%:*}"
            [[ "$EXISTING_WP_HOST" != "$TARGET_HOST" ]] || SITE_SCHEME="https"
        fi
    fi
fi
[[ "$SITE_SCHEME" == "http" || "$SITE_SCHEME" == "https" ]] \
    || fail "CDSI_SITE_SCHEME must be http or https."
WP_URL="${SITE_SCHEME}://${TARGET_HOST}"
if [[ -n "${WP_DOMAIN:-}" ]]; then
    log "Domain provided: ${WP_DOMAIN} (site URL → ${WP_URL})"
fi
WP_TITLE="CDSI Node"
WP_ADMIN_USER="cdsi"
WP_ADMIN_EMAIL="admin@cdsi.local"
WP_BEACON_APP_NAME="CDSI Beacon"
WP_LEGACY_ATLAS_APP_NAME="CDSI Atlas"
# Keep the Atlas-era app_id so upgraded nodes reuse the existing credential.
WP_BEACON_APP_ID="3549dd9a-23b7-5dbb-a9ef-78f9537c69ac"

# ── Read cdsi DB password from password/mysql.pass ────────
[[ -f "$MYSQL_PASS_FILE" ]] || fail "MySQL credential file not found: ${MYSQL_PASS_FILE}. Run install-mysql.sh first."
DB_PASSWORD="$(grep '^cdsi:' "$MYSQL_PASS_FILE" 2>/dev/null | cut -d: -f2-)"
[[ -n "$DB_PASSWORD" ]] || fail "cdsi password not found in ${MYSQL_PASS_FILE}."

# ── Password Generation (10-char alphanumeric) ─────────────
generate_password() {
    local pw
    pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || true)"
    [[ ${#pw} -eq 10 ]] || fail "Failed to generate 10-char password."
    echo "$pw"
}

# ── Detect PHP-FPM version installed ──────────────────────
detect_php_fpm() {
    # Resolve the actual FPM version, not a potentially customized `php`
    # alternative that may point to a different CLI version.
    cdsi_php_fpm_version 2>/dev/null || true
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

    if ! command -v sha256sum >/dev/null 2>&1; then
        fail "sha256sum is required."
    fi

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
        if cdsi_download_file "$partial" "$url" 2>/dev/null; then
            if ! actual="$(cdsi_sha256_file "$partial" 2>/dev/null)"; then
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
    local phpver="" fpm_service=""

    # Always reconcile through the component installer. Its package and
    # extension checks are the source of truth for both fresh and partial
    # installations; a php/mysqli-only shortcut can miss required modules.
    log "Reconciling PHP-FPM and required extensions through install-php.sh..."
    bash "${CDSI_ROOT}/scripts/install-php.sh" \
        || fail "PHP-FPM installation failed."

    install_wpcli

    phpver="$(detect_php_fpm)"
    [[ -n "$phpver" ]] || fail "Could not determine PHP version after installation."
    fpm_service="$(cdsi_php_service_name "$phpver")"
    cdsi_service_enable "$fpm_service" \
        || fail "Could not enable ${fpm_service} at boot."

    # A partial installation may have added extensions while FPM was already
    # active. Restart once so the web runtime, not only the CLI, loads them.
    cdsi_service_restart "$fpm_service" \
        || fail "Could not restart ${fpm_service} after PHP reconciliation."
    cdsi_service_active "$fpm_service" \
        || fail "${fpm_service} is not active."
    php -m | grep -qi '^mysqli$' \
        || fail "The required PHP mysqli extension is unavailable."
    PHP_FPM_VER="$phpver"

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
        cdsi_packages_update \
            || log "Package metadata update failed after retries; continuing with cached metadata..."
        cdsi_packages_install unzip \
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
# 5) CDSI Beacon Application Password
# ══════════════════════════════════════════════════════════
read_beacon_credential() {
    local key="$1"
    [[ -f "$WP_BEACON_PASS_FILE" ]] || return 0
    ${SUDO} awk -v prefix="${key}:" \
        'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' \
        "$WP_BEACON_PASS_FILE" 2>/dev/null || true
}

write_beacon_credentials() {
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
        printf 'name:%s\n' "$WP_BEACON_APP_NAME"
        printf 'app_id:%s\n' "$WP_BEACON_APP_ID"
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
    if ! destination_temp="$(${SUDO} mktemp "${WP_BEACON_PASS_FILE}.tmp.XXXXXX")"; then
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
    if ! ${SUDO} mv -f -- "$destination_temp" "$WP_BEACON_PASS_FILE"; then
        rm -f "$temp_file" || true
        ${SUDO} rm -f "$destination_temp" || true
        return 1
    fi

    rm -f "$temp_file" || true
    return 0
}

revoke_beacon_application_password() {
    local application_uuid="$1"
    [[ -n "$application_uuid" ]] || return 1
    ${SUDO} wp --path="$WP_DIR" user application-password delete \
        "$WP_ADMIN_USER" "$application_uuid" --allow-root >/dev/null 2>&1
}

is_supported_beacon_app_name() {
    [[ "$1" == "$WP_BEACON_APP_NAME" || "$1" == "$WP_LEGACY_ATLAS_APP_NAME" ]]
}

ensure_beacon_application_password() {
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
        "$WP_ADMIN_USER" --app_id="$WP_BEACON_APP_ID" --field=uuid \
        --allow-root --no-color)"; then
        fail "Failed to inspect existing WordPress Application Passwords."
    fi
    while IFS= read -r actual_uuid; do
        [[ -n "$actual_uuid" ]] && matching_uuids+=("$actual_uuid")
    done <<< "$uuid_output"

    (( ${#matching_uuids[@]} <= 1 )) \
        || fail "Multiple WordPress Application Passwords use the CDSI Beacon app_id. Refusing to choose or rotate automatically."

    if (( ${#matching_uuids[@]} == 1 )); then
        actual_uuid="${matching_uuids[0]}"
        actual_name="$(${SUDO} wp --path="$WP_DIR" user application-password get \
            "$WP_ADMIN_USER" "$actual_uuid" --field=name --allow-root 2>/dev/null || true)"
        stored_user="$(read_beacon_credential user)"
        stored_name="$(read_beacon_credential name)"
        stored_app_id="$(read_beacon_credential app_id)"
        stored_uuid="$(read_beacon_credential uuid)"
        stored_password="$(read_beacon_credential pass)"

        if [[ -z "$stored_password" || -z "$stored_uuid" ]]; then
            fail "Application Password '${actual_name:-$WP_BEACON_APP_NAME}' already exists, but its plaintext credentials are missing from ${WP_BEACON_PASS_FILE}. WordPress cannot recover them; explicitly rotate the credential, then re-run."
        fi
        if ! is_supported_beacon_app_name "$actual_name" \
            || ! is_supported_beacon_app_name "$stored_name" \
            || [[ "$stored_user" != "$WP_ADMIN_USER" \
                || "$stored_app_id" != "$WP_BEACON_APP_ID" \
                || "$stored_uuid" != "$actual_uuid" ]]; then
            fail "Stored CDSI Beacon credentials do not match the existing WordPress Application Password. Refusing to rotate it automatically."
        fi

        log "CDSI Beacon Application Password already exists; keeping stored credentials."
        return 0
    fi

    if ${SUDO} wp --path="$WP_DIR" user application-password exists \
        "$WP_ADMIN_USER" "$WP_BEACON_APP_NAME" --allow-root >/dev/null 2>&1 \
        || ${SUDO} wp --path="$WP_DIR" user application-password exists \
            "$WP_ADMIN_USER" "$WP_LEGACY_ATLAS_APP_NAME" --allow-root >/dev/null 2>&1; then
        fail "A Beacon or legacy Atlas Application Password already exists with a different app_id. Refusing to replace it automatically."
    fi

    log "Creating WordPress Application Password for ${WP_BEACON_APP_NAME}..."
    if ! application_password="$(${SUDO} wp --path="$WP_DIR" user application-password create \
        "$WP_ADMIN_USER" "$WP_BEACON_APP_NAME" --app-id="$WP_BEACON_APP_ID" \
        --porcelain --allow-root --no-color)"; then
        fail "Failed to create the CDSI Beacon Application Password."
    fi
    if [[ "$application_password" =~ ^[A-Za-z0-9]{24}$ ]]; then
        application_password_valid=true
    fi

    matching_uuids=()
    if uuid_output="$(${SUDO} wp --path="$WP_DIR" user application-password list \
        "$WP_ADMIN_USER" --app_id="$WP_BEACON_APP_ID" --field=uuid \
        --allow-root --no-color)"; then
        while IFS= read -r actual_uuid; do
            [[ -n "$actual_uuid" ]] && matching_uuids+=("$actual_uuid")
        done <<< "$uuid_output"
    fi
    if (( ${#matching_uuids[@]} != 1 )); then
        fallback_uuid="$(${SUDO} wp --path="$WP_DIR" user application-password list \
            "$WP_ADMIN_USER" --name="$WP_BEACON_APP_NAME" --field=uuid \
            --allow-root 2>/dev/null | head -n1 || true)"
        if [[ -n "$fallback_uuid" ]] \
            && revoke_beacon_application_password "$fallback_uuid"; then
            fail "The new CDSI Beacon Application Password could not be verified and was revoked."
        fi
        fail "The new CDSI Beacon Application Password could not be verified or revoked automatically. Revoke '${WP_BEACON_APP_NAME}' manually before re-running."
    fi
    actual_uuid="${matching_uuids[0]}"

    if [[ "$application_password_valid" != true ]]; then
        if revoke_beacon_application_password "$actual_uuid"; then
            fail "WordPress returned an invalid Application Password value; the new credential was revoked."
        fi
        fail "WordPress returned an invalid Application Password value, and UUID ${actual_uuid} could not be revoked automatically. Revoke it manually before re-running."
    fi

    if ! write_beacon_credentials "$actual_uuid" "$application_password"; then
        if revoke_beacon_application_password "$actual_uuid"; then
            fail "Failed to save CDSI Beacon credentials to ${WP_BEACON_PASS_FILE}; the new Application Password was revoked."
        fi
        fail "Failed to save CDSI Beacon credentials, and the new Application Password could not be revoked automatically. Revoke UUID ${actual_uuid} manually."
    fi

    log_ok "CDSI Beacon Application Password saved to: ${WP_BEACON_PASS_FILE} (mode 600)"
}

# ══════════════════════════════════════════════════════════
# 6) Nginx server block → php-fpm
# ══════════════════════════════════════════════════════════
configure_nginx() {
    local phpver upstream site_name conf_path enabled_path tmpl_file server_name tls_include_dir
    local rendered_file="" staged_file="" rollback_dir=""
    local preserve_certbot=false restore_failed=0 index path backup
    local -a rollback_paths=() rollback_backups=() rollback_present=()

    _wordpress_nginx_is_managed() {
        local managed_path="$1"
        [[ -f "$managed_path" ]] \
            && grep -Fq '# CDSI WordPress site block' "$managed_path" 2>/dev/null
    }

    _wordpress_nginx_backup_path() {
        local target_path="$1"
        local existing_path=""
        for existing_path in "${rollback_paths[@]}"; do
            [[ "$existing_path" != "$target_path" ]] || return 0
        done

        backup="${rollback_dir}/${#rollback_paths[@]}"
        if [[ -e "$target_path" || -L "$target_path" ]]; then
            if ! ${SUDO} cp -a -- "$target_path" "$backup"; then
                return 1
            fi
            rollback_present+=(1)
        else
            rollback_present+=(0)
        fi
        rollback_paths+=("$target_path")
        rollback_backups+=("$backup")
    }

    _wordpress_nginx_restore() {
        restore_failed=0
        for ((index = ${#rollback_paths[@]} - 1; index >= 0; index--)); do
            path="${rollback_paths[$index]}"
            if ! ${SUDO} rm -rf -- "$path"; then
                restore_failed=1
                continue
            fi
            if [[ "${rollback_present[$index]}" == "1" ]] \
               && ! ${SUDO} cp -a -- "${rollback_backups[$index]}" "$path"; then
                restore_failed=1
            fi
        done
        [[ "$restore_failed" -eq 0 ]]
    }

    _wordpress_nginx_abort() {
        local reason="$1"
        rm -f -- "$rendered_file" 2>/dev/null || true
        [[ -z "$staged_file" ]] || ${SUDO} rm -f -- "$staged_file" 2>/dev/null || true
        if ! _wordpress_nginx_restore; then
            fail "${reason} Rollback was incomplete; backups remain in ${rollback_dir}."
        fi
        ${SUDO} nginx -t >/dev/null 2>&1 || true
        cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1 || true
        ${SUDO} rm -rf -- "$rollback_dir" 2>/dev/null || true
        fail "${reason} The previous Nginx configuration was restored."
    }

    phpver="$(detect_php_fpm)"
    upstream="$(cdsi_php_fpm_upstream "$phpver")"
    [[ -n "$upstream" ]] || fail "Could not determine the PHP-FPM upstream."

    # Unified site-block file name: <domain>.conf (or 'wordpress.conf' when no
    # domain is provided). Migrate away any legacy 'wordpress' block so the
    # name is consistent and there is exactly one WordPress server block.
    site_name="${WP_DOMAIN:-wordpress}"
    server_name="${CDSI_DOMAIN:-${WP_DOMAIN:-}}"
    server_name="${server_name//,/ }"
    [[ -n "$server_name" ]] || server_name="${SERVER_IP:-_}"
    conf_path="${CDSI_NGINX_SITE_DIR}/${site_name}.conf"
    enabled_path="${CDSI_NGINX_ENABLED_DIR}/${site_name}.conf"
    tls_include_dir="${CDSI_IP_TLS_DIR:-/etc/nginx/cdsi-wordpress-tls}"
    ${SUDO} mkdir -p "$CDSI_NGINX_SITE_DIR" "$CDSI_NGINX_ENABLED_DIR"
    ${SUDO} mkdir -p "$tls_include_dir" \
        || fail "Could not create the Anchor TLS include directory."

    log "Configuring Nginx server block (${site_name}.conf) → ${WP_DIR} (php-fpm ${phpver})..."

    # Use the site template from config/ — variables substituted at install
    # time. Template uses {{WP_DOMAIN}}/{{WP_DIR}}/{{PHP_UPSTREAM}} placeholders
    # (not $VAR, to avoid clashing with nginx's own $uri/$args variables).
    tmpl_file="${CDSI_ROOT}/config/nginx-site.conf.template"
    if [[ ! -f "$tmpl_file" ]]; then
        fail "Nginx site template not found: ${tmpl_file}"
    fi
    log "  Using site template: ${tmpl_file}"

    rendered_file="$(mktemp "${TMPDIR:-/tmp}/cdsi-wordpress-nginx.XXXXXX")" \
        || fail "Could not create a temporary Nginx site configuration."
    rollback_dir="$(mktemp -d "${TMPDIR:-/tmp}/cdsi-wordpress-nginx-rollback.XXXXXX")" \
        || { rm -f -- "$rendered_file"; fail "Could not create an Nginx rollback directory."; }
    if ! sed -e "s|{{WP_DOMAIN}}|${server_name}|g" \
        -e "s|{{WP_DIR}}|${WP_DIR}|g" \
        -e "s|{{PHP_UPSTREAM}}|${upstream}|g" \
        -e "s|{{TLS_INCLUDE_DIR}}|${tls_include_dir}|g" \
        "$tmpl_file" > "$rendered_file"; then
        ${SUDO} rm -rf -- "$rollback_dir" 2>/dev/null || true
        rm -f -- "$rendered_file"
        fail "Failed to render the Nginx WordPress site configuration."
    fi

    if [[ -e "$conf_path" || -L "$conf_path" ]]; then
        _wordpress_nginx_is_managed "$conf_path" \
            || { ${SUDO} rm -rf -- "$rollback_dir"; rm -f -- "$rendered_file"; fail "Refusing to overwrite non-Anchor Nginx configuration: ${conf_path}."; }
        if grep -q 'managed by Certbot' "$conf_path" 2>/dev/null; then
            preserve_certbot=true
            log "Preserving existing Certbot-managed TLS configuration in ${conf_path}."
        fi
    fi

    if [[ "$preserve_certbot" != true ]]; then
        _wordpress_nginx_backup_path "$conf_path" \
            || _wordpress_nginx_abort "Could not back up ${conf_path}."
        staged_file="$(${SUDO} mktemp "${conf_path}.tmp.XXXXXX")" \
            || _wordpress_nginx_abort "Could not stage ${conf_path}."
        if ! ${SUDO} install -m 0644 "$rendered_file" "$staged_file" \
           || ! ${SUDO} mv -f -- "$staged_file" "$conf_path"; then
            _wordpress_nginx_abort "Could not install ${conf_path}."
        fi
        staged_file=""
    fi

    if [[ "$enabled_path" != "$conf_path" ]]; then
        if [[ -e "$enabled_path" || -L "$enabled_path" ]]; then
            _wordpress_nginx_is_managed "$enabled_path" \
                || _wordpress_nginx_abort "Refusing to replace non-Anchor Nginx configuration: ${enabled_path}."
        fi
        _wordpress_nginx_backup_path "$enabled_path" \
            || _wordpress_nginx_abort "Could not back up ${enabled_path}."
        ${SUDO} ln -sfn "$conf_path" "$enabled_path" \
            || _wordpress_nginx_abort "Could not enable ${conf_path}."
    fi

    if [[ "${site_name}" != "wordpress" ]]; then
        local legacy_path=""
        for legacy_path in \
            "${CDSI_NGINX_SITE_DIR}/wordpress" \
            "${CDSI_NGINX_SITE_DIR}/wordpress.conf" \
            "${CDSI_NGINX_ENABLED_DIR}/wordpress" \
            "${CDSI_NGINX_ENABLED_DIR}/wordpress.conf"; do
            [[ "$legacy_path" != "$conf_path" && "$legacy_path" != "$enabled_path" ]] \
                || continue
            [[ -e "$legacy_path" || -L "$legacy_path" ]] || continue
            if ! _wordpress_nginx_is_managed "$legacy_path"; then
                log "Leaving non-Anchor legacy Nginx path unchanged: ${legacy_path}."
                continue
            fi
            _wordpress_nginx_backup_path "$legacy_path" \
                || _wordpress_nginx_abort "Could not back up ${legacy_path}."
            ${SUDO} rm -f -- "$legacy_path" \
                || _wordpress_nginx_abort "Could not remove legacy Anchor site ${legacy_path}."
        done
    fi

    # A standalone domain change may replace either an older domain-specific
    # site or the IP-mode wordpress.conf. Remove only Anchor-managed paths and
    # include every mutation in this function's rollback transaction.
    if [[ -n "${CDSI_PREVIOUS_DOMAIN:-}" ]]; then
        local previous_primary="${CDSI_PREVIOUS_DOMAIN%%,*}"
        local previous_path=""
        for previous_path in \
            "${CDSI_NGINX_SITE_DIR}/${previous_primary}.conf" \
            "${CDSI_NGINX_ENABLED_DIR}/${previous_primary}.conf"; do
            [[ "$previous_path" != "$conf_path" && "$previous_path" != "$enabled_path" ]] \
                || continue
            [[ -e "$previous_path" || -L "$previous_path" ]] || continue
            if ! _wordpress_nginx_is_managed "$previous_path"; then
                _wordpress_nginx_abort "Refusing to remove non-Anchor Nginx configuration: ${previous_path}."
            fi
            _wordpress_nginx_backup_path "$previous_path" \
                || _wordpress_nginx_abort "Could not back up ${previous_path}."
            ${SUDO} rm -f -- "$previous_path" \
                || _wordpress_nginx_abort "Could not remove the previous Anchor site ${previous_path}."
        done
    fi

    # Disable the stock 'default' site once our domain block is enabled. The
    # default site ships with a catch-all server_name (_) and, if certbot ever
    # injected a TLS block into it, a duplicate server_name <domain> would
    # cause "conflicting server name ... ignored" and break the domain config.
    # Removing it keeps this block the sole handler for the domain.
    if [[ "$(basename "$enabled_path")" != "default" ]]; then
        local default_path="${CDSI_NGINX_ENABLED_DIR}/default"
        if [[ -e "$default_path" || -L "$default_path" ]]; then
            _wordpress_nginx_backup_path "$default_path" \
                || _wordpress_nginx_abort "Could not back up ${default_path}."
            ${SUDO} rm -f -- "$default_path" \
                || _wordpress_nginx_abort "Could not disable the stock Nginx default site."
        fi
    fi

    ${SUDO} nginx -t \
        || _wordpress_nginx_abort "nginx -t failed for the staged WordPress site."
    cdsi_service_reload "$CDSI_NGINX_SERVICE" \
        || _wordpress_nginx_abort "Failed to reload Nginx with the staged WordPress site."
    if [[ -n "${CDSI_NGINX_POST_APPLY_FUNCTION:-}" ]]; then
        declare -F "$CDSI_NGINX_POST_APPLY_FUNCTION" >/dev/null 2>&1 \
            || _wordpress_nginx_abort "Unknown Nginx post-apply function: ${CDSI_NGINX_POST_APPLY_FUNCTION}."
        "$CDSI_NGINX_POST_APPLY_FUNCTION" \
            || _wordpress_nginx_abort "WordPress rejected the new site URL."
    fi

    rm -f -- "$rendered_file"
    ${SUDO} rm -rf -- "$rollback_dir"
    log_ok "Nginx reloaded with WordPress server block (${site_name}.conf)."
}

# ── Align WordPress site URL with the configured WP_URL ──
set_site_url() {
    local old_siteurl="" old_home="" actual_siteurl="" actual_home=""
    if ${SUDO} wp --path="$WP_DIR" core is-installed --allow-root >/dev/null 2>&1; then
        old_siteurl="$(${SUDO} wp --path="$WP_DIR" option get siteurl --allow-root 2>/dev/null || true)"
        old_home="$(${SUDO} wp --path="$WP_DIR" option get home --allow-root 2>/dev/null || true)"
        if ! ${SUDO} wp --path="$WP_DIR" option update siteurl "$WP_URL" --allow-root >/dev/null \
           || ! ${SUDO} wp --path="$WP_DIR" option update home "$WP_URL" --allow-root >/dev/null; then
            [[ -z "$old_siteurl" ]] || ${SUDO} wp --path="$WP_DIR" option update siteurl "$old_siteurl" --allow-root >/dev/null 2>&1 || true
            [[ -z "$old_home" ]] || ${SUDO} wp --path="$WP_DIR" option update home "$old_home" --allow-root >/dev/null 2>&1 || true
            log_fail "Failed to update the WordPress site URL; the previous values were restored."
            return 1
        fi
        actual_siteurl="$(${SUDO} wp --path="$WP_DIR" option get siteurl --allow-root 2>/dev/null || true)"
        actual_home="$(${SUDO} wp --path="$WP_DIR" option get home --allow-root 2>/dev/null || true)"
        if [[ "${actual_siteurl%/}" != "${WP_URL%/}" \
           || "${actual_home%/}" != "${WP_URL%/}" ]]; then
            [[ -z "$old_siteurl" ]] || ${SUDO} wp --path="$WP_DIR" option update siteurl "$old_siteurl" --allow-root >/dev/null 2>&1 || true
            [[ -z "$old_home" ]] || ${SUDO} wp --path="$WP_DIR" option update home "$old_home" --allow-root >/dev/null 2>&1 || true
            log_fail "WordPress did not retain the requested site URL; the previous values were restored."
            return 1
        fi
        log_ok "WordPress site URL set to ${WP_URL}."
    fi
}

# ── Issue a TLS certificate via Certbot when a domain is set ─
maybe_issue_cert() {
    [[ "${CDSI_SKIP_CERTBOT:-false}" != true ]] || return 0
    [[ -n "${WP_DOMAIN:-}" ]] || return 0
    local cert_script="${CDSI_ROOT}/scripts/install-certbot.sh"
    [[ -f "$cert_script" ]] || return 0
    log "Requesting TLS certificate for ${WP_DOMAIN} via Certbot..."
    # Pass the domain + admin email through so a re-run does not hang on the
    # interactive email prompt (install-certbot.sh also self-skips if a live
    # cert for this domain already exists).
    if CDSI_DOMAIN="${CDSI_DOMAIN}" CDSI_CERT_EMAIL="${CDSI_CERT_EMAIL:-}" bash "$cert_script"; then
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
    ${SUDO} chown -R "${CDSI_WEB_USER}:${CDSI_WEB_GROUP}" "$WP_DIR" 2>/dev/null || true
    ${SUDO} find "$WP_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    ${SUDO} find "$WP_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    if [[ -f "${WP_DIR}/wp-config.php" ]]; then
        ${SUDO} chmod 600 "${WP_DIR}/wp-config.php" \
            || fail "Failed to secure ${WP_DIR}/wp-config.php."
    fi
}

configure_selinux() {
    [[ "$CDSI_PLATFORM" == "centos-stream" ]] || return 0
    command -v getenforce >/dev/null 2>&1 || return 0
    [[ "$(getenforce 2>/dev/null || true)" != "Disabled" ]] || return 0

    if ! command -v semanage >/dev/null 2>&1; then
        log "Installing SELinux management tools..."
        cdsi_packages_install policycoreutils-python-utils \
            || fail "Failed to install SELinux management tools."
    fi

    local fcontext_pattern="${WP_DIR}(/.*)?"
    local fcontext_marker="/etc/cdsi/selinux-wordpress-fcontext"
    if ${SUDO} semanage fcontext -a -t httpd_sys_rw_content_t \
        "$fcontext_pattern" >/dev/null 2>&1; then
        if ! ${SUDO} mkdir -p /etc/cdsi \
           || ! printf '%s\n' "$fcontext_pattern" \
                | ${SUDO} tee "$fcontext_marker" >/dev/null \
           || ! ${SUDO} chmod 600 "$fcontext_marker"; then
            ${SUDO} semanage fcontext -d "$fcontext_pattern" \
                >/dev/null 2>&1 || true
            fail "Failed to record the Anchor-added SELinux file-context rule; the rule was rolled back."
        fi
    elif ! ${SUDO} semanage fcontext -l 2>/dev/null \
        | grep -F -- "$fcontext_pattern" \
        | grep -q 'httpd_sys_rw_content_t'; then
        fail "An incompatible SELinux file-context rule already owns ${fcontext_pattern}; it was not changed."
    fi
    ${SUDO} restorecon -RF "$WP_DIR" \
        || fail "Failed to apply the WordPress SELinux file context."

    local boolean_marker="/etc/cdsi/selinux-httpd-db-boolean"
    if command -v getsebool >/dev/null 2>&1 \
       && getsebool httpd_can_network_connect_db 2>/dev/null | grep -q -- '--> off'; then
        ${SUDO} setsebool -P httpd_can_network_connect_db on \
            || fail "Failed to allow the web runtime to connect to the database under SELinux."
        if ! ${SUDO} mkdir -p /etc/cdsi \
           || ! printf '%s\n' 'httpd_can_network_connect_db' \
                | ${SUDO} tee "$boolean_marker" >/dev/null \
           || ! ${SUDO} chmod 600 "$boolean_marker"; then
            ${SUDO} setsebool -P httpd_can_network_connect_db off \
                >/dev/null 2>&1 || true
            fail "Failed to record the Anchor-added SELinux boolean; the boolean was rolled back."
        fi
    fi
}

# ── Main ───────────────────────────────────────────────────
log "=== CDSI WordPress Installer ==="

if [[ "${CDSI_WORDPRESS_CONFIGURE_ONLY:-false}" == true ]]; then
    command -v wp >/dev/null 2>&1 \
        || fail "wp-cli is required for configure-only mode."
    [[ -f "${WP_DIR}/wp-load.php" ]] \
        || fail "WordPress is not installed at ${WP_DIR}."
    command -v nginx >/dev/null 2>&1 \
        || fail "Nginx is required for configure-only mode."
    [[ -n "$(detect_php_fpm)" ]] \
        || fail "PHP-FPM is required for configure-only mode."
    fix_ownership
    configure_selinux
    CDSI_NGINX_POST_APPLY_FUNCTION=set_site_url configure_nginx
    log_ok "WordPress domain configuration complete."
    log "  URL: ${WP_URL}"
    exit 0
fi

provision_php
download_wordpress
write_wp_config
install_core
ensure_beacon_application_password
CDSI_NGINX_POST_APPLY_FUNCTION=set_site_url configure_nginx
fix_ownership
configure_selinux
if [[ "${CDSI_INSTALL_CONTEXT:-standalone}" != "all" ]]; then
    maybe_issue_cert
fi

# ── Summary ────────────────────────────────────────────────
log_ok "WordPress installation complete."
FINAL_WP_URL="$(cdsi_resolve_wordpress_url "$WP_DIR" "$WP_DOMAIN" "$WP_URL")"
log "  Version:   $(${SUDO} wp --path="$WP_DIR" core version --allow-root 2>/dev/null || echo unknown)"
log "  URL:       ${FINAL_WP_URL}"
if [[ -n "${WP_DOMAIN:-}" ]]; then
    if [[ "${CDSI_INSTALL_CONTEXT:-standalone}" == "all" ]]; then
        log "  Domain:    ${WP_DOMAIN} (Certbot SSL scheduled after WordPress)"
    else
        log "  Domain:    ${WP_DOMAIN} (Certbot SSL attempted)"
    fi
fi
log "  Web root:  ${WP_DIR}"
log "  DB:        ${DB_NAME} (user ${DB_USER})"
log "  Admin:     ${WP_ADMIN_USER}"
log "  WP pass:   ${WP_PASS_FILE} (mode 600)"
log "  Beacon:    ${WP_BEACON_PASS_FILE} (mode 600)"
log "  Login:     ${FINAL_WP_URL}/wp-admin/"

# The full install prints this once in its final verification report. Standalone
# and single-component runs print it here as their final step.
if [[ "${CDSI_INSTALL_CONTEXT:-standalone}" != "all" ]]; then
    cdsi_print_wordpress_access "$FINAL_WP_URL" "$WP_PASS_FILE" \
        "$WP_ADMIN_USER" "$WP_BEACON_PASS_FILE" "$WP_DOMAIN"
fi

exit 0
