#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${TEST_ROOT}/lib/common.sh"
# shellcheck source=../lib/logger.sh
source "${TEST_ROOT}/lib/logger.sh"
# shellcheck source=../lib/system.sh
source "${TEST_ROOT}/lib/system.sh"
# shellcheck source=../scripts/check-env.sh
source "${TEST_ROOT}/scripts/check-env.sh"

test_is_ubuntu=true
test_os_version="24.04"

check_os_ubuntu() { [[ "$test_is_ubuntu" == true ]]; }
get_os_pretty_name() { printf 'Ubuntu test\n'; }
get_os_version() { printf '%s\n' "$test_os_version"; }

assert_os_status() {
    local expected="$1"
    preflight_overall_status=0
    pf_check_os >/dev/null
    if [[ "$preflight_overall_status" -ne "$expected" ]]; then
        printf 'FAIL: OS=%s ubuntu=%s produced status %s, expected %s\n' \
            "$test_os_version" "$test_is_ubuntu" \
            "$preflight_overall_status" "$expected" >&2
        exit 1
    fi
}

assert_os_status 0
test_os_version="26.04"
assert_os_status 0
test_os_version="22.04"
assert_os_status 2
test_os_version="24.04"
test_is_ubuntu=false
assert_os_status 2

printf 'PASS: preflight supported Ubuntu release guard\n'
