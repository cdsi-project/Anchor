#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MYSQL_INSTALLER="${TEST_ROOT}/scripts/common/install-mysql.sh"

# shellcheck source=../lib/platform.sh
source "${TEST_ROOT}/lib/platform.sh"

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

assert_contains() {
    local pattern="$1"
    local message="$2"
    grep -Fq -- "$pattern" "$MYSQL_INSTALLER" || fail_test "$message"
}

assert_count() {
    local expected="$1"
    local pattern="$2"
    local message="$3"
    local actual
    actual="$(grep -Fc -- "$pattern" "$MYSQL_INSTALLER" || true)"
    assert_equal "$expected" "$actual" "$message"
}

assert_before() {
    local first_pattern="$1"
    local second_pattern="$2"
    local message="$3"
    local first_line second_line
    first_line="$(grep -nF -- "$first_pattern" "$MYSQL_INSTALLER" \
        | head -1 | cut -d: -f1)"
    second_line="$(grep -nF -- "$second_pattern" "$MYSQL_INSTALLER" \
        | head -1 | cut -d: -f1)"
    [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] \
        || fail_test "$message"
}

mock_kernel="Linux"
mock_arch="x86_64"
mock_os_id="ubuntu"
mock_os_version="24.04"
mock_os_name="Ubuntu"
mock_os_pretty="Ubuntu 24.04 LTS"

uname() {
    case "${1:-}" in
        -s) printf '%s\n' "$mock_kernel" ;;
        -m) printf '%s\n' "$mock_arch" ;;
        *) printf '%s\n' "$mock_kernel" ;;
    esac
}

awk() {
    if [[ "$*" == *"/^ID=/"* ]]; then
        printf '%s\n' "$mock_os_id"
    elif [[ "$*" == *"/^VERSION_ID=/"* ]]; then
        printf '%s\n' "$mock_os_version"
    elif [[ "$*" == *"/^NAME=/"* ]]; then
        printf '%s\n' "$mock_os_name"
    elif [[ "$*" == *"/^PRETTY_NAME=/"* ]]; then
        printf '%s\n' "$mock_os_pretty"
    else
        fail_test "unexpected awk invocation: $*"
    fi
}

reset_platform() {
    unset CDSI_PLATFORM_INITIALIZED CDSI_PLATFORM CDSI_OS_VERSION \
        CDSI_OS_PRETTY CDSI_ARCH CDSI_PACKAGE_BACKEND CDSI_SERVICE_BACKEND \
        CDSI_WEB_USER CDSI_WEB_GROUP CDSI_NGINX_SERVICE \
        CDSI_NGINX_CONF_DIR CDSI_NGINX_MAIN_CONF CDSI_NGINX_SITE_DIR \
        CDSI_NGINX_ENABLED_DIR CDSI_NGINX_LOG_DIR \
        CDSI_DB_PACKAGE CDSI_DB_SERVICE CDSI_DB_FLAVOR \
        CDSI_DB_CLIENT CDSI_DB_ADMIN_CLIENT CDSI_DB_ANCHOR_CONFIG \
        CDSI_MYSQL_PACKAGE CDSI_MYSQL_SERVICE CDSI_MYSQL_FLAVOR \
        CDSI_CERTBOT_CONFIG_DIR CDSI_PHP_VERSION CDSI_PHP_PACKAGE_PREFIX \
        CDSI_PHP_BIN CDSI_PHP_FPM_BIN CDSI_PHP_FPM_SERVICE \
        CDSI_PHP_FPM_UPSTREAM CDSI_PLATFORM_ROUTE 2>/dev/null || true
}

init_platform_fixture() {
    mock_os_id="$1"
    mock_os_version="$2"
    mock_os_name="$3"
    mock_os_pretty="$4"
    reset_platform
    cdsi_platform_init
}

init_platform_fixture ubuntu 24.04 Ubuntu "Ubuntu 24.04 LTS"
assert_equal "ubuntu" "$CDSI_PLATFORM" "Ubuntu platform"
assert_equal "apt" "$CDSI_PACKAGE_BACKEND" "Ubuntu package backend"
assert_equal "mysql-server" "$CDSI_DB_PACKAGE" "Ubuntu database package"
assert_equal "mysql" "$CDSI_DB_SERVICE" "Ubuntu database service"
assert_equal "mysql" "$CDSI_DB_FLAVOR" "Ubuntu database flavor"
assert_equal "mysql" "$CDSI_DB_CLIENT" "Ubuntu database client"
assert_equal "mysqladmin" "$CDSI_DB_ADMIN_CLIENT" \
    "Ubuntu database admin client"
assert_equal "$CDSI_DB_PACKAGE" "$CDSI_MYSQL_PACKAGE" \
    "Ubuntu package compatibility alias"
assert_equal "$CDSI_DB_SERVICE" "$CDSI_MYSQL_SERVICE" \
    "Ubuntu service compatibility alias"

