#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORDPRESS_SCRIPT="${TEST_ROOT}/scripts/common/install-wordpress.sh"
CHECKSUM_FILE="${TEST_ROOT}/SHA256SUMS"

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

extract_function() {
    local name="$1"
    awk -v signature="${name}() {" '
        $0 == signature { capture=1 }
        capture { print }
        capture && /^}$/ { exit }
    ' "$WORDPRESS_SCRIPT"
}

[[ -f "$WORDPRESS_SCRIPT" ]] \
    || fail_test "WordPress implementation not found: ${WORDPRESS_SCRIPT}"
bash -n "$WORDPRESS_SCRIPT" \
    || fail_test "WordPress implementation has invalid Bash syntax"
grep -Fq 'lib/zypper.sh' "$WORDPRESS_SCRIPT" \
    || fail_test "openSUSE WordPress path does not load the Zypper runtime"
grep -Fq 'cdsi_uses_selinux || return 0' "$WORDPRESS_SCRIPT" \
    || fail_test "WordPress SELinux integration is not shared by CentOS and openSUSE"
grep -Fq 'setsebool -P httpd_can_network_connect on' "$WORDPRESS_SCRIPT" \
    || fail_test "WordPress SELinux policy does not allow the required PHP-FPM and outbound network connections"
grep -Fq '/etc/cdsi/selinux-httpd-network-boolean' "$WORDPRESS_SCRIPT" \
    || fail_test "WordPress SELinux network policy is not recorded for scoped uninstall"
[[ "$(grep -Fc 'getsebool "$boolean_name"' "$WORDPRESS_SCRIPT")" -ge 2 ]] \
    || fail_test "WordPress SELinux network policy is not verified after reconciliation"
if grep -Fq 'setsebool -P httpd_can_network_connect_db on' "$WORDPRESS_SCRIPT"; then
    fail_test "WordPress must use the general web-network SELinux boolean, not the database-only boolean"
fi

