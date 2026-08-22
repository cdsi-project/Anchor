#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Allow the script to be sourced from non-root developer shells.
sudo() { "$@"; }

# shellcheck source=../uninstall.sh
source "${TEST_ROOT}/uninstall.sh"

mysql_log="$(mktemp)"
nginx_fixture="$(mktemp)"
trap 'rm -f "$mysql_log" "$nginx_fixture"' EXIT
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

printf 'PASS: uninstall database guards and Certbot Nginx cleanup\n'