init_platform_fixture debian 13 "Debian GNU/Linux" "Debian GNU/Linux 13"
assert_equal "debian" "$CDSI_PLATFORM" "Debian platform"
assert_equal "apt" "$CDSI_PACKAGE_BACKEND" "Debian package backend"
assert_equal "mariadb-server" "$CDSI_DB_PACKAGE" \
    "Debian MariaDB package"
assert_equal "mariadb" "$CDSI_DB_SERVICE" "Debian MariaDB service"
assert_equal "mariadb" "$CDSI_DB_FLAVOR" "Debian database flavor"
assert_equal "mysql" "$CDSI_DB_CLIENT" "Debian database client"
assert_equal "mysqladmin" "$CDSI_DB_ADMIN_CLIENT" \
    "Debian database admin client"
assert_equal "$CDSI_DB_PACKAGE" "$CDSI_MYSQL_PACKAGE" \
    "Debian package compatibility alias"
assert_equal "$CDSI_DB_SERVICE" "$CDSI_MYSQL_SERVICE" \
    "Debian service compatibility alias"

init_platform_fixture centos 10 "CentOS Stream" "CentOS Stream 10"
assert_equal "centos-stream" "$CDSI_PLATFORM" "CentOS Stream platform"
assert_equal "dnf" "$CDSI_PACKAGE_BACKEND" "CentOS package backend"
assert_equal "mysql8.4-server" "$CDSI_DB_PACKAGE" \
    "CentOS MySQL 8.4 package"
assert_equal "mysqld" "$CDSI_DB_SERVICE" "CentOS MySQL service"
assert_equal "mysql" "$CDSI_DB_FLAVOR" "CentOS database flavor"
assert_equal "mysql" "$CDSI_DB_CLIENT" "CentOS database client"
assert_equal "mysqladmin" "$CDSI_DB_ADMIN_CLIENT" \
    "CentOS database admin client"
assert_equal "$CDSI_DB_PACKAGE" "$CDSI_MYSQL_PACKAGE" \
    "CentOS package compatibility alias"
assert_equal "$CDSI_DB_SERVICE" "$CDSI_MYSQL_SERVICE" \
    "CentOS service compatibility alias"

init_platform_fixture opensuse-leap 16.0 "openSUSE Leap" \
    "openSUSE Leap 16.0"
assert_equal "opensuse-leap" "$CDSI_PLATFORM" "openSUSE Leap platform"
assert_equal "zypper" "$CDSI_PACKAGE_BACKEND" \
    "openSUSE Leap package backend"
assert_equal "mariadb" "$CDSI_DB_PACKAGE" \
    "openSUSE Leap MariaDB package"
assert_equal "mariadb" "$CDSI_DB_SERVICE" \
    "openSUSE Leap MariaDB service"
assert_equal "mariadb" "$CDSI_DB_FLAVOR" \
    "openSUSE Leap database flavor"
assert_equal "mariadb" "$CDSI_DB_CLIENT" \
    "openSUSE Leap database client"
assert_equal "mariadb-admin" "$CDSI_DB_ADMIN_CLIENT" \
    "openSUSE Leap database admin client"
assert_equal "/etc/my.cnf.d/99-cdsi-anchor.cnf" \
    "$CDSI_DB_ANCHOR_CONFIG" \
    "openSUSE Leap Anchor database configuration"

[[ -f "$MYSQL_INSTALLER" ]] || fail_test "missing MySQL installer"

assert_contains 'source "${CDSI_ROOT}/lib/dnf.sh"' \
    "MySQL installer does not load its standalone DNF runtime"
assert_contains 'source "${CDSI_ROOT}/lib/zypper.sh"' \
    "database installer does not load its standalone Zypper runtime"
assert_contains 'DB_PACKAGES=("${CDSI_DB_PACKAGE}")' \
    "database installer does not use the platform package mapping"
assert_contains 'DB_PACKAGES+=(mariadb-client)' \
    "openSUSE database install does not include the client package"
assert_contains 'cdsi_service_installed "${CDSI_MYSQL_SERVICE}"' \
    "MySQL installer does not use the platform service mapping"
assert_contains 'DB_CLIENT="$CDSI_DB_CLIENT"' \
    "database installer does not use the platform client mapping"
assert_contains 'DB_ADMIN_CLIENT="$CDSI_DB_ADMIN_CLIENT"' \
    "database installer does not use the platform admin-client mapping"

assert_contains 'if cdsi_is_centos_stream && cdsi_package_installed mariadb-server; then' \
    "CentOS MySQL installer lacks the MariaDB conflict guard"
assert_contains 'fail "MariaDB Server is already installed. Anchor will not replace an existing database server with MySQL 8.4."' \
    "MariaDB conflict guard does not promise a protective stop"
assert_count 1 'mariadb-server' \
    "MariaDB must appear only in the protective conflict guard"
assert_before \
    'if cdsi_is_centos_stream && cdsi_package_installed mariadb-server; then' \
    'DB_PACKAGES=("${CDSI_DB_PACKAGE}")' \
    "MariaDB conflict guard must run before MySQL package installation"

