#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remote_bootstrap="${TEST_ROOT}/bootstrap.sh"
entries=(
    check-env.sh
    install-nginx.sh
    install-mysql.sh
    install-php.sh
    install-wordpress.sh
    install-certbot.sh
)

configuration_entries=(
    configure-domain.sh
    configure-https.sh
)

[[ -f "$remote_bootstrap" ]] \
    || { printf 'FAIL: missing root remote bootstrap entry\n' >&2; exit 1; }
/bin/sh -n "$remote_bootstrap" \
    || { printf 'FAIL: root remote bootstrap is not POSIX shell compatible\n' >&2; exit 1; }
grep -Fq 'https://gitee.com/cdsi/anchor.git' "$remote_bootstrap" \
    && grep -Fq 'https://github.com/cdsi-project/Anchor.git' "$remote_bootstrap" \
    || { printf 'FAIL: remote bootstrap lacks the official mirror fallback pair\n' >&2; exit 1; }
grep -Fq 'bootstrap_start_installer' "$remote_bootstrap" \
    || { printf 'FAIL: remote bootstrap does not hand off to install.sh\n' >&2; exit 1; }

for entry in "${configuration_entries[@]}"; do
    script="${TEST_ROOT}/scripts/${entry}"
    [[ -f "$script" ]] \
        || { printf 'FAIL: missing standalone configuration entry %s\n' "$entry" >&2; exit 1; }
    bash -n "$script" \
        || { printf 'FAIL: standalone configuration entry has invalid Bash syntax: %s\n' "$entry" >&2; exit 1; }
done

if ! grep -Fq 'cdsi_domain_dns_ready' \
    "${TEST_ROOT}/scripts/configure-domain.sh"; then
    printf 'FAIL: standalone domain configuration does not enforce DNS readiness\n' >&2
    exit 1
fi
if ! grep -Fq 'domain.pending' \
    "${TEST_ROOT}/scripts/configure-domain.sh"; then
    printf 'FAIL: standalone domain configuration does not preserve pending DNS state\n' >&2
    exit 1
fi
if ! grep -Fq -- '--ip' \
    "${TEST_ROOT}/scripts/configure-https.sh"; then
    printf 'FAIL: standalone HTTPS configuration does not expose explicit IP mode\n' >&2
    exit 1
fi
if ! grep -Fq 'CDSI_ROOT_CMD=(sudo)' "${TEST_ROOT}/install.sh" \
   || ! grep -Fq 'CDSI_ROOT_CMD[@]' "${TEST_ROOT}/install.sh"; then
    printf 'FAIL: main-menu configuration entries do not preserve non-root sudo support\n' >&2
    exit 1
fi

for entry in "${entries[@]}"; do
    [[ -f "${TEST_ROOT}/scripts/${entry}" ]] \
        || { printf 'FAIL: missing dispatcher %s\n' "$entry" >&2; exit 1; }
    [[ -f "${TEST_ROOT}/scripts/common/${entry}" ]] \
        || { printf 'FAIL: missing shared implementation %s\n' "$entry" >&2; exit 1; }
    [[ -f "${TEST_ROOT}/scripts/ubuntu/${entry}" ]] \
        || { printf 'FAIL: missing Ubuntu route for %s\n' "$entry" >&2; exit 1; }
    [[ -f "${TEST_ROOT}/scripts/centos-stream/${entry}" ]] \
        || { printf 'FAIL: missing CentOS Stream route for %s\n' "$entry" >&2; exit 1; }
    [[ -f "${TEST_ROOT}/scripts/debian/${entry}" ]] \
        || { printf 'FAIL: missing Debian route for %s\n' "$entry" >&2; exit 1; }
    if ! grep -q 'CDSI_PLATFORM_ROUTE=centos-stream' \
        "${TEST_ROOT}/scripts/centos-stream/${entry}"; then
        printf 'FAIL: CentOS Stream route does not set its platform identity: %s\n' \
            "$entry" >&2
        exit 1
    fi
    if ! grep -q 'CDSI_PLATFORM_ROUTE=debian' \
        "${TEST_ROOT}/scripts/debian/${entry}"; then
        printf 'FAIL: Debian route does not set its platform identity: %s\n' \
            "$entry" >&2
        exit 1
    fi
    /bin/sh -n "${TEST_ROOT}/scripts/debian/${entry}" \
        || { printf 'FAIL: Debian route has invalid POSIX shell syntax: %s\n' "$entry" >&2; exit 1; }
done

[[ ! -e "${TEST_ROOT}/scripts/debian/README.md" ]] \
    || { printf 'FAIL: implemented Debian route still has a planned-only README\n' >&2; exit 1; }
