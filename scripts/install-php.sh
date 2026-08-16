#!/usr/bin/env bash

set -Eeuo pipefail

PHP_VERSION="${PHP_VERSION:-8.5}"

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
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    fail "This script requires root privileges or sudo."
fi

[[ -r /etc/os-release ]] || fail "/etc/os-release not found."

# shellcheck disable=SC1091
source /etc/os-release

case "${ID}" in
    ubuntu|debian)
        ;;
    *)
        fail "Unsupported distribution: ${ID:-unknown}. Currently supports Ubuntu and Debian."
        ;;
esac

log "Installing PHP ${PHP_VERSION} on ${PRETTY_NAME}..."

export DEBIAN_FRONTEND=noninteractive

${SUDO} apt-get update
${SUDO} apt-get install -y \
    ca-certificates \
    curl \
    lsb-release

if [[ "${ID}" == "ubuntu" ]]; then
    log "Configuring Ondrej PHP PPA..."
    ${SUDO} apt-get install -y software-properties-common
    ${SUDO} add-apt-repository -y ppa:ondrej/php
elif [[ "${ID}" == "debian" ]]; then
    log "Configuring DEB.SURY.ORG PHP repository..."

    KEYRING_DEB="/tmp/debsuryorg-archive-keyring.deb"

    curl -fsSL \
        https://packages.sury.org/debsuryorg-archive-keyring.deb \
        -o "${KEYRING_DEB}"

    ${SUDO} dpkg -i "${KEYRING_DEB}"
    rm -f "${KEYRING_DEB}"

    CODENAME="${VERSION_CODENAME:-$(lsb_release -sc)}"

    echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${CODENAME} main" \
        | ${SUDO} tee /etc/apt/sources.list.d/php.list >/dev/null
fi

${SUDO} apt-get update

PHP_PACKAGES=(
    "php${PHP_VERSION}-cli"
    "php${PHP_VERSION}-fpm"
    "php${PHP_VERSION}-common"
    "php${PHP_VERSION}-curl"
    "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-xml"
    "php${PHP_VERSION}-zip"
    "php${PHP_VERSION}-bcmath"
    "php${PHP_VERSION}-intl"
    "php${PHP_VERSION}-mysql"
    "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-opcache"
)

log "Installing PHP packages..."
${SUDO} apt-get install -y "${PHP_PACKAGES[@]}"

PHP_BIN="/usr/bin/php${PHP_VERSION}"

[[ -x "${PHP_BIN}" ]] || fail "PHP ${PHP_VERSION} binary was not installed."

if command -v update-alternatives >/dev/null 2>&1; then
    ${SUDO} update-alternatives --set php "${PHP_BIN}" >/dev/null 2>&1 || true
fi

FPM_SERVICE="php${PHP_VERSION}-fpm"

if command -v systemctl >/dev/null 2>&1; then
    log "Enabling ${FPM_SERVICE}..."
    ${SUDO} systemctl enable --now "${FPM_SERVICE}"
fi

INSTALLED_VERSION="$("${PHP_BIN}" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"

if [[ "${INSTALLED_VERSION}" != "${PHP_VERSION}" ]]; then
    fail "Expected PHP ${PHP_VERSION}, but installed ${INSTALLED_VERSION}."
fi

log "PHP installation completed."
"${PHP_BIN}" --version | head -n 1

if command -v systemctl >/dev/null 2>&1; then
    if ${SUDO} systemctl is-active --quiet "${FPM_SERVICE}"; then
        log "${FPM_SERVICE} is running."
    else
        fail "${FPM_SERVICE} is not running."
    fi
fi

log "PHP-FPM socket:"
if [[ -S "/run/php/php${PHP_VERSION}-fpm.sock" ]]; then
    printf '  /run/php/php%s-fpm.sock\n' "${PHP_VERSION}"
else
    warn "Expected socket /run/php/php${PHP_VERSION}-fpm.sock was not found."
fi
