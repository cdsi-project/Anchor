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
    if [[ "$1" == "opensuse-leap" ]]; then
        CDSI_PHP_VERSION="8.4"
    else
        CDSI_PHP_VERSION=""
    fi
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
    debian "13" "Debian GNU/Linux 13 (trixie)" apt \
    /usr/bin/php "" "" ""
mapfile -t packages < <(php_base_packages)
assert_equal \
    "php-cli php-fpm php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl php-mysql" \
    "${packages[*]}" \
    "Debian PHP base package plan"

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

set_platform_fixture \
    opensuse-leap "16.0" "openSUSE Leap 16.0" zypper \
    /usr/bin/php /usr/sbin/php-fpm php-fpm \
    127.0.0.1:9000
mapfile -t packages < <(php_base_packages)
assert_equal \
    "php8-cli php8-fpm php8-bcmath php8-ctype php8-curl php8-dom php8-fileinfo php8-iconv php8-intl php8-mbstring php8-mysql php8-openssl php8-phar php8-posix php8-tokenizer php8-xmlreader php8-xmlwriter php8-zip" \
    "${packages[*]}" \
    "openSUSE Leap PHP base package plan"
assert_equal "8.4" "$(php_expected_version "8.3")" \
    "openSUSE Leap must reject a non-default existing PHP version"
assert_equal "8.4" "$(php_expected_version "8.5")" \
    "openSUSE Leap must reject a future non-default PHP version"

set_platform_fixture \
    ubuntu "24.04" "Ubuntu 24.04 LTS" apt \
    /usr/bin/php "" "" ""
assert_equal "8.3" "$(php_expected_version "8.3")" \
    "platforms without a fixed PHP version must retain the detected version"

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
    debian "13" "Debian GNU/Linux 13 (trixie)" apt \
    /usr/bin/php "" "" ""
install_required_php_extensions "8.4"
assert_equal "3" "${#extension_calls[@]}" \
    "Debian required extension call count"
assert_equal "Zend OPcache|true|php-opcache php8.4-opcache" \
    "${extension_calls[0]}" "Debian OPcache candidates"
assert_equal "redis|true|php-redis php8.4-redis" \
    "${extension_calls[1]}" "Debian Redis candidates"
assert_equal "gd|true|php-gd php8.4-gd" \
    "${extension_calls[2]}" "Debian GD candidates"

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

extension_calls=()
set_platform_fixture \
    opensuse-leap "16.0" "openSUSE Leap 16.0" zypper \
    /usr/bin/php /usr/sbin/php-fpm php-fpm \
    127.0.0.1:9000
install_required_php_extensions "8.4"
assert_equal "3" "${#extension_calls[@]}" \
    "openSUSE required extension call count"
assert_equal "Zend OPcache|true|php8-opcache" \
    "${extension_calls[0]}" "openSUSE OPcache package"
assert_equal "redis|true|php8-redis" \
    "${extension_calls[1]}" "openSUSE Redis package"
assert_equal "gd|true|php8-gd" \
    "${extension_calls[2]}" "openSUSE GD package"

fixture_dir="$(mktemp -d)"
listener_server_pid=""
cleanup_fixture() {
    if [[ -n "$listener_server_pid" ]]; then
        kill "$listener_server_pid" >/dev/null 2>&1 || true
        wait "$listener_server_pid" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$fixture_dir"
}
trap cleanup_fixture EXIT
printf '#!/bin/sh\nprintf "8.3\\n"\n' > "${fixture_dir}/php"
printf '#!/bin/sh\nprintf "8.4\\n"\n' > "${fixture_dir}/php8"
printf '#!/bin/sh\nexit 0\n' > "${fixture_dir}/php-fpm"
printf '#!/bin/sh\nexit 0\n' > "${fixture_dir}/php-fpm8.4"
printf '#!/bin/sh\nexit 0\n' > "${fixture_dir}/php-fpm8.5"
chmod 0755 \
    "${fixture_dir}/php" \
    "${fixture_dir}/php8" \
    "${fixture_dir}/php-fpm" \
    "${fixture_dir}/php-fpm8.4" \
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
    opensuse-leap "16.0" "openSUSE Leap 16.0" zypper \
    "${fixture_dir}/php8" "${fixture_dir}/php-fpm" php-fpm \
    127.0.0.1:9000
