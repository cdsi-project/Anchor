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
    php-gd
    php-opcache
)

log "Updating Ubuntu package metadata..."
if ! "${ROOT_CMD[@]}" apt-get update; then
    fail "apt-get update failed. Check the configured Ubuntu sources and network connectivity."
fi

log "Installing PHP packages from the Ubuntu repositories..."
if ! "${ROOT_CMD[@]}" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y "${PHP_PACKAGES[@]}"; then
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

FPM_SERVICE="php${PHP_VERSION}-fpm"

log "Enabling ${FPM_SERVICE}..."
if ! "${ROOT_CMD[@]}" systemctl enable --now "${FPM_SERVICE}"; then
    fail "Could not enable and start ${FPM_SERVICE}."
fi

INSTALLED_VERSION="$("${PHP_BIN}" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"

if [[ "${INSTALLED_VERSION}" != "${PHP_VERSION}" ]]; then
    fail "Expected PHP ${PHP_VERSION}, but installed ${INSTALLED_VERSION}."
fi

log "PHP installation completed."
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
