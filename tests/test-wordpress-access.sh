#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${TEST_ROOT}/lib/common.sh"
# shellcheck source=../lib/wordpress-access.sh
source "${TEST_ROOT}/lib/wordpress-access.sh"

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

wordpress_fixture="$(mktemp -d)"
trap 'rm -rf -- "$wordpress_fixture"' EXIT
touch "${wordpress_fixture}/wp-load.php"

mock_wp_home=""
mock_public_ip="unknown"
mock_hostname_ips="172.27.64.181"
mock_curl_ip="172.27.64.181"

wp() {
    printf '%s\n' "$mock_wp_home"
}

get_public_ip() {
    if [[ "$mock_public_ip" == "unknown" ]]; then
        printf 'unknown\n'
        return 1
    fi
    printf '%s\n' "$mock_public_ip"
}

curl() {
    printf '%s\n' "$mock_curl_ip"
}

hostname() {
    [[ "${1:-}" == "-I" ]] || return 1
    printf '%s\n' "$mock_hostname_ips"
}

CDSI_SERVER_IP="192.168.10.8"
assert_equal "192.168.10.8" \
    "$(cdsi_resolve_wordpress_server_ip "$wordpress_fixture")" \
    "explicit server IP"

CDSI_SERVER_IP="not-an-ip"
if cdsi_resolve_wordpress_server_ip "$wordpress_fixture" >/dev/null; then
    fail_test "invalid explicit server IP was accepted"
fi

CDSI_SERVER_IP=""
mock_wp_home="http://8.8.4.4"
mock_public_ip="223.5.5.5"
assert_equal "8.8.4.4" \
    "$(cdsi_resolve_wordpress_server_ip "$wordpress_fixture")" \
    "existing public WordPress URL"

mock_wp_home="http://172.27.64.181"
mock_public_ip="1.1.1.1"
assert_equal "1.1.1.1" \
    "$(cdsi_resolve_wordpress_server_ip "$wordpress_fixture")" \
    "verified public IP fallback"

mock_public_ip="unknown"
mock_curl_ip="172.27.64.181"
mock_hostname_ips="172.27.64.181"
CDSI_ALLOW_PRIVATE_IP=false
assert_equal "" \
    "$(cdsi_resolve_wordpress_server_ip "$wordpress_fixture")" \
    "implicit private IP rejection"

CDSI_ALLOW_PRIVATE_IP=true
assert_equal "172.27.64.181" \
    "$(cdsi_resolve_wordpress_server_ip "$wordpress_fixture")" \
    "explicit private IP opt-in"

printf 'PASS: WordPress public/private server IP resolution\n'
