#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    _cdsi_script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
    exec /bin/sh "${_cdsi_script_dir}/../../lib/bootstrap.sh" \
        "${_cdsi_script_dir}/$(basename "$0")" "$@"
fi
# ═══════════════════════════════════════════════════
# CDSI Anchor — MySQL Installer
# Installs MySQL from the operating system's default package source.
# After install:
#   • Sets a password for the MySQL 'root'@'localhost' account
#     (auth method switched from auth_socket to caching_sha2_password).
#   • Creates database `cdsi` and user `cdsi`@localhost with a
#     random 10-char password.
#   • Saves both credentials to password/mysql.pass (mode 600),
#     one entry per line:  root:<password>  and  cdsi:<password>
#
# Idempotent: re-running detects the recorded passwords and
# skips when root/cdsi auth already works.
#
# Can be called by install.sh or run directly:
#   bash scripts/install-mysql.sh
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

# ── Paths ──────────────────────────────────────────────────
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
cdsi_platform_init
cdsi_platform_supported \
    || fail "Unsupported operating system. Anchor supports Ubuntu 24.04/26.04 LTS and CentOS Stream 10."

PASS_DIR="${CDSI_ROOT}/password"
PASS_FILE="${PASS_DIR}/mysql.pass"

DB_NAME="cdsi"
DB_USER="cdsi"
MYSQL_NETWORK_CONFIG_CHANGED=false

# ── Password Generation (10-char alphanumeric) ─────────────
generate_password() {
    local pw
    pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || true)"
    [[ ${#pw} -eq 10 ]] || fail "Failed to generate 10-char password."
    echo "$pw"
}

# ── Read a stored credential from the password file ───────
stored_cred() {
    # $1 = key (root|cdsi); echoes the value or nothing
    [[ -f "$PASS_FILE" ]] || return 0
    grep "^$1:" "$PASS_FILE" 2>/dev/null | cut -d: -f2- || true
}

write_credentials() {
    local root_password="$1"
    local cdsi_password="$2"
    local temp_file

    mkdir -p "$PASS_DIR" || return 1
    temp_file="$(mktemp "${PASS_FILE}.tmp.XXXXXX")" || return 1
    if ! {
        printf 'root:%s\n' "$root_password"
        printf 'cdsi:%s\n' "$cdsi_password"
    } > "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    chmod 600 "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    mv -f "$temp_file" "$PASS_FILE"
}

configure_mysql_network() {
    cdsi_is_centos_stream || return 0

    local config_file="/etc/my.cnf.d/zz-cdsi-anchor.cnf"
    local temp_file
    temp_file="$(mktemp "${TMPDIR:-/tmp}/cdsi-mysql-network.XXXXXX")" \
        || fail "Could not create a temporary MySQL network configuration."
    cat > "$temp_file" <<'MYSQL_NETWORK_CONFIG'
# Managed by CDSI Anchor. WordPress connects to MySQL on this host only.
[mysqld]
bind-address=127.0.0.1
mysqlx-bind-address=127.0.0.1
MYSQL_NETWORK_CONFIG

    if [[ -f "$config_file" ]]; then
        if cmp -s "$temp_file" "$config_file"; then
            rm -f -- "$temp_file"
            return 0
        fi
        rm -f -- "$temp_file"
        fail "Existing Anchor MySQL network configuration differs: ${config_file}. It was not overwritten."
    fi

    ${SUDO} install -m 0644 "$temp_file" "$config_file" \
        || { rm -f -- "$temp_file"; fail "Failed to install ${config_file}."; }
    rm -f -- "$temp_file"
    if ! ${SUDO} mysqld --validate-config >/dev/null 2>&1; then
        ${SUDO} rm -f -- "$config_file"
        fail "MySQL rejected the Anchor local-bind configuration; it was rolled back."
    fi
    MYSQL_NETWORK_CONFIG_CHANGED=true
    log "Configured MySQL and X Protocol to listen on 127.0.0.1 only."
}

verify_mysql_local_listeners() {
    cdsi_is_centos_stream || return 0
    command -v ss >/dev/null 2>&1 \
        || fail "ss is required to verify the MySQL network boundary."

    local address found_mysql=false
    local -a listeners=()
    mapfile -t listeners < <(
        ${SUDO} ss -ltnpH 2>/dev/null \
            | awk '/mysqld/ {print $4}'
    )
    for address in "${listeners[@]}"; do
        case "$address" in
            127.0.0.1:3306)
                found_mysql=true
                ;;
            127.0.0.1:33060)
                ;;
            *)
                fail "MySQL has a non-local TCP listener (${address}); existing network configuration was not considered safe."
                ;;
        esac
    done
    [[ "$found_mysql" == true ]] \
        || fail "MySQL is not listening on the expected local address 127.0.0.1:3306."
    log_ok "MySQL TCP listeners are restricted to 127.0.0.1."
}

