#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN_LIB="${TEST_ROOT}/lib/domain.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_ready() {
    local message="$1"
    shift
    "$@" || fail_test "$message"
}

assert_not_ready() {
    local message="$1"
    shift
    if "$@"; then
        fail_test "$message"
    fi
}

[[ -f "$DOMAIN_LIB" ]] \
    || fail_test "domain resolution library not found: ${DOMAIN_LIB}"
bash -n "$DOMAIN_LIB" \
    || fail_test "domain resolution library has invalid Bash syntax"
grep -Fq 'cdsi_packages_install dnsutils' "$DOMAIN_LIB" \
    || fail_test "Ubuntu DNS validation does not install dig from the system source"
grep -Fq 'debian) cdsi_packages_install bind9-dnsutils' "$DOMAIN_LIB" \
    || fail_test "Debian DNS validation does not install dig from the system source"
grep -Fq 'cdsi_packages_install bind-utils' "$DOMAIN_LIB" \
    || fail_test "RPM-family DNS validation does not install dig from the system source"
grep -Fq 'opensuse-leap) cdsi_packages_install bind-utils' "$DOMAIN_LIB" \
    || fail_test "openSUSE DNS validation does not install dig from the system source"
if grep -Fq 'getent ahost' "$DOMAIN_LIB"; then
    fail_test "DNS activation must not trust NSS or /etc/hosts through getent"
fi

# shellcheck source=../lib/common.sh
source "${TEST_ROOT}/lib/common.sh"
# shellcheck source=../lib/domain.sh
source "$DOMAIN_LIB"

for function_name in \
    cdsi_domain_dns_ready \
    cdsi_dns_query_records \
    cdsi_server_global_ipv6; do
    declare -F "$function_name" >/dev/null 2>&1 \
        || fail_test "domain library is missing ${function_name}"
done

# Override the network-facing probes. No case below may query real DNS or local
# interfaces; fixtures are keyed by record type and domain.
declare -A MOCK_DNS_A=()
declare -A MOCK_DNS_AAAA=()
declare -A MOCK_DNS_A_RC=()
declare -A MOCK_DNS_AAAA_RC=()
MOCK_SERVER_IPV6=""

cdsi_dns_query_records() {
    local record_type="$1"
    local domain="$2"
    local value=""
    local rc=0

    case "$record_type" in
        A)
            value="${MOCK_DNS_A[$domain]:-}"
            rc="${MOCK_DNS_A_RC[$domain]:-0}"
            ;;
        AAAA)
            value="${MOCK_DNS_AAAA[$domain]:-}"
            rc="${MOCK_DNS_AAAA_RC[$domain]:-0}"
            ;;
        *)
            fail_test "unexpected DNS record type: ${record_type}"
            ;;
    esac

    [[ -z "$value" ]] || printf '%b\n' "$value"
    return "$rc"
}

cdsi_server_global_ipv6() {
    [[ -z "$MOCK_SERVER_IPV6" ]] || printf '%b\n' "$MOCK_SERVER_IPV6"
}

reset_dns_fixture() {
    MOCK_DNS_A=()
    MOCK_DNS_AAAA=()
    MOCK_DNS_A_RC=()
    MOCK_DNS_AAAA_RC=()
    MOCK_SERVER_IPV6=""
    unset CDSI_ALLOW_DNS_MISMATCH 2>/dev/null || true
}

server_ip="1.1.1.1"

# A lookup failure and an empty A answer both mean propagation is not ready.
reset_dns_fixture
MOCK_DNS_A_RC[unresolved.example]=1
assert_not_ready "an unresolved domain was accepted" \
    cdsi_domain_dns_ready unresolved.example "$server_ip"

reset_dns_fixture
MOCK_DNS_A[empty.example]=""
assert_not_ready "a domain without an A record was accepted" \
    cdsi_domain_dns_ready empty.example "$server_ip"

# Every A record must target this single Anchor node. One correct answer among
# several does not make a partially stale DNS set safe for ACME validation.
reset_dns_fixture
MOCK_DNS_A[wrong.example]="8.8.8.8"
assert_not_ready "an A record pointing elsewhere was accepted" \
    cdsi_domain_dns_ready wrong.example "$server_ip"

reset_dns_fixture
MOCK_DNS_A[multi-a.example]=$'1.1.1.1\n8.8.8.8'
assert_not_ready "a mixed matching/mismatching A set was accepted" \
    cdsi_domain_dns_ready multi-a.example "$server_ip"

# An advertised AAAA record is also authoritative routing state. It must match
# one of the server's global IPv6 addresses; having a correct A is insufficient.
reset_dns_fixture
MOCK_DNS_A[wrong-v6.example]="$server_ip"
MOCK_DNS_AAAA[wrong-v6.example]="2001:db8::11"
MOCK_SERVER_IPV6="2001:db8::10"
assert_not_ready "a foreign AAAA record was accepted" \
    cdsi_domain_dns_ready wrong-v6.example "$server_ip"

# A-only and dual-stack domains are ready when every published address belongs
# to this server.
reset_dns_fixture
MOCK_DNS_A[ipv4.example]="$server_ip"
assert_ready "a matching A-only domain was rejected" \
    cdsi_domain_dns_ready ipv4.example "$server_ip"

reset_dns_fixture
MOCK_DNS_A[dual.example]="$server_ip"
MOCK_DNS_AAAA[dual.example]=$'2001:db8::10\n2001:db8::20'
MOCK_SERVER_IPV6=$'2001:db8::10\n2001:db8::20'
assert_ready "matching A and AAAA records were rejected" \
    cdsi_domain_dns_ready dual.example "$server_ip"

# Comma-separated certificate names are an all-or-nothing readiness check.
reset_dns_fixture
MOCK_DNS_A[one.example]="$server_ip"
MOCK_DNS_A[two.example]="$server_ip"
assert_ready "two matching certificate domains were rejected" \
    cdsi_domain_dns_ready one.example,two.example "$server_ip"

MOCK_DNS_A[two.example]="9.9.9.9"
assert_not_ready "a mismatching secondary certificate domain was accepted" \
    cdsi_domain_dns_ready one.example,two.example "$server_ip"

# Operators using a proxy or another intentional topology can explicitly take
# responsibility for DNS that does not point directly at this node.
CDSI_ALLOW_DNS_MISMATCH=true
assert_ready "the explicit DNS mismatch override was ignored" \
    cdsi_domain_dns_ready one.example,two.example "$server_ip"

printf 'PASS: domain A/AAAA readiness and explicit mismatch override\n'
