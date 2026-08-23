#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    _cdsi_script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
    exec /bin/sh "${_cdsi_script_dir}/../../lib/bootstrap.sh" \
        "${_cdsi_script_dir}/$(basename "$0")" "$@"
fi
# CDSI Anchor - Nginx installer
# Standalone script - can be called by install.sh or run directly:
#   bash scripts/install-nginx.sh

set -Eeuo pipefail

log() {
    printf '\033[1;34m[CDSI]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

fail() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"
# shellcheck source=../../lib/dnf.sh
source "${CDSI_ROOT}/lib/dnf.sh"
# shellcheck source=../../lib/platform.sh
source "${CDSI_ROOT}/lib/platform.sh"
# shellcheck source=../../lib/packages.sh
source "${CDSI_ROOT}/lib/packages.sh"
# shellcheck source=../../lib/services.sh
source "${CDSI_ROOT}/lib/services.sh"

if [[ "${EUID}" -eq 0 ]]; then
    ROOT_CMD=()
elif command -v sudo >/dev/null 2>&1; then
    ROOT_CMD=(sudo)
else
    fail "This script requires root privileges or sudo."
fi

cdsi_platform_init
if ! cdsi_platform_supported; then
    fail "Unsupported operating system: ${CDSI_OS_PRETTY}. Supported: Ubuntu 24.04/26.04 LTS and CentOS Stream 10."
fi

resolve_nginx_bin() {
    local candidate=""
    candidate="$(command -v nginx 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    for candidate in /usr/sbin/nginx; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

command -v systemctl >/dev/null 2>&1 || fail "systemctl is required."

if cdsi_is_ubuntu; then
    command -v apt-get >/dev/null 2>&1 || fail "apt-get is required."

    # Do not silently mix nginx.org or PPA packages with Ubuntu's packages.
    for source_file in \
        /etc/apt/sources.list \
        /etc/apt/sources.list.d/*.list \
        /etc/apt/sources.list.d/*.sources; do
        [[ -f "$source_file" ]] || continue
        if grep -qsE 'nginx\.org|ppa\.launchpad(content)?\.net/ondrej/nginx|ppa:(nginx|ondrej/nginx)' "$source_file"; then
            fail "Third-party Nginx source detected in ${source_file}. Remove it before continuing."
        fi
    done
fi

# Build the nginx.conf update without relying on in-place sed behavior.
_render_main_config() {
    local output_file="$1"
    local add_server_tokens=0
    local replace_server_tokens=0

    if grep -Eq '^[[:space:]]*server_tokens[[:space:]]+[^;]+;' "$CDSI_NGINX_MAIN_CONF"; then
        replace_server_tokens=1
    else
        add_server_tokens=1
    fi

    awk \
        -v add_server_tokens="$add_server_tokens" \
        -v replace_server_tokens="$replace_server_tokens" \
        '
        BEGIN { inserted = 0 }
        {
            line = $0
            if (replace_server_tokens && line ~ /^[[:space:]]*server_tokens[[:space:]]+[^;]+;/) {
                sub(/server_tokens[[:space:]]+[^;]+;/, "server_tokens off;", line)
            }
            print line
            if (!inserted && line ~ /^[[:space:]]*http[[:space:]]*\{/) {
                if (add_server_tokens) {
                    print "    server_tokens off;"
                }
                inserted = 1
            }
        }
        END {
            if (add_server_tokens && !inserted) {
                exit 42
            }
        }
    ' "$CDSI_NGINX_MAIN_CONF" > "$output_file"
}

_restore_tuning() {
    local main_backup="$1"
    local tuning_backup="$2"
    local tuning_existed="$3"
    local tuning_file="$4"

    if [[ -n "$main_backup" && -f "$main_backup" ]]; then
        "${ROOT_CMD[@]}" cp "$main_backup" "$CDSI_NGINX_MAIN_CONF" || true
    fi
    if [[ "$tuning_existed" == "1" ]]; then
        "${ROOT_CMD[@]}" cp "$tuning_backup" "$tuning_file" || true
    else
        "${ROOT_CMD[@]}" rm -f "$tuning_file" || true
    fi
}

_cleanup_tuning_files() {
    local file=""
    for file in "$@"; do
        [[ -z "$file" ]] || rm -f "$file"
    done
}

# Apply global tuning on fresh installs and safe reruns. Any invalid update is
# rolled back before the function reports failure.
_apply_tuning() {
    local tuning_dir="${CDSI_NGINX_CONF_DIR}/conf.d"
    local tuning_file="${tuning_dir}/cdsi-tuning.conf"
    local main_candidate main_backup="" tuning_candidate tuning_backup
    local tuning_existed=0

    [[ -f "$CDSI_NGINX_MAIN_CONF" ]] || return 1
    main_candidate="$(mktemp "${TMPDIR:-/tmp}/cdsi-nginx-main.XXXXXX")" || return 1
    tuning_candidate="$(mktemp "${TMPDIR:-/tmp}/cdsi-nginx-tuning.XXXXXX")" || {
        _cleanup_tuning_files "$main_candidate"
        return 1
    }
    tuning_backup="$(mktemp "${TMPDIR:-/tmp}/cdsi-nginx-tuning-backup.XXXXXX")" || {
        _cleanup_tuning_files "$main_candidate" "$tuning_candidate"
        return 1
    }

    if ! _render_main_config "$main_candidate"; then
        _cleanup_tuning_files "$main_candidate" "$tuning_candidate" "$tuning_backup"
        warn "Could not find the Nginx http block while preparing global tuning."
        return 1
    fi

    cat > "$tuning_candidate" <<'TUNING'
# CDSI Nginx global tuning - http block level.
# Managed by install-nginx.sh; rerunning the installer overwrites this file.

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

ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
TUNING

    if ! cmp -s "$main_candidate" "$CDSI_NGINX_MAIN_CONF"; then
        main_backup="$(mktemp "${TMPDIR:-/tmp}/cdsi-nginx-main-backup.XXXXXX")" || {
            _cleanup_tuning_files "$main_candidate" "$tuning_candidate" "$tuning_backup"
            return 1
        }
        if ! cp "$CDSI_NGINX_MAIN_CONF" "$main_backup"; then
            _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
            return 1
        fi
    fi

    if [[ -f "$tuning_file" ]]; then
        tuning_existed=1
        if ! cp "$tuning_file" "$tuning_backup"; then
            _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
            return 1
        fi
    fi

    log "Applying CDSI global Nginx tuning..."
    if ! "${ROOT_CMD[@]}" mkdir -p "$tuning_dir"; then
        _restore_tuning "$main_backup" "$tuning_backup" "$tuning_existed" "$tuning_file"
        _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
        return 1
    fi
    if [[ -n "$main_backup" ]] \
       && ! "${ROOT_CMD[@]}" cp "$main_candidate" "$CDSI_NGINX_MAIN_CONF"; then
        _restore_tuning "$main_backup" "$tuning_backup" "$tuning_existed" "$tuning_file"
        _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
        return 1
    fi
    if ! "${ROOT_CMD[@]}" cp "$tuning_candidate" "$tuning_file"; then
        _restore_tuning "$main_backup" "$tuning_backup" "$tuning_existed" "$tuning_file"
        _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
        return 1
    fi

    if ! "${ROOT_CMD[@]}" "$NGINX_BIN" -t; then
        _restore_tuning "$main_backup" "$tuning_backup" "$tuning_existed" "$tuning_file"
        _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
        warn "Nginx tuning was rolled back because configuration validation failed."
        return 1
    fi

    if cdsi_service_active "$CDSI_NGINX_SERVICE"; then
        if ! cdsi_service_reload "$CDSI_NGINX_SERVICE"; then
            _restore_tuning "$main_backup" "$tuning_backup" "$tuning_existed" "$tuning_file"
            "${ROOT_CMD[@]}" "$NGINX_BIN" -t >/dev/null 2>&1 || true
            cdsi_service_reload "$CDSI_NGINX_SERVICE" >/dev/null 2>&1 || true
            _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
            warn "Nginx tuning was rolled back because the service could not reload."
            return 1
        fi
    fi

    _cleanup_tuning_files "$main_candidate" "$main_backup" "$tuning_candidate" "$tuning_backup"
    log "Global tuning applied: server_tokens off, gzip types, SSL session cache."
}

_port_is_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH | awk -v port="$port" '$4 ~ (":" port "$") {found=1} END{exit found ? 0 : 1}'
    else
        return 2
    fi
}

_record_firewall_service() {
    local scope="$1"
    local service_name="$2"
    local record_dir="/etc/cdsi"
    local record_file="${record_dir}/firewall-added-services"
    local record_entry="${scope}:${service_name}"
    local record_tmp=""

    case "$record_entry" in
        permanent:http|permanent:https|runtime:http|runtime:https) ;;
        *) return 1 ;;
    esac

    if ! "${ROOT_CMD[@]}" mkdir -p "$record_dir"; then
        return 1
    fi

    record_tmp="$(mktemp "${TMPDIR:-/tmp}/cdsi-firewall-marker.XXXXXX")" \
        || return 1
    if [[ -f "$record_file" ]] \
       && ! "${ROOT_CMD[@]}" cat -- "$record_file" > "$record_tmp"; then
        rm -f -- "$record_tmp"
        return 1
    fi
    if ! awk 'NF && $0 !~ /^(permanent|runtime):(http|https)$/ { exit 1 }' \
        "$record_tmp"; then
        rm -f -- "$record_tmp"
        return 1
    fi
    if grep -Fqx -- "$record_entry" "$record_tmp"; then
        rm -f -- "$record_tmp"
        return 0
    fi
    printf '%s\n' "$record_entry" >> "$record_tmp"
    if ! "${ROOT_CMD[@]}" install -m 600 "$record_tmp" "$record_file"; then
        rm -f -- "$record_tmp"
        return 1
    fi
    rm -f -- "$record_tmp"
}

_firewall_scope_present() {
    local scope="$1"
    local service_name="$2"
    if [[ "$scope" == "permanent" ]]; then
        "${ROOT_CMD[@]}" firewall-cmd --permanent \
            --query-service="$service_name" >/dev/null 2>&1
    else
        "${ROOT_CMD[@]}" firewall-cmd \
            --query-service="$service_name" >/dev/null 2>&1
    fi
}

_firewall_scope_add() {
    local scope="$1"
    local service_name="$2"
    if [[ "$scope" == "permanent" ]]; then
        "${ROOT_CMD[@]}" firewall-cmd --permanent \
            --add-service="$service_name" >/dev/null
    else
        "${ROOT_CMD[@]}" firewall-cmd \
            --add-service="$service_name" >/dev/null
    fi
}

_firewall_scope_remove() {
    local scope="$1"
    local service_name="$2"
    if [[ "$scope" == "permanent" ]]; then
        "${ROOT_CMD[@]}" firewall-cmd --permanent \
            --remove-service="$service_name" >/dev/null 2>&1
    else
        "${ROOT_CMD[@]}" firewall-cmd \
            --remove-service="$service_name" >/dev/null 2>&1
    fi
}

_ensure_firewall_scope() {
    local scope="$1"
    local service_name="$2"

    if _firewall_scope_present "$scope" "$service_name"; then
        log "firewalld already allows ${service_name} in its ${scope} configuration; leaving that layer unchanged."
        return 0
    fi

    log "Opening ${service_name} in firewalld's ${scope} configuration for Nginx..."
    if ! _firewall_scope_add "$scope" "$service_name"; then
        warn "Could not add firewalld ${service_name} to the ${scope} configuration."
        return 1
    fi

    if ! _record_firewall_service "$scope" "$service_name"; then
        _firewall_scope_remove "$scope" "$service_name" || true
        warn "Could not record the Anchor-added firewalld ${scope} ${service_name} service; that layer was rolled back."
        return 1
    fi
    log "Recorded Anchor-added firewalld layer: ${scope}:${service_name}."
}

_configure_centos_firewall() {
    cdsi_is_centos_stream || return 0
    systemctl is-active --quiet firewalld 2>/dev/null || return 0
    command -v firewall-cmd >/dev/null 2>&1 \
        || { warn "firewalld is active, but firewall-cmd is unavailable."; return 1; }

    local service_name scope
    for service_name in http https; do
        for scope in permanent runtime; do
            _ensure_firewall_scope "$scope" "$service_name" || return 1
        done
    done
}

NGINX_BIN="$(resolve_nginx_bin || true)"

# Skip only when the package, configuration, and service are healthy. Tuning is
# still reconciled so reruns can safely pick up installer changes.
if [[ -n "$NGINX_BIN" ]] && cdsi_service_active "$CDSI_NGINX_SERVICE"; then
    if "${ROOT_CMD[@]}" "$NGINX_BIN" -t >/dev/null 2>&1; then
        if ! cdsi_service_enabled "$CDSI_NGINX_SERVICE"; then
            log "Enabling ${CDSI_NGINX_SERVICE} to start automatically at boot..."
            cdsi_service_enable "$CDSI_NGINX_SERVICE" \
                || fail "Could not enable ${CDSI_NGINX_SERVICE}."
        fi
        cdsi_service_enabled "$CDSI_NGINX_SERVICE" \
            || fail "${CDSI_NGINX_SERVICE} is not enabled at boot."
        _apply_tuning || fail "Could not safely apply Nginx global tuning."
        _configure_centos_firewall \
            || fail "Could not safely configure firewalld for Nginx."
        log "Nginx is already installed, its configuration is valid, and the service is running."
        log "Skipping installation."
        "$NGINX_BIN" -v 2>&1 | sed 's/^/  /'
        exit 0
    fi
fi

# Preserve a broken existing configuration instead of triggering a package
# operation that might reload it.
if [[ -n "$NGINX_BIN" ]]; then
    log "Validating the existing Nginx configuration..."
    if ! "${ROOT_CMD[@]}" "$NGINX_BIN" -t; then
        fail "Existing Nginx configuration is invalid; no changes were made."
    fi
fi

log "Updating ${CDSI_OS_PRETTY} package metadata..."
if ! cdsi_packages_update; then
    fail "Package metadata update failed. Check the system repositories and network connectivity."
fi

log "Installing Nginx from the system default repository..."
if ! cdsi_packages_install nginx; then
    fail "Nginx package installation failed."
fi

NGINX_BIN="$(resolve_nginx_bin || true)"
[[ -n "$NGINX_BIN" ]] || fail "Nginx was not installed."
cdsi_service_installed "$CDSI_NGINX_SERVICE" || fail "The Nginx service was not installed."

log "Validating and applying the Nginx configuration..."
if ! "${ROOT_CMD[@]}" "$NGINX_BIN" -t; then
    fail "Nginx configuration validation failed."
fi
_apply_tuning || fail "Could not safely apply Nginx global tuning."

log "Enabling ${CDSI_NGINX_SERVICE}..."
if ! cdsi_service_enable_now "$CDSI_NGINX_SERVICE"; then
    fail "Could not enable and start ${CDSI_NGINX_SERVICE}."
fi

if ! "${ROOT_CMD[@]}" "$NGINX_BIN" -t; then
    fail "Nginx configuration became invalid after service startup."
fi

if cdsi_service_active "$CDSI_NGINX_SERVICE"; then
    log "${CDSI_NGINX_SERVICE} is running."
else
    fail "${CDSI_NGINX_SERVICE} is not running."
fi

_configure_centos_firewall \
    || fail "Could not safely configure firewalld for Nginx."

if _port_is_listening 80; then
    log "Nginx is listening on port 80."
else
    listener_status=$?
    if [[ "$listener_status" -eq 2 ]]; then
        warn "ss is unavailable; skipped port listener checks."
    else
        fail "Nginx is running but is not listening on port 80."
    fi
fi

if _port_is_listening 443; then
    log "Nginx is listening on port 443."
else
    listener_status=$?
    if [[ "$listener_status" -ne 2 ]]; then
        log "Port 443 is not configured yet; HTTPS will be handled by Certbot."
    fi
fi

if command -v curl >/dev/null 2>&1; then
    HTTP_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/ || true)"
    if [[ "$HTTP_STATUS" =~ ^[0-9]{3}$ ]]; then
        log "Local HTTP request returned status ${HTTP_STATUS}."
    else
        fail "Nginx is running but the local HTTP request failed."
    fi
fi

NGINX_VERSION="$("${ROOT_CMD[@]}" "$NGINX_BIN" -v 2>&1)"
log "Nginx installation completed: ${NGINX_VERSION}"
