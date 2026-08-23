#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Allow the script to be sourced from non-root developer shells.
sudo() { "$@"; }

# shellcheck source=../uninstall.sh
source "${TEST_ROOT}/uninstall.sh"

mysql_log="$(mktemp)"
nginx_fixture="$(mktemp)"
centos_action_log="$(mktemp)"
centos_fixture_dir="$(mktemp -d)"
trap 'rm -f "$mysql_log" "$nginx_fixture" "$centos_action_log"; rm -rf "$centos_fixture_dir"' EXIT
mysql() {
    printf 'mysql called\n' >> "$mysql_log"
    [[ "${mysql_should_fail:-false}" != true ]]
}

DRY_RUN=true
dry_output="$(drop_cdsi_database)"
if [[ -s "$mysql_log" ]]; then
    printf 'FAIL: dry-run called mysql\n' >&2
    exit 1
fi
if [[ "$dry_output" != *"将删除 MySQL 数据库 cdsi"* ]]; then
    printf 'FAIL: dry-run did not describe the database deletion\n' >&2
    exit 1
fi

DRY_RUN=false
drop_cdsi_database
if [[ "$(wc -l < "$mysql_log" | tr -d '[:space:]')" != "2" ]]; then
    printf 'FAIL: normal mode should check and then delete through mysql\n' >&2
    exit 1
fi

: > "$mysql_log"
mysql_should_fail=true
if drop_cdsi_database 2>/dev/null; then
    printf 'FAIL: authentication failure should be reported\n' >&2
    exit 1
fi
if [[ "$(wc -l < "$mysql_log" | tr -d '[:space:]')" != "1" ]]; then
    printf 'FAIL: authentication failure should stop before DROP DATABASE\n' >&2
    exit 1
fi

