#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# Keep expected retry failures out of the test output.
log() { :; }
log_fail() { :; }

# shellcheck source=../lib/dnf.sh
source "${CDSI_ROOT}/lib/dnf.sh"

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

reset_fake_dnf() {
    dnf_calls=0
    sudo_calls=0
    sleep_calls=0
    timeout_calls=0
    fail_until=0
    fake_exit_code=74
    last_dnf_args=""
    last_timeout=""
}

sudo() {
    ((sudo_calls += 1))
    "$@"
}

timeout() {
    ((timeout_calls += 1))
    [[ "${1:-}" == "--foreground" ]] \
        || fail_test "timeout must run in foreground"
    last_timeout="${2:-}"
    shift 2
    "$@"
}

dnf() {
    ((dnf_calls += 1))
    last_dnf_args="$*"
    if ((dnf_calls <= fail_until)); then
        return "$fake_exit_code"
    fi
    return 0
}

sleep() {
    [[ "${1:-}" == "0" ]] || fail_test "tests must not perform a real wait"
    ((sleep_calls += 1))
}

expected_sudo_calls() {
    local dnf_attempts="$1"
    if [[ "${EUID}" -eq 0 ]]; then
        printf '0\n'
    else
        printf '%s\n' "$dnf_attempts"
    fi
}

reset_fake_dnf
CDSI_DNF_RETRY_ATTEMPTS=3 CDSI_DNF_COMMAND_TIMEOUT=45 CDSI_DNF_RETRY_DELAY=0 \
    cdsi_dnf makecache -q --refresh
assert_equal 1 "$dnf_calls" "first-attempt success call count"
assert_equal 1 "$timeout_calls" "first-attempt timeout count"
assert_equal 0 "$sleep_calls" "first-attempt success sleep count"
assert_equal "$(expected_sudo_calls 1)" "$sudo_calls" \
    "first-attempt sudo count"
assert_equal "45" "$last_timeout" "DNF command timeout"
assert_equal \
    "--setopt=retries=3 --setopt=timeout=30 makecache -q --refresh" \
    "$last_dnf_args" \
    "DNF argument forwarding"

reset_fake_dnf
fail_until=1
CDSI_DNF_QUERY_RETRY_DELAY=0 \
    cdsi_dnf_query -q list --available php-gd
assert_equal 2 "$dnf_calls" "query retry call count"
assert_equal 2 "$timeout_calls" "query timeout wrapper count"
assert_equal 1 "$sleep_calls" "query retry sleep count"
assert_equal 120 "$last_timeout" "query command timeout"
assert_equal \
    "--setopt=retries=3 --setopt=timeout=30 -q list --available php-gd" \
    "$last_dnf_args" \
    "DNF query argument forwarding"

reset_fake_dnf
fail_until=2
CDSI_DNF_RETRY_ATTEMPTS=3 CDSI_DNF_COMMAND_TIMEOUT=60 CDSI_DNF_RETRY_DELAY=0 \
    cdsi_dnf install -y mysql8.4-server
assert_equal 3 "$dnf_calls" "retry-then-success call count"
assert_equal 3 "$timeout_calls" "retry-then-success timeout count"
assert_equal 2 "$sleep_calls" "retry-then-success sleep count"
assert_equal "$(expected_sudo_calls 3)" "$sudo_calls" "retry sudo count"

reset_fake_dnf
fail_until=99
if CDSI_DNF_RETRY_ATTEMPTS=3 CDSI_DNF_COMMAND_TIMEOUT=30 \
    CDSI_DNF_RETRY_DELAY=0 cdsi_dnf install -y nginx; then
    fail_test "permanent DNF failure unexpectedly succeeded"
else
    actual_exit_code=$?
fi
assert_equal "$fake_exit_code" "$actual_exit_code" "last DNF exit code"
assert_equal 3 "$dnf_calls" "permanent failure call count"
assert_equal 2 "$sleep_calls" "permanent failure sleep count"

for invalid_attempts in 0 08 11 999999999999999999999; do
    reset_fake_dnf
    if CDSI_DNF_RETRY_ATTEMPTS="$invalid_attempts" cdsi_dnf makecache; then
        fail_test "invalid attempts value '${invalid_attempts}' was accepted"
    else
        actual_exit_code=$?
    fi
    assert_equal 2 "$actual_exit_code" "invalid attempts exit code"
    assert_equal 0 "$dnf_calls" "invalid attempts DNF call count"
done

for invalid_timeout in 29 1801; do
    reset_fake_dnf
    if CDSI_DNF_COMMAND_TIMEOUT="$invalid_timeout" cdsi_dnf makecache; then
        fail_test "invalid command timeout '${invalid_timeout}' was accepted"
    else
        actual_exit_code=$?
    fi
    assert_equal 2 "$actual_exit_code" "invalid command timeout exit code"
    assert_equal 0 "$dnf_calls" "invalid timeout DNF call count"
done

reset_fake_dnf
if cdsi_dnf; then
    fail_test "empty DNF operation unexpectedly succeeded"
else
    actual_exit_code=$?
fi
assert_equal 2 "$actual_exit_code" "empty DNF operation exit code"
assert_equal 0 "$dnf_calls" "empty operation DNF call count"

printf 'DNF helper tests: PASS\n'