# ── Service state ──────────────────────────────────────────
ensure_mysql_running() {
    cdsi_service_installed "${CDSI_MYSQL_SERVICE}" \
        || fail "MySQL service '${CDSI_MYSQL_SERVICE}' is not installed."

    cdsi_service_enable "${CDSI_MYSQL_SERVICE}" \
        || fail "Failed to enable ${CDSI_MYSQL_SERVICE} at boot."
    cdsi_service_enabled "${CDSI_MYSQL_SERVICE}" \
        || fail "${CDSI_MYSQL_SERVICE} is not enabled at boot."
    if cdsi_service_active "${CDSI_MYSQL_SERVICE}"; then
        return 0
    fi

    log "MySQL is installed but not running - starting ${CDSI_MYSQL_SERVICE}..."
    cdsi_service_start "${CDSI_MYSQL_SERVICE}" \
        || fail "Failed to start ${CDSI_MYSQL_SERVICE}."
    cdsi_service_active "${CDSI_MYSQL_SERVICE}" \
        || fail "${CDSI_MYSQL_SERVICE} did not reach the active state."
    log_ok "MySQL started."
}

wait_for_mysql() {
    log "Waiting for MySQL to accept connections..."
    local ready=0
    local i
    for i in $(seq 1 60); do
        if command -v mysqladmin >/dev/null 2>&1 \
           && ${SUDO} mysqladmin --protocol=socket --silent ping >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 1
    done
    [[ "$ready" -eq 1 ]] || fail "MySQL did not become ready in time."
    log_ok "MySQL is up."
    verify_mysql_local_listeners
}

reconcile_mysql_runtime() {
    configure_mysql_network
    ensure_mysql_running
    if [[ "$MYSQL_NETWORK_CONFIG_CHANGED" == true \
       && "$MYSQL_SERVICE_WAS_ACTIVE" == true ]]; then
        log "Restarting ${CDSI_MYSQL_SERVICE} to apply the local-only network binding..."
        cdsi_service_restart "${CDSI_MYSQL_SERVICE}" \
            || fail "Failed to restart ${CDSI_MYSQL_SERVICE} after securing its listeners."
        cdsi_service_active "${CDSI_MYSQL_SERVICE}" \
            || fail "${CDSI_MYSQL_SERVICE} did not return to the active state."
    fi
    wait_for_mysql
}

MYSQL_SERVICE_WAS_ACTIVE=false
if cdsi_service_active "${CDSI_MYSQL_SERVICE}"; then
    MYSQL_SERVICE_WAS_ACTIVE=true
fi

# ── Idempotency / skip ────────────────────────────────────
# Fully done when MySQL is installed, the credential file records BOTH
# root and cdsi passwords, and we can connect as root with that password.
if command -v mysql >/dev/null 2>&1 \
   && cdsi_service_installed "${CDSI_MYSQL_SERVICE}" \
   && [[ -f "$PASS_FILE" ]]; then
    reconcile_mysql_runtime
    STORED_ROOT="$(stored_cred root)"
    STORED_CDSI="$(stored_cred cdsi)"
    if [[ -n "$STORED_ROOT" && -n "$STORED_CDSI" ]] \
       && mysql -u root -p"$STORED_ROOT" -e "SELECT 1" >/dev/null 2>&1 \
       && mysql -u "${DB_USER}" -p"$STORED_CDSI" -D "$DB_NAME" \
            -e "SELECT 1" >/dev/null 2>&1; then
        log "MySQL is already installed and root/cdsi passwords are set."
        log_ok "MySQL is already running."
        exit 0
    fi
    # Do not guess or reset authentication for an existing server. The only
    # supported recovery path below is the package's fresh local root login.
fi

# ── Install MySQL (if not present) ─────────────────────────
if cdsi_is_centos_stream && cdsi_package_installed mariadb-server; then
    fail "MariaDB Server is already installed. Anchor will not replace an existing database server with MySQL 8.4."
fi

if ! command -v mysql >/dev/null 2>&1 \
   || ! cdsi_service_installed "${CDSI_MYSQL_SERVICE}"; then
    MYSQL_PACKAGE="${CDSI_DB_PACKAGE}"
    log "Installing ${MYSQL_PACKAGE} from the system default package source..."

    cdsi_packages_update \
        || log "Package metadata update failed; continuing with cached metadata..."

    cdsi_packages_install "${MYSQL_PACKAGE}" \
        || fail "Package installation failed for ${MYSQL_PACKAGE}."

    command -v mysql >/dev/null 2>&1 \
        || fail "The MySQL client was not installed with ${MYSQL_PACKAGE}."
    cdsi_service_installed "${CDSI_MYSQL_SERVICE}" \
        || fail "${MYSQL_PACKAGE} did not install service '${CDSI_MYSQL_SERVICE}'."

    log_ok "MySQL package installed."
