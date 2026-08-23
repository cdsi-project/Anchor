#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../scripts/common/install-php.sh
source "${TEST_ROOT}/scripts/common/install-php.sh"

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

set_platform_fixture() {
    CDSI_PLATFORM_INITIALIZED=1
    CDSI_PLATFORM="$1"
    CDSI_OS_VERSION="$2"
    CDSI_OS_PRETTY="$3"
    CDSI_ARCH="x86_64"
    CDSI_PACKAGE_BACKEND="$4"
    CDSI_SERVICE_BACKEND="systemd"
    CDSI_PHP_BIN="${5:-/usr/bin/php}"
    CDSI_PHP_FPM_BIN="${6:-}"
    CDSI_PHP_FPM_SERVICE="$7"
    CDSI_PHP_FPM_UPSTREAM="$8"
}

set_platform_fixture \
    ubuntu "24.04" "Ubuntu 24.04 LTS" apt \
    /usr/bin/php "" "" ""
mapfile -t packages < <(php_base_packages)
assert_equal \
    "php-cli php-fpm php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl php-mysql" \
    "${packages[*]}" \
    "Ubuntu PHP base package plan"

set_platform_fixture \
    centos-stream "10" "CentOS Stream 10" dnf \
    /usr/bin/php /usr/sbin/php-fpm php-fpm \
    unix:/run/php-fpm/www.sock
mapfile -t packages < <(php_base_packages)
assert_equal \
    "php-cli php-fpm php-common php-mbstring php-xml php-bcmath php-intl php-mysqlnd php-process" \
    "${packages[*]}" \
    "CentOS Stream PHP base package plan"
for forbidden_package in php-curl php-zip php-mysql; do
    if [[ " ${packages[*]} " == *" ${forbidden_package} "* ]]; then
        fail_test "CentOS package plan leaked Ubuntu package ${forbidden_package}"
    fi
done

extension_calls=()
install_php_extension() {
    extension_calls+=("$1|$2|${*:3}")
}

set_platform_fixture \
    ubuntu "26.04" "Ubuntu 26.04 LTS" apt \
    /usr/bin/php "" "" ""
install_required_php_extensions "8.5"
assert_equal "3" "${#extension_calls[@]}" \
    "Ubuntu required extension call count"
assert_equal "Zend OPcache|true|php-opcache php8.5-opcache" \
    "${extension_calls[0]}" "Ubuntu OPcache candidates"
assert_equal "redis|true|php-redis php8.5-redis" \
    "${extension_calls[1]}" "Ubuntu Redis candidates"
assert_equal "gd|true|php-gd php8.5-gd" \
    "${extension_calls[2]}" "Ubuntu GD candidates"

extension_calls=()
set_platform_fixture \
    centos-stream "10" "CentOS Stream 10" dnf \
    /usr/bin/php /usr/sbin/php-fpm php-fpm \
    unix:/run/php-fpm/www.sock
install_required_php_extensions "8.3"
assert_equal "4" "${#extension_calls[@]}" \
    "CentOS required extension call count"
assert_equal "Zend OPcache|true|php-opcache" \
    "${extension_calls[0]}" "CentOS OPcache package"
assert_equal "redis|true|php-pecl-redis6" \
    "${extension_calls[1]}" "CentOS Redis package"
assert_equal "gd|true|php-gd" \
    "${extension_calls[2]}" "CentOS GD package"
assert_equal "zip|true|php-pecl-zip" \
    "${extension_calls[3]}" "CentOS ZIP package"

optional_order=()
php_extension_loaded() { return 1; }
cdsi_enable_epel() {
    optional_order+=(epel)
}
install_php_extension() {
    optional_order+=("install:$1|$2|${*:3}")
}
install_optional_imagick "8.3" >/dev/null
assert_equal "epel install:imagick|false|php-pecl-imagick" \
    "${optional_order[*]}" \
    "CentOS Imagick must enable EPEL before package installation"

