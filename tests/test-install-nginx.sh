#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_SCRIPT="${TEST_ROOT}/scripts/common/install-nginx.sh"
fixture_dir="$(mktemp -d)"
action_log="$(mktemp)"
trap 'rm -f "$action_log"; rm -rf "$fixture_dir"' EXIT

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}()/,/^}/p" "$NGINX_SCRIPT"
}

# Load only the firewalld helpers so the installer top level cannot touch the
# developer host. Rebind its production marker directory to this fixture.
# shellcheck disable=SC1090
source <(extract_function _record_firewall_service \
    | sed "s|local record_dir=\"/etc/cdsi\"|local record_dir=\"${fixture_dir}\"|")
for helper in \
    _firewall_scope_present \
    _firewall_scope_add \
    _firewall_scope_remove \
    _ensure_firewall_scope \
    _configure_managed_firewall; do
    # shellcheck disable=SC1090
    source <(extract_function "$helper")
done

ROOT_CMD=()
log() { :; }
warn() { :; }
platform_fixture="centos-stream"
cdsi_uses_firewalld() {
    [[ "$platform_fixture" == "centos-stream" \
        || "$platform_fixture" == "opensuse-leap" ]]
}
systemctl() { [[ "$*" == "is-active --quiet firewalld" ]]; }

declare -A permanent_state=( [http]=1 [https]=1 )
declare -A runtime_state=( [http]=0 [https]=1 )

firewall-cmd() {
    local scope="runtime"
    local operation=""
    local service_name=""
    if [[ "${1:-}" == "--permanent" ]]; then
        scope="permanent"
        shift
    fi
    case "${1:-}" in
        --query-service=*) operation="query"; service_name="${1#*=}" ;;
        --add-service=*) operation="add"; service_name="${1#*=}" ;;
        --remove-service=*) operation="remove"; service_name="${1#*=}" ;;
        *) return 2 ;;
    esac
    printf '%s:%s:%s\n' "$scope" "$operation" "$service_name" >> "$action_log"

    if [[ "$scope" == "permanent" ]]; then
        case "$operation" in
            query) [[ "${permanent_state[$service_name]:-0}" == 1 ]] ;;
            add) permanent_state[$service_name]=1 ;;
            remove) permanent_state[$service_name]=0 ;;
        esac
    else
        case "$operation" in
            query) [[ "${runtime_state[$service_name]:-0}" == 1 ]] ;;
            add) runtime_state[$service_name]=1 ;;
            remove) runtime_state[$service_name]=0 ;;
        esac
    fi
}

assert_action() {
    local expected="$1"
    grep -Fqx -- "$expected" "$action_log" \
        || { printf 'FAIL: expected Nginx firewalld action: %s\n' "$expected" >&2; exit 1; }
}

assert_no_action() {
    local unexpected="$1"
    if grep -Fqx -- "$unexpected" "$action_log"; then
        printf 'FAIL: unexpected Nginx firewalld action: %s\n' "$unexpected" >&2
        exit 1
    fi
}

marker="${fixture_dir}/firewall-added-services"

# A pre-existing permanent rule must not make the installer skip a missing
# runtime rule. Only the runtime layer is Anchor-owned and recorded.
_configure_managed_firewall
assert_action "permanent:query:http"
assert_action "runtime:query:http"
assert_action "runtime:add:http"
assert_no_action "permanent:add:http"
[[ "$(cat "$marker")" == "runtime:http" ]] \
    || { printf 'FAIL: runtime-only firewalld ownership was not recorded exactly\n' >&2; exit 1; }

# When both layers are absent, each addition receives its own marker entry.
rm -f "$marker"
: > "$action_log"
permanent_state[http]=0
runtime_state[http]=0
_configure_managed_firewall
assert_action "permanent:add:http"
assert_action "runtime:add:http"
expected_marker=$'permanent:http\nruntime:http'
[[ "$(cat "$marker")" == "$expected_marker" ]] \
    || { printf 'FAIL: permanent/runtime firewalld ownership was not recorded separately\n' >&2; exit 1; }

# A rerun observes both rules and performs no duplicate mutation.
: > "$action_log"
_configure_managed_firewall
if grep -Fq ':add:' "$action_log"; then
    printf 'FAIL: Nginx firewalld rerun duplicated an existing rule\n' >&2
    exit 1
fi

# Refuse an old/invalid marker before retaining an untracked new layer. The
# just-added runtime rule is rolled back without touching permanent state.
printf 'http\n' > "$marker"
: > "$action_log"
permanent_state[http]=1
runtime_state[http]=1
permanent_state[https]=1
runtime_state[https]=0
if _configure_managed_firewall; then
    printf 'FAIL: invalid firewalld ownership marker was accepted\n' >&2
    exit 1
fi
assert_action "runtime:add:https"
assert_action "runtime:remove:https"
assert_no_action "permanent:remove:https"
[[ "${runtime_state[https]}" == 0 ]] \
    || { printf 'FAIL: unrecorded runtime rule was not rolled back\n' >&2; exit 1; }
[[ "$(cat "$marker")" == "http" ]] \
    || { printf 'FAIL: invalid firewalld marker was unexpectedly rewritten\n' >&2; exit 1; }

# openSUSE Leap uses the same provenance-tracked firewalld integration.
rm -f "$marker"
: > "$action_log"
platform_fixture="opensuse-leap"
permanent_state[http]=1
runtime_state[http]=1
permanent_state[https]=0
runtime_state[https]=0
_configure_managed_firewall
assert_action "permanent:add:https"
assert_action "runtime:add:https"
expected_marker=$'permanent:https\nruntime:https'
[[ "$(cat "$marker")" == "$expected_marker" ]] \
    || { printf 'FAIL: openSUSE firewalld ownership was not recorded\n' >&2; exit 1; }

# Platforms outside the managed firewalld set must not be inspected or changed.
: > "$action_log"
platform_fixture="ubuntu"
_configure_managed_firewall
[[ ! -s "$action_log" ]] \
    || { printf 'FAIL: non-firewalld platform changed firewall state\n' >&2; exit 1; }

# The healthy-running fast path must also reconcile boot enablement.
fast_path="$(sed -n '/# Skip only when/,/# Preserve a broken existing configuration/p' "$NGINX_SCRIPT")"
[[ "$fast_path" == *'cdsi_service_enabled "$CDSI_NGINX_SERVICE"'* \
   && "$fast_path" == *'cdsi_service_enable "$CDSI_NGINX_SERVICE"'* ]] \
    || { printf 'FAIL: Nginx fast path does not ensure boot enablement\n' >&2; exit 1; }

printf 'PASS: Nginx fast-path enablement and CentOS/openSUSE firewalld ownership\n'
