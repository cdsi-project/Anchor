#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/platform.sh
source "${TEST_ROOT}/lib/platform.sh"
# shellcheck source=../lib/packages.sh
source "${TEST_ROOT}/lib/packages.sh"

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

last_apt_args=""
last_dnf_args=""
last_dnf_query=""
mock_candidate="1.0"
mock_installed=true
mock_dnf_available=true
mock_extras_repo="extras-common"
epel_test_dir="$(mktemp -d)"
CDSI_EPEL_MARKER="${epel_test_dir}/epel-added"
trap 'rm -f -- "$CDSI_EPEL_MARKER"; rmdir -- "$epel_test_dir" 2>/dev/null || true' EXIT

# Tests set the backend explicitly and must not inspect the developer machine.
cdsi_platform_init() { :; }

cdsi_apt_get() {
    last_apt_args="$*"
}

cdsi_dnf() {
    last_dnf_args="$*"
}

cdsi_dnf_query() {
    last_dnf_query="$*"
    if [[ "$*" == *"epel-release"* && "$*" == *"--enablerepo="* ]]; then
        [[ "$*" == *"--enablerepo=${mock_extras_repo}"* ]]
        return
    fi
    [[ "$mock_dnf_available" == true ]]
}

sudo() {
    "$@"
}

function apt-cache {
    [[ "${1:-}" == "policy" ]] || return 1
    printf '  Candidate: %s\n' "$mock_candidate"
}

function dpkg-query {
    if [[ "$mock_installed" == true ]]; then
        printf 'install ok installed\n'
        return 0
    fi
    return 1
}

rpm() {
    [[ "${1:-}" == "-q" && "${2:-}" == "--quiet" ]] || return 2
    [[ "$mock_installed" == true ]]
}

CDSI_PACKAGE_BACKEND="apt"
assert_success "APT update should succeed" cdsi_packages_update
assert_equal "update -qq" "$last_apt_args" "APT update arguments"

assert_success "APT install should succeed" cdsi_packages_install nginx php-fpm
assert_equal "install -y -qq nginx php-fpm" "$last_apt_args" \
    "APT install arguments"

assert_success "APT purge should succeed" cdsi_packages_remove nginx
assert_equal "purge -y nginx" "$last_apt_args" "APT purge arguments"

assert_success "APT autoremove should succeed" cdsi_packages_autoremove
assert_equal "autoremove --purge -y" "$last_apt_args" \
    "APT autoremove arguments"

mock_candidate="1.0"
assert_success "package candidate should be detected" cdsi_package_available nginx
mock_candidate="(none)"
assert_failure "missing package candidate should be rejected" \
    cdsi_package_available missing

mock_installed=true
assert_success "installed package should be detected" cdsi_package_installed nginx
mock_installed=false
assert_failure "missing package should be rejected" cdsi_package_installed missing

CDSI_PACKAGE_BACKEND="dnf"
assert_success "DNF metadata update should succeed" cdsi_packages_update
assert_equal "makecache -q --refresh" "$last_dnf_args" \
    "DNF metadata arguments"

assert_success "DNF install should succeed" \
    cdsi_packages_install nginx php-fpm
assert_equal "install -y -q nginx php-fpm" "$last_dnf_args" \
    "DNF install arguments"

assert_success "DNF remove should succeed" cdsi_packages_remove nginx
assert_equal "remove -y -q nginx" "$last_dnf_args" "DNF remove arguments"

assert_success "DNF autoremove should succeed" cdsi_packages_autoremove
assert_equal "autoremove -y -q" "$last_dnf_args" "DNF autoremove arguments"

mock_dnf_available=true
assert_success "available DNF package should be detected" \
    cdsi_package_available nginx
assert_equal "-q list --available nginx" "$last_dnf_query" \
    "DNF availability query"
mock_dnf_available=false
assert_failure "missing DNF package should be rejected" \
    cdsi_package_available missing
mock_installed=true
assert_success "installed RPM should remain an available package candidate" \
    cdsi_package_available nginx

assert_success "installed RPM should be detected" \
    cdsi_package_installed nginx
mock_installed=false
assert_failure "missing RPM should be rejected" \
    cdsi_package_installed missing

CDSI_PLATFORM="centos-stream"
mock_installed=true
last_dnf_args=""
rm -f -- "$CDSI_EPEL_MARKER"
assert_success "existing EPEL release should be preserved" cdsi_enable_epel
assert_equal "" "$last_dnf_args" "existing EPEL package install"
[[ ! -e "$CDSI_EPEL_MARKER" ]] \
    || fail_test "existing EPEL package was incorrectly marked as Anchor-owned"

mock_installed=false
mock_extras_repo="extras-common"
last_dnf_args=""
rm -f -- "$CDSI_EPEL_MARKER"
assert_success "EPEL should install from CentOS Extras" cdsi_enable_epel
assert_equal \
    "install -y -q --disablerepo=* --enablerepo=extras-common epel-release" \
    "$last_dnf_args" \
    "EPEL install source"
assert_equal "epel-release" "$(tr -d '\r\n' < "$CDSI_EPEL_MARKER")" \
    "Anchor EPEL ownership marker"

(
    rm -f -- "$CDSI_EPEL_MARKER"
    last_dnf_args=""
    cdsi_record_epel_added() { return 1; }
    assert_failure "EPEL should fail when its ownership marker cannot be written" \
        cdsi_enable_epel
    assert_equal "remove -y -q epel-release" "$last_dnf_args" \
        "untracked EPEL install rollback"
)

mock_extras_repo="unavailable"
last_dnf_args=""
rm -f -- "$CDSI_EPEL_MARKER"
assert_failure "EPEL should fail when CentOS Extras has no release package" \
    cdsi_enable_epel
assert_equal "" "$last_dnf_args" "EPEL install without CentOS Extras"
[[ ! -e "$CDSI_EPEL_MARKER" ]] \
    || fail_test "failed EPEL install wrote an ownership marker"

CDSI_PLATFORM="ubuntu"
CDSI_PACKAGE_BACKEND="apt"
last_dnf_args=""
assert_failure "EPEL enable should be rejected outside CentOS Stream" \
    cdsi_enable_epel
assert_equal "" "$last_dnf_args" "non-CentOS EPEL install"

CDSI_PACKAGE_BACKEND="unknown"
assert_failure "unknown package backend unexpectedly succeeded" \
    cdsi_packages_update

CDSI_PACKAGE_BACKEND="apt"
assert_failure "empty install unexpectedly succeeded" cdsi_packages_install
assert_failure "empty purge unexpectedly succeeded" cdsi_packages_remove

printf 'PASS: APT/DNF package operations and explicit EPEL enablement\n'
