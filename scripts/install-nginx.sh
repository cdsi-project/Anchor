#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Bootstrap — Nginx Installer
# Standalone script — can be called by install.sh or run directly:
#   bash scripts/install-nginx.sh
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
    ROOT_CMD=()
elif command -v sudo >/dev/null 2>&1; then
    ROOT_CMD=(sudo)
else
    fail "This script requires root privileges or sudo."
fi

# ── Platform Checks ───────────────────────────────────────
[[ -r /etc/os-release ]] || fail "/etc/os-release not found."

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-unknown}" in
    ubuntu)
        ;;
    *)
        fail "Unsupported distribution: ${ID:-unknown}. CDSI currently supports Ubuntu only."
        ;;
esac

case "${VERSION_ID:-unknown}" in
    24.04|26.04)
        ;;
    *)
        fail "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported versions: 24.04 and 26.04 LTS."
        ;;
esac

command -v apt-get >/dev/null 2>&1 || fail "apt-get is required."
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required."

# Do not silently mix nginx.org packages with Ubuntu's nginx packages.
for source_file in \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list \
    /etc/apt/sources.list.d/*.sources; do
    [[ -f "$source_file" ]] || continue
    if grep -qsE 'nginx\.org|ppa:(nginx|ondrej/nginx)' "$source_file"; then
        fail "Third-party Nginx source detected in ${source_file}. Remove it before continuing."
    fi
done

# Preserve an existing broken configuration instead of starting a package
# operation that may reload it.
if command -v nginx >/dev/null 2>&1; then
    log "Validating the existing Nginx configuration..."
    if ! "${ROOT_CMD[@]}" nginx -t; then
        fail "Existing Nginx configuration is invalid; no changes were made."
    fi
fi

# ── Install ───────────────────────────────────────────────
log "Updating Ubuntu package metadata..."
if ! "${ROOT_CMD[@]}" apt-get update; then
    fail "apt-get update failed. Check the configured Ubuntu sources and network connectivity."
fi

log "Installing Nginx from the Ubuntu repositories..."
if ! "${ROOT_CMD[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y nginx; then
    fail "Nginx package installation failed."
fi

command -v nginx >/dev/null 2>&1 || fail "Nginx was not installed."

log "Validating the Nginx configuration..."
if ! "${ROOT_CMD[@]}" nginx -t; then
    fail "Nginx configuration validation failed."
fi

log "Enabling nginx.service..."
if ! "${ROOT_CMD[@]}" systemctl enable --now nginx; then
    fail "Could not enable and start nginx.service."
fi

if "${ROOT_CMD[@]}" systemctl is-active --quiet nginx; then
    log "nginx.service is running."
else
    fail "nginx.service is not running."
fi

if command -v ss >/dev/null 2>&1; then
    if ss -ltnH | awk '$4 ~ /(:)80$/ {found=1} END{exit found ? 0 : 1}'; then
        log "Nginx is listening on port 80."
    else
        fail "Nginx is running but is not listening on port 80."
    fi

    if ss -ltnH | awk '$4 ~ /(:)443$/ {found=1} END{exit found ? 0 : 1}'; then
        log "Nginx is listening on port 443."
    else
        log "Port 443 is not configured yet; HTTPS will be handled by Certbot."
    fi
else
    log "ss is unavailable; skipped port listener checks."
fi

if command -v curl >/dev/null 2>&1; then
    HTTP_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/ || true)"
    if [[ "$HTTP_STATUS" =~ ^[0-9]{3}$ ]]; then
        log "Local HTTP request returned status ${HTTP_STATUS}."
    else
        fail "Nginx is running but the local HTTP request failed."
    fi
fi

NGINX_VERSION="$("${ROOT_CMD[@]}" nginx -v 2>&1)"
log "Nginx installation completed: ${NGINX_VERSION}"
