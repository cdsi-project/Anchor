#!/usr/bin/env bash
# ═══════════════════════════════════════════════════
# CDSI Bootstrap — MySQL Installer
# Installs MySQL from system default apt source.
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
PASS_DIR="$(cd "${SCRIPT_DIR}/../password" && pwd)"
PASS_FILE="${PASS_DIR}/mysql.pass"

DB_NAME="cdsi"
DB_USER="cdsi"

# ── Password Generation (10-char alphanumeric) ─────────────
generate_password() {
    local pw
    pw="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || true)"
    [[ ${#pw} -eq 10 ]] || fail "Failed to generate 10-char password."
    echo "$pw"
}

# ── Read a stored credential from the password file ───────
stored_cred() {
    # $1 = key (root|cdsi); echoes the value or nothing
    [[ -f "$PASS_FILE" ]] || return 0
    grep "^$1:" "$PASS_FILE" 2>/dev/null | cut -d: -f2- || true
}

# ── Idempotency / skip ────────────────────────────────────
# Fully done when MySQL is installed, the credential file records BOTH
# root and cdsi passwords, and we can connect as root with that password.
if command -v mysql >/dev/null 2>&1 && [[ -f "$PASS_FILE" ]]; then
    STORED_ROOT="$(stored_cred root)"
    STORED_CDSI="$(stored_cred cdsi)"
    if [[ -n "$STORED_ROOT" && -n "$STORED_CDSI" ]] \
       && mysql -u root -p"$STORED_ROOT" -e "SELECT 1" >/dev/null 2>&1; then
        log "MySQL is already installed and root/cdsi passwords are set."
        if systemctl is-active --quiet mysql 2>/dev/null; then
            log_ok "MySQL is already running."
        else
            log "MySQL installed but not running — starting..."
            ${SUDO} systemctl start mysql || fail "Failed to start mysql."
            log_ok "MySQL started."
        fi
        exit 0
    fi
    # Credential file present but root password missing/invalid
    # (e.g. upgraded from an older script) → fall through and set it.
fi

# ── Install MySQL (if not present) ─────────────────────────
if ! command -v mysql >/dev/null 2>&1; then
    log "Installing MySQL from system default apt source..."

    ${SUDO} apt-get update -qq || log "apt-get update had warnings, continuing..."

    DEBIAN_FRONTEND=noninteractive ${SUDO} apt-get install -y -qq mysql-server || \
        fail "apt-get install mysql-server failed."

    ${SUDO} systemctl enable mysql >/dev/null 2>&1 || true

    log_ok "MySQL package installed."
fi

# ── Wait for MySQL to be ready (root uses auth_socket, no pw) ──
log "Waiting for MySQL to accept connections..."
READY=0
for i in $(seq 1 60); do
    if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done
[[ ${READY} -eq 1 ]] || fail "MySQL did not become ready in time."
log_ok "MySQL is up."

# ── Resolve credentials ───────────────────────────────────
# Reuse an existing cdsi password when upgrading from the old single-line
# format so we don't invalidate apps that already read password/mysql.pass.
EXISTING_CDSI="$(stored_cred cdsi)"
if [[ -z "$EXISTING_CDSI" && -f "$PASS_FILE" ]]; then
    # Old format: the whole file was just the cdsi password.
    EXISTING_CDSI="$(head -n1 "$PASS_FILE" 2>/dev/null | tr -d '[:space:]')"
fi

log "Generating random 10-character passwords..."
ROOT_PASSWORD="$(generate_password)"
if [[ -n "$EXISTING_CDSI" ]]; then
    CDSI_PASSWORD="$EXISTING_CDSI"
    log "  Reusing existing cdsi password (upgrade path)."
else
    CDSI_PASSWORD="$(generate_password)"
    log "  Generated new cdsi password."
fi

# ── Provision root password + database + user ──────────────
# At this point root still authenticates via auth_socket (fresh Ubuntu
# install), so we can connect without a password and switch it over.
log "Setting root password and provisioning database/user..."
mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${CDSI_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── Store password file ───────────────────────────────────
mkdir -p "${PASS_DIR}"
{
    echo "root:${ROOT_PASSWORD}"
    echo "cdsi:${CDSI_PASSWORD}"
} > "${PASS_FILE}"
chmod 600 "${PASS_FILE}"
log_ok "Credentials saved to: ${PASS_FILE} (mode 600)"

# ── Verify connections ────────────────────────────────────
log "Verifying connections..."
if mysql -u root -p"${ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
    log_ok "  root@localhost auth: OK"
else
    log_fail "Authentication as root failed."
    fail "root password verification failed."
fi
if mysql -u "${DB_USER}" -p"${CDSI_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
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
