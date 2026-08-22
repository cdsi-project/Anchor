#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Anchor — Redis Installer
# Installs Redis from system default apt source.
# Generates a random password, sets it in redis.conf,
# and stores it in password/redis.pass.
#
# Can be called by install.sh or run directly:
#   bash scripts/install-redis.sh
# ═══════════════════════════════════════════════════════════════

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
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"
PASS_DIR="${CDSI_ROOT}/password"
PASS_FILE="${PASS_DIR}/redis.pass"
REDIS_CONF="/etc/redis/redis.conf"

# ── Password Generation (10-char alphanumeric) ─────────────
generate_password() {
    local pw
    pw="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || true)"
    [[ ${#pw} -eq 10 ]] || fail "Failed to generate 10-char password."
    echo "$pw"
}

# ── Set requirepass in redis.conf ──────────────────────────
set_redis_password() {
    local password="$1"

    if grep -q "^\s*requirepass" "$REDIS_CONF" 2>/dev/null; then
        # Replace existing requirepass line
        ${SUDO} sed -i "s/^\s*requirepass.*/requirepass ${password}/" "$REDIS_CONF"
    else
        # Append requirepass at end of config
        echo "requirepass ${password}" | ${SUDO} tee -a "$REDIS_CONF" >/dev/null
    fi
}

# ── Idempotency: already installed & configured? ──────────
if command -v redis-server >/dev/null 2>&1 && [[ -f "$PASS_FILE" ]]; then
    log "Redis is already installed and password file exists."

    if systemctl is-active --quiet redis-server 2>/dev/null; then
        log_ok "Redis is already running with password configured."
    else
        log "Redis installed but not running — starting..."
        ${SUDO} systemctl start redis-server || fail "Failed to start redis-server."
        log_ok "Redis started."
    fi

    exit 0
fi

# ── Install Redis (if not present) ─────────────────────────
if ! command -v redis-server >/dev/null 2>&1; then
    log "Installing Redis from system default apt source..."

    cdsi_apt_get update -qq \
        || log "apt-get update failed after retries; continuing with cached package metadata..."

    cdsi_apt_get install -y -qq redis-server || \
        fail "apt-get install redis-server failed."

    log_ok "Redis installed."
fi

# ── Generate Password ─────────────────────────────────────
log "Generating random 10-character password..."
REDIS_PASSWORD="$(generate_password)"
log "  Password generated."

# ── Configure redis.conf ──────────────────────────────────
log "Configuring redis.conf..."

if [[ ! -f "$REDIS_CONF" ]]; then
    fail "redis.conf not found at ${REDIS_CONF}"
fi

# Set password
set_redis_password "$REDIS_PASSWORD"

# Bind to localhost only (security: no external access)
if grep -q "^\s*bind " "$REDIS_CONF" 2>/dev/null; then
    ${SUDO} sed -i "s/^\s*bind .*/bind 127.0.0.1 -::1/" "$REDIS_CONF"
else
    echo "bind 127.0.0.1 -::1" | ${SUDO} tee -a "$REDIS_CONF" >/dev/null
fi

log_ok "  requirepass set"
log_ok "  bind 127.0.0.1 (localhost only)"

# ── Store Password File ───────────────────────────────────
mkdir -p "$PASS_DIR"
echo "$REDIS_PASSWORD" > "$PASS_FILE"
chmod 600 "$PASS_FILE"
log_ok "  Password saved to: ${PASS_FILE} (mode 600)"

# ── Restart Redis ─────────────────────────────────────────
log "Restarting redis-server..."
${SUDO} systemctl restart redis-server || fail "Failed to restart redis-server."
${SUDO} systemctl enable redis-server >/dev/null 2>&1 || true
log_ok "  Service restarted and enabled on boot."

# ── Verify ────────────────────────────────────────────────
log "Verifying installation..."

systemctl is-active --quiet redis-server || fail "redis-server is not active."
log_ok "  Service: active"

command -v redis-cli >/dev/null 2>&1 || fail "redis-cli not found."
log_ok "  CLI: $(command -v redis-cli)"

# Test AUTH
if redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
    log_ok "  Auth test: PONG received"
else
    log_fail "Auth test failed — redis-cli could not authenticate."
    fail "Redis password verification failed."
fi

# ── Summary ───────────────────────────────────────────────
log_ok "Redis installation complete."
log "  Version:   $(redis-server --version 2>&1 | awk '{print $3}')"
log "  Service:   active (enabled on boot)"
log "  Bind:      127.0.0.1 (localhost only)"
log "  Password:  ${PASS_FILE} (mode 600)"
log "  Config:    ${REDIS_CONF}"

exit 0
