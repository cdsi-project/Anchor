#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# CDSI Bootstrap — Certbot (Let's Encrypt) Installer
#
# Installs Certbot + the Nginx plugin from the system apt source,
# then obtains and auto-configures a free TLS certificate for a
# domain (or list of domains) using the `certbot --nginx` plugin,
# which edits the Nginx server block and forces HTTP→HTTPS.
#
# Domain input (pick one):
#   • environment variable:  CDSI_DOMAIN="cdsi.example.com"
#                            (comma/space separated for multiple:
#                             CDSI_DOMAIN="example.com,www.example.com")
#   • interactive prompt     when run inside install.sh / a TTY
#   • admin email:           CDSI_CERT_EMAIL="you@example.com"
#                            (defaults to admin@cdsi.local if omitted)
#
# Idempotent:
#   • Certbot package: skips if already installed.
#   • Certificate:     skips issuance if a live cert for the domain
#                      already exists under /etc/letsencrypt/live/<domain>.
#   • Auto-renewal:    enables certbot.timer (installed by the package).
#
# Can be called by install.sh or run directly:
#   bash scripts/install-certbot.sh
# ═══════════════════════════════════════════════════════════════

set -Eeuo pipefail

# ── Locate bootstrap root (for the persisted domain file) ─
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# Normalize Backspace → ^H so the domain prompt edits cleanly
# when this script is run directly (install.sh already sets this,
# but setting it here keeps standalone runs consistent).
stty erase '^H' 2>/dev/null || true

command -v apt-get >/dev/null 2>&1 || fail "apt-get is required."
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required."

NGINX_AVAILABLE=false
if command -v nginx >/dev/null 2>&1; then
    NGINX_AVAILABLE=true
fi

# ── Install Certbot + Nginx plugin ─────────────────────────
if command -v certbot >/dev/null 2>&1; then
    log "Certbot is already installed: $(certbot --version 2>&1)"
else
    log "Installing Certbot + Nginx plugin from the system apt source..."
    ${SUDO} apt-get update -qq || log "apt-get update had warnings, continuing..."
    DEBIAN_FRONTEND=noninteractive ${SUDO} apt-get install -y -qq \
        certbot python3-certbot-nginx || fail "apt-get install certbot failed."
    command -v certbot >/dev/null 2>&1 || fail "certbot was not installed."
    log_ok "Certbot installed: $(certbot --version 2>&1)"
fi

# Ensure the Nginx plugin is present (needed for --nginx auto-config).
if ! ${SUDO} certbot plugins 2>/dev/null | grep -q "nginx"; then
    log "Installing the Certbot Nginx plugin..."
    DEBIAN_FRONTEND=noninteractive ${SUDO} apt-get install -y -qq \
        python3-certbot-nginx || fail "apt-get install python3-certbot-nginx failed."
fi
${SUDO} certbot plugins 2>/dev/null | grep -q "nginx" \
    || fail "Certbot Nginx plugin not available; cannot auto-configure Nginx."
log_ok "Certbot Nginx plugin available."

# ── Determine domain(s) ────────────────────────────────────
DOMAINS=()
# Fall back to the domain persisted by install.sh (config/domain).
if [[ -z "${CDSI_DOMAIN:-}" ]] && [[ -f "${CDSI_ROOT}/config/domain" ]]; then
    CDSI_DOMAIN="$(cat "${CDSI_ROOT}/config/domain" 2>/dev/null | head -1 | tr -d '[:space:]')"
fi
if [[ -n "${CDSI_DOMAIN:-}" ]]; then
    # shellcheck disable=SC2206
    IFS=', ' read -r -a _raw <<< "${CDSI_DOMAIN}"
    for _d in "${_raw[@]}"; do
        [[ -n "$_d" ]] && DOMAINS+=("$_d")
    done
elif [[ -t 0 ]]; then
    printf "\033[1;34m[CDSI]\033[0m \033[5mEnter domain for the TLS certificate (e.g. cdsi.example.com, comma-separated for several):\033[0m "
    read -r _input
    # shellcheck disable=SC2206
    IFS=', ' read -r -a _raw <<< "${_input:-}"
    for _d in "${_raw[@]}"; do
        [[ -n "$_d" ]] && DOMAINS+=("$_d")
    done
