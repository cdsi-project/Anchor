#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/platform.sh
source "${TEST_ROOT}/lib/platform.sh"
# shellcheck source=../lib/services.sh
source "${TEST_ROOT}/lib/services.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_success() {
    local message="$1"
    shift
    "$@" || fail_test "$message"
}

assert_failure() {
    local message="$1"
    shift
    if "$@"; then
        fail_test "$message"
    fi
}

service_log="$(mktemp)"
trap 'rm -f "$service_log"' EXIT

record_call() {
    printf '%s\n' "$*" >> "$service_log"
}

assert_log_line() {
    local expected="$1"
    grep -Fqx -- "$expected" "$service_log" \
        || fail_test "expected command was not called: ${expected}"
}

assert_no_log_line() {
    local unexpected="$1"
    if grep -Fqx -- "$unexpected" "$service_log"; then
        fail_test "unexpected command was called: ${unexpected}"
    fi
}

# Tests set the backend explicitly and must not inspect the developer machine.
cdsi_platform_init() { :; }

sudo() {
    record_call "sudo $*"
    "$@"
}

mock_systemd_installed=true
mock_systemd_active=true
mock_systemd_enabled=true

systemctl() {
    record_call "systemctl $*"
    case "${1:-}" in
        list-unit-files)
            if [[ "$mock_systemd_installed" == true ]]; then
                printf '%s enabled\n' "${*: -1}"
            fi
            return 0
            ;;
        is-active) [[ "$mock_systemd_active" == true ]] ;;
        is-enabled) [[ "$mock_systemd_enabled" == true ]] ;;
        enable) mock_systemd_enabled=true ;;
        start) mock_systemd_active=true ;;
        disable)
            mock_systemd_enabled=false
            [[ " $* " != *" --now "* ]] || mock_systemd_active=false
            ;;
        *) return 0 ;;
    esac
}

CDSI_SERVICE_BACKEND="systemd"
assert_success "installed service should be detected" cdsi_service_installed nginx
assert_success "active service should be detected" cdsi_service_active nginx
assert_success "enabled service should be detected" cdsi_service_enabled nginx

mock_systemd_installed=false
assert_failure "missing service should be rejected" cdsi_service_installed missing
mock_systemd_active=false
assert_failure "inactive service should be rejected" cdsi_service_active nginx
mock_systemd_enabled=false
assert_failure "disabled service should be rejected" cdsi_service_enabled nginx

: > "$service_log"
cdsi_service_enable nginx
cdsi_service_start nginx
cdsi_service_reload nginx
cdsi_service_restart nginx
cdsi_service_stop_disable nginx
assert_log_line "systemctl enable nginx"
assert_log_line "systemctl start nginx"
assert_log_line "systemctl reload nginx"
assert_log_line "systemctl restart nginx"
assert_log_line "systemctl disable --now nginx"

: > "$service_log"
mock_systemd_active=false
cdsi_service_enable_now nginx
assert_log_line "systemctl enable nginx"
assert_log_line "systemctl is-active --quiet nginx"
assert_log_line "systemctl start nginx"

: > "$service_log"
mock_systemd_active=true
cdsi_service_enable_now nginx
assert_log_line "systemctl enable nginx"
assert_log_line "systemctl is-active --quiet nginx"
assert_no_log_line "systemctl start nginx"

mock_systemd_installed=true
mock_systemd_active=true
mock_systemd_enabled=true
assert_success "CentOS MySQL service should use systemd" \
    cdsi_service_installed mysqld
assert_success "CentOS PHP-FPM service should use systemd" \
    cdsi_service_active php-fpm
assert_success "CentOS Nginx service should use systemd" \
    cdsi_service_enabled nginx

CDSI_SERVICE_BACKEND="unknown"
assert_failure "unknown service backend unexpectedly succeeded" \
    cdsi_service_active nginx

printf 'PASS: Ubuntu and CentOS Stream systemd service mappings\n'
