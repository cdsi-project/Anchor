#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/platform.sh
source "${TEST_ROOT}/lib/platform.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "$actual" == "$expected" ]] \
        || fail_test "${message}: expected '${expected}', got '${actual}'"
}

assert_success() {
    local message="$1"
    shift
    "$@" || fail_test "$message"
}

assert_failure() {
    local message="$1"
    shift
    if "$@"; then
        fail_test "$message"
    fi
}

mock_kernel="Linux"
mock_arch="x86_64"
mock_os_id="ubuntu"
mock_os_version="24.04"
mock_os_name="Ubuntu"
mock_os_pretty="Ubuntu 24.04 LTS"

uname() {
    case "${1:-}" in
        -s) printf '%s\n' "$mock_kernel" ;;
        -m) printf '%s\n' "$mock_arch" ;;
        -r) printf 'test-kernel\n' ;;
        *) printf '%s\n' "$mock_kernel" ;;
    esac
}

awk() {
    if [[ "$*" == *"/^ID=/"* ]]; then
        printf '%s\n' "$mock_os_id"
    elif [[ "$*" == *"/^VERSION_ID=/"* ]]; then
        printf '%s\n' "$mock_os_version"
    elif [[ "$*" == *"/^NAME=/"* ]]; then
        printf '%s\n' "$mock_os_name"
    elif [[ "$*" == *"/^PRETTY_NAME=/"* ]]; then
        printf '%s\n' "$mock_os_pretty"
    else
        fail_test "unexpected awk invocation: $*"
    fi
}

reset_platform() {
    unset CDSI_PLATFORM_INITIALIZED CDSI_PLATFORM CDSI_OS_VERSION \
        CDSI_OS_PRETTY CDSI_ARCH CDSI_PACKAGE_BACKEND CDSI_SERVICE_BACKEND \
        CDSI_WEB_USER CDSI_WEB_GROUP CDSI_NGINX_SERVICE \
        CDSI_NGINX_CONF_DIR CDSI_NGINX_MAIN_CONF CDSI_NGINX_SITE_DIR \
        CDSI_NGINX_ENABLED_DIR CDSI_NGINX_LOG_DIR \
        CDSI_DB_PACKAGE CDSI_DB_SERVICE CDSI_DB_FLAVOR \
        CDSI_MYSQL_PACKAGE CDSI_MYSQL_SERVICE CDSI_MYSQL_FLAVOR \
        CDSI_CERTBOT_CONFIG_DIR CDSI_PHP_VERSION \
        CDSI_PHP_PACKAGE_PREFIX CDSI_PHP_BIN CDSI_PHP_FPM_BIN \
        CDSI_PHP_FPM_SERVICE CDSI_PHP_FPM_UPSTREAM 2>/dev/null || true
    unset CDSI_PLATFORM_ROUTE 2>/dev/null || true
}

init_ubuntu_fixture() {
    local version="$1"
    mock_kernel="Linux"
    mock_arch="x86_64"
    mock_os_id="ubuntu"
    mock_os_version="$version"
    mock_os_name="Ubuntu"
    mock_os_pretty="Ubuntu ${version} LTS"
    reset_platform
    cdsi_platform_init
}

init_ubuntu_fixture "24.04"
assert_equal "ubuntu" "$CDSI_PLATFORM" "Ubuntu platform detection"
assert_equal "24.04" "$CDSI_OS_VERSION" "Ubuntu version detection"
assert_equal "apt" "$CDSI_PACKAGE_BACKEND" "Ubuntu package backend"
assert_equal "systemd" "$CDSI_SERVICE_BACKEND" "Ubuntu service backend"
assert_equal "/etc/nginx/sites-available" "$CDSI_NGINX_SITE_DIR" \
    "Ubuntu Nginx site path"
assert_equal "php8.3-fpm" "$(cdsi_php_service_name 8.3)" \
    "Ubuntu PHP-FPM service"
assert_equal "unix:/run/php/php8.3-fpm.sock" \
    "$(cdsi_php_fpm_upstream 8.3)" "Ubuntu PHP-FPM upstream"
assert_success "empty Ubuntu PHP service lookup should remain a safe probe" \
    cdsi_php_service_name
assert_success "empty Ubuntu PHP upstream lookup should remain a safe probe" \
    cdsi_php_fpm_upstream
