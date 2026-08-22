#!/usr/bin/env bash
# ═══════════════════════════════════════════════════
# CDSI Anchor — Supervisor Installer
# Installs Supervisor from the system default apt source.
# Enables and starts the supervisor service, then verifies
# supervisord is reachable via supervisorctl.
#
# Can be called by install.sh or run directly:
#   bash scripts/install-supervisor.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"

# ── Root Check ─────────────────────────────────────────────
if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    fail "This script requires root privileges or sudo."
fi

command -v apt-get >/dev/null 2>&1 || fail "apt-get is required."
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required."

SUPVISOR_SERVICE="supervisor"
SUPVISOR_CONF_DIR="/etc/supervisor/conf.d"

# ── Idempotency ────────────────────────────────────────────
if command -v supervisord >/dev/null 2>&1; then
    if systemctl is-active --quiet "${SUPVISOR_SERVICE}" 2>/dev/null; then
        log "Supervisor is already installed and running."
        supervisorctl status 2>/dev/null || true
        exit 0
    fi
    log "Supervisor is installed but not running — starting it..."
    ${SUDO} systemctl enable "${SUPVISOR_SERVICE}" >/dev/null 2>&1 || true
    ${SUDO} systemctl start "${SUPVISOR_SERVICE}" || fail "Failed to start ${SUPVISOR_SERVICE}."
    ${SUDO} systemctl is-active --quiet "${SUPVISOR_SERVICE}" || fail "${SUPVISOR_SERVICE} is not active after start."
    log_ok "Supervisor started."
    exit 0
fi

# ── Install Supervisor (system default apt source) ────────
log "Installing Supervisor from the system default apt source..."
cdsi_apt_get update -qq \
    || log "apt-get update failed after retries; continuing with cached package metadata..."
cdsi_apt_get install -y -qq supervisor || \
    fail "apt-get install supervisor failed."

command -v supervisord >/dev/null 2>&1 || fail "supervisord was not installed."

# ── Ensure program include directory exists ────────────────
${SUDO} mkdir -p "${SUPVISOR_CONF_DIR}"

# ── Enable & start ─────────────────────────────────────────
${SUDO} systemctl enable "${SUPVISOR_SERVICE}" >/dev/null 2>&1 || true
${SUDO} systemctl start "${SUPVISOR_SERVICE}" || fail "Failed to start ${SUPVISOR_SERVICE}."

# ── Verify ─────────────────────────────────────────────────
systemctl is-active --quiet "${SUPVISOR_SERVICE}" || fail "${SUPVISOR_SERVICE} is not active."
log_ok "  Service: active (enabled on boot)"

if supervisorctl status >/dev/null 2>&1; then
    log_ok "  supervisorctl: connected to supervisord"
else
    log_fail "supervisorctl could not reach supervisord."
    fail "Supervisor verification failed."
fi

# ── Summary ────────────────────────────────────────────────
log_ok "Supervisor installation complete."
log "  Version:   $(supervisord --version 2>&1)"
log "  Service:   active (enabled on boot)"
log "  Config:    /etc/supervisor/supervisord.conf"
log "  Programs:  ${SUPVISOR_CONF_DIR}/*.conf"
log "  Control:   supervisorctl status"

exit 0
