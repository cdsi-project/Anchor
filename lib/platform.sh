#!/usr/bin/env bash

# Platform detection and deployment constants.

cdsi_platform_init() {
    if [[ "${CDSI_PLATFORM_INITIALIZED:-}" == "1" ]]; then
        return 0
    fi

    local kernel os_id os_version os_name os_pretty arch platform_identity
    kernel="$(uname -s 2>/dev/null || printf 'unknown')"
    arch="$(uname -m 2>/dev/null || printf 'unknown')"

    if [[ "$kernel" == "Linux" ]]; then
        os_id="$(awk -F= '/^ID=/{gsub(/\"/, "", $2); print tolower($2); exit}' /etc/os-release 2>/dev/null || true)"
        os_version="$(awk -F= '/^VERSION_ID=/{gsub(/\"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null || true)"
        os_name="$(awk -F= '/^NAME=/{sub(/^[^=]*=/, ""); gsub(/^\"|\"$/, ""); print; exit}' /etc/os-release 2>/dev/null || true)"
        os_pretty="$(awk -F= '/^PRETTY_NAME=/{sub(/^[^=]*=/, ""); gsub(/^\"|\"$/, ""); print; exit}' /etc/os-release 2>/dev/null || true)"
        platform_identity="$(printf '%s %s' "$os_name" "$os_pretty" \
            | tr '[:upper:]' '[:lower:]')"
        if [[ "$os_id" == "centos" && "$platform_identity" == *"centos stream"* ]]; then
            CDSI_PLATFORM="centos-stream"
        else
            CDSI_PLATFORM="${os_id:-linux}"
        fi
    else
        CDSI_PLATFORM="unknown"
        os_version="unknown"
        os_pretty="$kernel"
    fi

    CDSI_OS_VERSION="${os_version:-unknown}"
    CDSI_OS_PRETTY="${os_pretty:-unknown}"
    CDSI_ARCH="$arch"

    case "$CDSI_PLATFORM" in
        ubuntu)
            CDSI_PACKAGE_BACKEND="apt"
            CDSI_SERVICE_BACKEND="systemd"
            CDSI_WEB_USER="www-data"
            CDSI_WEB_GROUP="www-data"
            CDSI_NGINX_SERVICE="nginx"
            CDSI_NGINX_CONF_DIR="/etc/nginx"
            CDSI_NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
            CDSI_NGINX_SITE_DIR="/etc/nginx/sites-available"
            CDSI_NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
            CDSI_NGINX_LOG_DIR="/var/log/nginx"
            CDSI_DB_PACKAGE="mysql-server"
            CDSI_DB_SERVICE="mysql"
            CDSI_DB_FLAVOR="mysql"
            CDSI_CERTBOT_CONFIG_DIR="/etc/letsencrypt"
            CDSI_PHP_VERSION=""
            CDSI_PHP_PACKAGE_PREFIX="php"
            CDSI_PHP_BIN="/usr/bin/php"
            CDSI_PHP_FPM_BIN=""
            CDSI_PHP_FPM_SERVICE=""
            CDSI_PHP_FPM_UPSTREAM=""
            ;;
        debian)
            CDSI_PACKAGE_BACKEND="apt"
            CDSI_SERVICE_BACKEND="systemd"
            CDSI_WEB_USER="www-data"
            CDSI_WEB_GROUP="www-data"
            CDSI_NGINX_SERVICE="nginx"
            CDSI_NGINX_CONF_DIR="/etc/nginx"
            CDSI_NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
            CDSI_NGINX_SITE_DIR="/etc/nginx/sites-available"
            CDSI_NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
            CDSI_NGINX_LOG_DIR="/var/log/nginx"
            CDSI_DB_PACKAGE="default-mysql-server"
            CDSI_DB_SERVICE="mariadb"
            CDSI_DB_FLAVOR="mariadb"
            CDSI_CERTBOT_CONFIG_DIR="/etc/letsencrypt"
            CDSI_PHP_VERSION=""
            CDSI_PHP_PACKAGE_PREFIX="php"
            CDSI_PHP_BIN="/usr/bin/php"
            CDSI_PHP_FPM_BIN=""
            CDSI_PHP_FPM_SERVICE=""
            CDSI_PHP_FPM_UPSTREAM=""
            ;;
        centos-stream)
            CDSI_PACKAGE_BACKEND="dnf"
            CDSI_SERVICE_BACKEND="systemd"
            CDSI_WEB_USER="apache"
            CDSI_WEB_GROUP="apache"
            CDSI_NGINX_SERVICE="nginx"
            CDSI_NGINX_CONF_DIR="/etc/nginx"
            CDSI_NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
            CDSI_NGINX_SITE_DIR="/etc/nginx/conf.d"
            CDSI_NGINX_ENABLED_DIR="/etc/nginx/conf.d"
            CDSI_NGINX_LOG_DIR="/var/log/nginx"
            CDSI_DB_PACKAGE="mysql8.4-server"
            CDSI_DB_SERVICE="mysqld"
            CDSI_DB_FLAVOR="mysql"
            CDSI_CERTBOT_CONFIG_DIR="/etc/letsencrypt"
            CDSI_PHP_VERSION=""
            CDSI_PHP_PACKAGE_PREFIX="php"
            CDSI_PHP_BIN="/usr/bin/php"
            CDSI_PHP_FPM_BIN="/usr/sbin/php-fpm"
            CDSI_PHP_FPM_SERVICE="php-fpm"
            CDSI_PHP_FPM_UPSTREAM="unix:/run/php-fpm/www.sock"
            ;;
        *)
            CDSI_PACKAGE_BACKEND="unknown"
            CDSI_SERVICE_BACKEND="unknown"
            CDSI_WEB_USER=""
            CDSI_WEB_GROUP=""
            CDSI_NGINX_SERVICE=""
            CDSI_NGINX_CONF_DIR=""
            CDSI_NGINX_MAIN_CONF=""
            CDSI_NGINX_SITE_DIR=""
            CDSI_NGINX_ENABLED_DIR=""
            CDSI_NGINX_LOG_DIR=""
            CDSI_DB_PACKAGE=""
            CDSI_DB_SERVICE=""
            CDSI_DB_FLAVOR=""
            CDSI_CERTBOT_CONFIG_DIR=""
            CDSI_PHP_VERSION=""
            CDSI_PHP_PACKAGE_PREFIX=""
            CDSI_PHP_BIN=""
            CDSI_PHP_FPM_BIN=""
            CDSI_PHP_FPM_SERVICE=""
            CDSI_PHP_FPM_UPSTREAM=""
            ;;
    esac

    # Keep the existing MySQL-prefixed names as compatibility aliases while
    # component scripts migrate to the database-neutral constants.
    CDSI_MYSQL_PACKAGE="$CDSI_DB_PACKAGE"
    CDSI_MYSQL_SERVICE="$CDSI_DB_SERVICE"
    CDSI_MYSQL_FLAVOR="$CDSI_DB_FLAVOR"

    CDSI_PLATFORM_INITIALIZED=1
    export CDSI_PLATFORM CDSI_OS_VERSION CDSI_OS_PRETTY CDSI_ARCH
    export CDSI_PACKAGE_BACKEND CDSI_SERVICE_BACKEND
    export CDSI_WEB_USER CDSI_WEB_GROUP
    export CDSI_NGINX_SERVICE CDSI_NGINX_CONF_DIR
    export CDSI_NGINX_MAIN_CONF CDSI_NGINX_SITE_DIR CDSI_NGINX_ENABLED_DIR
    export CDSI_NGINX_LOG_DIR CDSI_DB_PACKAGE CDSI_DB_SERVICE CDSI_DB_FLAVOR
    export CDSI_MYSQL_PACKAGE CDSI_MYSQL_SERVICE CDSI_MYSQL_FLAVOR
    export CDSI_CERTBOT_CONFIG_DIR
    export CDSI_PHP_VERSION CDSI_PHP_PACKAGE_PREFIX CDSI_PHP_BIN
    export CDSI_PHP_FPM_BIN CDSI_PHP_FPM_SERVICE CDSI_PHP_FPM_UPSTREAM
}

