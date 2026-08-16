#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Bootstrap — Redis Installer
# Standalone script — can be called by install.sh or run directly:
#   bash scripts/install-redis.sh
# ═══════════════════════════════════════════════════════════════

set -Eeuo pipefail

log() {
    printf '\033[1;34m[CDSI]\033[0m %s\n' "$*"
}

fail() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
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

# ── Install ───────────────────────────────────────────────
log "Redis installer — not implemented (planned for M2)."
log "No system changes were made."

# Exit 3 tells install.sh that this component is intentionally unavailable.
exit 3
