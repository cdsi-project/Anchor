#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT

# shellcheck source=../install.sh
source "${TEST_ROOT}/install.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

CDSI_DOMAIN_FILE="${fixture_dir}/domain"
CDSI_PENDING_DOMAIN_FILE="${fixture_dir}/domain.pending"
CDSI_ROOT_CMD=()
configure_status=0
configure_calls=()
configure_call_args=()
log_blank() { :; }
log_separator() { :; }
log_info() { :; }
log_success() { :; }
log_warning() { :; }
log_error() { :; }
logger_run_component() {
    configure_calls+=("$*")
    configure_call_args=("$@")
    return "$configure_status"
}

reset_finalization() {
    CDSI_COMP_DONE[$CDSI_CERTBOT_COMPONENT_INDEX]=false
    CDSI_COMP_OPTIONAL_STATUS[$CDSI_CERTBOT_COMPONENT_INDEX]=""
    CDSI_CURRENT_STAGE="MENU"
    configure_calls=()
    configure_call_args=()
    configure_status=0
}

assert_exact_configure_arg_once() {
    local expected="$1"
    local arg="" matches=0
    for arg in "${configure_call_args[@]}"; do
        [[ "$arg" != "$expected" ]] || matches=$((matches + 1))
    done
    [[ "$matches" -eq 1 ]] \
        || fail_test "expected one exact configure argument '${expected}', found ${matches}"
}

printf '%s\n' 'bad/path' > "$CDSI_DOMAIN_FILE"
invalid_before="$(sha256sum "$CDSI_DOMAIN_FILE" | awk '{print $1}')"
cdsi_prepare_install_domain_state
[[ "$CDSI_BASE_DOMAIN_FILE" == /dev/null ]] \
    || fail_test "invalid active state was not isolated from the base install"
[[ "$(sha256sum "$CDSI_DOMAIN_FILE" | awk '{print $1}')" == "$invalid_before" ]] \
    || fail_test "base preparation changed an invalid active-domain file"

printf '%s\n' 'active.example.com' > "$CDSI_DOMAIN_FILE"
printf '%s\n' 'pending.example.com' > "$CDSI_PENDING_DOMAIN_FILE"
cdsi_prepare_install_domain_state
[[ "$CDSI_BASE_DOMAIN_FILE" == "$CDSI_DOMAIN_FILE" ]] \
    || fail_test "valid active state was isolated from the base install"
active_before="$(sha256sum "$CDSI_DOMAIN_FILE" | awk '{print $1}')"
pending_before="$(sha256sum "$CDSI_PENDING_DOMAIN_FILE" | awk '{print $1}')"
reset_finalization
cdsi_configure_optional_domain_https "" <<< "" >/dev/null
[[ "${#configure_calls[@]}" -eq 0 ]] \
    || fail_test "Enter skip invoked domain/HTTPS configuration"
[[ "${CDSI_COMP_OPTIONAL_STATUS[$CDSI_CERTBOT_COMPONENT_INDEX]}" == skipped ]] \
    || fail_test "Enter skip did not record the optional status"
[[ "$(sha256sum "$CDSI_DOMAIN_FILE" | awk '{print $1}')" == "$active_before" \
   && "$(sha256sum "$CDSI_PENDING_DOMAIN_FILE" | awk '{print $1}')" == "$pending_before" ]] \
    || fail_test "Enter skip changed active or pending domain state"

reset_finalization
cdsi_configure_optional_domain_https "" </dev/null >/dev/null
[[ "${#configure_calls[@]}" -eq 0 ]] \
    || fail_test "EOF skip invoked domain/HTTPS configuration"

reset_finalization
cdsi_configure_optional_domain_https "bad/path" <<< "" >/dev/null
[[ "${#configure_calls[@]}" -eq 0 ]] \
    || fail_test "invalid domain followed by Enter did not skip"

reset_finalization
configure_status=10
cdsi_configure_optional_domain_https "new.example.com" >/dev/null
[[ "${#configure_calls[@]}" -eq 1 ]] \
    || fail_test "domain finalization did not call configure-https once"
[[ "${configure_calls[0]}" == *"scripts/configure-https.sh new.example.com"* ]] \
    || fail_test "domain was not passed to configure-https"