optional_order=()
cdsi_enable_epel() {
    optional_order+=(epel)
    return 1
}
install_optional_imagick "8.3" >/dev/null 2>&1
assert_equal "epel" "${optional_order[*]}" \
    "Imagick must remain optional when EPEL cannot be enabled"

set_platform_fixture \
    ubuntu "24.04" "Ubuntu 24.04 LTS" apt \
    /usr/bin/php "" "" ""
optional_order=()
cdsi_enable_epel() {
    optional_order+=(epel)
}
install_php_extension() {
    optional_order+=("install:$1|$2|${*:3}")
}
install_optional_imagick "8.3" >/dev/null
assert_equal "install:imagick|false|php-imagick php8.3-imagick" \
    "${optional_order[*]}" \
    "Ubuntu Imagick candidates and repository behavior"

fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
printf '#!/bin/sh\nprintf "8.3\\n"\n' > "${fixture_dir}/php"
printf '#!/bin/sh\nexit 0\n' > "${fixture_dir}/php-fpm"
printf '#!/bin/sh\nexit 0\n' > "${fixture_dir}/php-fpm8.5"
chmod 0755 \
    "${fixture_dir}/php" \
    "${fixture_dir}/php-fpm" \
    "${fixture_dir}/php-fpm8.5"

set_platform_fixture \
    centos-stream "10" "CentOS Stream 10" dnf \
    "${fixture_dir}/php" "${fixture_dir}/php-fpm" php-fpm \
    unix:/run/php-fpm/www.sock
assert_equal "${fixture_dir}/php-fpm" "$(resolve_fpm_bin "8.3")" \
    "CentOS unversioned PHP-FPM binary"

dpkg_query_log="${fixture_dir}/dpkg-query.log"
: > "$dpkg_query_log"
function dpkg-query() {
    printf 'called\n' >> "$dpkg_query_log"
    return 99
}
resolve_installed_php_runtime
assert_equal "0" "$(wc -l < "$dpkg_query_log" | tr -d '[:space:]')" \
    "CentOS runtime resolution must not call dpkg-query"
assert_equal "8.3" "$PHP_VERSION" "CentOS PHP version resolution"
assert_equal "${fixture_dir}/php" "$PHP_BIN" "CentOS PHP binary resolution"
assert_equal "php-fpm" "$FPM_PACKAGE" "CentOS FPM package resolution"

set_platform_fixture \
    ubuntu "26.04" "Ubuntu 26.04 LTS" apt \
    /usr/bin/php "" "" ""
PATH="${fixture_dir}:${PATH}"
assert_equal "${fixture_dir}/php-fpm8.5" "$(resolve_fpm_bin "8.5")" \
    "Ubuntu versioned PHP-FPM binary"
function dpkg-query() {
    printf 'called\n' >> "$dpkg_query_log"
    printf 'php8.5-fpm (>= 8.5.0)\n'
}
: > "$dpkg_query_log"
resolve_installed_php_runtime
assert_equal "1" "$(wc -l < "$dpkg_query_log" | tr -d '[:space:]')" \
    "Ubuntu runtime resolution must inspect the php-fpm metapackage"
assert_equal "8.5" "$PHP_VERSION" "Ubuntu PHP version resolution"
assert_equal "/usr/bin/php8.5" "$PHP_BIN" "Ubuntu PHP binary resolution"
assert_equal "php8.5-fpm" "$FPM_PACKAGE" "Ubuntu FPM package resolution"

PHP_INSTALLER="${TEST_ROOT}/scripts/common/install-php.sh"
grep -Fq 'cdsi_service_enable_now "$current_fpm_service"' "$PHP_INSTALLER" \
    || fail_test "healthy PHP fast path must enable PHP-FPM at boot"
grep -Fq 'cdsi_service_restart "$FPM_SERVICE"' "$PHP_INSTALLER" \
    || fail_test "PHP reconciliation must restart FPM after extension installation"

printf 'PASS: Ubuntu and CentOS Stream PHP package, extension, and FPM mappings\n'
