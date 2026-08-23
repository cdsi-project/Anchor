#!/bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    _cdsi_script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
    exec /bin/sh "${_cdsi_script_dir}/../../lib/bootstrap.sh" \
        "${_cdsi_script_dir}/$(basename "$0")" "$@"
fi

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

resolve_php_bin() {
    local candidate=""

    if cdsi_is_centos_stream \
       && [[ -n "${CDSI_PHP_BIN:-}" && -x "$CDSI_PHP_BIN" ]]; then
        printf '%s\n' "$CDSI_PHP_BIN"
        return 0
    fi

    candidate="$(command -v php 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    for candidate in /usr/bin/php; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

resolve_fpm_bin() {
    local version="$1"
    local candidate=""

    if cdsi_is_centos_stream; then
        for candidate in \
            "${CDSI_PHP_FPM_BIN:-}" \
            "$(command -v php-fpm 2>/dev/null || true)" \
            /usr/sbin/php-fpm; do
            if [[ -n "$candidate" && -x "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
        return 1
    fi

    for candidate in \
        "$(command -v "php-fpm${version}" 2>/dev/null || true)" \
        "/usr/sbin/php-fpm${version}"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

php_extension_loaded() {
    local extension="$1"
    PHP_EXTENSION_NAME="$extension" "$PHP_BIN" \
        -r 'exit(extension_loaded(getenv("PHP_EXTENSION_NAME")) ? 0 : 1);'
}

required_php_extensions_loaded() {
    local extension=""
    local -a extensions=(
        curl
        dom
        fileinfo
        filter
        gd
        iconv
        mbstring
        mysqli
        "Zend OPcache"
        Phar
        posix
        redis
        session
        SimpleXML
        tokenizer
        xml
        xmlreader
        xmlwriter
        zip
    )

    for extension in "${extensions[@]}"; do
        php_extension_loaded "$extension" || return 1
    done
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
    local candidate=""
    for candidate in "$@"; do
        if cdsi_package_available "$candidate"; then
            package="$candidate"
            break
        fi
    done

    if [[ -z "$package" ]]; then
        if [[ "$required" == true ]]; then
            fail "No system package is available for required PHP extension ${extension}: $*"
        fi
        warn "Optional PHP extension ${extension} is unavailable from the system repository."
        return 0
    fi

    log "Installing ${package} for PHP extension ${extension}..."
    if ! cdsi_packages_install "$package"; then
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

php_base_packages() {
    cdsi_platform_init
    case "$CDSI_PLATFORM" in
        ubuntu)
            printf '%s\n' \
                php-cli \
                php-fpm \
                php-common \
                php-curl \
                php-mbstring \
                php-xml \
                php-zip \
                php-bcmath \
                php-intl \
                php-mysql
            ;;
        centos-stream)
            printf '%s\n' \
                php-cli \
                php-fpm \
                php-common \
                php-mbstring \
                php-xml \
                php-bcmath \
                php-intl \
                php-mysqlnd \
                php-process
            ;;
        *)
            return 1
            ;;
    esac
}

install_required_php_extensions() {
    local version="$1"
    case "$CDSI_PLATFORM" in
        ubuntu)
            install_php_extension "Zend OPcache" true \
                php-opcache "php${version}-opcache"
            install_php_extension redis true \
                php-redis "php${version}-redis"
            install_php_extension gd true \
                php-gd "php${version}-gd"
            ;;
        centos-stream)
            install_php_extension "Zend OPcache" true php-opcache
            install_php_extension redis true php-pecl-redis6
            install_php_extension gd true php-gd
            install_php_extension zip true php-pecl-zip
            ;;
        *)
            return 1
            ;;
    esac
}

install_optional_imagick() {
    local version="$1"
    if cdsi_is_ubuntu; then
        install_php_extension imagick false \
            php-imagick "php${version}-imagick"
        return
    fi

    cdsi_is_centos_stream || return 1
    if php_extension_loaded imagick; then
        log "PHP extension imagick is already loaded."
        return 0
    fi

    log "Enabling EPEL for the optional PHP Imagick package..."
    if ! cdsi_enable_epel; then
        warn "Could not enable EPEL; optional PHP extension imagick was skipped."
        return 0
    fi
    install_php_extension imagick false php-pecl-imagick
}