cdsi_is_ubuntu() {
    cdsi_platform_init
    [[ "$CDSI_PLATFORM" == "ubuntu" ]]
}

cdsi_is_debian() {
    cdsi_platform_init
    [[ "$CDSI_PLATFORM" == "debian" ]]
}

cdsi_is_apt_family() {
    cdsi_platform_init
    [[ "$CDSI_PLATFORM" == "ubuntu" || "$CDSI_PLATFORM" == "debian" ]]
}

cdsi_is_centos_stream() {
    cdsi_platform_init
    [[ "$CDSI_PLATFORM" == "centos-stream" ]]
}

cdsi_platform_supported() {
    cdsi_platform_init
    if [[ -n "${CDSI_PLATFORM_ROUTE:-}" \
        && "$CDSI_PLATFORM_ROUTE" != "$CDSI_PLATFORM" ]]; then
        return 1
    fi
    case "$CDSI_PLATFORM" in
        ubuntu)
            [[ "$CDSI_OS_VERSION" == "24.04" || "$CDSI_OS_VERSION" == "26.04" ]] \
                && cdsi_arch_supported
            ;;
        debian)
            [[ "$CDSI_OS_VERSION" == "13" ]] && cdsi_arch_supported
            ;;
        centos-stream)
            [[ "$CDSI_OS_VERSION" == "10" ]] && cdsi_arch_supported
            ;;
        *)
            return 1
            ;;
    esac
}

