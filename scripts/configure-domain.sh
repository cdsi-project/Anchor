#!/usr/bin/env bash
# Configure or clear the active WordPress domain without reinstalling services.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${CDSI_ROOT}/lib/common.sh"
# shellcheck source=../lib/platform.sh
source "${CDSI_ROOT}/lib/platform.sh"
# shellcheck source=../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"
# shellcheck source=../lib/dnf.sh
source "${CDSI_ROOT}/lib/dnf.sh"
# shellcheck source=../lib/zypper.sh
source "${CDSI_ROOT}/lib/zypper.sh"
# shellcheck source=../lib/packages.sh
source "${CDSI_ROOT}/lib/packages.sh"
# shellcheck source=../lib/services.sh
source "${CDSI_ROOT}/lib/services.sh"
# shellcheck source=../lib/wordpress-access.sh
source "${CDSI_ROOT}/lib/wordpress-access.sh"
# shellcheck source=../lib/domain.sh
source "${CDSI_ROOT}/lib/domain.sh"

cdsi_platform_init

log() { printf '\033[1;34m[CDSI]\033[0m %s\n' "$*"; }
log_ok() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
log_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
log_fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }

usage() {
    printf 'Usage: sudo bash scripts/configure-domain.sh [options] [domain[,domain...]]\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --clear       Switch the site back to HTTP on the server IP.\n'
    printf '  --force-dns   Accept a deliberate DNS mismatch (proxy/load balancer).\n'
    printf '  -h, --help    Show this help.\n'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ "${EUID}" -ne 0 ]]; then
    log_fail "Domain configuration requires root privileges."
    exit 1
fi
cdsi_platform_supported || {
    log_fail "Unsupported operating system."
    exit 3
}

DOMAIN_FILE="${CDSI_DOMAIN_FILE:-${CDSI_ROOT}/config/domain}"
PENDING_DOMAIN_FILE="${CDSI_PENDING_DOMAIN_FILE:-${CDSI_ROOT}/config/domain.pending}"
WP_DIR="${CDSI_WORDPRESS_DIR:-/var/www/wordpress}"
WORDPRESS_SCRIPT="${CDSI_ROOT}/scripts/install-wordpress.sh"
TLS_SNIPPET="${CDSI_IP_TLS_SNIPPET:-/etc/nginx/cdsi-wordpress-tls/ip.conf}"

clear_domain=false
requested_domain=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --clear)
            clear_domain=true
            ;;
        --force-dns)
            CDSI_ALLOW_DNS_MISMATCH=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            [[ "$#" -eq 0 ]] || requested_domain="$1"
            break
            ;;
        -*)
            log_fail "Unknown option: $1"
            usage >&2
            exit 2
            ;;
        *)
            [[ -z "$requested_domain" ]] || {
                log_fail "Only one domain list may be supplied."
                exit 2
            }
            requested_domain="$1"
            ;;
    esac
    shift
done

active_domain="$(cdsi_domain_state_read "$DOMAIN_FILE" 2>/dev/null || true)"

configure_wordpress_target() {
    local target_domain="$1"
    local force_ip="$2"
    local site_scheme="http"

    if [[ ! -f "${WP_DIR}/wp-load.php" ]]; then
        log "WordPress is not installed yet; the setting will be used during installation."
        return 0
    fi
    [[ -f "$WORDPRESS_SCRIPT" ]] || {
        log_fail "WordPress configuration script not found: ${WORDPRESS_SCRIPT}"
        return 1
    }

    if [[ "$force_ip" != true && "$target_domain" == "$active_domain" ]]; then
        # An idempotent same-domain run keeps an existing HTTPS URL. A new
        # domain starts on HTTP until configure-https.sh succeeds.
        site_scheme=""
    fi
    env \
        CDSI_WORDPRESS_CONFIGURE_ONLY=true \
        CDSI_SKIP_CERTBOT=true \
        CDSI_DNS_VERIFIED=true \
        CDSI_FORCE_IP="$force_ip" \
        CDSI_SITE_SCHEME="$site_scheme" \
        CDSI_DOMAIN="$target_domain" \
        CDSI_PREVIOUS_DOMAIN="$active_domain" \
        CDSI_DOMAIN_FILE="$DOMAIN_FILE" \
        CDSI_PENDING_DOMAIN_FILE="$PENDING_DOMAIN_FILE" \
        CDSI_SERVER_IP="${CDSI_SERVER_IP:-}" \
        bash "$WORDPRESS_SCRIPT"
}

