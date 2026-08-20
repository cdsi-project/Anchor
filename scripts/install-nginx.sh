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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"

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

# ── Apply CDSI global Nginx tuning (conf.d/cdsi-tuning.conf) ──
# Idempotent: writes the tuning file and reloads nginx if running.
# Called both on fresh install and on idempotent skip so the tuning stays
# in sync with the installer's version.
_apply_tuning() {
    local tuning_file="/etc/nginx/conf.d/cdsi-tuning.conf"
    [[ -d /etc/nginx/conf.d ]] || return 0
    log "Applying CDSI global Nginx tuning..."

    # server_tokens must be patched in nginx.conf directly — putting it in
    # conf.d would duplicate the directive already in the http block.
    if grep -q 'server_tokens build;' /etc/nginx/nginx.conf; then
        "${ROOT_CMD[@]}" sed -i 's/server_tokens build;/server_tokens off;/' /etc/nginx/nginx.conf
        log "  server_tokens: build → off (patched nginx.conf)"
    elif ! grep -q 'server_tokens off;' /etc/nginx/nginx.conf; then
        "${ROOT_CMD[@]}" sed -i '/^http {/a\\tserver_tokens off;' /etc/nginx/nginx.conf
        log "  server_tokens off added to nginx.conf"
    fi
    cat > /tmp/cdsi-tuning.$$ <<'TUNING'
# CDSI Nginx global tuning — http block level.
# Managed by install-nginx.sh; re-running the installer overwrites this file.
# (server_tokens is patched in nginx.conf directly to avoid duplication.)

# ── Gzip compression ──
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_min_length 256;
gzip_types
    text/plain
    text/css
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    application/rss+xml
    application/atom+xml
    image/svg+xml;

# ── SSL session cache (used by certbot-managed 443 blocks) ──
# Note: ssl_protocols and ssl_prefer_server_ciphers are already set in
# nginx.conf; only add session cache here to avoid duplicate directives.
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# ── Keepalive ──
keepalive_timeout 65;
TUNING
    "${ROOT_CMD[@]}" cp /tmp/cdsi-tuning.$$ "$tuning_file"
    rm -f /tmp/cdsi-tuning.$$
    # Reload only if nginx is running and the config validates.
    if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
        if "${ROOT_CMD[@]}" nginx -t >/dev/null 2>&1; then
            "${ROOT_CMD[@]}" systemctl reload nginx 2>/dev/null || true
            log "Global tuning applied: server_tokens off, gzip types, SSL session cache."
        else
            log "WARNING: nginx -t failed after tuning; leaving config as-is."
        fi
    fi
}

# ── Idempotency: skip if already installed, configured, and running ──
# Re-running the installer should not re-validate and re-enable Nginx when
# nothing needs to change. We only skip when the service is healthy.
if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
    if "${ROOT_CMD[@]}" nginx -t >/dev/null 2>&1; then
        _apply_tuning
        log "Nginx is already installed, its configuration is valid, and the service is running."
        log "Skipping installation."
        nginx -v 2>&1 | sed 's/^/  /'
        exit 0
    fi
fi

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
if ! cdsi_apt_get update; then
    fail "apt-get update failed. Check the configured Ubuntu sources and network connectivity."
fi

log "Installing Nginx from the Ubuntu repositories..."
if ! cdsi_apt_get install -y nginx; then
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
    _apply_tuning
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