resolve_installed_php_runtime() {
    local fpm_depends=""
    if cdsi_is_ubuntu; then
        if ! fpm_depends="$(dpkg-query -W -f='${Depends}' php-fpm 2>/dev/null)"; then
            fail "Could not inspect the installed php-fpm package."
        fi
        if [[ "$fpm_depends" =~ (php[0-9]+\.[0-9]+-fpm) ]]; then
            FPM_PACKAGE="${BASH_REMATCH[1]}"
        else
            fail "Could not determine the Ubuntu default PHP-FPM version from: ${fpm_depends}"
        fi
        PHP_VERSION="${FPM_PACKAGE#php}"
        PHP_VERSION="${PHP_VERSION%-fpm}"
        PHP_BIN="/usr/bin/php${PHP_VERSION}"
        return 0
    fi

    cdsi_is_centos_stream || return 1
    FPM_PACKAGE="php-fpm"
    PHP_BIN="$(resolve_php_bin || true)"
    [[ -n "$PHP_BIN" && -x "$PHP_BIN" ]] \
        || fail "The system PHP binary was not installed."
    PHP_VERSION="$("$PHP_BIN" \
        -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"
    [[ "$PHP_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] \
        || fail "Could not determine the installed PHP version."
}

# Keep this implementation sourceable so focused tests can exercise package and
# runtime mappings without performing installation work.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

if [[ "${EUID}" -eq 0 ]]; then
    ROOT_CMD=()
elif command -v sudo >/dev/null 2>&1; then
    ROOT_CMD=(sudo)
else
    fail "This script requires root privileges or sudo."
fi

cdsi_platform_init
if ! cdsi_platform_supported; then
    fail "Unsupported operating system: ${CDSI_OS_PRETTY}. Supported: Ubuntu 24.04/26.04 LTS or CentOS Stream 10."
fi

command -v systemctl >/dev/null 2>&1 || fail "systemctl is required."

if cdsi_is_ubuntu; then
    command -v apt-get >/dev/null 2>&1 || fail "apt-get is required."

    # Do not remove a configured PPA automatically because another application
    # on the host may depend on it.
    for source_file in \
        /etc/apt/sources.list \
        /etc/apt/sources.list.d/*.list \
        /etc/apt/sources.list.d/*.sources; do
        [[ -f "$source_file" ]] || continue
        if grep -qsE 'ppa\.launchpad(content)?\.net/ondrej/php|ppa:ondrej/php' "$source_file"; then
            fail "Third-party Ondrej PHP source detected in ${source_file}. Remove it before continuing: sudo add-apt-repository --remove -y ppa:ondrej/php"
        fi
    done
elif cdsi_is_centos_stream; then
    command -v dnf >/dev/null 2>&1 || fail "dnf is required."
fi

# Skip only if the expected runtime, all required extensions, and PHP-FPM are
# already healthy.

PHP_BIN="$(resolve_php_bin || true)"
if [[ -n "$PHP_BIN" ]]; then
    current_version="$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"
    current_fpm_service="$(cdsi_php_service_name "$current_version")"
    current_fpm_bin="$(resolve_fpm_bin "$current_version" || true)"
    expected_version="$current_version"

    if [[ -n "$current_version" && "$current_version" == "$expected_version" \
          && -n "$current_fpm_bin" \
          && -n "$current_fpm_service" ]] \
       && cdsi_service_active "$current_fpm_service" \
       && required_php_extensions_loaded; then
        cdsi_service_enable_now "$current_fpm_service" \
            || fail "Could not enable ${current_fpm_service} at boot."
        log "PHP ${current_version} (PHP-FPM and required extensions) is already installed and running."
        log "Skipping installation."
        "$PHP_BIN" -v 2>&1 | head -1 | sed 's/^/  /'
        exit 0
    fi
fi

log "Installing PHP from the ${CDSI_OS_PRETTY} system repository..."

mapfile -t PHP_PACKAGES < <(php_base_packages)
[[ "${#PHP_PACKAGES[@]}" -gt 0 ]] \
    || fail "Could not determine the PHP package set for ${CDSI_OS_PRETTY}."

log "Updating package metadata..."
if ! cdsi_packages_update; then
    fail "Package metadata update failed. Check the system repositories and network connectivity."
fi

log "Installing PHP packages from the system default repository..."
if ! cdsi_packages_install "${PHP_PACKAGES[@]}"; then
    fail "PHP package installation failed."
fi

resolve_installed_php_runtime

[[ -n "$PHP_BIN" && -x "$PHP_BIN" ]] || fail "PHP ${PHP_VERSION} binary was not installed."

install_required_php_extensions "$PHP_VERSION"
install_optional_imagick "$PHP_VERSION"

if ! required_php_extensions_loaded; then
    missing_extensions=()
    for required_extension in curl dom fileinfo filter gd iconv mbstring mysqli "Zend OPcache" Phar posix redis session SimpleXML tokenizer xml xmlreader xmlwriter zip; do
        if ! php_extension_loaded "$required_extension"; then
            missing_extensions+=("$required_extension")
        fi
    done
    fail "Required PHP extensions are not loaded: ${missing_extensions[*]}"
fi

FPM_SERVICE="$(cdsi_php_service_name "$PHP_VERSION")"
FPM_BIN="$(resolve_fpm_bin "$PHP_VERSION" || true)"
[[ -n "$FPM_SERVICE" ]] || fail "Could not determine the PHP-FPM service name."
[[ -n "$FPM_BIN" ]] || fail "PHP-FPM ${PHP_VERSION} binary was not installed."
cdsi_service_installed "$FPM_SERVICE" || fail "The ${FPM_SERVICE} service was not installed."

log "Validating PHP-FPM configuration..."
if ! "${ROOT_CMD[@]}" "$FPM_BIN" -t; then
    fail "PHP-FPM configuration validation failed."
fi

log "Enabling ${FPM_SERVICE}..."
if ! cdsi_service_enable_now "$FPM_SERVICE"; then
    fail "Could not enable and start ${FPM_SERVICE}."
fi

# Package managers may start FPM before the extension packages are installed.
# Restart after reconciliation so existing workers load the verified modules.
log "Restarting ${FPM_SERVICE} to load the installed PHP extensions..."
if ! cdsi_service_restart "$FPM_SERVICE"; then
    fail "Could not restart ${FPM_SERVICE} after installing PHP extensions."
fi

INSTALLED_VERSION="$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
if [[ "$INSTALLED_VERSION" != "$PHP_VERSION" ]]; then
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

if cdsi_service_active "$FPM_SERVICE"; then
    log "${FPM_SERVICE} is running."
else
    fail "${FPM_SERVICE} is not running."
fi

FPM_UPSTREAM="$(cdsi_php_fpm_upstream "$PHP_VERSION")"
[[ -n "$FPM_UPSTREAM" ]] || fail "Could not determine the PHP-FPM upstream."

if [[ "$FPM_UPSTREAM" == unix:* ]]; then
    FPM_SOCKET="${FPM_UPSTREAM#unix:}"
    [[ -S "$FPM_SOCKET" ]] || fail "Expected PHP-FPM socket ${FPM_SOCKET} was not found."
else
    FPM_HOST="${FPM_UPSTREAM%:*}"
    FPM_PORT="${FPM_UPSTREAM##*:}"
    if command -v nc >/dev/null 2>&1; then
        nc -z "$FPM_HOST" "$FPM_PORT" >/dev/null 2>&1 \
            || fail "PHP-FPM is not listening on ${FPM_UPSTREAM}."
    else
        warn "nc is unavailable; skipped PHP-FPM listener verification."
    fi
fi

log "PHP-FPM upstream: ${FPM_UPSTREAM}"
log "PHP installation completed."
