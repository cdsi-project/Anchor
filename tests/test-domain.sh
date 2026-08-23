#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${TEST_ROOT}/lib/common.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for valid in example.com cdsi.example.com xn--fiqs8s.example; do
    cdsi_validate_domain "$valid" \
        || fail_test "valid domain was rejected: ${valid}"
done

invalid_domains=(
    localhost
    192.0.2.1
    '*.example.com'
    '../example.com'
    'example.com/path'
    'example_com'
    '-bad.example'
    'bad-.example'
    'example.com|touch'
    'example.com&other'
)
for invalid in "${invalid_domains[@]}"; do
    if cdsi_validate_domain "$invalid"; then
        fail_test "invalid domain was accepted: ${invalid}"
    fi
done

normalized="$(cdsi_normalize_domain_list 'CDSI.Example.COM, www.example.com cdsi.example.com')"
[[ "$normalized" == "cdsi.example.com,www.example.com" ]] \
    || fail_test "unexpected normalized domain list: ${normalized}"

if cdsi_normalize_domain_list $'example.com\nmalicious.example' >/dev/null; then
    fail_test "newline-separated domain input was accepted"
fi

for public_ip in 1.1.1.1 8.8.8.8 223.5.5.5; do
    cdsi_is_public_ipv4 "$public_ip" \
        || fail_test "public IPv4 was rejected: ${public_ip}"
done

for non_public_ip in \
    10.0.0.1 100.64.0.1 127.0.0.1 169.254.1.1 172.16.0.1 \
    192.0.0.1 192.0.2.1 192.168.1.1 198.18.0.1 198.51.100.1 \
    203.0.113.1 224.0.0.1 999.1.1.1 01.2.3.4 \
    1.2.3.4. 1.2.3.4..; do
    if cdsi_is_public_ipv4 "$non_public_ip"; then
        fail_test "non-public IPv4 was accepted: ${non_public_ip}"
    fi
done

printf 'PASS: domain and public IPv4 validation\n'