fi

if [[ "${#DOMAINS[@]}" -eq 0 ]]; then
    log "No domain provided — Certbot is installed and ready."
    log "To issue a certificate, re-run with a domain, e.g.:"
    log "  CDSI_DOMAIN=cdsi.example.com bash scripts/install-certbot.sh"
    log "  (Nginx must be installed and the domain's DNS A record must point here,"
    log "   with port 80 reachable from the internet for the ACME HTTP-01 challenge.)"
    exit 0
fi

PRIMARY_DOMAIN="${DOMAINS[0]}"
log "Target domain(s): ${DOMAINS[*]}"

# ── Resolve admin email (required for the ACME account) ───
# When a live cert for this domain already exists, certbot reuses it and does
# NOT require an email prompt — we fall back to a placeholder so the re-apply
# step below stays non-interactive. Only a fresh issuance needs a real email
# (from env or an interactive prompt).
CERT_ALREADY_ISSUED=false
[[ -d "/etc/letsencrypt/live/${PRIMARY_DOMAIN}" ]] && CERT_ALREADY_ISSUED=true
EMAIL="${CDSI_CERT_EMAIL:-}"
if [[ "$CERT_ALREADY_ISSUED" == true ]]; then
    [[ -z "$EMAIL" ]] && EMAIL="admin@cdsi.local"
    log_ok "Live cert for ${PRIMARY_DOMAIN} present — reusing it (no email prompt)."
else
    if [[ -z "$EMAIL" ]] && [[ -t 0 ]]; then
        printf "\033[1;34m[CDSI]\033[0m \033[5mEnter admin email for certificate renewal notices:\033[0m "
        read -r _email_input
        EMAIL="$(printf '%s' "${_email_input:-}" | tr -d '[:space:]')"
    fi
    [[ -n "$EMAIL" ]] || fail "A valid admin email is required to obtain a TLS certificate. Set CDSI_CERT_EMAIL=you@example.com and re-run."
fi
if [[ -z "$EMAIL" ]] && [[ -t 0 ]]; then
    printf "\033[1;34m[CDSI]\033[0m \033[5mEnter admin email for certificate renewal notices:\033[0m "
    read -r _email_input
    EMAIL="$(printf '%s' "${_email_input:-}" | tr -d '[:space:]')"
fi
[[ -n "$EMAIL" ]] || fail "A valid admin email is required to obtain a TLS certificate. Set CDSI_CERT_EMAIL=you@example.com and re-run."

# ── Nginx must be present for --nginx auto-config ──────────
if [[ "${NGINX_AVAILABLE}" != true ]]; then
    fail "Nginx is not installed. Install Nginx first (option 1 in install.sh), then re-run Certbot."
fi