assert_count 2 'local config_file="$CDSI_DB_ANCHOR_CONFIG"' \
    "database local-bind paths must use the platform mapping"
assert_contains 'bind-address=127.0.0.1' \
    "MySQL TCP listener is not restricted to localhost"
assert_contains 'mysqlx-bind-address=127.0.0.1' \
    "MySQL X Protocol listener is not restricted to localhost"
assert_contains '${SUDO} mysqld --validate-config' \
    "MySQL local-bind config is not validated before use"
assert_contains '${SUDO} rm -f -- "$config_file"' \
    "invalid MySQL local-bind config is not rolled back"
assert_contains 'if [[ "$CDSI_DB_FLAVOR" == "mariadb" ]]; then' \
    "MariaDB local-bind configuration is not shared by Debian and openSUSE"
assert_contains '[mariadbd]' \
    "Debian MariaDB local-bind config group is missing"
assert_contains '${SUDO} mariadbd --verbose --help' \
    "MariaDB local-bind configuration is not validated"
assert_contains 'cdsi_service_restart "${CDSI_MYSQL_SERVICE}"' \
    "an active MySQL service is not restarted after listener hardening"
assert_contains 'has a non-local TCP listener (${address});' \
    "database installer does not reject non-local listeners"
assert_count 3 'reconcile_mysql_runtime' \
    "MySQL network/runtime reconciliation must cover rerun and fresh paths"
assert_count 2 'MYSQL_NETWORK_CONFIG_CHANGED=false' \
    "database network-change state must be initialized and cleared after reconciliation"

assert_contains "DB_NAME=\"cdsi\"" "database name is not pinned to cdsi"
assert_contains "DB_USER=\"cdsi\"" "database user is not pinned to cdsi"
assert_contains "LC_ALL=C tr -dc 'A-Za-z0-9'" \
    "database password generation is not byte-oriented alphanumeric"
assert_contains 'temp_file="$(mktemp "${PASS_FILE}.tmp.XXXXXX")"' \
    "database credentials are not prepared through a temporary file"
assert_contains 'chmod 600 "$temp_file"' \
    "database credential file is not restricted to mode 600"
assert_contains 'mv -f "$temp_file" "$PASS_FILE"' \
    "database credentials are not installed atomically"

assert_contains \
    "SELECT COUNT(*) FROM mysql.user WHERE User='\${DB_USER}' AND Host='localhost';" \
    "installer does not inspect an existing local application account"
assert_contains \
    "already exists, but Anchor has no stored credential for it. Existing authentication was not changed." \
    "installer may overwrite an unknown existing application credential"
assert_contains \
    "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '\${ROOT_PASSWORD}';" \
    "MySQL root authentication is not pinned to caching_sha2_password"
assert_contains 'ROOT_AUTH_MODE="socket"' \
    "Debian MariaDB does not preserve unix_socket root authentication"
assert_contains 'ROOT_PASSWORD=""' \
    "MariaDB should not persist a root password"
assert_contains '"${DB_ROOT_CMD[@]}" "$DB_ADMIN_CLIENT" \' \
    "database readiness does not use the platform admin client"
assert_contains '--protocol=socket --silent ping' \
    "database readiness does not use a local socket ping"
assert_contains 'mysql_as_current_root <<SQL' \
    "database provisioning does not use the platform root authentication path"
assert_contains \
    'CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;' \
    "database creation is not idempotent utf8mb4 provisioning"
assert_contains \
    "CREATE USER IF NOT EXISTS '\${DB_USER}'@'localhost' IDENTIFIED BY '\${CDSI_PASSWORD}';" \
    "application account creation is not local and idempotent"
assert_contains \
    "ALTER USER '\${DB_USER}'@'localhost' IDENTIFIED BY '\${CDSI_PASSWORD}';" \
    "owned application credentials are not reconciled"
assert_contains \
    "GRANT ALL PRIVILEGES ON \${DB_NAME}.* TO '\${DB_USER}'@'localhost';" \
    "application grants are not scoped to the CDSI database"
assert_contains 'FLUSH PRIVILEGES;' "database grants are not flushed"

assert_before \
    'write_credentials "$ROOT_PASSWORD" "$CDSI_PASSWORD"' \
    "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password" \
    "credentials must be persisted before root authentication changes"
assert_before \
    'CREATE DATABASE IF NOT EXISTS ${DB_NAME}' \
    "GRANT ALL PRIVILEGES ON \${DB_NAME}.*" \
    "database must exist before its privileges are granted"

assert_contains \
    'db_client -u root -p"${ROOT_PASSWORD}" -e "SELECT 1"' \
    "root credential is not verified after provisioning"
assert_count 2 '-D "$DB_NAME"' \
    "application verification must check database access on rerun and final paths"
assert_contains \
    'db_client -u "${DB_USER}" -p"${CDSI_PASSWORD}" -D "$DB_NAME"' \
    "final application connection does not select the CDSI database"

printf 'PASS: Ubuntu/Debian/CentOS/openSUSE database mapping and safety contracts\n'
