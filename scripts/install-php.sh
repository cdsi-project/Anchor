#!/usr/bin/env bash

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
CDSI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"

php_extension_loaded() {
    local extension="$1"
    PHP_EXTENSION_NAME="$extension" "${PHP_BIN}" \
        -r 'exit(extension_loaded(getenv("PHP_EXTENSION_NAME")) ? 0 : 1);'
}

package_candidate_available() {
    local package="$1"
    local candidate=""
    candidate="$(LC_ALL=C apt-cache policy "$package" 2>/dev/null | \
        awk '/Candidate:/{print $2; exit}' || true)"
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

install_php_extension() {
    local extension="$1"
    local required="$2"
    shift 2

    if php_extension_loaded "$extension"; then
        log "PHP extension ${extension} is already loaded."
        return 0
    fi

    local package=""
    local candidate
    for candidate in "$@"; do
        if package_candidate_available "$candidate"; then
            package="$candidate"
            break
        fi
    done

    if [[ -z "$package" ]]; then
        if [[ "$required" == true ]]; then
            fail "No Ubuntu package candidate is available for required PHP extension ${extension}: $*"
        fi
        warn "Optional PHP extension ${extension} is unavailable from the Ubuntu repositories."
        return 0
    fi

    log "Installing ${package} for PHP extension ${extension}..."
    if ! cdsi_apt_get install -y "$package"; then
        if [[ "$required" == true ]]; then
            fail "Could not install required PHP extension ${extension} from ${package}."
        fi
        warn "Could not install optional PHP extension ${extension} from ${package}."
        return 0
    fi

    if ! php_extension_loaded "$extension"; then
        if [[ "$required" == true ]]; then
            fail "Required PHP extension ${extension} is not loaded after installing ${package}."
        fi
        warn "Optional PHP extension ${extension} is not loaded after installing ${package}."
        return 0
    fi

    log "PHP extension ${extension} is loaded."
}

if [[ "${EUID}" -eq 0 ]]; then
    ROOT_CMD=()
elif command -v sudo >/dev/null 2>&1; then
    ROOT_CMD=(sudo)
else
    fail "This script requires root privileges or sudo."
fi

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

# A previously configured PHP PPA can override Ubuntu packages or make
# apt-get update fail on unsupported Ubuntu releases. Do not remove it
# automatically because it may be used by another application.
for source_file in \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list \
    /etc/apt/sources.list.d/*.sources; do
    [[ -f "$source_file" ]] || continue
    if grep -qsE 'ppa\.launchpad(content)?\.net/ondrej/php|ppa:ondrej/php' "$source_file"; then
        fail "Third-party Ondrej PHP source detected in ${source_file}. Remove it before continuing: sudo add-apt-repository --remove -y ppa:ondrej/php"
    fi
done

# ── Idempotency: skip if PHP-FPM is already installed and running ──
# The step functions below are individually idempotent, but re-running the
# full apt-get install + service enable on every invocation is wasteful and
# noisy. Only fall through to a real install when something is actually missing.
if command -v php >/dev/null 2>&1; then
    _cur="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"
    if [[ -n "$_cur" ]] \
       && command -v "php-fpm${_cur}" >/dev/null 2>&1 \
       && systemctl is-active --quiet "php${_cur}-fpm" 2>/dev/null \
       && php -m 2>/dev/null | grep -qi 'mysqli'; then
        log "PHP ${_cur} (php-fpm + core extensions) is already installed and running."
        log "Skipping installation."
        php -v 2>&1 | head -1 | sed 's/^/  /'
        exit 0
    fi
fi

log "Installing the Ubuntu default PHP version on ${PRETTY_NAME:-Ubuntu}..."

PHP_PACKAGES=(
    php-cli
    php-fpm
    php-common
    php-curl
    php-mbstring
    php-xml
    php-zip
    php-bcmath
    php-intl
    php-mysql
)

log "Updating Ubuntu package metadata..."
if ! cdsi_apt_get update; then
    fail "apt-get update failed. Check the configured Ubuntu sources and network connectivity."
fi

log "Installing PHP packages from the Ubuntu repositories..."
if ! cdsi_apt_get install -y "${PHP_PACKAGES[@]}"; then
    fail "PHP package installation failed."
fi

FPM_DEPENDS=""
if ! FPM_DEPENDS="$(dpkg-query -W -f='${Depends}' php-fpm 2>/dev/null)"; then
    fail "Could not inspect the installed php-fpm package."
fi

if [[ "$FPM_DEPENDS" =~ (php[0-9]+\.[0-9]+-fpm) ]]; then
    FPM_PACKAGE="${BASH_REMATCH[1]}"
else
    fail "Could not determine the Ubuntu default PHP-FPM version from: ${FPM_DEPENDS}"
fi

PHP_VERSION="${FPM_PACKAGE#php}"
PHP_VERSION="${PHP_VERSION%-fpm}"

PHP_BIN="/usr/bin/php${PHP_VERSION}"

[[ -x "${PHP_BIN}" ]] || fail "PHP ${PHP_VERSION} binary was not installed."

install_php_extension "Zend OPcache" true \
    php-opcache "php${PHP_VERSION}-opcache"
install_php_extension redis true \
    php-redis "php${PHP_VERSION}-redis"
install_php_extension gd true \
    php-gd "php${PHP_VERSION}-gd"
install_php_extension imagick false \
    php-imagick "php${PHP_VERSION}-imagick"

FPM_SERVICE="php${PHP_VERSION}-fpm"

log "Enabling ${FPM_SERVICE}..."
if ! "${ROOT_CMD[@]}" systemctl enable --now "${FPM_SERVICE}"; then
    fail "Could not enable and start ${FPM_SERVICE}."
fi

INSTALLED_VERSION="$("${PHP_BIN}" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"

if [[ "${INSTALLED_VERSION}" != "${PHP_VERSION}" ]]; then
    fail "Expected PHP ${PHP_VERSION}, but installed ${INSTALLED_VERSION}."
fi

log "Installed PHP version: ${INSTALLED_VERSION}"

if command -v php >/dev/null 2>&1; then
    DEFAULT_PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
    if [[ "$DEFAULT_PHP_VERSION" != "$PHP_VERSION" ]]; then
        warn "The system php command points to ${DEFAULT_PHP_VERSION}; PHP-FPM uses ${PHP_VERSION}. Existing alternatives were left unchanged."
    fi
else
    warn "The system php command is not available on PATH."
fi

if "${ROOT_CMD[@]}" systemctl is-active --quiet "${FPM_SERVICE}"; then
    log "${FPM_SERVICE} is running."
else
    fail "${FPM_SERVICE} is not running."
fi

log "PHP-FPM socket:"
if [[ -S "/run/php/php${PHP_VERSION}-fpm.sock" ]]; then
    printf '  /run/php/php%s-fpm.sock\n' "${PHP_VERSION}"
else
    fail "Expected socket /run/php/php${PHP_VERSION}-fpm.sock was not found."
fi

log "PHP installation completed."