cat > "$nginx_fixture" <<'EOF'
server {
    listen 80;
    server_name example.com;

    if ($host = example.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    if ($scheme != "https") {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem; # managed by Certbot

    if ($host = custom.example.com) {
        return 301 https://$host$request_uri;
    } # custom redirect

    if ($scheme != "https") {
        return 301 https://$host$request_uri;
    } # custom scheme redirect
}
EOF

_certbot_strip_nginx_file "$nginx_fixture"
if grep -qE 'managed by Certbot|if \(\$host = example\.com|listen 443|ssl_certificate' \
    "$nginx_fixture"; then
    printf 'FAIL: Certbot directives remain in the Nginx fixture\n' >&2
    exit 1
fi
if ! grep -q 'listen 80;' "$nginx_fixture"; then
    printf 'FAIL: non-Certbot Nginx directives were removed\n' >&2
    exit 1
fi
if [[ "$(grep -Fc 'if ($host = custom.example.com) {' "$nginx_fixture")" != "1" \
   || "$(grep -Fc 'if ($scheme != "https") {' "$nginx_fixture")" != "1" \
   || "$(grep -Fc 'return 301 https://$host$request_uri;' "$nginx_fixture")" != "2" \
   || "$(grep -Fc '} # custom redirect' "$nginx_fixture")" != "1" \
   || "$(grep -Fc '} # custom scheme redirect' "$nginx_fixture")" != "1" ]]; then
    printf 'FAIL: custom Nginx redirect blocks were not preserved exactly once\n' >&2
    exit 1
fi

missing_domain="${nginx_fixture}.missing-domain"
if [[ -n "$(read_anchor_domain "$missing_domain")" ]]; then
    printf 'FAIL: a missing domain file should resolve to an empty value\n' >&2
    exit 1
fi

php() { return 127; }
function dpkg-query { return 1; }

if [[ -n "$(detect_installed_php_version)" ]]; then
    printf 'FAIL: missing PHP packages should resolve to an empty version\n' >&2
    exit 1
fi

DRY_RUN=true
uninstall_nginx >/dev/null \
    || { printf 'FAIL: IP-mode Nginx dry-run aborted\n' >&2; exit 1; }
uninstall_wordpress >/dev/null \
    || { printf 'FAIL: IP-mode WordPress dry-run aborted\n' >&2; exit 1; }
uninstall_php >/dev/null \
    || { printf 'FAIL: missing-PHP dry-run aborted\n' >&2; exit 1; }

record_centos_action() {
    printf '%s\n' "$*" >> "$centos_action_log"
}

assert_centos_action() {
    local expected="$1"
    grep -Fqx -- "$expected" "$centos_action_log" \
        || { printf 'FAIL: expected CentOS action was not called: %s\n' "$expected" >&2; exit 1; }
}

assert_no_centos_action() {
    local unexpected="$1"
    if grep -Fqx -- "$unexpected" "$centos_action_log"; then
        printf 'FAIL: unexpected CentOS action was called: %s\n' "$unexpected" >&2
        exit 1
    fi
}

assert_no_destructive_action() {
    if [[ -s "$centos_action_log" ]]; then
        printf 'FAIL: dry-run called destructive commands:\n' >&2
        sed 's/^/  /' "$centos_action_log" >&2
        exit 1
    fi
}

set_centos_fixture() {
    CDSI_PLATFORM_INITIALIZED=1
    CDSI_PLATFORM="centos-stream"
    CDSI_OS_VERSION="10"
    CDSI_OS_PRETTY="CentOS Stream 10"
    CDSI_PACKAGE_BACKEND="dnf"
    CDSI_SERVICE_BACKEND="systemd"
    CDSI_NGINX_SERVICE="nginx"
    CDSI_NGINX_SITE_DIR="/etc/nginx/conf.d"
    CDSI_NGINX_ENABLED_DIR="/etc/nginx/conf.d"
    CDSI_DB_PACKAGE="mysql8.4-server"
    CDSI_DB_SERVICE="mysqld"
    CDSI_DB_FLAVOR="mysql"
    CDSI_MYSQL_PACKAGE="$CDSI_DB_PACKAGE"
    CDSI_MYSQL_SERVICE="$CDSI_DB_SERVICE"
    CDSI_MYSQL_FLAVOR="$CDSI_DB_FLAVOR"
}

set_debian_fixture() {
    CDSI_PLATFORM_INITIALIZED=1
    CDSI_PLATFORM="debian"
    CDSI_OS_VERSION="13"
    CDSI_OS_PRETTY="Debian GNU/Linux 13"
    CDSI_PACKAGE_BACKEND="apt"
    CDSI_SERVICE_BACKEND="systemd"
    CDSI_NGINX_SERVICE="nginx"
    CDSI_NGINX_SITE_DIR="/etc/nginx/sites-available"
    CDSI_NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
    CDSI_DB_PACKAGE="mariadb-server"
    CDSI_DB_SERVICE="mariadb"
    CDSI_DB_FLAVOR="mariadb"
    CDSI_MYSQL_PACKAGE="$CDSI_DB_PACKAGE"
    CDSI_MYSQL_SERVICE="$CDSI_DB_SERVICE"
    CDSI_MYSQL_FLAVOR="$CDSI_DB_FLAVOR"
}

set_centos_fixture
SUDO=()

# DNF removal must receive only installed RPM names matching the requested
# package glob, as an argument array rather than an unexpanded wildcard.
rpm() {
    printf '%s\n' \
        mysql8.4-server \
        mysql8.4-libs \
        mysql-community-server \
        nginx \
        unrelated
}
cdsi_packages_remove() {
    record_centos_action "packages-remove:$*"
}

: > "$centos_action_log"
DRY_RUN=false
purge_glob 'mysql8.4*' >/dev/null
assert_centos_action "packages-remove:mysql8.4-server mysql8.4-libs"
assert_no_centos_action "packages-remove:mysql-community-server"

# Package dry-runs may inspect installed RPMs, but must not invoke removal or
# autoremove commands.
: > "$centos_action_log"
DRY_RUN=true
purge_glob 'mysql8.4*' >/dev/null
cdsi_packages_autoremove() {
    record_centos_action "packages-autoremove"
}
autoremove >/dev/null
assert_no_destructive_action

# The CentOS database uninstaller must use the MySQL 8.4 package family and
# mysqld service. It must not fall back to Ubuntu package/service mappings.
drop_cdsi_database() {
    record_centos_action "drop-database"
}
stop_disable_svc() {
    record_centos_action "stop-disable:$1"
}
purge_glob() {
    record_centos_action "purge-glob:$1"
}
do_rm() {
    record_centos_action "remove-path:$1"
}

: > "$centos_action_log"
DRY_RUN=false
uninstall_mysql >/dev/null
assert_centos_action "drop-database"
assert_centos_action "stop-disable:mysqld"
assert_centos_action "purge-glob:mysql8.4*"
assert_centos_action "remove-path:/etc/my.cnf.d/zz-cdsi-anchor.cnf"
assert_centos_action "remove-path:/var/lib/mysql"
assert_no_centos_action "stop-disable:mysql"
assert_no_centos_action "purge-glob:mysql-server*"
assert_no_centos_action "remove-path:/etc/my.cnf"
assert_no_centos_action "remove-path:/etc/my.cnf.d"
centos_mysql_summary="$(comp_what mysql)"
if [[ "$centos_mysql_summary" != *"/etc/my.cnf.d/zz-cdsi-anchor.cnf"* ]]; then
    printf 'FAIL: CentOS MySQL confirmation omits the Anchor-owned config file\n' >&2
    exit 1
fi

# Redis and Supervisor are intentionally Ubuntu-only compatibility scripts;
# Debian/CentOS uninstall must not stop services, remove packages, or delete paths.
set_debian_fixture
: > "$centos_action_log"
uninstall_mysql >/dev/null
assert_centos_action "drop-database"
assert_centos_action "stop-disable:mariadb"
assert_centos_action "purge-glob:default-mysql-server*"
assert_centos_action "purge-glob:mariadb-server*"
assert_centos_action "purge-glob:mariadb-client*"
assert_centos_action "purge-glob:mariadb-common"
assert_centos_action "remove-path:/etc/mysql/mariadb.conf.d/99-cdsi-anchor.cnf"
assert_centos_action "remove-path:/var/lib/mysql"
assert_no_centos_action "remove-path:/etc/mysql"
assert_no_centos_action "purge-glob:mysql8.4*"
debian_mysql_summary="$(comp_what mysql)"
if [[ "$debian_mysql_summary" != *"/etc/mysql/mariadb.conf.d/99-cdsi-anchor.cnf"* ]]; then
    printf 'FAIL: Debian MariaDB confirmation omits the Anchor-owned config file\n' >&2
    exit 1
fi

: > "$centos_action_log"
uninstall_redis >/dev/null 2>&1
uninstall_supervisor >/dev/null 2>&1
assert_no_destructive_action
set_centos_fixture

# Rebind only the hard-coded marker paths to disposable fixtures. The function
# bodies under test remain the uninstaller's implementations.
firewall_marker="${centos_fixture_dir}/firewall-added-services"
selinux_fcontext_marker="${centos_fixture_dir}/selinux-wordpress-fcontext"
selinux_boolean_marker="${centos_fixture_dir}/selinux-httpd-db-boolean"
epel_marker="${centos_fixture_dir}/epel-added"

# shellcheck disable=SC1090
source <(declare -f remove_anchor_firewall_services \
    | sed "s|/etc/cdsi/firewall-added-services|${firewall_marker}|g")
# shellcheck disable=SC1090
source <(declare -f remove_anchor_selinux_state \
    | sed \
        -e "s|/etc/cdsi/selinux-wordpress-fcontext|${selinux_fcontext_marker}|g" \
        -e "s|/etc/cdsi/selinux-httpd-db-boolean|${selinux_boolean_marker}|g")
# shellcheck disable=SC1090
source <(declare -f remove_anchor_epel \
    | sed "s|/etc/cdsi/epel-added|${epel_marker}|g")

systemctl() {
    [[ "$*" == "is-active --quiet firewalld" ]]
}
firewall_runtime_remove_should_fail=false
firewall-cmd() {
    record_centos_action "firewall-cmd:$*"
    if [[ "$firewall_runtime_remove_should_fail" == true \
       && "$*" == "--remove-service=http" ]]; then
        return 1
    fi
}
semanage() {
    record_centos_action "semanage:$*"
}
setsebool() {
    record_centos_action "setsebool:$*"
}
cdsi_package_installed() {
    [[ "$1" == "epel-release" ]]
}
cdsi_packages_remove() {
    record_centos_action "packages-remove:$*"
}

# No marker means no host-security or repository state may be changed.
rm -f "$firewall_marker" "$selinux_fcontext_marker" \
    "$selinux_boolean_marker" "$epel_marker"
: > "$centos_action_log"
DRY_RUN=false
remove_anchor_firewall_services
remove_anchor_selinux_state
remove_anchor_epel
assert_no_destructive_action

# Marker contents are root-owned in production. A sudo-capable non-root run
# must read them through the privileged command wrapper, not shell redirection.
sudo() {
    record_centos_action "sudo:$*"
    "$@"
}
printf 'epel-release\n' > "$epel_marker"
: > "$centos_action_log"
DRY_RUN=true
SUDO=(sudo)
remove_anchor_epel >/dev/null
assert_centos_action "sudo:cat -- ${epel_marker}"
[[ -f "$epel_marker" ]] \
    || { printf 'FAIL: privileged marker dry-run consumed the marker\n' >&2; exit 1; }
SUDO=()
rm -f "$epel_marker"

# Invalid marker contents must be rejected without changing global host state,
# and the marker must remain available for manual recovery.
printf 'permanent:http\nssh\n' > "$firewall_marker"
printf 'invalid-pattern\n' > "$selinux_fcontext_marker"
printf 'unexpected-package\n' > "$epel_marker"
: > "$centos_action_log"
DRY_RUN=false
if remove_anchor_firewall_services >/dev/null 2>&1; then
    printf 'FAIL: invalid firewalld marker was accepted\n' >&2
    exit 1
fi
if remove_anchor_selinux_state >/dev/null 2>&1; then
    printf 'FAIL: invalid SELinux fcontext marker was accepted\n' >&2
    exit 1
fi
if remove_anchor_epel >/dev/null 2>&1; then
    printf 'FAIL: invalid EPEL marker was accepted\n' >&2
    exit 1
fi
assert_no_destructive_action
for marker in "$firewall_marker" "$selinux_fcontext_marker" "$epel_marker"; do
    [[ -f "$marker" ]] \
        || { printf 'FAIL: invalid marker was consumed: %s\n' "$marker" >&2; exit 1; }
done
rm -f "$firewall_marker" "$selinux_fcontext_marker" "$epel_marker"

printf 'unexpected_boolean\n' > "$selinux_boolean_marker"
: > "$centos_action_log"
if remove_anchor_selinux_state >/dev/null 2>&1; then
    printf 'FAIL: invalid SELinux boolean marker was accepted\n' >&2
    exit 1
fi
assert_no_destructive_action
[[ -f "$selinux_boolean_marker" ]] \
    || { printf 'FAIL: invalid SELinux boolean marker was consumed\n' >&2; exit 1; }
rm -f "$selinux_boolean_marker"

# Marker-backed dry-runs describe work but never invoke destructive commands
# and never consume the provenance markers.
printf 'permanent:http\nruntime:https\n' > "$firewall_marker"
printf '/var/www/wordpress(/.*)?\n' > "$selinux_fcontext_marker"
printf 'httpd_can_network_connect_db\n' > "$selinux_boolean_marker"
printf 'epel-release\n' > "$epel_marker"
: > "$centos_action_log"
DRY_RUN=true
remove_anchor_firewall_services >/dev/null
remove_anchor_selinux_state >/dev/null
remove_anchor_epel >/dev/null
assert_no_destructive_action
for marker in "$firewall_marker" "$selinux_fcontext_marker" \
    "$selinux_boolean_marker" "$epel_marker"; do
    [[ -f "$marker" ]] \
        || { printf 'FAIL: dry-run consumed marker: %s\n' "$marker" >&2; exit 1; }
done

# A runtime firewalld removal failure must leave the permanent layer untouched
# and keep the marker, so a later rerun can finish only that recorded rollback.
printf 'runtime:http\n' > "$firewall_marker"
: > "$centos_action_log"
DRY_RUN=false
firewall_runtime_remove_should_fail=true
if remove_anchor_firewall_services >/dev/null 2>&1; then
    printf 'FAIL: firewalld runtime removal failure was reported as success\n' >&2
    exit 1
fi
firewall_runtime_remove_should_fail=false
assert_centos_action "firewall-cmd:--query-service=http"
assert_centos_action "firewall-cmd:--remove-service=http"
assert_no_centos_action "firewall-cmd:--permanent --query-service=http"
assert_no_centos_action "firewall-cmd:--permanent --remove-service=http"
assert_no_centos_action "firewall-cmd:--permanent --add-service=http"
[[ -f "$firewall_marker" ]] \
    || { printf 'FAIL: failed firewalld rollback consumed its marker\n' >&2; exit 1; }

# Clear the retained failure fixture before the successful all-marker rollback.
: > "$centos_action_log"
remove_anchor_firewall_services

# Normal rollback consumes only marker-backed state and invokes the exact
# firewalld, SELinux, and EPEL operations represented by those markers.
printf 'permanent:http\nruntime:http\npermanent:https\nruntime:https\n' > "$firewall_marker"
: > "$centos_action_log"
DRY_RUN=false
remove_anchor_firewall_services
remove_anchor_selinux_state
remove_anchor_epel
assert_centos_action "firewall-cmd:--permanent --query-service=http"
assert_centos_action "firewall-cmd:--permanent --remove-service=http"
assert_centos_action "firewall-cmd:--query-service=http"
assert_centos_action "firewall-cmd:--remove-service=http"
assert_centos_action "firewall-cmd:--permanent --query-service=https"
assert_centos_action "firewall-cmd:--permanent --remove-service=https"
assert_centos_action "firewall-cmd:--query-service=https"
assert_centos_action "firewall-cmd:--remove-service=https"
assert_centos_action "semanage:fcontext -d /var/www/wordpress(/.*)?"
assert_centos_action "setsebool:-P httpd_can_network_connect_db off"
assert_centos_action "packages-remove:epel-release"
for marker in "$firewall_marker" "$selinux_fcontext_marker" \
    "$selinux_boolean_marker" "$epel_marker"; do
    [[ ! -e "$marker" ]] \
        || { printf 'FAIL: successful rollback retained marker: %s\n' "$marker" >&2; exit 1; }
done

printf 'PASS: Ubuntu/Debian/CentOS uninstall guards, scoped config cleanup, dry-run, and marker rollback\n'