assert_equal "${fixture_dir}/php-fpm" "$(resolve_fpm_bin "8.4")" \
    "openSUSE unversioned PHP-FPM binary"
: > "$dpkg_query_log"
resolve_installed_php_runtime
assert_equal "0" "$(wc -l < "$dpkg_query_log" | tr -d '[:space:]')" \
    "openSUSE runtime resolution must not call dpkg-query"
assert_equal "8.4" "$PHP_VERSION" "openSUSE PHP version resolution"
assert_equal "${fixture_dir}/php8" "$PHP_BIN" \
    "openSUSE PHP binary resolution"
assert_equal "php8-fpm" "$FPM_PACKAGE" \
    "openSUSE FPM package resolution"

mock_ss_output='LISTEN 0 4096 127.0.0.1:9000 0.0.0.0:*'
ss() {
    printf '%s\n' "$mock_ss_output"
}
php_fpm_upstream_ready "127.0.0.1:9000" \
    || fail_test "openSUSE expected PHP-FPM listener was not detected"
mock_ss_output='LISTEN 0 4096 127.0.0.1:9001 0.0.0.0:*'
if php_fpm_upstream_ready "127.0.0.1:9000"; then
    fail_test "mismatched PHP-FPM listener was accepted"
fi
mock_ss_output='LISTEN 0 4096 0.0.0.0:9000 0.0.0.0:*'
if php_fpm_upstream_ready "127.0.0.1:9000"; then
    fail_test "public PHP-FPM wildcard listener was accepted"
fi
if php_fpm_upstream_ready "invalid-upstream"; then
    fail_test "malformed PHP-FPM upstream was accepted"
fi
for invalid_upstream in 127.0.0.1:0 127.0.0.1:65536; do
    if php_fpm_upstream_ready "$invalid_upstream"; then
        fail_test "out-of-range PHP-FPM upstream was accepted: ${invalid_upstream}"
    fi
done

unix_socket="${fixture_dir}/php-fpm.sock"
python3 - "$unix_socket" <<'PY' &
import socket
import sys
import time

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
time.sleep(10)
PY
listener_server_pid=$!
for _ in {1..100}; do
    [[ -S "$unix_socket" ]] && break
    sleep 0.02
done
php_fpm_upstream_ready "unix:${unix_socket}" \
    || fail_test "existing PHP-FPM Unix socket was not detected"
kill "$listener_server_pid" >/dev/null 2>&1 || true
wait "$listener_server_pid" >/dev/null 2>&1 || true
listener_server_pid=""

tcp_port_file="${fixture_dir}/tcp-port"
python3 - "$tcp_port_file" <<'PY' &
import socket
import sys
import time

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("127.0.0.1", 0))
server.listen(1)
with open(sys.argv[1], "w", encoding="ascii") as output:
    output.write(str(server.getsockname()[1]))
time.sleep(10)
PY
listener_server_pid=$!
for _ in {1..100}; do
    [[ -s "$tcp_port_file" ]] && break
    sleep 0.02
done
tcp_port="$(< "$tcp_port_file")"
(
    command() {
        if [[ "$1" == -v && "$2" == ss ]]; then
            return 1
        fi
        builtin command "$@"
    }
    nc() { return 0; }
    php_fpm_upstream_ready "127.0.0.1:${tcp_port}"
) || fail_test "PHP-FPM /proc listener fallback failed"
kill "$listener_server_pid" >/dev/null 2>&1 || true
wait "$listener_server_pid" >/dev/null 2>&1 || true
listener_server_pid=""