fi

reconcile_mysql_runtime

# ── Resolve credentials ───────────────────────────────────
# Reuse an existing cdsi password when upgrading from the old single-line
# format so we don't invalidate apps that already read password/mysql.pass.
STORED_ROOT="$(stored_cred root)"
EXISTING_CDSI="$(stored_cred cdsi)"
if [[ -z "$EXISTING_CDSI" && -f "$PASS_FILE" ]] \
   && ! grep -qE '^(root|cdsi):' "$PASS_FILE" 2>/dev/null; then
    # Old format: the whole file was just the cdsi password.
    EXISTING_CDSI="$(head -n1 "$PASS_FILE" 2>/dev/null | tr -d '[:space:]')"
fi

log "Generating random 10-character passwords..."
ROOT_NEEDS_ALTER=true
ROOT_AUTH_MODE=""
if [[ -n "$STORED_ROOT" ]] \
   && mysql -u root -p"$STORED_ROOT" -e "SELECT 1" >/dev/null 2>&1; then
    ROOT_PASSWORD="$STORED_ROOT"
    ROOT_NEEDS_ALTER=false
    ROOT_AUTH_MODE="stored"
    log "  Reusing the stored MySQL root credential (recovery/rerun path)."
elif ${SUDO} mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
    ROOT_PASSWORD="$(generate_password)"
    ROOT_AUTH_MODE="passwordless"
    log "  Generated a new MySQL root password."
else
    fail "MySQL is running, but neither the stored root credential nor local passwordless root authentication works. Existing root authentication was not changed."
fi

mysql_as_current_root() {
    if [[ "$ROOT_AUTH_MODE" == "stored" ]]; then
        mysql -u root -p"$ROOT_PASSWORD" "$@"
    else
        ${SUDO} mysql -u root "$@"
    fi
}

if [[ -n "$EXISTING_CDSI" ]]; then
    CDSI_PASSWORD="$EXISTING_CDSI"
    log "  Reusing existing cdsi password (upgrade path)."
else
    EXISTING_CDSI_COUNT="$(mysql_as_current_root --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM mysql.user WHERE User='${DB_USER}' AND Host='localhost';" \
        2>/dev/null)" \
        || fail "Could not inspect the existing MySQL application account."
    [[ "$EXISTING_CDSI_COUNT" =~ ^[0-9]+$ ]] \
        || fail "MySQL returned an invalid application-account count."
    if (( EXISTING_CDSI_COUNT > 0 )); then
        fail "MySQL user '${DB_USER}'@'localhost' already exists, but Anchor has no stored credential for it. Existing authentication was not changed."
    fi
    CDSI_PASSWORD="$(generate_password)"
    log "  Generated new cdsi password."
fi

# Persist the proposed credentials before changing root authentication. If a
# later DDL step fails, a rerun can authenticate with the stored root password
# and safely finish provisioning instead of losing the new credential.
write_credentials "$ROOT_PASSWORD" "$CDSI_PASSWORD" \
    || fail "Failed to save MySQL credentials before provisioning."
log_ok "Credentials saved to: ${PASS_FILE} (mode 600)"

if [[ "$ROOT_NEEDS_ALTER" == true ]]; then
    log "Setting the MySQL root password..."
    ${SUDO} mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASSWORD}';
SQL
    mysql -u root -p"${ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1 \
        || fail "MySQL root password changed, but the stored credential could not be verified."
fi

# ── Provision database + application user ─────────────────
log "Provisioning database and application user..."
mysql -u root -p"${ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${CDSI_PASSWORD}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${CDSI_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── Verify connections ────────────────────────────────────
log "Verifying connections..."
if mysql -u root -p"${ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
    log_ok "  root@localhost auth: OK"
else
    log_fail "Authentication as root failed."
    fail "root password verification failed."
fi
if mysql -u "${DB_USER}" -p"${CDSI_PASSWORD}" -D "$DB_NAME" \
    -e "SELECT 1" >/dev/null 2>&1; then
    log_ok "  ${DB_USER}@localhost auth: OK"
else
    log_fail "Authentication as '${DB_USER}' failed."
    fail "cdsi user verification failed."
fi

# ── Summary ───────────────────────────────────────────────
log_ok "MySQL installation complete."
log "  Version:         $(mysql -V | awk '{print $3}')"
log "  Service:         active (enabled on boot)"
log "  Database:        ${DB_NAME} (utf8mb4)"
log "  User:            ${DB_USER}@localhost"
log "  Root auth:       caching_sha2_password (password set)"
log "  Credentials file: ${PASS_FILE} (mode 600)"
log "    root:${ROOT_PASSWORD}"
log "    cdsi:${CDSI_PASSWORD}"

exit 0
