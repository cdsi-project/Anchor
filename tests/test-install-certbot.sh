#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERTBOT_SCRIPT="${TEST_ROOT}/scripts/common/install-certbot.sh"

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

assert_file_line() {
    local expected="$1"
    local file="$2"
    grep -Fqx -- "$expected" "$file" \
        || fail_test "expected call was not recorded: ${expected}"
}

assert_no_file_line() {
    local unexpected="$1"
    local file="$2"
    if grep -Fqx -- "$unexpected" "$file"; then
        fail_test "unexpected call was recorded: ${unexpected}"
    fi
}

extract_function() {
    local function_name="$1"
    awk -v signature="${function_name}() {" '
        $0 == signature { capture=1 }
        capture { print }
        capture && /^}$/ { exit }
    ' "$CERTBOT_SCRIPT"
}

[[ -f "$CERTBOT_SCRIPT" ]] \
    || fail_test "Certbot implementation not found: ${CERTBOT_SCRIPT}"
bash -n "$CERTBOT_SCRIPT" \
    || fail_test "Certbot implementation has invalid Bash syntax"

repository_function="$(awk '
    /^prepare_certbot_repository\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "$CERTBOT_SCRIPT")"
[[ -n "$repository_function" ]] \
    || fail_test "could not extract prepare_certbot_repository"
eval "$repository_function"

fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
epel_log="${fixture_dir}/epel.log"
: > "$epel_log"

platform_fixture="centos-stream"
cdsi_is_centos_stream() {
    [[ "$platform_fixture" == "centos-stream" ]]
}
cdsi_enable_epel() {
    printf 'enable-epel\n' >> "$epel_log"
}
log() { :; }
fail() { fail_test "$*"; }

CERTBOT_REPOSITORY_READY=false
prepare_certbot_repository
prepare_certbot_repository
assert_equal "1" "$(wc -l < "$epel_log" | tr -d '[:space:]')" \
    "CentOS EPEL enablement must be idempotent within one run"
assert_equal "true" "$CERTBOT_REPOSITORY_READY" \
    "CentOS Certbot repository state"

platform_fixture="ubuntu"
CERTBOT_REPOSITORY_READY=false
prepare_certbot_repository
assert_equal "1" "$(wc -l < "$epel_log" | tr -d '[:space:]')" \
    "Ubuntu Certbot path must not enable EPEL"
assert_equal "false" "$CERTBOT_REPOSITORY_READY" \
    "Ubuntu repository state must remain unchanged"

prepare_call_line="$(awk '
    /^[[:space:]]+prepare_certbot_repository$/ { print NR; exit }
' "$CERTBOT_SCRIPT")"
package_install_line="$(awk '
    /cdsi_packages_install "\$\{CERTBOT_PACKAGES\[@\]\}"/ { print NR; exit }
' "$CERTBOT_SCRIPT")"
[[ "$prepare_call_line" =~ ^[0-9]+$ && "$package_install_line" =~ ^[0-9]+$ ]] \
    || fail_test "could not locate Certbot repository/package installation order"
(( prepare_call_line < package_install_line )) \
    || fail_test "Certbot package installation occurs before repository preparation"
grep -Fq 'CERTBOT_PACKAGES=(certbot python3-certbot-nginx)' "$CERTBOT_SCRIPT" \
    || fail_test "Ubuntu Certbot package pair changed"

# ACME fallback is a reachability decision, not an unconditional CA switch.
# Exercise the selector with a mocked directory probe so no network request is
# made by this test.
selector_function="$(extract_function select_acme_server)"
[[ -n "$selector_function" ]] \
    || fail_test "could not extract select_acme_server"
eval "$selector_function"

primary_acme="https://acme-v02.api.letsencrypt.org/directory"
fallback_acme="https://acme.zerossl.com/v2/DV90"