assert_success "Ubuntu 24.04 should be supported" cdsi_platform_supported
assert_success "Ubuntu should be recognized as an APT-family platform" \
    cdsi_is_apt_family
assert_failure "Ubuntu should not match the Debian helper" cdsi_is_debian

init_ubuntu_fixture "26.04"
assert_success "Ubuntu 26.04 should be supported" cdsi_platform_supported

mock_arch="riscv64"
reset_platform
cdsi_platform_init
assert_failure "Ubuntu unsupported architecture should be rejected" \
    cdsi_platform_supported

init_ubuntu_fixture "22.04"
assert_failure "Ubuntu 22.04 should be rejected" cdsi_platform_supported

mock_kernel="Linux"
mock_os_id="debian"
mock_os_version="13"
mock_os_name="Debian GNU/Linux"
mock_os_pretty="Debian GNU/Linux 13"
reset_platform
cdsi_platform_init
assert_equal "debian" "$CDSI_PLATFORM" "Debian platform detection"
assert_equal "apt" "$CDSI_PACKAGE_BACKEND" "Debian package backend"
assert_equal "systemd" "$CDSI_SERVICE_BACKEND" "Debian service backend"
assert_equal "www-data" "$CDSI_WEB_USER" "Debian web user"
assert_equal "www-data" "$CDSI_WEB_GROUP" "Debian web group"
assert_equal "/etc/nginx/sites-available" "$CDSI_NGINX_SITE_DIR" \
    "Debian Nginx site path"
assert_equal "/etc/nginx/sites-enabled" "$CDSI_NGINX_ENABLED_DIR" \
    "Debian Nginx enabled path"
assert_equal "mariadb-server" "$CDSI_DB_PACKAGE" \
    "Debian database package"
assert_equal "mariadb" "$CDSI_DB_SERVICE" "Debian database service"
assert_equal "mariadb" "$CDSI_DB_FLAVOR" "Debian database flavor"
assert_equal "$CDSI_DB_PACKAGE" "$CDSI_MYSQL_PACKAGE" \
    "Debian database package compatibility alias"
assert_equal "$CDSI_DB_SERVICE" "$CDSI_MYSQL_SERVICE" \
    "Debian database service compatibility alias"
assert_equal "$CDSI_DB_FLAVOR" "$CDSI_MYSQL_FLAVOR" \
    "Debian database flavor compatibility alias"
assert_equal "php8.4-fpm" "$(cdsi_php_service_name 8.4)" \
    "Debian PHP-FPM service"
assert_equal "unix:/run/php/php8.4-fpm.sock" \
    "$(cdsi_php_fpm_upstream 8.4)" "Debian PHP-FPM upstream"
assert_success "Debian helper should match" cdsi_is_debian
assert_success "Debian should be recognized as an APT-family platform" \
    cdsi_is_apt_family
assert_success "Debian 13 x86_64 should be supported" cdsi_platform_supported
CDSI_PLATFORM_ROUTE="debian"
assert_success "matching Debian route should be accepted" \
    cdsi_platform_supported
CDSI_PLATFORM_ROUTE="ubuntu"
assert_failure "a non-Debian route should be rejected on Debian" \
    cdsi_platform_supported

mock_arch="aarch64"
reset_platform
cdsi_platform_init
assert_success "Debian 13 aarch64 should be supported" cdsi_platform_supported

mock_arch="x86_64"
mock_os_version="12"
reset_platform
cdsi_platform_init
assert_failure "Debian 12 should be rejected" cdsi_platform_supported

mock_os_version="14"
reset_platform
cdsi_platform_init
assert_failure "Debian 14 should be rejected" cdsi_platform_supported

init_ubuntu_fixture "24.04"
CDSI_PLATFORM_ROUTE="debian"
assert_failure "a mismatched platform route should be rejected" \
    cdsi_platform_supported
CDSI_PLATFORM_ROUTE="ubuntu"
assert_success "the matching Ubuntu route should be accepted" \
    cdsi_platform_supported

mock_kernel="Linux"
mock_arch="x86_64"
mock_os_id="centos"
mock_os_version="10"
mock_os_name="CentOS Stream"
mock_os_pretty="CentOS Stream 10"
reset_platform
cdsi_platform_init
assert_equal "centos-stream" "$CDSI_PLATFORM" \
    "CentOS Stream platform normalization"