TRANSITION_DIR=""
DOMAIN_STATE_EXISTED=false
PENDING_STATE_EXISTED=false
IP_TLS_EXISTED=false
TRANSITION_SNAPSHOT_READY=false
TRANSITION_MUTATED=false

begin_domain_transition() {
    local new_domain="$1"
    TRANSITION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cdsi-domain-transition.XXXXXX")" \
        || return 1

    if [[ -f "$DOMAIN_FILE" ]]; then
        cp -a -- "$DOMAIN_FILE" "${TRANSITION_DIR}/domain" || return 1
        DOMAIN_STATE_EXISTED=true
    fi
    if [[ -f "$PENDING_DOMAIN_FILE" ]]; then
        cp -a -- "$PENDING_DOMAIN_FILE" "${TRANSITION_DIR}/domain.pending" || return 1
        PENDING_STATE_EXISTED=true
    fi
    if [[ -f "$TLS_SNIPPET" ]]; then
        cp -a -- "$TLS_SNIPPET" "${TRANSITION_DIR}/ip.conf" || return 1
        IP_TLS_EXISTED=true
    fi

    TRANSITION_SNAPSHOT_READY=true
    TRANSITION_MUTATED=true
    if [[ -n "$new_domain" ]]; then
        cdsi_domain_state_write "$DOMAIN_FILE" "$new_domain" || return 1
    else
        rm -f -- "$DOMAIN_FILE" || return 1
    fi
    rm -f -- "$PENDING_DOMAIN_FILE" || return 1
    if [[ "$IP_TLS_EXISTED" == true ]]; then
        rm -f -- "$TLS_SNIPPET" || return 1
    fi
}

restore_domain_transition() {
    local restore_failed=false
    if [[ "$TRANSITION_MUTATED" != true ]]; then
        rm -rf -- "$TRANSITION_DIR" 2>/dev/null || true
        return 0
    fi

    if [[ "$DOMAIN_STATE_EXISTED" == true ]]; then
        install -m 0644 "${TRANSITION_DIR}/domain" "$DOMAIN_FILE" 2>/dev/null \
            || restore_failed=true
    else
        rm -f -- "$DOMAIN_FILE" 2>/dev/null || restore_failed=true
    fi
    if [[ "$PENDING_STATE_EXISTED" == true ]]; then
        install -m 0644 "${TRANSITION_DIR}/domain.pending" "$PENDING_DOMAIN_FILE" 2>/dev/null \
            || restore_failed=true
    else
        rm -f -- "$PENDING_DOMAIN_FILE" 2>/dev/null || restore_failed=true
    fi
    if [[ "$IP_TLS_EXISTED" == true ]]; then
        mkdir -p "$(dirname "$TLS_SNIPPET")" 2>/dev/null \
            && install -m 0644 "${TRANSITION_DIR}/ip.conf" "$TLS_SNIPPET" 2>/dev/null \
            || restore_failed=true
        if [[ "$restore_failed" != true ]] \
           && { ! nginx -t >/dev/null 2>&1 \
                || ! cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1; }; then
            restore_failed=true
        fi
    fi
    if [[ "$restore_failed" == true ]]; then
        log_fail "Automatic rollback was incomplete. Recovery files remain in ${TRANSITION_DIR}."
        return 1
    fi
    rm -rf -- "$TRANSITION_DIR" 2>/dev/null || true
}