run_acme_selection_case() {
    local label="$1"
    local primary_reachable="$2"
    local expected_server="$3"
    local probe_log="${fixture_dir}/${label}.acme.log"
    local selected=""
    : > "$probe_log"

    (
        PROBE_LOG="$probe_log"
        PRIMARY_REACHABLE="$primary_reachable"
        LETSENCRYPT_ACME_DIRECTORY="$primary_acme"
        ZEROSSL_ACME_DIRECTORY="$fallback_acme"
        CDSI_ACME_PRIMARY_DIRECTORY="$primary_acme"
        CDSI_ACME_FALLBACK_DIRECTORY="$fallback_acme"
        ACME_PRIMARY_SERVER="$primary_acme"
        ACME_FALLBACK_SERVER="$fallback_acme"
        CDSI_ZEROSSL_EAB_KID="test-eab-kid"
        CDSI_ZEROSSL_EAB_HMAC_KEY="test-eab-hmac"
        acme_directory_reachable() {
            local directory="$1"
            printf '%s\n' "$directory" >> "$PROBE_LOG"
            if [[ "$directory" == "$primary_acme" ]]; then
                [[ "$PRIMARY_REACHABLE" == true ]]
            else
                return 0
            fi
        }
        log() { :; }
        log_fail() { :; }

        selected="$(select_acme_server)" \
            || fail_test "${label} ACME server selection failed"
        assert_equal "$expected_server" "$selected" \
            "${label} ACME server"
    ) || fail_test "${label} ACME selection case failed"

    assert_file_line "$primary_acme" "$probe_log"
    if [[ "$primary_reachable" == true ]]; then
        assert_equal "1" "$(wc -l < "$probe_log" | tr -d '[:space:]')" \
            "reachable primary must not probe or select a fallback"
    else
        first_probe="$(head -n1 "$probe_log")"
        assert_equal "$primary_acme" "$first_probe" \
            "primary directory must be probed before fallback selection"
    fi
}

run_acme_selection_case primary-ready true "$primary_acme"
run_acme_selection_case primary-blocked false "$fallback_acme"

# Public IP certificates require Certbot 5.4 or newer. Keep this as a function
# boundary so supported-package updates do not require parsing live output in
# higher-level tests.
version_function="$(extract_function version_at_least)"
ip_support_function="$(extract_function certbot_supports_ip_certificates)"
[[ -n "$version_function" && -n "$ip_support_function" ]] \
    || fail_test "could not extract Certbot IP version helpers"
eval "$version_function"
eval "$ip_support_function"

MOCK_CERTBOT_VERSION=""
certbot() {
    case "${1:-}" in
        --version)
            printf 'certbot %s\n' "$MOCK_CERTBOT_VERSION"
            ;;
        certonly)
            [[ "${2:-}" == "--help" ]] || return 2
            printf '%s\n' '--ip-address --preferred-profile --webroot'
            ;;
        *)
            return 2
            ;;
    esac
}
CERTBOT_BIN=certbot

for unsupported_version in 4.2.0 5.3.9 invalid; do
    MOCK_CERTBOT_VERSION="$unsupported_version"
    if certbot_supports_ip_certificates; then
        fail_test "Certbot ${unsupported_version} unexpectedly supports IP certificates"
    fi
done
for supported_version in 5.4.0 5.4.1 6.0.0; do
    MOCK_CERTBOT_VERSION="$supported_version"
    certbot_supports_ip_certificates \
        || fail_test "Certbot ${supported_version} was rejected for IP certificates"
done

for ip_argument in \
    '--ip-address' \
    '--preferred-profile' \
    'shortlived' \
    '--webroot'; do
    grep -Fq -- "$ip_argument" "$CERTBOT_SCRIPT" \
        || fail_test "IP certificate path is missing ${ip_argument}"
done

timer_block="$(awk '
    /^RENEWAL_SUMMARY=/ { capture=1 }
    /^# .*Verify/ { if (capture) exit }
    capture { print }
' "$CERTBOT_SCRIPT")"
[[ -n "$timer_block" ]] \
    || fail_test "could not extract Certbot renewal timer selection"
renewal_function="$(extract_function ensure_certbot_renewal_timer)"
[[ -n "$renewal_function" ]] \
    || fail_test "could not extract ensure_certbot_renewal_timer"
eval "$renewal_function"

