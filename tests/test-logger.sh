#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT

CDSI_LOG_DIR="${fixture_dir}/log"
CDSI_LOG_FILE="${CDSI_LOG_DIR}/install.log"
CLR_CYAN=""
CLR_GREEN=""
CLR_YELLOW=""
CLR_RED=""
CLR_RESET=""

# shellcheck source=../lib/logger.sh
source "${TEST_ROOT}/lib/logger.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

logger_init
[[ "$CDSI_LOG_WRITABLE" == true ]] \
    || fail_test "logger did not initialize its fixture log"
[[ "$(stat -c '%a' "$CDSI_LOG_FILE")" == "600" ]] \
    || fail_test "install log permissions are not 600"

terminal_stdout="${fixture_dir}/stdout"
terminal_stderr="${fixture_dir}/stderr"
for expected_status in 3 10 37; do
    actual_status=0
    logger_run_component bash -c '
        printf "stdout-secret-status-%s\n" "$1"
        printf "stderr-diagnostic-status-%s\n" "$1" >&2
        exit "$1"
    ' _ "$expected_status" >> "$terminal_stdout" 2>> "$terminal_stderr" \
        || actual_status=$?
    [[ "$actual_status" -eq "$expected_status" ]] \
        || fail_test "component status ${expected_status} changed to ${actual_status}"
done

for expected_status in 3 10 37; do
    grep -Fq "stdout-secret-status-${expected_status}" "$terminal_stdout" \
        || fail_test "component stdout was not relayed to the terminal"
    grep -Fq "stderr-diagnostic-status-${expected_status}" "$terminal_stderr" \
        || fail_test "component stderr was not relayed to the terminal"
    grep -Fq "stderr-diagnostic-status-${expected_status}" "$CDSI_LOG_FILE" \
        || fail_test "component stderr was not persisted"
done
if grep -Fq 'stdout-secret-status-' "$CDSI_LOG_FILE"; then
    fail_test "component stdout was persisted and could leak credentials"
fi

log_size_before="$(wc -c < "$CDSI_LOG_FILE" | tr -d '[:space:]')"
CDSI_LOG_WRITABLE=false
fallback_status=0
logger_run_component bash -c '
    printf "fallback-stdout\n"
    printf "fallback-stderr\n" >&2
    exit 19
' > "${fixture_dir}/fallback.stdout" 2> "${fixture_dir}/fallback.stderr" \
    || fallback_status=$?
[[ "$fallback_status" -eq 19 ]] \
    || fail_test "unwritable-log fallback changed the component status"
grep -Fq 'fallback-stdout' "${fixture_dir}/fallback.stdout" \
    || fail_test "unwritable-log fallback lost component stdout"
grep -Fq 'fallback-stderr' "${fixture_dir}/fallback.stderr" \
    || fail_test "unwritable-log fallback lost component stderr"
[[ "$(wc -c < "$CDSI_LOG_FILE" | tr -d '[:space:]')" == "$log_size_before" ]] \
    || fail_test "unwritable-log fallback unexpectedly changed the log"

printf 'PASS: component diagnostics logging and secret boundary\n'
