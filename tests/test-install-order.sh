#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../install.sh
source "${TEST_ROOT}/install.sh"

if [[ "${CDSI_COMP_NAMES[3]}" != WordPress \
   || "${CDSI_COMP_SCRIPTS[3]}" != */scripts/install-wordpress.sh \
   || "${CDSI_COMP_NAMES[4]}" != Certbot \
   || "${CDSI_COMP_SCRIPTS[4]}" != */scripts/install-certbot.sh ]]; then
    printf 'FAIL: WordPress/Certbot component registry order is incorrect\n' >&2
    exit 1
fi

grep -Fq 'if logger_run_component env \' "${TEST_ROOT}/install.sh" \
    || { printf 'FAIL: component execution bypasses diagnostic logging\n' >&2; exit 1; }

component_calls=()
cdsi_install_component() {
    local idx="$1"
    component_calls+=("$idx")
    CDSI_COMP_DONE[$idx]=true
    return 0
}

cdsi_install_all >/dev/null 2>&1

if [[ "${component_calls[*]}" != "0 1 2 3" ]]; then
    printf 'FAIL: unexpected install-all order: %s\n' "${component_calls[*]}" >&2
    exit 1
fi
if [[ "${CDSI_COMP_DONE[0]}" != true \
   || "${CDSI_COMP_DONE[1]}" != true \
   || "${CDSI_COMP_DONE[2]}" != true \
   || "${CDSI_COMP_DONE[3]}" != true ]]; then
    printf 'FAIL: a required component did not complete\n' >&2
    exit 1
fi
if [[ "${CDSI_COMP_DONE[4]}" == true ]]; then
    printf 'FAIL: optional Certbot ran before final domain setup\n' >&2
    exit 1
fi

printf 'PASS: required install order leaves domain and Certbot for final setup\n'