run_timer_case() {
    local label="$1"
    local available_timer="$2"
    local expected_timer="$3"
    local timer_log="${fixture_dir}/${label}.timer.log"
    : > "$timer_log"

    (
        SUDO=""
        CERTBOT_BIN="/usr/bin/certbot"
        AVAILABLE_TIMER="$available_timer"
        TIMER_LOG="$timer_log"
        log() { :; }
        log_ok() { :; }
        systemctl() {
            local command="${1:-}"
            local candidate="${*: -1}"
            printf '%s\n' "$*" >> "$TIMER_LOG"
            case "$command" in
                list-unit-files)
                    if [[ "$candidate" == "$AVAILABLE_TIMER" ]]; then
                        printf '%s enabled\n' "$candidate"
                    fi
                    ;;
                is-enabled)
                    [[ "$candidate" == "$AVAILABLE_TIMER" ]]
                    ;;
                is-active)
                    [[ "$candidate" == "$AVAILABLE_TIMER" ]]
                    ;;
                enable)
                    [[ "$candidate" == "$AVAILABLE_TIMER" ]]
                    ;;
                *)
                    return 1
                    ;;
            esac
        }

        eval "$timer_block"
        assert_equal "$expected_timer" "$RENEWAL_TIMER" \
            "${label} renewal timer selection"
        assert_equal "$expected_timer" "$RENEWAL_SUMMARY" \
            "${label} renewal summary"
    ) || fail_test "${label} renewal timer block failed"

    assert_file_line "enable --now ${expected_timer}" "$timer_log"
    assert_file_line "is-enabled --quiet ${expected_timer}" "$timer_log"
    assert_file_line "is-active --quiet ${expected_timer}" "$timer_log"
    if [[ "$expected_timer" == "certbot.timer" ]]; then
        assert_no_file_line "enable --now certbot-renew.timer" "$timer_log"
    else
        assert_no_file_line "enable --now certbot.timer" "$timer_log"
    fi
}

run_timer_case ubuntu certbot.timer certbot.timer
run_timer_case centos-stream certbot-renew.timer certbot-renew.timer

domain_guard="$(awk '
    index($0, "if [[ \"${#DOMAINS[@]}\" -eq 0 ]]") { capture=1 }
    capture { print }
    capture && /^fi$/ { exit }
' "$CERTBOT_SCRIPT")"
[[ -n "$domain_guard" ]] \
    || fail_test "could not extract the no-domain guard"
grep -Fq 'exit 10' <<< "$domain_guard" \
    || fail_test "the no-domain guard no longer reports deferred HTTPS"
grep -Fq 'ensure_certbot_renewal_timer' <<< "$domain_guard" \
    || fail_test "the no-domain path no longer reconciles the renewal timer"

issuance_marker="${fixture_dir}/certificate-requested"
guard_rc=0
if (
    DOMAINS=()
    log() { :; }
    ensure_certbot_renewal_timer() { :; }
    eval "$domain_guard"
    printf 'requested\n' > "$issuance_marker"
); then
    fail_test "the no-domain path unexpectedly returned success"
else
    guard_rc=$?
fi
assert_equal "10" "$guard_rc" "no-domain deferred exit status"
[[ ! -e "$issuance_marker" ]] \
    || fail_test "the no-domain path continued into certificate issuance"

domain_guard_line="$(awk '
    index($0, "if [[ \"${#DOMAINS[@]}\" -eq 0 ]]") { print NR; exit }
' "$CERTBOT_SCRIPT")"
issuance_line="$(awk '
    index($0, "\"${CERTBOT_BIN}\" --nginx") { print NR; exit }
' "$CERTBOT_SCRIPT")"
[[ "$domain_guard_line" =~ ^[0-9]+$ && "$issuance_line" =~ ^[0-9]+$ ]] \
    || fail_test "could not locate no-domain and certificate issuance paths"
(( domain_guard_line < issuance_line )) \
    || fail_test "certificate issuance occurs before the no-domain guard"

grep -Fq -- '--non-interactive --redirect --reinstall' "$CERTBOT_SCRIPT" \
    || fail_test "existing certificate re-application is not deterministic"
