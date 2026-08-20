#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDSI_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# Keep expected retry failures out of the test output.
log() { :; }
log_fail() { :; }

# shellcheck source=../lib/apt.sh
source "${CDSI_ROOT}/lib/apt.sh"

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

reset_fake_apt() {
    apt_calls=0
    sudo_calls=0
    sleep_calls=0
    fail_until=0
    fake_exit_code=73
    last_apt_args=""
}

env() {
    [[ "${1:-}" == "DEBIAN_FRONTEND=noninteractive" ]] \
        || fail_test "DEBIAN_FRONTEND was not passed through env"
    shift
    "$@"
}

sudo() {
    ((sudo_calls += 1))
    [[ "${1:-}" == "env" ]] || fail_test "sudo must invoke env first"
    "$@"
}

apt-get() {
    ((apt_calls += 1))
    last_apt_args="$*"
    if ((apt_calls <= fail_until)); then
        return "$fake_exit_code"
    fi
    return 0
}

sleep() {
    [[ "${1:-}" == "0" ]] || fail_test "tests must not perform a real wait"
    ((sleep_calls += 1))
}

expected_sudo_calls() {
    local apt_attempts="$1"
    if [[ "${EUID}" -eq 0 ]]; then
        printf '0\n'
    else
        printf '%s\n' "$apt_attempts"
    fi
}

reset_fake_apt
CDSI_APT_RETRY_ATTEMPTS=3 CDSI_APT_LOCK_TIMEOUT=7 CDSI_APT_RETRY_DELAY=0 \
    cdsi_apt_get update -qq
assert_equal 1 "$apt_calls" "first-attempt success call count"
assert_equal 0 "$sleep_calls" "first-attempt success sleep count"
assert_equal "$(expected_sudo_calls 1)" "$sudo_calls" "first-attempt sudo count"
assert_equal \
    "-o DPkg::Lock::Timeout=7 -o Acquire::Retries=3 update -qq" \
    "$last_apt_args" \
    "apt-get argument forwarding"

reset_fake_apt
fail_until=2
CDSI_APT_RETRY_ATTEMPTS=3 CDSI_APT_LOCK_TIMEOUT=9 CDSI_APT_RETRY_DELAY=0 \
    cdsi_apt_get install -y mysql-server
assert_equal 3 "$apt_calls" "retry-then-success call count"
assert_equal 2 "$sleep_calls" "retry-then-success sleep count"
assert_equal "$(expected_sudo_calls 3)" "$sudo_calls" "retry sudo count"

reset_fake_apt
fail_until=99
if CDSI_APT_RETRY_ATTEMPTS=3 CDSI_APT_LOCK_TIMEOUT=5 CDSI_APT_RETRY_DELAY=0 \
    cdsi_apt_get install -y nginx; then
    fail_test "permanent apt failure unexpectedly succeeded"
else
    actual_exit_code=$?
fi
assert_equal "$fake_exit_code" "$actual_exit_code" "last apt exit code"
assert_equal 3 "$apt_calls" "permanent failure call count"
assert_equal 2 "$sleep_calls" "permanent failure sleep count"

for invalid_attempts in 0 08 11 999999999999999999999; do
    reset_fake_apt
    if CDSI_APT_RETRY_ATTEMPTS="$invalid_attempts" cdsi_apt_get update; then
        fail_test "invalid attempts value '${invalid_attempts}' was accepted"
    else
        actual_exit_code=$?
    fi
    assert_equal 2 "$actual_exit_code" "invalid attempts exit code"
    assert_equal 0 "$apt_calls" "invalid attempts apt call count"
done

reset_fake_apt
if CDSI_APT_LOCK_TIMEOUT=601 cdsi_apt_get update; then
    fail_test "lock timeout above the hard limit was accepted"
else
    actual_exit_code=$?
fi
assert_equal 2 "$actual_exit_code" "invalid lock timeout exit code"
assert_equal 0 "$apt_calls" "invalid lock timeout apt call count"

printf 'apt helper tests: PASS\n'
