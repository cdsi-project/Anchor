#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/platform.sh
source "${TEST_ROOT}/lib/platform.sh"
# shellcheck source=../lib/services.sh
source "${TEST_ROOT}/lib/services.sh"
# shellcheck source=../lib/common.sh
source "${TEST_ROOT}/lib/common.sh"
# shellcheck source=../lib/logger.sh
source "${TEST_ROOT}/lib/logger.sh"
# shellcheck source=../lib/system.sh
source "${TEST_ROOT}/lib/system.sh"
# shellcheck source=../scripts/common/check-env.sh
source "${TEST_ROOT}/scripts/common/check-env.sh"

set_platform_fixture() {
    CDSI_PLATFORM_INITIALIZED=1
    CDSI_PLATFORM="$1"
    CDSI_OS_VERSION="$2"
    CDSI_OS_PRETTY="$3"
    CDSI_ARCH="${4:-x86_64}"
}

assert_os_status() {
    local expected="$1"
    preflight_overall_status=0
    pf_check_os >/dev/null
    if [[ "$preflight_overall_status" -ne "$expected" ]]; then
        printf 'FAIL: OS=%s version=%s produced status %s, expected %s\n' \
            "$CDSI_PLATFORM" "$CDSI_OS_VERSION" \
            "$preflight_overall_status" "$expected" >&2
        exit 1
    fi
}

set_platform_fixture ubuntu "24.04" "Ubuntu 24.04 LTS"
assert_os_status 0
set_platform_fixture ubuntu "26.04" "Ubuntu 26.04 LTS"
assert_os_status 0
set_platform_fixture centos-stream "10" "CentOS Stream 10"
assert_os_status 0
set_platform_fixture centos-stream "9" "CentOS Stream 9"
assert_os_status 2
set_platform_fixture centos "10" "CentOS Linux 10"
assert_os_status 2
set_platform_fixture ubuntu "22.04" "Ubuntu 22.04 LTS"
assert_os_status 2
set_platform_fixture debian "13" "Debian GNU/Linux 13"
assert_os_status 0
set_platform_fixture debian "12" "Debian GNU/Linux 12"
assert_os_status 2
set_platform_fixture debian "14" "Debian GNU/Linux 14"
assert_os_status 2

assert_arch_status() {
    local expected="$1"
    preflight_overall_status=0
    pf_check_arch >/dev/null
    if [[ "$preflight_overall_status" -ne "$expected" ]]; then
        printf 'FAIL: architecture=%s produced status %s, expected %s\n' \
            "$CDSI_ARCH" "$preflight_overall_status" "$expected" >&2
        exit 1
    fi
}

CDSI_ARCH="x86_64"
assert_arch_status 0
CDSI_ARCH="aarch64"
assert_arch_status 0
CDSI_ARCH="riscv64"
assert_arch_status 1

mock_root=false
mock_sudo=true
check_root() { [[ "$mock_root" == true ]]; }
check_sudo() { [[ "$mock_sudo" == true ]]; }
whoami() { printf 'anchor-test\n'; }

assert_user_status() {
    local expected="$1"
    preflight_overall_status=0
    pf_check_user >/dev/null
    if [[ "$preflight_overall_status" -ne "$expected" ]]; then
        printf 'FAIL: platform=%s root=%s produced user status %s, expected %s\n' \
            "$CDSI_PLATFORM" "$mock_root" "$preflight_overall_status" \
            "$expected" >&2
        exit 1
    fi
}

set_platform_fixture ubuntu "24.04" "Ubuntu 24.04 LTS"
assert_user_status 0
mock_sudo=false
assert_user_status 2

getenforce() { printf '%s\n' "${mock_selinux_mode}"; }
cdsi_service_active() { [[ "$1" == firewalld && "${mock_firewalld_active}" == true ]]; }

set_platform_fixture centos-stream "10" "CentOS Stream 10"
mock_selinux_mode="Enforcing"
preflight_overall_status=0
pf_check_selinux >/dev/null
[[ "$preflight_overall_status" -eq 0 ]] \
    || { printf 'FAIL: enforcing SELinux should pass preflight\n' >&2; exit 1; }

mock_selinux_mode="Disabled"
preflight_overall_status=0
pf_check_selinux >/dev/null
[[ "$preflight_overall_status" -eq 1 ]] \
    || { printf 'FAIL: disabled SELinux should warn\n' >&2; exit 1; }

mock_firewalld_active=false
preflight_overall_status=0
pf_check_firewalld >/dev/null
[[ "$preflight_overall_status" -eq 1 ]] \
    || { printf 'FAIL: inactive firewalld should warn\n' >&2; exit 1; }

mock_firewalld_active=true
preflight_overall_status=0
pf_check_firewalld >/dev/null
[[ "$preflight_overall_status" -eq 0 ]] \
    || { printf 'FAIL: active firewalld should pass\n' >&2; exit 1; }

printf 'PASS: supported releases, architecture, privileges, and CentOS security preflight\n'