for directory_field in newNonce newAccount newOrder; do
    grep -Fq "$directory_field" "$CERTBOT_SCRIPT" \
        || fail_test "ACME directory validation is missing ${directory_field}"
done
grep -Fq 'Recovery backup retained at' "$CERTBOT_SCRIPT" \
    || fail_test "IP TLS rollback can discard its only recovery backup"
grep -Fq 'CDSI_SITE_SCHEME=""' "$CERTBOT_SCRIPT" \
    || fail_test "IP HTTPS reruns do not preserve the existing WordPress scheme"

server_name_function="$(awk '
    /^_update_server_name\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "$CERTBOT_SCRIPT")"
[[ -n "$server_name_function" ]] \
    || fail_test "could not extract the Anchor Nginx server_name updater"
eval "$server_name_function"

site_dir="${fixture_dir}/nginx-sites"
mkdir -p "$site_dir"
anchor_site="${site_dir}/wordpress.conf"
unrelated_site="${site_dir}/unrelated.conf"
cat > "$anchor_site" <<'EOF'
# CDSI WordPress site block - managed by install-wordpress.sh
server { server_name _; }
EOF
cat > "$unrelated_site" <<'EOF'
server { server_name _; }
EOF
unrelated_before="$(sha256sum "$unrelated_site" | awk '{print $1}')"

(
    SUDO=""
    CDSI_NGINX_SITE_DIR="$site_dir"
    CDSI_NGINX_SERVICE="nginx"
    PRIMARY_DOMAIN="example.com"
    log() { :; }
    log_ok() { :; }
    fail() { printf 'FAIL: %s\n' "$*" >&2; exit 91; }
    nginx() { return 0; }
    cdsi_service_reload() { return 0; }
    _update_server_name
) || fail_test "Anchor-only server_name update failed"
grep -Fq 'server_name example.com;' "$anchor_site" \
    || fail_test "Anchor WordPress site was not updated"
assert_equal "$unrelated_before" "$(sha256sum "$unrelated_site" | awk '{print $1}')" \
    "Certbot must not modify an unrelated catch-all site"

cat > "$anchor_site" <<'EOF'
# CDSI WordPress site block - managed by install-wordpress.sh
server { server_name _; }
EOF
anchor_before="$(sha256sum "$anchor_site" | awk '{print $1}')"
if (
    SUDO=""
    CDSI_NGINX_SITE_DIR="$site_dir"
    CDSI_NGINX_SERVICE="nginx"
    PRIMARY_DOMAIN="example.com"
    nginx_calls=0
    log() { :; }
    log_ok() { :; }
    fail() { exit 91; }
    nginx() {
        ((nginx_calls += 1))
        ((nginx_calls > 1))
    }
    cdsi_service_reload() { return 0; }
    _update_server_name
); then
    fail_test "invalid staged Anchor Nginx configuration unexpectedly succeeded"
fi
assert_equal "$anchor_before" "$(sha256sum "$anchor_site" | awk '{print $1}')" \
    "failed Certbot Nginx validation must restore the Anchor site"

cat > "${site_dir}/example.com.conf" <<'EOF'
# Existing configuration owned by another application
server { server_name example.com; }
EOF
non_anchor_before="$(sha256sum "${site_dir}/example.com.conf" | awk '{print $1}')"
if (
    SUDO=""
    CDSI_NGINX_SITE_DIR="$site_dir"
    CDSI_NGINX_SERVICE="nginx"
    PRIMARY_DOMAIN="example.com"
    log() { :; }
    log_ok() { :; }
    fail() { exit 91; }
    nginx() { return 0; }
    cdsi_service_reload() { return 0; }
    _update_server_name
); then
    fail_test "non-Anchor domain configuration was accepted"
fi
assert_equal "$non_anchor_before" \
    "$(sha256sum "${site_dir}/example.com.conf" | awk '{print $1}')" \
    "non-Anchor domain configuration must remain unchanged"

printf 'PASS: Certbot EPEL, renewal, no-domain, and Anchor-only Nginx contracts\n'