assert_equal "dnf" "$CDSI_PACKAGE_BACKEND" "CentOS package backend"
assert_equal "systemd" "$CDSI_SERVICE_BACKEND" "CentOS service backend"
assert_equal "apache" "$CDSI_WEB_USER" "CentOS PHP-FPM web user"
assert_equal "/etc/nginx/conf.d" "$CDSI_NGINX_SITE_DIR" \
    "CentOS Nginx site path"
assert_equal "$CDSI_NGINX_SITE_DIR" "$CDSI_NGINX_ENABLED_DIR" \
    "CentOS Nginx enabled path"
assert_equal "mysql8.4-server" "$CDSI_DB_PACKAGE" \
    "CentOS database package"
assert_equal "mysqld" "$CDSI_DB_SERVICE" "CentOS database service"
assert_equal "mysql" "$CDSI_DB_FLAVOR" "CentOS database flavor"
assert_equal "$CDSI_DB_PACKAGE" "$CDSI_MYSQL_PACKAGE" \
    "database package compatibility alias"
assert_equal "$CDSI_DB_SERVICE" "$CDSI_MYSQL_SERVICE" \
    "database service compatibility alias"
assert_equal "$CDSI_DB_FLAVOR" "$CDSI_MYSQL_FLAVOR" \
    "database flavor compatibility alias"
assert_equal "php-fpm" "$(cdsi_php_service_name 8.4)" \
    "CentOS PHP-FPM service"
assert_equal "unix:/run/php-fpm/www.sock" "$(cdsi_php_fpm_upstream 8.4)" \
    "CentOS PHP-FPM upstream"
assert_equal "/usr/bin/php" "$CDSI_PHP_BIN" "CentOS PHP binary"
assert_equal "/usr/sbin/php-fpm" "$CDSI_PHP_FPM_BIN" \
    "CentOS PHP-FPM binary"
assert_success "CentOS Stream helper should match" cdsi_is_centos_stream
assert_failure "CentOS Stream should not match the APT-family helper" \
    cdsi_is_apt_family
assert_success "CentOS Stream 10 x86_64 should be supported" \
    cdsi_platform_supported
CDSI_PLATFORM_ROUTE="centos-stream"
assert_success "matching CentOS Stream route should be accepted" \
    cdsi_platform_supported
CDSI_PLATFORM_ROUTE="centos"
assert_failure "non-canonical CentOS route should be rejected" \
    cdsi_platform_supported

mock_arch="aarch64"
reset_platform
cdsi_platform_init
assert_success "CentOS Stream 10 aarch64 should be supported" \
    cdsi_platform_supported

mock_arch="x86_64"
mock_os_version="9"
reset_platform
cdsi_platform_init
assert_failure "CentOS Stream 9 should be rejected" cdsi_platform_supported

mock_os_version="10"
mock_os_name="CentOS Linux"
mock_os_pretty="CentOS Linux 10"
reset_platform
cdsi_platform_init
assert_equal "centos" "$CDSI_PLATFORM" \
    "non-Stream CentOS should not be normalized"
assert_failure "non-Stream CentOS should be rejected" cdsi_platform_supported

mock_os_name="CentOS Stream"
mock_os_pretty="CentOS 10"
reset_platform
cdsi_platform_init
assert_equal "centos-stream" "$CDSI_PLATFORM" \
    "CentOS Stream NAME identity"
assert_success "CentOS Stream NAME identity should be supported" \
    cdsi_platform_supported

mock_arch="riscv64"
reset_platform
cdsi_platform_init
assert_failure "CentOS Stream unsupported architecture should be rejected" \
    cdsi_platform_supported

mock_kernel="Darwin"
mock_arch="arm64"
reset_platform
cdsi_platform_init
assert_equal "unknown" "$CDSI_PLATFORM" "unknown kernel detection"
assert_failure "unknown kernels should be rejected" cdsi_platform_supported

for supported_arch in x86_64 aarch64; do
    CDSI_PLATFORM_INITIALIZED=1
    CDSI_ARCH="$supported_arch"
    assert_success "architecture ${supported_arch} should be supported" \
        cdsi_arch_supported
done

for unsupported_arch in i386 amd64 arm64 riscv64 powerpc64; do
    CDSI_PLATFORM_INITIALIZED=1
    CDSI_ARCH="$unsupported_arch"
    assert_failure "architecture ${unsupported_arch} should be rejected" \
        cdsi_arch_supported
done

printf 'PASS: platform detection, supported releases, paths, and architectures\n'