cdsi_arch_supported() {
    cdsi_platform_init
    case "$CDSI_ARCH" in
        x86_64|aarch64)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cdsi_php_service_name() {
    cdsi_platform_init
    local version="${1:-${CDSI_PHP_VERSION:-}}"
    case "$CDSI_PLATFORM" in
        ubuntu|debian)
            if [[ -n "$version" ]]; then
                printf 'php%s-fpm\n' "$version"
            fi
            ;;
        centos-stream)
            printf '%s\n' "$CDSI_PHP_FPM_SERVICE"
            ;;
        *)
            return 1
            ;;
    esac
}

cdsi_php_fpm_version() {
    cdsi_platform_init
    local depends="" unit=""
    if cdsi_is_centos_stream; then
        if [[ -x "$CDSI_PHP_BIN" ]]; then
            "$CDSI_PHP_BIN" \
                -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null
            return
        fi
        return 1
    fi
    cdsi_is_apt_family || return 1
    if command -v dpkg-query >/dev/null 2>&1; then
        depends="$(dpkg-query -W -f='${Depends}' php-fpm 2>/dev/null || true)"
        if [[ "$depends" =~ php([0-9]+\.[0-9]+)-fpm ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    if command -v systemctl >/dev/null 2>&1; then
        unit="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null \
            | awk '$1 ~ /^php[0-9]+\.[0-9]+-fpm\.service$/ {print $1; exit}' \
            | sed -E 's/^php([0-9]+\.[0-9]+)-fpm\.service$/\1/' || true)"
        if [[ -n "$unit" ]]; then
            printf '%s\n' "$unit"
            return 0
        fi
    fi
    if command -v php >/dev/null 2>&1; then
        php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null
        return
    fi
    return 1
}

cdsi_php_fpm_upstream() {
    cdsi_platform_init
    local version="${1:-${CDSI_PHP_VERSION:-}}"
    case "$CDSI_PLATFORM" in
        ubuntu|debian)
            if [[ -n "$version" ]]; then
                printf 'unix:/run/php/php%s-fpm.sock\n' "$version"
            fi
            ;;
        centos-stream)
            printf '%s\n' "$CDSI_PHP_FPM_UPSTREAM"
            ;;
        *)
            return 1
            ;;
    esac
}

cdsi_sha256_file() {
    local file="$1"
    command -v sha256sum >/dev/null 2>&1 || return 127
    sha256sum "$file" | awk '{print tolower($1)}'
}

cdsi_download_file() {
    local destination="$1"
    local url="$2"
    command -v curl >/dev/null 2>&1 || return 127
    curl -fsSL --retry 2 --connect-timeout 15 --max-time 900 \
        --speed-limit 1024 --speed-time 60 -o "$destination" "$url"
}
