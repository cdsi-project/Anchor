#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    _cdsi_script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
    exec /bin/sh "${_cdsi_script_dir}/../../lib/bootstrap.sh" \
        "${_cdsi_script_dir}/$(basename "$0")" "$@"
fi
# ═══════════════════════════════════════════════════════════════
# CDSI Anchor — Certbot (Let's Encrypt) Installer
#
# Installs Certbot + the Nginx plugin from the system package source,
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
#                            (defaults to admin@<domain> if omitted)
#
# Idempotent:
#   • Certbot package: skips if already installed.
#   • Certificate:     skips issuance if a live cert for the domain
#                      already exists under the Certbot config dir.
#   • Auto-renewal:    enables and verifies certbot.timer or certbot-renew.timer.
#
# Can be called by install.sh or run directly:
#   bash scripts/install-certbot.sh
# ═══════════════════════════════════════════════════════════════

set -Eeuo pipefail

# ── Locate installer root (for the persisted domain file) ─
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Logging ────────────────────────────────────────────────
log()     { printf "\033[1;34m[CDSI]\033[0m %s\n" "$*"; }
log_ok()  { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
log_fail(){ printf "\033[1;31m[FAIL]\033[0m %s\n" "$*" >&2; }

fail() {
    log_fail "$*"
    exit 1
}

# shellcheck source=../../lib/common.sh
source "${CDSI_ROOT}/lib/common.sh"
# shellcheck source=../../lib/platform.sh
source "${CDSI_ROOT}/lib/platform.sh"
# shellcheck source=../../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"
# shellcheck source=../../lib/dnf.sh
source "${CDSI_ROOT}/lib/dnf.sh"
# shellcheck source=../../lib/zypper.sh
source "${CDSI_ROOT}/lib/zypper.sh"
# shellcheck source=../../lib/packages.sh
source "${CDSI_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/services.sh
source "${CDSI_ROOT}/lib/services.sh"
# shellcheck source=../../lib/wordpress-access.sh
source "${CDSI_ROOT}/lib/wordpress-access.sh"
# shellcheck source=../../lib/domain.sh
source "${CDSI_ROOT}/lib/domain.sh"
cdsi_platform_init
cdsi_platform_supported \
    || fail "Unsupported operating system. Anchor supports Ubuntu 24.04/26.04 LTS, Debian 13, CentOS Stream 10, and openSUSE Leap 16.0."

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

NGINX_AVAILABLE=false
if command -v nginx >/dev/null 2>&1; then
    NGINX_AVAILABLE=true
fi

CERTBOT_BIN=""
resolve_certbot_bin() {
    local candidate
    for candidate in certbot; do
        if command -v "$candidate" >/dev/null 2>&1; then
            CERTBOT_BIN="$(command -v "$candidate")"
            return 0
        fi
    done
    return 1
}

CERTBOT_REPOSITORY_READY=false
prepare_certbot_repository() {
    if cdsi_is_centos_stream && [[ "$CERTBOT_REPOSITORY_READY" != true ]]; then
        log "CentOS Stream: enabling EPEL through the system package helper before installing Certbot."
        cdsi_enable_epel || fail "Could not enable EPEL for the CentOS Stream Certbot packages."
        CERTBOT_REPOSITORY_READY=true
    fi
}

certbot_packages() {
    if cdsi_is_opensuse_leap; then
        printf '%s\n' python313-certbot python313-certbot-nginx \
            certbot-systemd-timer
    else
        printf '%s\n' certbot python3-certbot-nginx
    fi
}

certbot_nginx_package() {
    if cdsi_is_opensuse_leap; then
        printf '%s\n' python313-certbot-nginx
    else
        printf '%s\n' python3-certbot-nginx
    fi
}

certbot_timer_package() {
    if cdsi_is_opensuse_leap; then
        printf '%s\n' certbot-systemd-timer
    fi
}

ensure_certbot_timer_package() {
    local timer_package=""
    timer_package="$(certbot_timer_package)"
    [[ -n "$timer_package" ]] || return 0
    if cdsi_package_installed "$timer_package"; then
        return 0
    fi

    log "Installing the Certbot renewal timer package..."
    cdsi_packages_update \
        || log "Package metadata update failed; continuing with cached metadata..."
    cdsi_packages_install "$timer_package" \
        || fail "Package installation failed for ${timer_package}."
    cdsi_package_installed "$timer_package" \
        || fail "${timer_package} was not installed; certificate configuration was not started."
}

ensure_certbot_renewal_timer() {
    RENEWAL_SUMMARY="manual: ${CERTBOT_BIN} renew"
    RENEWAL_TIMER=""
    local timer_candidate=""
    for timer_candidate in certbot.timer certbot-renew.timer; do
        if ${SUDO} systemctl list-unit-files --type=timer --no-legend \
            "$timer_candidate" 2>/dev/null \
            | awk -v timer="$timer_candidate" '$1 == timer {found=1} END {exit found ? 0 : 1}'; then
            RENEWAL_TIMER="$timer_candidate"
            break
        fi
    done
    [[ -n "$RENEWAL_TIMER" ]] \
        || fail "Certbot renewal timer not found; automatic renewal cannot be guaranteed."
    ${SUDO} systemctl enable --now "$RENEWAL_TIMER" >/dev/null 2>&1 \
        || fail "Could not enable and start ${RENEWAL_TIMER}."
    ${SUDO} systemctl is-enabled --quiet "$RENEWAL_TIMER" 2>/dev/null \
        || fail "${RENEWAL_TIMER} is not enabled at boot."
    ${SUDO} systemctl is-active --quiet "$RENEWAL_TIMER" 2>/dev/null \
        || fail "${RENEWAL_TIMER} is not active."
    RENEWAL_SUMMARY="$RENEWAL_TIMER"
    log_ok "Auto-renewal timer is active and enabled (${RENEWAL_TIMER})."
}

# ── Install Certbot + Nginx plugin ─────────────────────────
if resolve_certbot_bin; then
    log "Certbot is already installed: $("${CERTBOT_BIN}" --version 2>&1)"
else
    mapfile -t CERTBOT_PACKAGES < <(certbot_packages)
    prepare_certbot_repository
    if cdsi_is_centos_stream; then
        log "Installing Certbot + Nginx plugin from EPEL..."
    else
        log "Installing Certbot + Nginx plugin from the system default package source..."
    fi
    cdsi_packages_update \
        || log "Package metadata update failed; continuing with cached metadata..."
    cdsi_packages_install "${CERTBOT_PACKAGES[@]}" \
        || fail "Package installation failed for: ${CERTBOT_PACKAGES[*]}."
    resolve_certbot_bin || fail "Certbot was not installed or its executable was not found."
    log_ok "Certbot installed: $("${CERTBOT_BIN}" --version 2>&1)"
fi

# Leap packages the renewal timer separately. Reconcile it even when Certbot
# was already present, before any certificate or Nginx state can be changed.
ensure_certbot_timer_package

# Ensure the Nginx plugin is present (needed for --nginx auto-config).
if ! ${SUDO} "${CERTBOT_BIN}" plugins 2>/dev/null | grep -q "nginx"; then
    CERTBOT_NGINX_PACKAGE="$(certbot_nginx_package)"
    prepare_certbot_repository
    log "Installing the Certbot Nginx plugin..."
    cdsi_packages_install "${CERTBOT_NGINX_PACKAGE}" \
        || fail "Package installation failed for ${CERTBOT_NGINX_PACKAGE}."
fi
${SUDO} "${CERTBOT_BIN}" plugins 2>/dev/null | grep -q "nginx" \
    || fail "Certbot Nginx plugin not available; cannot auto-configure Nginx."
log_ok "Certbot Nginx plugin available."

# ── ACME selection and certificate validation helpers ─────
ACME_PRIMARY_SERVER="${CDSI_ACME_PRIMARY_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"
ACME_FALLBACK_SERVER="${CDSI_ACME_FALLBACK_SERVER:-}"

acme_directory_reachable() {
    local directory_url="${1:-}"
    local response_file=""
    [[ "$directory_url" == https://* ]] || return 1
    command -v curl >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 || return 1
    response_file="$(mktemp "${TMPDIR:-/tmp}/cdsi-acme-directory.XXXXXX")" \
        || return 1
    if ! curl -fsS --connect-timeout 5 --max-time 12 \
        --retry 2 --retry-delay 1 --retry-all-errors \
        -o "$response_file" "$directory_url"; then
        rm -f -- "$response_file"
        return 1
    fi
    if ! python3 -c 'import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
required = ("newNonce", "newAccount", "newOrder")
raise SystemExit(0 if all(isinstance(data.get(k), str) and data[k].startswith("http") for k in required) else 1)' \
        "$response_file" >/dev/null 2>&1; then
        rm -f -- "$response_file"
        return 1
    fi
    rm -f -- "$response_file"
}

# A fallback is selected only when the primary directory cannot be reached.
# Validation, authorization, CAA, and rate-limit failures never call this.
select_acme_server() {
    if acme_directory_reachable "$ACME_PRIMARY_SERVER"; then
        printf '%s\n' "$ACME_PRIMARY_SERVER"
        return 0
    fi
    [[ -n "$ACME_FALLBACK_SERVER" ]] || return 1
    acme_directory_reachable "$ACME_FALLBACK_SERVER" || return 1
    printf '%s\n' "$ACME_FALLBACK_SERVER"
}

version_at_least() {
    local actual="${1:-0}" required="${2:-0}"
    [[ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -n1)" == "$required" ]]
}

certbot_supports_ip_certificates() {
    local version="" help_output=""
    version="$("${CERTBOT_BIN}" --version 2>&1 | awk '{print $NF}' | sed 's/[^0-9.].*$//')"
    version_at_least "$version" "5.4" || return 1
    help_output="$("${CERTBOT_BIN}" certonly --help all 2>/dev/null || true)"
    grep -Fq -- '--ip-address' <<< "$help_output" \
        && grep -Fq -- '--preferred-profile' <<< "$help_output"
}

certificate_valid_for_identifiers() {
    local cert_dir="${1:-}"
    shift || true
    local identifier="" san_output="" cert_public="" key_public=""

    [[ -s "${cert_dir}/fullchain.pem" && -s "${cert_dir}/privkey.pem" ]] || return 1
    ${SUDO} openssl x509 -checkend 86400 -noout \
        -in "${cert_dir}/fullchain.pem" >/dev/null 2>&1 || return 1
    san_output="$(${SUDO} openssl x509 -in "${cert_dir}/fullchain.pem" \
        -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed 's/^[[:space:]]*//')"
    for identifier in "$@"; do
        if cdsi_is_ipv4 "$identifier"; then
            grep -Fqx "IP Address:${identifier}" <<< "$san_output" || return 1
        else
            grep -Fqx "DNS:${identifier}" <<< "$san_output" || return 1
        fi
    done
    cert_public="$(${SUDO} openssl x509 -in "${cert_dir}/fullchain.pem" -pubkey -noout 2>/dev/null \
        | openssl pkey -pubin -outform PEM 2>/dev/null \
        | sha256sum | awk '{print $1}')"
    key_public="$(${SUDO} openssl pkey -in "${cert_dir}/privkey.pem" -pubout -outform PEM 2>/dev/null \
        | sha256sum | awk '{print $1}')"
    [[ -n "$cert_public" && "$cert_public" == "$key_public" ]]
}

install_renewal_deploy_hook() {
    local source_hook="${CDSI_ROOT}/templates/certbot-deploy-hook.sh"
    local hook_dir="${CDSI_CERTBOT_CONFIG_DIR}/renewal-hooks/deploy"
    local hook_path="${hook_dir}/cdsi-nginx-reload"
    [[ -f "$source_hook" ]] || fail "Renewal deploy hook template not found: ${source_hook}."
    ${SUDO} mkdir -p "$hook_dir" \
        || fail "Could not create the Certbot deploy-hook directory."
    ${SUDO} install -m 0755 "$source_hook" "$hook_path" \
        || fail "Could not install the Certbot Nginx deploy hook."
}

update_wordpress_https_url() {
    local target_url="$1"
    local wp_dir="${CDSI_WORDPRESS_DIR:-/var/www/wordpress}"
    local old_siteurl="" old_home="" actual_siteurl="" actual_home=""
    command -v wp >/dev/null 2>&1 || return 0
    [[ -f "${wp_dir}/wp-load.php" ]] || return 0
    old_siteurl="$(${SUDO} wp --path="$wp_dir" option get siteurl --allow-root 2>/dev/null || true)"
    old_home="$(${SUDO} wp --path="$wp_dir" option get home --allow-root 2>/dev/null || true)"
    if ! ${SUDO} wp --path="$wp_dir" option update siteurl "$target_url" --allow-root >/dev/null \
       || ! ${SUDO} wp --path="$wp_dir" option update home "$target_url" --allow-root >/dev/null; then
        [[ -z "$old_siteurl" ]] || ${SUDO} wp --path="$wp_dir" option update siteurl "$old_siteurl" --allow-root >/dev/null 2>&1 || true
        [[ -z "$old_home" ]] || ${SUDO} wp --path="$wp_dir" option update home "$old_home" --allow-root >/dev/null 2>&1 || true
        return 1
    fi
    actual_siteurl="$(${SUDO} wp --path="$wp_dir" option get siteurl --allow-root 2>/dev/null || true)"
    actual_home="$(${SUDO} wp --path="$wp_dir" option get home --allow-root 2>/dev/null || true)"
    if [[ "${actual_siteurl%/}" != "${target_url%/}" \
       || "${actual_home%/}" != "${target_url%/}" ]]; then
        [[ -z "$old_siteurl" ]] || ${SUDO} wp --path="$wp_dir" option update siteurl "$old_siteurl" --allow-root >/dev/null 2>&1 || true
        [[ -z "$old_home" ]] || ${SUDO} wp --path="$wp_dir" option update home "$old_home" --allow-root >/dev/null 2>&1 || true
        return 1
    fi
}

install_ip_tls_nginx() {
    local cert_dir="$1"
    local tls_dir="${CDSI_IP_TLS_DIR:-/etc/nginx/cdsi-wordpress-tls}"
    local tls_path="${CDSI_IP_TLS_SNIPPET:-${tls_dir}/ip.conf}"
    local staged="" backup="" had_existing=false

    ${SUDO} mkdir -p "$tls_dir" || return 1
    staged="$(${SUDO} mktemp "${tls_path}.tmp.XXXXXX")" || return 1
    backup="$(mktemp "${TMPDIR:-/tmp}/cdsi-ip-tls-backup.XXXXXX")" || {
        ${SUDO} rm -f -- "$staged"
        return 1
    }
    if [[ -e "$tls_path" ]]; then
        if ! ${SUDO} cp -a -- "$tls_path" "$backup"; then
            ${SUDO} rm -f -- "$staged" 2>/dev/null || true
            rm -f -- "$backup"
            return 1
        fi
        had_existing=true
    fi
    if ! printf '%s\n' \
        '# CDSI IP TLS block - managed by install-certbot.sh' \
        'listen 443 ssl;' \
        'listen [::]:443 ssl;' \
        "ssl_certificate ${cert_dir}/fullchain.pem;" \
        "ssl_certificate_key ${cert_dir}/privkey.pem;" \
        'ssl_protocols TLSv1.2 TLSv1.3;' \
        | ${SUDO} tee "$staged" >/dev/null \
       || ! ${SUDO} chmod 0644 "$staged" \
       || ! ${SUDO} mv -f -- "$staged" "$tls_path" \
       || ! ${SUDO} nginx -t \
       || ! cdsi_service_reload "$CDSI_NGINX_SERVICE"; then
        local restore_failed=false
        ${SUDO} rm -f -- "$staged" "$tls_path" 2>/dev/null \
            || restore_failed=true
        if [[ "$had_existing" == true ]]; then
            ${SUDO} install -m 0644 "$backup" "$tls_path" 2>/dev/null \
                || restore_failed=true
        fi
        if [[ "$restore_failed" != true ]] \
           && { ! ${SUDO} nginx -t >/dev/null 2>&1 \
                || ! cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1; }; then
            restore_failed=true
        fi
        if [[ "$restore_failed" == true ]]; then
            log_fail "IP TLS rollback was incomplete. Recovery backup retained at ${backup}."
            return 1
        fi
        rm -f -- "$backup"
        return 1
    fi
    rm -f -- "$backup"
}

# Certbot matches a server block by server_name. Restrict any repair to the
# WordPress site emitted by Anchor; unrelated catch-all sites are never used.
_update_server_name() {
    local desired_names="${CDSI_DOMAIN:-${PRIMARY_DOMAIN:-}}"
    local primary="${PRIMARY_DOMAIN:-${desired_names%%,*}}"
    local file="" temporary="" backup="" candidate=""
    local updated=false
    local -a candidates=()

    desired_names="${desired_names//,/ }"
    [[ -n "$primary" && -n "$desired_names" ]] \
        || fail "No domain is available for the Nginx server_name."
    [[ -d "${CDSI_NGINX_SITE_DIR}" ]] \
        || fail "Nginx site directory not found: ${CDSI_NGINX_SITE_DIR}."
    candidates=(
        "${CDSI_NGINX_SITE_DIR}/${primary}.conf"
        "${CDSI_NGINX_SITE_DIR}/wordpress.conf"
        "${CDSI_NGINX_SITE_DIR}/wordpress"
    )
    for candidate in "${candidates[@]}"; do
        [[ -f "$candidate" ]] || continue
        if grep -Fq '# CDSI WordPress site block' "$candidate" 2>/dev/null; then
            file="$candidate"
            break
        fi
        if [[ "$candidate" == "${CDSI_NGINX_SITE_DIR}/${primary}.conf" ]]; then
            fail "Refusing to modify non-Anchor Nginx configuration: ${candidate}."
        fi
    done
    [[ -n "$file" ]] \
        || fail "Anchor-managed WordPress Nginx configuration was not found. Run install-wordpress.sh first."

    if awk -v expected_names="$desired_names" '
        BEGIN {
            expected_count = split(expected_names, expected, /[[:space:]]+/)
        }
        {
            line = $0
            sub(/[[:space:]]*#.*/, "", line)
            gsub(/[{}]/, ";", line)
            buffer = buffer " " line
            while ((separator = index(buffer, ";")) > 0) {
                directive = substr(buffer, 1, separator - 1)
                buffer = substr(buffer, separator + 1)
                sub(/^[[:space:]]+/, "", directive)
                sub(/[[:space:]]+$/, "", directive)
                field_count = split(directive, fields, /[[:space:]]+/)
                if (fields[1] != "server_name") {
                    continue
                }
                directive_count++
                for (field_index = 2; field_index <= field_count; field_index++) {
                    matched = 0
                    for (expected_index = 1; expected_index <= expected_count; expected_index++) {
                        if (fields[field_index] == expected[expected_index]) {
                            matched = 1
                            seen[directive_count, expected_index] = 1
                        }
                    }
                    if (!matched) {
                        extra_name = 1
                    }
                }
            }
        }
        END {
            mismatch = (directive_count == 0 || extra_name)
            for (directive_index = 1; directive_index <= directive_count; directive_index++) {
                for (expected_index = 1; expected_index <= expected_count; expected_index++) {
                    if (expected[expected_index] != "" \
                        && !seen[directive_index, expected_index]) {
                        mismatch = 1
                    }
                }
            }
            exit(mismatch ? 1 : 0)
        }
    ' "$file"; then
        :
    else
        temporary="$(mktemp)" || fail "Could not stage the Nginx domain update."
        backup="$(mktemp)" || { rm -f -- "$temporary"; fail "Could not back up the Nginx site."; }
        awk -v desired_names="$desired_names" '
            {
                original = $0
                code = $0
                sub(/[[:space:]]*#.*/, "", code)
                if (skipping_server_name) {
                    if (code ~ /;/) {
                        skipping_server_name = 0
                    }
                    next
                }
                if (code ~ /^[[:space:]]*server_name([[:space:]]|$)/) {
                    indentation = original
                    sub(/[^[:space:]].*$/, "", indentation)
                    suffix = ""
                    separator = index(original, ";")
                    if (separator > 0) {
                        suffix = substr(original, separator + 1)
                    } else {
                        skipping_server_name = 1
                    }
                    print indentation "server_name " desired_names ";" suffix
                    replaced = 1
                    next
                }
                print original
            }
            END { exit(replaced ? 0 : 2) }
        ' "$file" > "$temporary" \
            || { rm -f -- "$temporary" "$backup"; fail "Could not safely rewrite the Anchor Nginx server_name directives."; }
        cp -a -- "$file" "$backup" \
            || { rm -f -- "$temporary" "$backup"; fail "Could not back up the Anchor Nginx site."; }
        if ! ${SUDO} cp -- "$temporary" "$file"; then
            rm -f -- "$temporary"
            if ${SUDO} cp -- "$backup" "$file" 2>/dev/null; then
                rm -f -- "$backup"
                fail "Could not update the Anchor Nginx domain; the previous site was restored."
            fi
            fail "Could not update the Anchor Nginx domain; recovery backup retained at ${backup}."
        fi
        updated=true
    fi

    if ! ${SUDO} nginx -t || ! cdsi_service_reload "$CDSI_NGINX_SERVICE"; then
        if [[ "$updated" == true ]]; then
            rm -f -- "$temporary"
            if ! ${SUDO} cp -- "$backup" "$file" 2>/dev/null \
               || ! ${SUDO} nginx -t >/dev/null 2>&1 \
               || ! cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1; then
                fail "Nginx rejected the domain update and rollback was incomplete; recovery backup retained at ${backup}."
            fi
            rm -f -- "$backup"
            fail "Nginx rejected the domain update; the previous Anchor site was restored."
        fi
        fail "Nginx rejected the existing Anchor site; no server_name change was made."
    fi
    rm -f -- "$temporary" "$backup"
    log_ok "Nginx server_name is ready for ${desired_names}."
}

# ── Determine domain(s) or explicit IP mode ───────────────
DOMAIN_FILE="${CDSI_DOMAIN_FILE:-${CDSI_ROOT}/config/domain}"
PENDING_DOMAIN_FILE="${CDSI_PENDING_DOMAIN_FILE:-${CDSI_ROOT}/config/domain.pending}"
IP_MODE="${CDSI_ENABLE_IP_HTTPS:-false}"
DOMAINS=()
if [[ "$IP_MODE" != true && -z "${CDSI_DOMAIN:-}" && -f "$DOMAIN_FILE" ]]; then
    CDSI_DOMAIN="$(cdsi_domain_state_read "$DOMAIN_FILE" 2>/dev/null || true)"
fi
if [[ "$IP_MODE" != true && -n "${CDSI_DOMAIN:-}" ]]; then
    CDSI_DOMAIN="$(cdsi_normalize_domain_list "$CDSI_DOMAIN")" \
        || fail "Invalid CDSI_DOMAIN. Use DNS hostnames only."
    IFS=',' read -r -a _raw <<< "$CDSI_DOMAIN"
    for _d in "${_raw[@]}"; do
        [[ -n "$_d" ]] && DOMAINS+=("$_d")
    done
elif [[ "$IP_MODE" != true \
    && "${CDSI_INSTALL_CONTEXT:-standalone}" != "all" && -t 0 ]]; then
    printf "\033[1;34m[CDSI]\033[0m Enter domain for TLS (leave empty to keep HTTP-only): "
    read -r _input
    if [[ -n "${_input:-}" ]]; then
        _input="$(cdsi_normalize_domain_list "$_input")" \
            || fail "Invalid domain. Use DNS hostnames only."
        IFS=',' read -r -a _raw <<< "$_input"
        for _d in "${_raw[@]}"; do
            [[ -n "$_d" ]] && DOMAINS+=("$_d")
        done
        CDSI_DOMAIN="$_input"
    fi
fi

if [[ "${#DOMAINS[@]}" -eq 0 ]] && [[ "${IP_MODE:-false}" != true ]]; then
    ensure_certbot_renewal_timer
    log "No active domain provided; Certbot is installed and the site remains HTTP-only."
    log "Configure one later with: sudo bash scripts/configure-domain.sh example.com"
    log "Then enable HTTPS with: sudo bash scripts/configure-https.sh"
    exit 10
fi

[[ "$NGINX_AVAILABLE" == true ]] \
    || fail "Nginx is not installed. Install Nginx first, then re-run Certbot."

SERVER_IP="$(cdsi_resolve_wordpress_server_ip "${CDSI_WORDPRESS_DIR:-/var/www/wordpress}" || true)"
[[ -n "$SERVER_IP" ]] \
    || fail "Could not determine the server IP. Set CDSI_SERVER_IP and retry."

PRIMARY_DOMAIN=""
CERT_NAME=""
TARGET_LABEL=""
EMAIL_ARGS=()
IDENTIFIERS=()
if [[ "$IP_MODE" == true ]]; then
    cdsi_is_public_ipv4 "$SERVER_IP" \
        || fail "Publicly trusted IP certificates require a public IPv4 address."
    [[ ! -s "$DOMAIN_FILE" ]] \
        || fail "An active domain exists. Run configure-domain.sh --clear before explicitly enabling IP HTTPS."
    if ! certbot_supports_ip_certificates; then
        log_fail "The system Certbot does not support IP certificates (requires Certbot 5.4+ with --ip-address). HTTPS was deferred and HTTP was not changed."
        exit 10
    fi
    CERT_NAME="$SERVER_IP"
    TARGET_LABEL="$SERVER_IP"
    IDENTIFIERS=("$SERVER_IP")
    if [[ -n "${CDSI_CERT_EMAIL:-}" ]]; then
        EMAIL_ARGS=(--email "$CDSI_CERT_EMAIL" --no-eff-email)
    else
        EMAIL_ARGS=(--register-unsafely-without-email)
    fi
else
    PRIMARY_DOMAIN="${DOMAINS[0]}"
    CERT_NAME="$PRIMARY_DOMAIN"
    TARGET_LABEL="${DOMAINS[*]}"
    IDENTIFIERS=("${DOMAINS[@]}")
    EMAIL="${CDSI_CERT_EMAIL:-admin@${PRIMARY_DOMAIN}}"
    EMAIL_ARGS=(--email "$EMAIL" --no-eff-email)
fi

CERT_DIR="${CDSI_CERTBOT_CONFIG_DIR}/live/${CERT_NAME}"
CERT_ALREADY_VALID=false
if certificate_valid_for_identifiers "$CERT_DIR" "${IDENTIFIERS[@]}"; then
    CERT_ALREADY_VALID=true
    log_ok "Existing certificate is valid for ${TARGET_LABEL}."
fi

write_pending_domain() {
    local value="$1"
    local temporary=""
    if [[ -z "$SUDO" ]]; then
        cdsi_domain_state_write "$PENDING_DOMAIN_FILE" "$value"
        return
    fi
    temporary="$(mktemp "${TMPDIR:-/tmp}/cdsi-domain-pending.XXXXXX")" \
        || return 1
    printf '%s\n' "$value" > "$temporary" \
        && chmod 0644 "$temporary" \
        && ${SUDO} mkdir -p "$(dirname "$PENDING_DOMAIN_FILE")" \
        && ${SUDO} install -m 0644 "$temporary" "$PENDING_DOMAIN_FILE"
    local status=$?
    rm -f -- "$temporary"
    return "$status"
}

if [[ "$IP_MODE" != true ]]; then
    cdsi_ensure_dns_tools \
        || fail "Could not install the system DNS query tool required for domain validation."
    active_domain="$(cdsi_domain_state_read "$DOMAIN_FILE" 2>/dev/null || true)"
    if ! cdsi_domain_dns_ready "$CDSI_DOMAIN" "$SERVER_IP"; then
        if [[ "$CERT_ALREADY_VALID" == true && "$active_domain" == "$CDSI_DOMAIN" ]]; then
            log "${CDSI_DNS_MESSAGE} Keeping the already-valid certificate and active HTTPS site."
        else
            write_pending_domain "$CDSI_DOMAIN" \
                || fail "${CDSI_DNS_MESSAGE} The pending state could not be saved."
            log_fail "${CDSI_DNS_MESSAGE} Certificate issuance was deferred and HTTP remains available."
            exit 10
        fi
    elif [[ "$CDSI_DNS_STATUS" != ready ]]; then
        log "DNS override active: ${CDSI_DNS_MESSAGE}"
    else
        log_ok "$CDSI_DNS_MESSAGE"
    fi

    if [[ "$active_domain" != "$CDSI_DOMAIN" ]]; then
        log "Activating the verified domain before requesting its certificate..."
        ${SUDO} env \
            CDSI_DOMAIN="$CDSI_DOMAIN" \
            CDSI_SERVER_IP="$SERVER_IP" \
            CDSI_ALLOW_DNS_MISMATCH="${CDSI_ALLOW_DNS_MISMATCH:-false}" \
            bash "${CDSI_ROOT}/scripts/configure-domain.sh" "$CDSI_DOMAIN" \
            || fail "The verified domain could not be activated."
    fi
    _update_server_name
fi

ACME_SERVER="$ACME_PRIMARY_SERVER"
EAB_CONFIG=""
cleanup_certbot_secret() {
    [[ -z "$EAB_CONFIG" ]] || rm -f -- "$EAB_CONFIG" 2>/dev/null || true
}
trap cleanup_certbot_secret EXIT

if [[ "$CERT_ALREADY_VALID" != true ]]; then
    if [[ "$IP_MODE" == true ]]; then
        acme_directory_reachable "$ACME_PRIMARY_SERVER" \
            || { log_fail "Let's Encrypt ACME directory is unreachable; IP certificate issuance was deferred. HTTP was not changed."; exit 10; }
    else
        ACME_SERVER="$(select_acme_server)" \
            || { log_fail "Neither the primary ACME directory nor the configured fallback is reachable. HTTP remains available."; exit 10; }
        if [[ "$ACME_SERVER" == "$ACME_FALLBACK_SERVER" ]]; then
            log "Primary ACME directory is unreachable; using the explicitly configured fallback."
        fi
    fi
fi

if [[ "$ACME_SERVER" == "$ACME_FALLBACK_SERVER" && -n "$ACME_FALLBACK_SERVER" ]]; then
    EAB_KID="${CDSI_ACME_FALLBACK_EAB_KID:-}"
    EAB_HMAC="${CDSI_ACME_FALLBACK_EAB_HMAC_KEY:-}"
    if [[ "$ACME_SERVER" == *zerossl* && ( -z "$EAB_KID" || -z "$EAB_HMAC" ) ]]; then
        fail "ZeroSSL fallback requires CDSI_ACME_FALLBACK_EAB_KID and CDSI_ACME_FALLBACK_EAB_HMAC_KEY."
    fi
    if [[ -n "$EAB_KID" || -n "$EAB_HMAC" ]]; then
        [[ "$EAB_KID" =~ ^[A-Za-z0-9._-]+$ \
           && "$EAB_HMAC" =~ ^[A-Za-z0-9_-]+={0,2}$ ]] \
            || fail "Fallback EAB credentials contain invalid characters."
        EAB_CONFIG="$(mktemp "${TMPDIR:-/tmp}/cdsi-certbot-eab.XXXXXX")" \
            || fail "Could not create a protected Certbot EAB configuration."
        chmod 0600 "$EAB_CONFIG"
        printf 'eab-kid = %s\neab-hmac-key = %s\n' "$EAB_KID" "$EAB_HMAC" > "$EAB_CONFIG"
    fi
fi

CERTBOT_CONFIG_ARGS=()
[[ -z "$EAB_CONFIG" ]] || CERTBOT_CONFIG_ARGS=(--config "$EAB_CONFIG")
CERTBOT_LOG="$(mktemp)"
DNS_ARGS=()
for d in "${DOMAINS[@]}"; do
    DNS_ARGS+=(-d "$d")
done

if [[ "$CERT_ALREADY_VALID" != true ]]; then
    set +e
    if [[ "$IP_MODE" == true ]]; then
        log "Requesting a short-lived Let's Encrypt IP certificate..."
        ${SUDO} "${CERTBOT_BIN}" certonly \
            --webroot --webroot-path "${CDSI_WORDPRESS_DIR:-/var/www/wordpress}" \
            --preferred-profile shortlived \
            --ip-address "$SERVER_IP" \
            --cert-name "$CERT_NAME" \
            --server "$ACME_SERVER" \
            --non-interactive --agree-tos \
            "${EMAIL_ARGS[@]}" \
            --key-type rsa \
            "${CERTBOT_CONFIG_ARGS[@]}" \
            2>&1 | tee "$CERTBOT_LOG"
    else
        log "Requesting a domain certificate with the Certbot Nginx plugin..."
        ${SUDO} "${CERTBOT_BIN}" --nginx \
            "${DNS_ARGS[@]}" \
            --cert-name "$CERT_NAME" \
            --server "$ACME_SERVER" \
            --non-interactive --agree-tos \
            "${EMAIL_ARGS[@]}" \
            --redirect --key-type rsa \
            "${CERTBOT_CONFIG_ARGS[@]}" \
            2>&1 | tee "$CERTBOT_LOG"
    fi
    CERTBOT_RC="${PIPESTATUS[0]}"
    set -e
    if [[ "$CERTBOT_RC" -ne 0 ]]; then
        if grep -qiE "too many certificates|rate.?limit|retry after" "$CERTBOT_LOG"; then
            log_fail "Certificate authority rate limit reached. HTTP remains available; no fallback CA was attempted."
            rm -f -- "$CERTBOT_LOG"
            exit 10
        fi
        tail -20 "$CERTBOT_LOG" >&2 || true
        rm -f -- "$CERTBOT_LOG"
        fail "Certbot failed (exit ${CERTBOT_RC}). DNS/CAA/authorization failures do not trigger automatic CA fallback."
    fi
else
    log "Certificate issuance skipped; applying the existing certificate configuration."
    if [[ "$IP_MODE" != true ]]; then
        set +e
        ${SUDO} "${CERTBOT_BIN}" --nginx \
            "${DNS_ARGS[@]}" --cert-name "$CERT_NAME" \
            --non-interactive --redirect --reinstall \
            2>&1 | tee "$CERTBOT_LOG"
        CERTBOT_RC="${PIPESTATUS[0]}"
        set -e
        [[ "$CERTBOT_RC" -eq 0 ]] \
            || fail "Certbot could not re-apply the existing domain certificate."
    fi
fi
rm -f -- "$CERTBOT_LOG"

certificate_valid_for_identifiers "$CERT_DIR" "${IDENTIFIERS[@]}" \
    || fail "The issued certificate failed SAN, expiry, or private-key validation."

if [[ "$IP_MODE" == true ]]; then
    # Refresh the IP-mode template so its TLS include exists before installing
    # the snippet. This is configure-only and does not reinstall WordPress.
    CDSI_WORDPRESS_CONFIGURE_ONLY=true \
    CDSI_SKIP_CERTBOT=true \
    CDSI_DNS_VERIFIED=true \
    CDSI_FORCE_IP=true \
    CDSI_DOMAIN="" \
    CDSI_SITE_SCHEME="" \
    CDSI_SERVER_IP="$SERVER_IP" \
        bash "${CDSI_ROOT}/scripts/install-wordpress.sh" \
        || fail "Could not prepare the WordPress Nginx site for IP HTTPS."
    install_ip_tls_nginx "$CERT_DIR" \
        || fail "Could not install the IP TLS Nginx configuration; the previous configuration was restored."
    update_wordpress_https_url "https://${SERVER_IP}" \
        || fail "IP HTTPS is active, but WordPress could not be switched to its HTTPS URL."
else
    update_wordpress_https_url "https://${PRIMARY_DOMAIN}" \
        || fail "HTTPS is active, but WordPress could not be switched to its HTTPS URL."
fi

install_renewal_deploy_hook

# ── Enable auto-renewal ───────────────────────────────────
RENEWAL_SUMMARY="manual: ${CERTBOT_BIN} renew"
RENEWAL_TIMER=""
ensure_certbot_renewal_timer

# ── Verify ─────────────────────────────────────────────────
if declare -F check_port_listening >/dev/null 2>&1; then
    check_port_listening 443 \
        || fail "Nginx is not listening on port 443 after certificate installation."
fi
log_ok "Certificate list:"
${SUDO} "${CERTBOT_BIN}" certificates 2>/dev/null | sed 's/^/  /' || true

log_ok "Certbot setup complete."
log "  Target:    ${TARGET_LABEL}"
log "  CA:        ${ACME_SERVER}"
log "  Cert path: ${CERT_DIR}/"
log "  Renewal:   ${RENEWAL_SUMMARY}; test with '${CERTBOT_BIN} renew --dry-run'"

exit 0