wildcard_port_file="${fixture_dir}/wildcard-port"
python3 - "$wildcard_port_file" <<'PY' &
import socket
import sys
import time

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("0.0.0.0", 0))
server.listen(1)
with open(sys.argv[1], "w", encoding="ascii") as output:
    output.write(str(server.getsockname()[1]))
time.sleep(10)
PY
listener_server_pid=$!
for _ in {1..100}; do
    [[ -s "$wildcard_port_file" ]] && break
    sleep 0.02
done
wildcard_port="$(< "$wildcard_port_file")"
if (
    command() {
        if [[ "$1" == -v && "$2" == ss ]]; then
            return 1
        fi
        builtin command "$@"
    }
    nc() { return 0; }
    php_fpm_upstream_ready "127.0.0.1:${wildcard_port}"
); then
    fail_test "PHP-FPM /proc fallback accepted a wildcard listener"
fi
kill "$listener_server_pid" >/dev/null 2>&1 || true
wait "$listener_server_pid" >/dev/null 2>&1 || true
listener_server_pid=""

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

set_platform_fixture \
    debian "13" "Debian GNU/Linux 13 (trixie)" apt \
    /usr/bin/php "" "" ""
assert_equal "${fixture_dir}/php-fpm8.4" "$(resolve_fpm_bin "8.4")" \
    "Debian versioned PHP-FPM binary"
function dpkg-query() {
    printf 'called\n' >> "$dpkg_query_log"
    printf 'php8.4-fpm (>= 8.4.0)\n'
}
: > "$dpkg_query_log"
resolve_installed_php_runtime
assert_equal "1" "$(wc -l < "$dpkg_query_log" | tr -d '[:space:]')" \
    "Debian runtime resolution must inspect the php-fpm metapackage"
assert_equal "8.4" "$PHP_VERSION" "Debian PHP version resolution"
assert_equal "/usr/bin/php8.4" "$PHP_BIN" "Debian PHP binary resolution"
assert_equal "php8.4-fpm" "$FPM_PACKAGE" "Debian FPM package resolution"

PHP_INSTALLER="${TEST_ROOT}/scripts/common/install-php.sh"
if grep -Eqi 'imagick|cdsi_enable_epel' "$PHP_INSTALLER"; then
    fail_test "PHP installer must not install Imagick or enable EPEL"
fi
grep -Fq 'install_php_extension "Zend OPcache" true php8-opcache' "$PHP_INSTALLER" \
    || fail_test "openSUSE must install its separately packaged OPcache extension"
grep -Fq 'php8-openssl' "$PHP_INSTALLER" \
    || fail_test "openSUSE must install its separately packaged OpenSSL extension"
grep -Fq 'lib/zypper.sh' "$PHP_INSTALLER" \
    || fail_test "openSUSE PHP path does not load the Zypper runtime"
grep -Fq 'packages\.sury\.org/php' "$PHP_INSTALLER" \
    || fail_test "Debian PHP path must reject packages.sury.org/php"
grep -Fq 'cdsi_service_enable_now "$current_fpm_service"' "$PHP_INSTALLER" \
    || fail_test "healthy PHP fast path must enable PHP-FPM at boot"
grep -Fq 'expected_version="$(php_expected_version "$current_version")"' \
    "$PHP_INSTALLER" \
    || fail_test "PHP fast path does not enforce a platform-fixed version"
grep -Fq 'EXPECTED_PHP_VERSION="$(php_expected_version "$PHP_VERSION")"' \
    "$PHP_INSTALLER" \
    || fail_test "fresh PHP path does not enforce a platform-fixed version"
grep -Fq 'cdsi_service_restart "$FPM_SERVICE"' "$PHP_INSTALLER" \
    || fail_test "PHP reconciliation must restart FPM after extension installation"
[[ "$(grep -Fc 'php_fpm_upstream_ready' "$PHP_INSTALLER")" -ge 3 ]] \
    || fail_test "PHP listener validation must cover both fast and fresh paths"

printf 'PASS: Ubuntu, Debian, CentOS Stream, and openSUSE Leap PHP mappings\n'
