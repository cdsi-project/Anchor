#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORDPRESS_SCRIPT="${TEST_ROOT}/scripts/common/install-wordpress.sh"

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

provision_php_function="$(extract_function provision_php)"
configure_nginx_function="$(extract_function configure_nginx)"
[[ -n "$provision_php_function" && -n "$configure_nginx_function" ]] \
    || fail_test "could not extract WordPress PHP/Nginx functions"
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

printf 'PASS: WordPress PHP reconciliation and transactional Nginx configuration\n'