# ── Point the Nginx server block at the domain ────────────
# The CDSI WordPress site ships with a catch-all server_name (_;).
# certbot --nginx matches a server block by server_name, so we set it
# to the real domain first. We deliberately skip the stock "default" site,
# otherwise certbot would inject the TLS config there and create a duplicate
# server_name (the WordPress <domain>.conf block would then be shadowed).
_update_server_name() {
    local esc
    esc="$(printf '%s' "$PRIMARY_DOMAIN" | sed 's/[.[\*^$]/\\&/g')"
    local updated=0
    for f in /etc/nginx/sites-available/*; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == "default" ]] && continue
        if grep -q "server_name _;" "$f"; then
            ${SUDO} sed -i "s/server_name _;/server_name ${esc};/" "$f"
            updated=1
        fi
    done
    if [[ "$updated" -eq 1 ]]; then
        log "Updated Nginx server_name to ${PRIMARY_DOMAIN}."
    fi
    ${SUDO} nginx -t || fail "Nginx configuration is invalid after server_name update."
    ${SUDO} systemctl reload nginx || fail "Failed to reload Nginx."
    log_ok "Nginx reloaded with domain ${PRIMARY_DOMAIN}."
}
_update_server_name

# ── Issue / re-apply certificate (idempotent) ──────────────
# certbot --nginx is safe to re-run: when a valid cert already exists it is
# reused (no new issuance) while the Nginx SSL configuration is re-applied.
# This lets a WordPress re-install "re-check" and re-wire the TLS server block.
CERT_DIR="/etc/letsencrypt/live/${PRIMARY_DOMAIN}"
DNS_ARGS=()
for d in "${DOMAINS[@]}"; do
    DNS_ARGS+=( -d "$d" )
done
if [[ -d "$CERT_DIR" ]]; then
    log "Certificate for ${PRIMARY_DOMAIN} already exists — re-applying Nginx SSL config (no new issuance)."
    log_ok "Existing cert: $(${SUDO} openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
else
    log "Obtaining certificate via certbot --nginx (this performs the ACME HTTP-01 challenge)..."
fi

# Capture certbot output so we can detect Let's Encrypt rate-limit errors and
# degrade gracefully (keep HTTP-only) instead of aborting the whole install.
CERTBOT_LOG="$(mktemp)"
set +e
${SUDO} certbot --nginx \
    "${DNS_ARGS[@]}" \
    --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --no-eff-email \
    --redirect \
    --key-type rsa \
    2>&1 | tee "$CERTBOT_LOG"
CERTBOT_RC="${PIPESTATUS[0]}"
set -e

if [[ "$CERTBOT_RC" -ne 0 ]]; then
    # Detect Let's Encrypt rate-limit, e.g.:
    #   "too many certificates (5) already issued for this exact set of
    #    identifiers in the last 168h0m0s, retry after 2026-08-18 20:52:38 UTC"
    # In that case the site stays HTTP-only; user re-runs certbot after cooldown.
    if grep -qiE "too many certificates|rate.?limit|retry after" "$CERTBOT_LOG"; then
        _retry="$(grep -oiE 'retry after [0-9: -]+UTC' "$CERTBOT_LOG" | head -1 || true)"
        log_fail "Let's Encrypt rate limit reached — certificate NOT issued."
        [[ -n "$_retry" ]] && log_fail "  ${_retry}"
        log_fail "  The site stays HTTP-only for now. After the cooldown, re-run:"
        log_fail "    bash scripts/install-certbot.sh"
        log_fail "  Existing Nginx HTTP config is preserved; no rollback needed."
        rm -f "$CERTBOT_LOG"
        exit 0
    fi
    echo "--- certbot output (tail) ---" >&2
    tail -20 "$CERTBOT_LOG" >&2 || true
    rm -f "$CERTBOT_LOG"
    fail "certbot failed to obtain/apply the certificate (exit ${CERTBOT_RC}). Check DNS (A record → this server) and that port 80 is reachable."
fi
rm -f "$CERTBOT_LOG"
log_ok "Nginx SSL configuration applied for: ${DOMAINS[*]}"

# ── Enable auto-renewal ───────────────────────────────────
if ${SUDO} systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    ${SUDO} systemctl enable --now certbot.timer >/dev/null 2>&1 || true
    if ${SUDO} systemctl is-enabled --quiet certbot.timer 2>/dev/null; then
        log_ok "Auto-renewal timer enabled (certbot.timer)."
    else
        log "certbot.timer not enabled; renewal relies on the certbot cron job."
    fi
else
    log "certbot.timer not present; the certbot package normally installs it."
fi

# ── Verify ─────────────────────────────────────────────────
if command -v ss >/dev/null 2>&1; then
    if ss -ltnH | awk '$4 ~ /(:)443$/ {found=1} END{exit found ? 0 : 1}'; then
        log_ok "Nginx is listening on port 443 (HTTPS)."
    else
        log_fail "Nginx is not listening on port 443 — HTTPS may not be served."
    fi
fi
log_ok "Certificate list:"
${SUDO} certbot certificates 2>/dev/null | sed 's/^/  /' || true

# ── Summary ────────────────────────────────────────────────
log_ok "Certbot setup complete."
log "  Domain(s): ${DOMAINS[*]}"
log "  Cert path: /etc/letsencrypt/live/${PRIMARY_DOMAIN}/"
log "  Renewal:   certbot renew (timer-enabled) or 'certbot renew --dry-run'"

exit 0