expected_wp_package="wordpress-7.1-zh_CN.zip"
expected_wp_sha256="6bd9237178dd870f7b47cf33e7129219d9bd2a85a92be641cf487c2cd61a2dba"
actual_wp_package="$(sed -n 's/^WP_PACKAGE_NAME="\([^"]*\)"$/\1/p' "$WORDPRESS_SCRIPT")"
assert_equal "$expected_wp_package" "$actual_wp_package" \
    "WordPress package version"
grep -Fq '"http://cdn.aicsi.cn/packages/${WP_PACKAGE_NAME}"' "$WORDPRESS_SCRIPT" \
    || fail_test "WordPress CDN URL must use the configured package name"
grep -Fq '"https://cn.wordpress.org/${WP_PACKAGE_NAME}"' "$WORDPRESS_SCRIPT" \
    || fail_test "WordPress official fallback URL is missing"

checksum_entry_count="$(awk -v package="$expected_wp_package" \
    '$2 == package { count += 1 } END { print count + 0 }' "$CHECKSUM_FILE")"
assert_equal "1" "$checksum_entry_count" \
    "WordPress checksum entry count"
actual_wp_sha256="$(awk -v package="$expected_wp_package" \
    '$2 == package { print $1 }' "$CHECKSUM_FILE")"
assert_equal "$expected_wp_sha256" "$actual_wp_sha256" \
    "WordPress package SHA-256"
if grep -Fq 'wordpress-7.0.4-zh_CN.zip' "$WORDPRESS_SCRIPT" "$CHECKSUM_FILE"; then
    fail_test "obsolete WordPress 7.0.4 package reference remains"
fi

provision_php_function="$(extract_function provision_php)"
configure_nginx_function="$(extract_function configure_nginx)"
configure_selinux_function="$(extract_function configure_selinux)"
[[ -n "$provision_php_function" && -n "$configure_nginx_function" \
   && -n "$configure_selinux_function" ]] \
    || fail_test "could not extract WordPress PHP/Nginx/SELinux functions"
eval "$provision_php_function"
eval "$configure_nginx_function"

fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
php_log="${fixture_dir}/php.log"
: > "$php_log"

CDSI_ROOT="$TEST_ROOT"
PHP_FPM_VER=""
log() { :; }
log_ok() { :; }
fail() { fail_test "$*"; }
bash() {
    printf 'installer:%s\n' "$1" >> "$php_log"
}
install_wpcli() {
    printf 'wp-cli\n' >> "$php_log"
}
detect_php_fpm() {
    printf '8.3\n'
}
cdsi_php_service_name() {
    printf 'php-fpm\n'
}
cdsi_service_enable() {
    printf 'enable:%s\n' "$1" >> "$php_log"
}
cdsi_service_restart() {
    printf 'restart:%s\n' "$1" >> "$php_log"
}
cdsi_service_active() {
    [[ "$1" == "php-fpm" ]]
}
php() {
    [[ "${1:-}" == "-m" ]] || return 1
    printf 'mysqli\n'
}

provision_php
grep -Fqx "installer:${TEST_ROOT}/scripts/install-php.sh" "$php_log" \
    || fail_test "WordPress did not reconcile PHP through install-php.sh"
grep -Fqx 'enable:php-fpm' "$php_log" \
    || fail_test "WordPress did not enable PHP-FPM at boot"
grep -Fqx 'restart:php-fpm' "$php_log" \
    || fail_test "WordPress did not restart PHP-FPM after extension reconciliation"
assert_equal "8.3" "$PHP_FPM_VER" "WordPress PHP-FPM version"

site_dir="${fixture_dir}/nginx-sites"
mkdir -p "$site_dir"
site_file="${site_dir}/example.com.conf"

SUDO=""
CDSI_NGINX_SITE_DIR="$site_dir"
CDSI_NGINX_ENABLED_DIR="$site_dir"
CDSI_NGINX_SERVICE="nginx"
CDSI_IP_TLS_DIR="${fixture_dir}/nginx-tls"
WP_DOMAIN="example.com"
WP_DIR="${fixture_dir}/wordpress"
SERVER_IP=""
detect_php_fpm() { printf '8.3\n'; }
cdsi_php_fpm_upstream() { printf 'unix:/run/php-fpm/www.sock\n'; }
nginx() { return 0; }
cdsi_service_reload() { return 0; }

cat > "$site_file" <<'EOF'
# CDSI WordPress site block - managed by install-wordpress.sh
server {
    listen 80;
    server_name example.com;
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem; # managed by Certbot
}
EOF
tls_before="$(sha256sum "$site_file" | awk '{print $1}')"
configure_nginx
assert_equal "$tls_before" "$(sha256sum "$site_file" | awk '{print $1}')" \
    "WordPress rerun must preserve existing Certbot TLS configuration"

cat > "$site_file" <<'EOF'
# CDSI WordPress site block - managed by install-wordpress.sh
server {
    listen 80;
    server_name example.com;
    old_anchor_directive on;
}
EOF
http_before="$(sha256sum "$site_file" | awk '{print $1}')"
if (
    nginx_calls=0
    log() { :; }
    log_ok() { :; }
    fail() { exit 91; }
    nginx() {
        ((nginx_calls += 1))
        ((nginx_calls > 1))
    }
    cdsi_service_reload() { return 0; }
    configure_nginx
); then
    fail_test "invalid staged WordPress Nginx configuration unexpectedly succeeded"
fi
assert_equal "$http_before" "$(sha256sum "$site_file" | awk '{print $1}')" \
    "failed WordPress Nginx validation must restore the previous site"

cat > "$site_file" <<'EOF'
# Configuration owned by another application
server { server_name example.com; }
EOF
foreign_before="$(sha256sum "$site_file" | awk '{print $1}')"
if (
    log() { :; }
    log_ok() { :; }
    fail() { exit 91; }
    nginx() { return 0; }
    cdsi_service_reload() { return 0; }
    configure_nginx
); then
    fail_test "WordPress overwrote a non-Anchor Nginx site"
fi
assert_equal "$foreign_before" "$(sha256sum "$site_file" | awk '{print $1}')" \
    "non-Anchor WordPress site path must remain unchanged"

# IP-to-domain migration must remove the enabled symlink before its managed
# target. Otherwise the link becomes dangling, loses its ownership marker, and
# makes nginx -t fail even though both paths belonged to Anchor.
migration_root="${fixture_dir}/nginx-migration"
migration_available="${migration_root}/sites-available"
migration_enabled="${migration_root}/sites-enabled"
mkdir -p "$migration_available" "$migration_enabled"
cat > "${migration_available}/wordpress.conf" <<'EOF'
# CDSI WordPress site block - managed by install-wordpress.sh
server { server_name 192.0.2.10; }
EOF
ln -s "${migration_available}/wordpress.conf" \
    "${migration_enabled}/wordpress.conf"

CDSI_NGINX_SITE_DIR="$migration_available"
CDSI_NGINX_ENABLED_DIR="$migration_enabled"
WP_DOMAIN="example.com"
CDSI_DOMAIN="example.com"
unset CDSI_PREVIOUS_DOMAIN
nginx() {
    local enabled_site
    for enabled_site in "${CDSI_NGINX_ENABLED_DIR}"/*; do
        [[ ! -L "$enabled_site" || -e "$enabled_site" ]] || return 1
    done
    return 0
}
cdsi_service_reload() { return 0; }
configure_nginx

[[ -f "${migration_available}/example.com.conf" ]] \
    || fail_test "domain migration did not create the available site"
[[ -L "${migration_enabled}/example.com.conf" \
   && -e "${migration_enabled}/example.com.conf" ]] \
    || fail_test "domain migration did not create a valid enabled site link"
[[ ! -e "${migration_available}/wordpress.conf" \
   && ! -L "${migration_enabled}/wordpress.conf" ]] \
    || fail_test "domain migration retained the legacy IP-mode site"

WP_DOMAIN="next.example.com"
CDSI_DOMAIN="next.example.com"
CDSI_PREVIOUS_DOMAIN="example.com"
configure_nginx
[[ -f "${migration_available}/next.example.com.conf" \
   && -L "${migration_enabled}/next.example.com.conf" \
   && -e "${migration_enabled}/next.example.com.conf" ]] \
    || fail_test "domain-to-domain migration did not create a valid new site"
[[ ! -e "${migration_available}/example.com.conf" \
   && ! -L "${migration_enabled}/example.com.conf" ]] \
    || fail_test "domain-to-domain migration retained the previous site"

WP_DOMAIN=""
CDSI_DOMAIN=""
SERVER_IP="192.0.2.10"
CDSI_PREVIOUS_DOMAIN="next.example.com"
configure_nginx
[[ -f "${migration_available}/wordpress.conf" \
   && -L "${migration_enabled}/wordpress.conf" \
   && -e "${migration_enabled}/wordpress.conf" ]] \
    || fail_test "domain-to-IP migration did not create a valid IP-mode site"
[[ ! -e "${migration_available}/next.example.com.conf" \
   && ! -L "${migration_enabled}/next.example.com.conf" ]] \
    || fail_test "domain-to-IP migration retained the previous domain site"

ip_site_before="$(sha256sum "${migration_available}/wordpress.conf" | awk '{print $1}')"
ip_link_before="$(readlink "${migration_enabled}/wordpress.conf")"
if (
    WP_DOMAIN="broken.example.com"
    CDSI_DOMAIN="broken.example.com"
    CDSI_PREVIOUS_DOMAIN=""
    nginx_calls=0
    fail() { exit 91; }
    nginx() {
        ((nginx_calls += 1))
        ((nginx_calls > 1))
    }
    cdsi_service_reload() { return 0; }
    configure_nginx
); then
    fail_test "invalid IP-to-domain migration unexpectedly succeeded"
fi
assert_equal "$ip_site_before" \
    "$(sha256sum "${migration_available}/wordpress.conf" | awk '{print $1}')" \
    "failed migration must restore the IP-mode site file"
assert_equal "$ip_link_before" \
    "$(readlink "${migration_enabled}/wordpress.conf")" \
    "failed migration must restore the IP-mode enabled link"
[[ -e "${migration_enabled}/wordpress.conf" ]] \
    || fail_test "failed migration restored a dangling IP-mode link"
[[ ! -e "${migration_available}/broken.example.com.conf" \
   && ! -L "${migration_enabled}/broken.example.com.conf" ]] \
    || fail_test "failed migration retained the staged domain site"

# Exercise SELinux reconciliation without touching the host. Each case rewrites
# Anchor's marker directory into the disposable fixture and supplies command
# shims for the policy state transitions owned by configure_selinux().
if ! (
    eval "$configure_selinux_function"
    cdsi_uses_selinux() { return 1; }
    getenforce() { fail_test "disabled SELinux path inspected enforcement"; }
    configure_selinux
); then
    fail_test "disabled SELinux path should be a no-op"
fi

selinux_success_root="${fixture_dir}/selinux-success"
selinux_success_function="$(printf '%s\n' "$configure_selinux_function" \
    | sed "s|/etc/cdsi|${selinux_success_root}/state|g")"
mkdir -p "${selinux_success_root}/wordpress"
if ! (
    eval "$selinux_success_function"
    SUDO=""
    WP_DIR="${selinux_success_root}/wordpress"
    action_log="${selinux_success_root}/actions.log"
    rule_state="${selinux_success_root}/rule"
    boolean_state_file="${selinux_success_root}/boolean"
    printf 'off\n' > "$boolean_state_file"
    : > "$action_log"

    cdsi_uses_selinux() { return 0; }
    getenforce() { printf 'Enforcing\n'; }
    cdsi_packages_install() { fail_test "SELinux tools were already mocked"; }
    semanage() {
        printf 'semanage:%s\n' "$*" >> "$action_log"
        case "${1:-}:${2:-}" in
            fcontext:-a)
                [[ ! -e "$rule_state" ]] || return 1
                printf '%s\n' "${WP_DIR}(/.*)?" > "$rule_state"
                ;;
            fcontext:-l)
                [[ -e "$rule_state" ]] \
                    && printf '%s all files system_u:object_r:httpd_sys_rw_content_t:s0\n' \
                        "$(< "$rule_state")"
                ;;
            fcontext:-d)
                rm -f -- "$rule_state"
                ;;
            *) return 1 ;;
        esac
    }
    restorecon() { printf 'restorecon:%s\n' "$*" >> "$action_log"; }
    getsebool() {
        printf 'getsebool:%s\n' "$*" >> "$action_log"
        printf 'httpd_can_network_connect --> %s\n' "$(< "$boolean_state_file")"
    }
    setsebool() {
        printf 'setsebool:%s\n' "$*" >> "$action_log"
        printf '%s\n' "${3:-}" > "$boolean_state_file"
    }

    configure_selinux
    configure_selinux
); then
    fail_test "SELinux first-run/idempotency reconciliation failed"
fi
assert_equal "${selinux_success_root}/wordpress(/.*)?" \
    "$(< "${selinux_success_root}/state/selinux-wordpress-fcontext")" \
    "SELinux file-context ownership marker"
assert_equal "httpd_can_network_connect" \
    "$(< "${selinux_success_root}/state/selinux-httpd-network-boolean")" \
    "SELinux network-boolean ownership marker"
assert_equal "1" \
    "$(grep -Fc 'setsebool:-P httpd_can_network_connect on' \
        "${selinux_success_root}/actions.log")" \
    "SELinux idempotent boolean enable count"
assert_equal "4" \
    "$(grep -Fc 'getsebool:httpd_can_network_connect' \
        "${selinux_success_root}/actions.log")" \
    "SELinux initial and final boolean verification count"

selinux_conflict_root="${fixture_dir}/selinux-conflict"
selinux_conflict_function="$(printf '%s\n' "$configure_selinux_function" \
    | sed "s|/etc/cdsi|${selinux_conflict_root}/state|g")"
mkdir -p "${selinux_conflict_root}/wordpress"
if (
    eval "$selinux_conflict_function"
    SUDO=""
    WP_DIR="${selinux_conflict_root}/wordpress"
    action_log="${selinux_conflict_root}/actions.log"
    : > "$action_log"
    fail() { exit 91; }
    cdsi_uses_selinux() { return 0; }
    getenforce() { printf 'Enforcing\n'; }
    semanage() {
        printf 'semanage:%s\n' "$*" >> "$action_log"
        if [[ "${1:-}:${2:-}" == "fcontext:-l" ]]; then
            printf '%s all files system_u:object_r:var_t:s0\n' "${WP_DIR}(/.*)?"
        else
            return 1
        fi
    }
    restorecon() { printf 'restorecon\n' >> "$action_log"; }
    getsebool() { printf 'httpd_can_network_connect --> on\n'; }
    setsebool() { printf 'setsebool\n' >> "$action_log"; }
    configure_selinux
); then
    fail_test "incompatible SELinux file-context rule unexpectedly succeeded"
fi
if grep -Eq '^(restorecon|setsebool)$' "${selinux_conflict_root}/actions.log"; then
    fail_test "SELinux conflict path changed policy after detecting an incompatible rule"
fi

selinux_rollback_root="${fixture_dir}/selinux-rollback"
selinux_rollback_function="$(printf '%s\n' "$configure_selinux_function" \
    | sed "s|/etc/cdsi|${selinux_rollback_root}/state|g")"
mkdir -p "${selinux_rollback_root}/wordpress"
if (
    eval "$selinux_rollback_function"
    SUDO=""
    WP_DIR="${selinux_rollback_root}/wordpress"
    action_log="${selinux_rollback_root}/actions.log"
    rule_state="${selinux_rollback_root}/rule"
    boolean_state_file="${selinux_rollback_root}/boolean"
    printf 'off\n' > "$boolean_state_file"
    : > "$action_log"
    fail() { exit 91; }
    cdsi_uses_selinux() { return 0; }
    getenforce() { printf 'Enforcing\n'; }
    semanage() {
        case "${1:-}:${2:-}" in
            fcontext:-a) printf '%s\n' "${WP_DIR}(/.*)?" > "$rule_state" ;;
            fcontext:-l)
                printf '%s all files system_u:object_r:httpd_sys_rw_content_t:s0\n' \
                    "$(< "$rule_state")"
                ;;
            fcontext:-d) rm -f -- "$rule_state" ;;
            *) return 1 ;;
        esac
    }
    restorecon() { return 0; }
    getsebool() {
        printf 'httpd_can_network_connect --> %s\n' "$(< "$boolean_state_file")"
    }
    setsebool() {
        printf 'setsebool:%s\n' "$*" >> "$action_log"
        printf '%s\n' "${3:-}" > "$boolean_state_file"
    }
    tee() {
        local target="${*: -1}"
        if [[ "$target" == *selinux-httpd-network-boolean ]]; then
            return 1
        fi
        command tee "$@"
    }
    configure_selinux
); then
    fail_test "SELinux boolean marker write failure unexpectedly succeeded"
fi
assert_equal "off" "$(< "${selinux_rollback_root}/boolean")" \
    "SELinux boolean rollback state"
grep -Fqx 'setsebool:-P httpd_can_network_connect on' \
    "${selinux_rollback_root}/actions.log" \
    || fail_test "SELinux rollback case did not first enable the network boolean"
grep -Fqx 'setsebool:-P httpd_can_network_connect off' \
    "${selinux_rollback_root}/actions.log" \
    || fail_test "SELinux rollback case did not restore the network boolean"
[[ ! -e "${selinux_rollback_root}/state/selinux-httpd-network-boolean" ]] \
    || fail_test "failed SELinux boolean marker was retained"

printf 'PASS: WordPress PHP, SELinux, and transactional Nginx configuration\n'