[[ ! -e "${TEST_ROOT}/scripts/centos-stream/README.md" ]] \
    || { printf 'FAIL: implemented CentOS Stream route still has a planned-only README\n' >&2; exit 1; }

if ! grep -Fq 'if [ "$cdsi_os_name" = "CentOS Stream" ]; then' \
    "${TEST_ROOT}/scripts/dispatch.sh"; then
    printf 'FAIL: CentOS dispatch is not restricted to the explicit CentOS Stream name\n' >&2
    exit 1
fi

for compatibility_script in install-redis.sh install-supervisor.sh; do
    if ! grep -q 'cdsi_platform_supported' \
        "${TEST_ROOT}/scripts/${compatibility_script}" \
       || ! grep -q 'cdsi_is_ubuntu' \
        "${TEST_ROOT}/scripts/${compatibility_script}"; then
        printf 'FAIL: standalone compatibility script lacks an Ubuntu guard: %s\n' \
            "$compatibility_script" >&2
        exit 1
    fi
done

nginx_installer="${TEST_ROOT}/scripts/common/install-nginx.sh"
if ! grep -q 'firewall-added-services' "$nginx_installer" \
   || ! grep -q -- '--permanent' "$nginx_installer" \
   || ! grep -q -- '--query-service' "$nginx_installer"; then
    printf 'FAIL: CentOS Nginx firewalld changes are not provenance-tracked\n' >&2
    exit 1
fi

certbot_installer="${TEST_ROOT}/scripts/common/install-certbot.sh"
if ! grep -q 'cdsi_enable_epel' "$certbot_installer"; then
    printf 'FAIL: CentOS Certbot installation does not prepare EPEL\n' >&2
    exit 1
fi

for dnf_component in "$nginx_installer" "$certbot_installer"; do
    if ! grep -q 'lib/dnf.sh' "$dnf_component"; then
        printf 'FAIL: DNF-capable component does not load its standalone runtime: %s\n' \
            "$dnf_component" >&2
        exit 1
    fi
done

if ! grep -q "^ALTER USER '\${DB_USER}'@'localhost' IDENTIFIED BY '\${CDSI_PASSWORD}';$" \
    "${TEST_ROOT}/scripts/common/install-mysql.sh"; then
    printf 'FAIL: MySQL provisioning does not reconcile the cdsi credential\n' >&2
    exit 1
fi

for password_script in \
    "${TEST_ROOT}/scripts/common/install-mysql.sh" \
    "${TEST_ROOT}/scripts/common/install-wordpress.sh"; do
    if ! grep -q "LC_ALL=C tr -dc 'A-Za-z0-9'" "$password_script"; then
        printf 'FAIL: password generation is not byte-oriented in %s\n' \
            "$password_script" >&2
        exit 1
    fi
done

for nginx_template in "${TEST_ROOT}/config/nginx-site.conf.template"; do
    uploads_deny_line="$(grep -nF 'location ~* /(?:uploads|files)/.*\.php$ {' \
        "$nginx_template" | cut -d: -f1)"
    generic_php_line="$(grep -nF 'location ~ \.php$ {' \
        "$nginx_template" | cut -d: -f1)"
    if [[ -z "$uploads_deny_line" || -z "$generic_php_line" \
       || "$uploads_deny_line" -ge "$generic_php_line" ]]; then
        printf 'FAIL: uploads PHP deny rule must precede PHP-FPM in %s\n' \
            "$nginx_template" >&2
        exit 1
    fi
    if ! grep -Fq 'include fastcgi_params;' "$nginx_template" \
       || ! grep -Fq 'fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;' \
            "$nginx_template"; then
        printf 'FAIL: Nginx PHP forwarding is not portable across supported platforms\n' >&2
        exit 1
    fi
done

if ! grep -q 'cdsi_configure_optional_domain_https' "${TEST_ROOT}/install.sh" \
   || ! grep -q 'scripts/configure-https.sh' "${TEST_ROOT}/install.sh"; then
    printf 'FAIL: install-all lacks the optional final domain/HTTPS step\n' >&2
    exit 1
fi

if ! grep -q 'CDSI_INSTALL_CONTEXT:-standalone.*!= "all"' \
    "${TEST_ROOT}/scripts/common/install-certbot.sh"; then
    printf 'FAIL: full install can prompt for the domain twice\n' >&2
    exit 1
fi

if ! grep -q -- '-D "$DB_NAME"' \
    "${TEST_ROOT}/scripts/common/install-mysql.sh"; then
    printf 'FAIL: MySQL verification does not check cdsi database access\n' >&2
    exit 1
fi

printf 'PASS: Ubuntu, Debian, and CentOS Stream platform dispatcher layout\n'
