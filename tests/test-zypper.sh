#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# Keep expected retry failures out of the test output.
log() { :; }
log_fail() { :; }

# shellcheck source=../lib/zypper.sh
source "${CDSI_ROOT}/lib/zypper.sh"

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

reset_fake_zypper() {
    zypper_calls=0
    sudo_calls=0
    sleep_calls=0
    timeout_calls=0
    fail_until=0
    fake_exit_code=75
    last_zypper_args=""
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

zypper() {
    ((zypper_calls += 1))
    last_zypper_args="$*"
    if ((zypper_calls <= fail_until)); then
        return "$fake_exit_code"
    fi
    return 0
}

sleep() {
    [[ "${1:-}" == "0" ]] || fail_test "tests must not perform a real wait"
    ((sleep_calls += 1))
}

expected_sudo_calls() {
    local zypper_attempts="$1"
    if [[ "${EUID}" -eq 0 ]]; then
        printf '0\n'
    else
        printf '%s\n' "$zypper_attempts"
    fi
}

reset_fake_zypper
CDSI_ZYPPER_RETRY_ATTEMPTS=3 CDSI_ZYPPER_COMMAND_TIMEOUT=45 \
    CDSI_ZYPPER_RETRY_DELAY=0 cdsi_zypper refresh --force
assert_equal 1 "$zypper_calls" "first-attempt success call count"
assert_equal 1 "$timeout_calls" "first-attempt timeout count"
assert_equal 0 "$sleep_calls" "first-attempt success sleep count"
assert_equal "$(expected_sudo_calls 1)" "$sudo_calls" \
    "first-attempt sudo count"
assert_equal "45" "$last_timeout" "Zypper command timeout"
assert_equal "--non-interactive refresh --force" "$last_zypper_args" \
    "Zypper argument forwarding"

reset_fake_zypper
fail_until=1
CDSI_ZYPPER_QUERY_RETRY_DELAY=0 \
    cdsi_zypper_query search --match-exact --type package php8-gd
assert_equal 2 "$zypper_calls" "query retry call count"
assert_equal 2 "$timeout_calls" "query timeout wrapper count"
assert_equal 1 "$sleep_calls" "query retry sleep count"
assert_equal 120 "$last_timeout" "query command timeout"
assert_equal \
    "--non-interactive --no-refresh search --match-exact --type package php8-gd" \
    "$last_zypper_args" \
    "Zypper query argument forwarding"

reset_fake_zypper
fail_until=2
CDSI_ZYPPER_RETRY_ATTEMPTS=3 CDSI_ZYPPER_COMMAND_TIMEOUT=60 \
    CDSI_ZYPPER_RETRY_DELAY=0 cdsi_zypper install --no-recommends nginx
assert_equal 3 "$zypper_calls" "retry-then-success call count"
assert_equal 3 "$timeout_calls" "retry-then-success timeout count"
assert_equal 2 "$sleep_calls" "retry-then-success sleep count"
assert_equal "$(expected_sudo_calls 3)" "$sudo_calls" "retry sudo count"

reset_fake_zypper
fail_until=99
if CDSI_ZYPPER_RETRY_ATTEMPTS=3 CDSI_ZYPPER_COMMAND_TIMEOUT=30 \
    CDSI_ZYPPER_RETRY_DELAY=0 cdsi_zypper install nginx; then
    fail_test "permanent Zypper failure unexpectedly succeeded"
else
    actual_exit_code=$?
fi
assert_equal "$fake_exit_code" "$actual_exit_code" "last Zypper exit code"
assert_equal 3 "$zypper_calls" "permanent failure call count"
assert_equal 2 "$sleep_calls" "permanent failure sleep count"

for invalid_attempts in 0 08 11 999999999999999999999; do
    reset_fake_zypper
    if CDSI_ZYPPER_RETRY_ATTEMPTS="$invalid_attempts" cdsi_zypper refresh; then
        fail_test "invalid attempts value '${invalid_attempts}' was accepted"
    else
        actual_exit_code=$?
    fi
    assert_equal 2 "$actual_exit_code" "invalid attempts exit code"
    assert_equal 0 "$zypper_calls" "invalid attempts Zypper call count"
done

for invalid_timeout in 29 1801; do
    reset_fake_zypper
    if CDSI_ZYPPER_COMMAND_TIMEOUT="$invalid_timeout" cdsi_zypper refresh; then
        fail_test "invalid command timeout '${invalid_timeout}' was accepted"
    else
        actual_exit_code=$?
    fi
    assert_equal 2 "$actual_exit_code" "invalid command timeout exit code"
    assert_equal 0 "$zypper_calls" "invalid timeout Zypper call count"
done

reset_fake_zypper
if CDSI_ZYPPER_RETRY_DELAY=61 cdsi_zypper refresh; then
    fail_test "retry delay above the hard limit was accepted"
else
    actual_exit_code=$?
fi
assert_equal 2 "$actual_exit_code" "invalid retry delay exit code"
assert_equal 0 "$zypper_calls" "invalid delay Zypper call count"

reset_fake_zypper
if cdsi_zypper; then
    fail_test "empty Zypper operation unexpectedly succeeded"
else
    actual_exit_code=$?
fi
assert_equal 2 "$actual_exit_code" "empty Zypper operation exit code"
assert_equal 0 "$zypper_calls" "empty operation Zypper call count"

printf 'Zypper helper tests: PASS\n'