commit_domain_transition() {
    rm -rf -- "$TRANSITION_DIR" 2>/dev/null || true
}

if [[ -z "$requested_domain" ]]; then
    requested_domain="${CDSI_DOMAIN:-}"
fi
if [[ "$clear_domain" != true && -z "$requested_domain" && -t 0 ]]; then
    printf '\033[1;34m[CDSI]\033[0m Enter domain, or type "ip" to use IP mode: '
    read -r requested_domain
fi
case "${requested_domain,,}" in
    ip|clear)
        clear_domain=true
        requested_domain=""
        ;;
esac

if [[ "$clear_domain" == true ]]; then
    server_ip="$(cdsi_resolve_wordpress_server_ip "$WP_DIR" || true)"
    [[ -n "$server_ip" ]] || {
        log_fail "Could not determine the server IP. Set CDSI_SERVER_IP and retry."
        exit 1
    }
    if ! begin_domain_transition ""; then
        if restore_domain_transition; then
            log_fail "Could not stage the IP-mode state; the previous state was preserved."
        fi
        exit 1
    fi
    if ! configure_wordpress_target "" true; then
        if restore_domain_transition; then
            log_fail "Could not switch WordPress and Nginx to IP mode; the previous state was restored."
        fi
        exit 1
    fi
    commit_domain_transition
    log_ok "IP mode active: http://${server_ip}"
    exit 0
fi

requested_domain="$(cdsi_normalize_domain_list "$requested_domain")" || {
    log_fail "Invalid domain. Use DNS hostnames only."
    exit 2
}

server_ip="$(cdsi_resolve_wordpress_server_ip "$WP_DIR" || true)"
[[ -n "$server_ip" ]] || {
    log_fail "Could not determine the server IP. Set CDSI_SERVER_IP and retry."
    exit 1
}

if ! cdsi_ensure_dns_tools; then
    log_fail "Could not install the system DNS query tool required for domain validation."
    exit 1
fi

if ! cdsi_domain_dns_ready "$requested_domain" "$server_ip"; then
    if ! cdsi_domain_state_write "$PENDING_DOMAIN_FILE" "$requested_domain"; then
        log_fail "DNS is not ready and the pending domain could not be saved."
        exit 1
    fi
    log_warn "$CDSI_DNS_MESSAGE"
    log_warn "Saved as pending: ${PENDING_DOMAIN_FILE}"
    log_warn "The current WordPress URL and Nginx configuration were not changed."
    exit 10
fi
if [[ "$CDSI_DNS_STATUS" != "ready" ]]; then
    log_warn "$CDSI_DNS_MESSAGE"
    log_warn "Continuing because --force-dns was explicitly supplied."
else
    log_ok "$CDSI_DNS_MESSAGE"
fi

if ! begin_domain_transition "$requested_domain"; then
    if restore_domain_transition; then
        log_fail "Could not stage the new domain state; the previous state was preserved."
    fi
    exit 1
fi
if ! configure_wordpress_target "$requested_domain" false; then
    if restore_domain_transition; then
        log_fail "Domain activation failed; the previous state was restored."
    fi
    exit 1
fi
commit_domain_transition

primary_domain="${requested_domain%%,*}"
site_url=""
if command -v wp >/dev/null 2>&1 && [[ -f "${WP_DIR}/wp-load.php" ]]; then
    site_url="$(wp --path="$WP_DIR" option get home --allow-root 2>/dev/null || true)"
fi
[[ -n "$site_url" ]] || site_url="http://${primary_domain}"
validated_site_url="$(cdsi_resolve_wordpress_url \
    "$WP_DIR" "$requested_domain" "http://${primary_domain}")"
log_ok "Domain active: ${requested_domain}"
log "Site URL: ${site_url}"
if [[ "$site_url" == https://* && "$validated_site_url" == https://* ]]; then
    log_ok "HTTPS is already active for ${primary_domain}."
else
    log "Next step: sudo bash scripts/configure-https.sh"
fi
