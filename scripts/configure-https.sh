#!/usr/bin/env bash
# Configure HTTPS independently from the service installation flow.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${CDSI_ROOT}/lib/common.sh"
# shellcheck source=../lib/domain.sh
source "${CDSI_ROOT}/lib/domain.sh"

log() { printf '\033[1;34m[CDSI]\033[0m %s\n' "$*"; }
log_fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }

usage() {
    printf 'Usage: sudo bash scripts/configure-https.sh [options] [domain[,domain...]]\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --ip          Explicitly request HTTPS for the public server IP.\n'
    printf '  --force-dns   Accept a deliberate domain DNS mismatch.\n'
    printf '  -h, --help    Show this help.\n'
    printf '\n'
    printf 'Fallback CA variables (used only when the primary directory is unreachable):\n'
    printf '  CDSI_ACME_FALLBACK_SERVER\n'
    printf '  CDSI_ACME_FALLBACK_EAB_KID\n'
    printf '  CDSI_ACME_FALLBACK_EAB_HMAC_KEY\n'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ "${EUID}" -ne 0 ]]; then
    log_fail "HTTPS configuration requires root privileges."
    exit 1
fi

ip_mode=false
force_dns=false
requested_domain=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --ip)
            ip_mode=true
            ;;
        --force-dns)
            force_dns=true
            ;;
        -h|--help)
            usage
            exit 0
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

if [[ "$ip_mode" == true && -n "$requested_domain" ]]; then
    log_fail "Choose either --ip or a domain, not both."
    exit 2
fi

if [[ "$ip_mode" != true && -z "$requested_domain" ]]; then
    active_domain="$(cdsi_domain_state_read \
        "${CDSI_DOMAIN_FILE:-${CDSI_ROOT}/config/domain}" 2>/dev/null || true)"
    if [[ -z "$active_domain" && -t 0 ]]; then
        printf '\033[1;34m[CDSI]\033[0m Enter domain, or type "ip" for public-IP HTTPS: '
        read -r requested_domain
        if [[ "${requested_domain,,}" == ip ]]; then
            ip_mode=true
            requested_domain=""
        fi
    fi
fi

if [[ -n "$requested_domain" ]]; then
    domain_args=()
    [[ "$force_dns" != true ]] || domain_args+=(--force-dns)
    domain_args+=("$requested_domain")
    log "Validating and activating the domain before HTTPS configuration..."
    CDSI_ALLOW_DNS_MISMATCH="$force_dns" \
        bash "${CDSI_ROOT}/scripts/configure-domain.sh" "${domain_args[@]}"
fi

if [[ "$ip_mode" == true ]]; then
    CDSI_ENABLE_IP_HTTPS=true \
        bash "${CDSI_ROOT}/scripts/install-certbot.sh"
else
    CDSI_ALLOW_DNS_MISMATCH="$force_dns" \
        bash "${CDSI_ROOT}/scripts/install-certbot.sh"
fi
