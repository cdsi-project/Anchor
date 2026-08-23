#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_LIB="${TEST_ROOT}/lib/common.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

normalize_path() {
    local initial="$1"
    (
        PATH="$initial"
        export PATH
        CDSI_PLATFORM_INITIALIZED=1
        # shellcheck source=../lib/common.sh
        source "$COMMON_LIB"
        printf '%s\n' "$PATH"
    )
}

expected="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
actual="$(normalize_path '/usr/sbin:/usr/bin:/sbin:/bin')"
[[ "$actual" == "$expected" ]] \
    || fail_test "restricted PATH was not normalized: ${actual}"

expected="/usr/local/sbin:/usr/local/bin:/usr/bin:/opt/anchor-tools:/bin"
actual="$(normalize_path '/usr/bin:/usr/local/bin:/opt/anchor-tools:/usr/local/sbin:/usr/local/bin:/bin')"
[[ "$actual" == "$expected" ]] \
    || fail_test "PATH normalization is not ordered and idempotent: ${actual}"

printf 'PASS: common local administrative PATH normalization\n'