assert_exact_configure_arg_once "CDSI_DOMAIN=new.example.com"
last_arg_index=$((${#configure_call_args[@]} - 1))
[[ "${configure_call_args[$last_arg_index]}" == new.example.com ]] \
    || fail_test "domain argument boundary was not preserved"
[[ "${CDSI_COMP_OPTIONAL_STATUS[$CDSI_CERTBOT_COMPONENT_INDEX]}" == deferred ]] \
    || fail_test "deferred HTTPS did not preserve successful base-install status"

reset_finalization
configure_status=7
cdsi_configure_optional_domain_https "new.example.com" >/dev/null
[[ "${CDSI_COMP_OPTIONAL_STATUS[$CDSI_CERTBOT_COMPONENT_INDEX]}" == failed ]] \
    || fail_test "failed HTTPS was not recorded as an optional failure"
[[ "$CDSI_CURRENT_STAGE" == MENU ]] \
    || fail_test "failed optional finalization did not restore the menu stage"

reset_finalization
cdsi_configure_optional_domain_https ip >/dev/null
[[ "${configure_calls[0]}" == *"scripts/configure-https.sh --ip"* ]] \
    || fail_test "ip input was not mapped to explicit public-IP HTTPS"
assert_exact_configure_arg_once "CDSI_DOMAIN="
last_arg_index=$((${#configure_call_args[@]} - 1))
[[ "${configure_call_args[$last_arg_index]}" == --ip ]] \
    || fail_test "IP HTTPS argument boundary was not preserved"
[[ "${CDSI_COMP_DONE[$CDSI_CERTBOT_COMPONENT_INDEX]}" == true ]] \
    || fail_test "successful HTTPS did not mark Certbot complete"

reset_finalization
configure_status=128
cdsi_configure_optional_domain_https "new.example.com" >/dev/null
[[ "${CDSI_COMP_OPTIONAL_STATUS[$CDSI_CERTBOT_COMPONENT_INDEX]}" == failed ]] \
    || fail_test "ordinary exit 128 was mistaken for a signal interruption"

reset_finalization
CDSI_ROOT_CMD=(sudo)
cdsi_configure_optional_domain_https "new.example.com" >/dev/null
[[ "${configure_call_args[0]}" == sudo && "${configure_call_args[1]}" == env ]] \
    || fail_test "root command prefix was not preserved for HTTPS configuration"
assert_exact_configure_arg_once "CDSI_DOMAIN=new.example.com"
CDSI_ROOT_CMD=()

reset_finalization
configure_status=130
interrupt_rc=0
if cdsi_configure_optional_domain_https "new.example.com" >/dev/null; then
    fail_test "interrupted optional HTTPS returned success"
else
    interrupt_rc=$?
fi
[[ "$interrupt_rc" -eq 130 ]] \
    || fail_test "optional HTTPS swallowed an interrupt exit status"

for i in "${!CDSI_COMP_DONE[@]}"; do
    CDSI_COMP_DONE[$i]=false
    CDSI_COMP_OPTIONAL_STATUS[$i]=""
done
for i in 0 1 2 "$CDSI_WORDPRESS_COMPONENT_INDEX"; do
    CDSI_COMP_DONE[$i]=true
done
summary_output="$(
    log_success() { printf '%s\n' "$*"; }
    cdsi_summary
)"
[[ "$summary_output" == *"Certbot (optional, not configured)"* ]] \
    || fail_test "summary treated unconfigured Certbot as required"
[[ "$summary_output" == *"All required components installed."* ]] \
    || fail_test "summary did not recognize the completed base installation"

run_install_flow_case() {
    local configure_rc="$1"
    local flow_log="${fixture_dir}/flow-${configure_rc}.log"

    : > "$flow_log"
    if ! (
        CDSI_DOMAIN="flow.example.com"
        export CDSI_DOMAIN
        cdsi_show_menu() { :; }
        clear() { :; }
        cdsi_prepare_install_domain_state() { :; }
        cdsi_install_all() {
            printf 'core-domain:%s\n' "${CDSI_DOMAIN:-<empty>}" >> "$flow_log"
        }
        logger_run_component() {
            printf 'optional-domain:%s\n' "${CDSI_DOMAIN:-<empty>}" >> "$flow_log"
            return "$configure_rc"
        }
        cdsi_summary() { printf 'summary\n' >> "$flow_log"; }
        cdsi_post_install_report() { printf 'report\n' >> "$flow_log"; }
        log_info() { :; }
        cdsi_run_install_flow <<< "0"
    ) >/dev/null; then
        fail_test "install flow failed after optional HTTPS exit ${configure_rc}"
    fi

    expected_flow="$(printf '%s\n' \
        'core-domain:<empty>' \
        'optional-domain:flow.example.com' \
        'summary' \
        'report')"
    [[ "$(<"$flow_log")" == "$expected_flow" ]] \
        || fail_test "install flow order/domain isolation failed after HTTPS exit ${configure_rc}"
}

run_install_flow_case 10
run_install_flow_case 7

skip_flow_log="${fixture_dir}/flow-skip.log"
rm -f -- "$CDSI_DOMAIN_FILE" "$CDSI_PENDING_DOMAIN_FILE"
: > "$skip_flow_log"
if ! (
    CDSI_DOMAIN=""
    export CDSI_DOMAIN
    cdsi_show_menu() { :; }
    clear() { :; }
    cdsi_prepare_install_domain_state() { :; }
    cdsi_install_all() {
        printf 'core-domain:%s\n' "${CDSI_DOMAIN:-<empty>}" >> "$skip_flow_log"
    }
    cdsi_summary() {
        printf 'summary:%s\n' \
            "${CDSI_COMP_OPTIONAL_STATUS[$CDSI_CERTBOT_COMPONENT_INDEX]}" \
            >> "$skip_flow_log"
    }
    cdsi_post_install_report() { printf 'report\n' >> "$skip_flow_log"; }
    log_info() { :; }
    cdsi_run_install_flow <<< $'0\n'
) >/dev/null; then
    fail_test "fresh install flow failed after Enter skip"
fi
expected_skip_flow="$(printf '%s\n' \
    'core-domain:<empty>' \
    'summary:skipped' \
    'report')"
[[ "$(<"$skip_flow_log")" == "$expected_skip_flow" ]] \
    || fail_test "Enter skip did not continue to the final report"

invalid_flow_log="${fixture_dir}/flow-invalid-state.log"
printf '%s\n' 'bad/path' > "$CDSI_DOMAIN_FILE"
invalid_before="$(sha256sum "$CDSI_DOMAIN_FILE" | awk '{print $1}')"
: > "$invalid_flow_log"
if ! (
    CDSI_DOMAIN=""
    export CDSI_DOMAIN
    cdsi_show_menu() { :; }
    clear() { :; }
    cdsi_install_all() {
        printf 'base-domain-file:%s\n' "$CDSI_DOMAIN_FILE" >> "$invalid_flow_log"
    }
    cdsi_summary() { printf 'summary\n' >> "$invalid_flow_log"; }
    cdsi_post_install_report() { printf 'report\n' >> "$invalid_flow_log"; }
    log_info() { :; }
    cdsi_run_install_flow <<< $'0\n'
) >/dev/null; then
    fail_test "install flow failed while isolating invalid active state"
fi
expected_invalid_flow="$(printf '%s\n' \
    'base-domain-file:/dev/null' \
    'summary' \
    'report')"
[[ "$(<"$invalid_flow_log")" == "$expected_invalid_flow" ]] \
    || fail_test "invalid active state was not isolated during the base install"
[[ "$(sha256sum "$CDSI_DOMAIN_FILE" | awk '{print $1}')" == "$invalid_before" ]] \
    || fail_test "full install flow changed the invalid active-domain file"

rm -f -- "$CDSI_DOMAIN_FILE"

render_access_report() {
    (
        cdsi_php_fpm_version() { :; }
        cdsi_service_active() { return 1; }
        cdsi_service_enabled() { return 1; }
        cdsi_service_installed() { return 1; }
        systemctl() { return 1; }
        curl() { printf '200'; }
        cdsi_resolve_wordpress_server_ip() { printf '203.0.113.10\n'; }
        cdsi_resolve_wordpress_url() {
            local report_domain="$2"
            local report_fallback="$3"
            if [[ -n "$report_domain" ]]; then
                printf 'http://%s\n' "${report_domain%%,*}"
            else
                printf '%s\n' "$report_fallback"
            fi
        }
        cdsi_print_wordpress_access() {
            printf 'ACCESS site=%s domain=%s\n' "$1" "$5"
        }
        log_info() { :; }
        CDSI_DOMAIN="stale.example.com"
        export CDSI_DOMAIN
        cdsi_post_install_report
    )
}

printf '%s\n' 'pending.example.com' > "$CDSI_PENDING_DOMAIN_FILE"
pending_report="$(render_access_report)"
[[ "$pending_report" == *"Pending Domain:"*"pending.example.com"* ]] \
    || fail_test "pending-only report omitted the pending domain"
[[ "$pending_report" == *"ACCESS site=http://203.0.113.10 domain="* ]] \
    || fail_test "pending-only report did not keep the IP HTTP URL"
[[ "$pending_report" != *"ACCESS site="*"stale.example.com"* ]] \
    || fail_test "report treated the parent CDSI_DOMAIN as active state"

printf '%s\n' 'active.example.com' > "$CDSI_DOMAIN_FILE"
active_report="$(render_access_report)"
[[ "$active_report" == *"ACCESS site=http://active.example.com domain=active.example.com"* ]] \
    || fail_test "report did not use the persisted active domain"

install_all_line="$(grep -nE '^[[:space:]]+cdsi_install_all$' "${TEST_ROOT}/install.sh" | cut -d: -f1)"
finalize_line="$(grep -nE '^[[:space:]]+cdsi_configure_optional_domain_https ' "${TEST_ROOT}/install.sh" | cut -d: -f1)"
summary_line="$(grep -nE '^[[:space:]]+cdsi_summary$' "${TEST_ROOT}/install.sh" | head -n1 | cut -d: -f1)"
report_line="$(grep -nE '^[[:space:]]+cdsi_post_install_report$' "${TEST_ROOT}/install.sh" | cut -d: -f1)"
[[ "$install_all_line" -lt "$finalize_line" \
   && "$finalize_line" -lt "$summary_line" \
   && "$summary_line" -lt "$report_line" ]] \
    || fail_test "install-all finalization/report order is incorrect"

printf 'PASS: optional final domain/HTTPS setup and skip/defer behavior\n'
