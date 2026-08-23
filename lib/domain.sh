#!/usr/bin/env bash
# Domain resolution and deployment-state helpers. Intended to be sourced.

CDSI_DNS_STATUS=""
CDSI_DNS_MESSAGE=""

_cdsi_unique_lines() {
    awk 'NF && !seen[tolower($0)]++'
}

# DNS activation must query DNS itself, not NSS (/etc/hosts, mDNS, or a local
# split-horizon override). Install the platform's dig provider from the system
# package source when a caller has loaded the shared package backend.
cdsi_ensure_dns_tools() {
    command -v dig >/dev/null 2>&1 && return 0
    declare -F cdsi_packages_install >/dev/null 2>&1 || return 1
    if declare -F cdsi_platform_init >/dev/null 2>&1; then
        cdsi_platform_init
    fi
    case "${CDSI_PLATFORM:-}" in
        ubuntu) cdsi_packages_install dnsutils ;;
        centos-stream) cdsi_packages_install bind-utils ;;
        *) return 1 ;;
    esac
    command -v dig >/dev/null 2>&1
}

# Query A or AAAA records. Returns 2 only when no resolver tool is available
# or the resolver itself cannot be queried; an empty successful result means
# that the requested record does not exist.
cdsi_dns_query_records() {
    local record_type="${1:-}"
    local domain="${2:-}"
    local output="" line=""

    [[ "$record_type" == "A" || "$record_type" == "AAAA" ]] || return 2
    cdsi_validate_domain "$domain" || return 2

    command -v dig >/dev/null 2>&1 || return 2
    if ! output="$(dig +time=4 +tries=2 +short "$record_type" "$domain" 2>/dev/null)"; then
        return 2
    fi
    while IFS= read -r line; do
        line="${line%.}"
        if [[ "$record_type" == "A" ]]; then
            cdsi_is_ipv4 "$line" && printf '%s\n' "$line"
        elif [[ "$line" == *:* ]]; then
            printf '%s\n' "${line,,}"
        fi
    done <<< "$output" | _cdsi_unique_lines
}

# Print the global IPv6 addresses assigned to this host. Tests and advanced
# deployments can override this function or set CDSI_SERVER_IPV6 explicitly.
cdsi_server_global_ipv6() {
    local value="${CDSI_SERVER_IPV6:-}"
    local address=""

    if [[ -n "$value" ]]; then
        value="${value//,/ }"
        for address in $value; do
            address="${address%%%*}"
            address="${address%%/*}"
            [[ "$address" == *:* ]] && printf '%s\n' "${address,,}"
        done | _cdsi_unique_lines
        return 0
    fi

    command -v ip >/dev/null 2>&1 || return 0
    ip -6 -o addr show scope global 2>/dev/null \
        | awk '{print $4}' \
        | cut -d/ -f1 \
        | tr '[:upper:]' '[:lower:]' \
        | _cdsi_unique_lines
}

_cdsi_dns_mismatch_result() {
    CDSI_DNS_STATUS="$1"
    CDSI_DNS_MESSAGE="$2"
    [[ "${CDSI_ALLOW_DNS_MISMATCH:-false}" == "true" ]]
}

# Verify that every requested hostname resolves exclusively to this server.
# A wrong AAAA record is rejected because ACME validators may prefer IPv6.
cdsi_domain_dns_ready() {
    local raw_domains="${1:-}"
    local server_ipv4="${2:-${CDSI_SERVER_IP:-}}"
    local normalized="" domain="" record="" query_output=""
    local query_status=0 found_ipv4=false
    local -a domains=() ipv4_records=() ipv6_records=() server_ipv6=()

    CDSI_DNS_STATUS=""
    CDSI_DNS_MESSAGE=""

    normalized="$(cdsi_normalize_domain_list "$raw_domains")" || {
        CDSI_DNS_STATUS="invalid"
        CDSI_DNS_MESSAGE="域名格式无效。"
        return 1
    }
    cdsi_is_ipv4 "$server_ipv4" || {
        CDSI_DNS_STATUS="indeterminate"
        CDSI_DNS_MESSAGE="无法确定用于校验 DNS 的服务器 IPv4 地址。"
        return 1
    }

    IFS=',' read -r -a domains <<< "$normalized"
    while IFS= read -r record; do
        [[ -n "$record" ]] && server_ipv6+=("${record,,}")
    done < <(cdsi_server_global_ipv6)

    for domain in "${domains[@]}"; do
        ipv4_records=()
        if query_output="$(cdsi_dns_query_records A "$domain")"; then
            query_status=0
        else
            query_status=$?
        fi
        if [[ "$query_status" -eq 2 ]]; then
            _cdsi_dns_mismatch_result "indeterminate" \
                "无法查询 ${domain} 的 DNS A 记录；请安装 dig 或检查系统 DNS。"
            return
        fi
        while IFS= read -r record; do
            [[ -n "$record" ]] && ipv4_records+=("$record")
        done <<< "$query_output"
        if [[ "${#ipv4_records[@]}" -eq 0 ]]; then
            _cdsi_dns_mismatch_result "unresolved" \
                "${domain} 尚无可用的 DNS A 记录。"
            return
        fi

        found_ipv4=false
        for record in "${ipv4_records[@]}"; do
            if [[ "$record" == "$server_ipv4" ]]; then
                found_ipv4=true
            else
                _cdsi_dns_mismatch_result "mismatch" \
                    "${domain} 的 A 记录 ${record} 不属于本服务器 ${server_ipv4}。"
                return
            fi
        done
        if [[ "$found_ipv4" != true ]]; then
            _cdsi_dns_mismatch_result "mismatch" \
                "${domain} 的 A 记录未指向本服务器 ${server_ipv4}。"
            return
        fi

        ipv6_records=()
        if query_output="$(cdsi_dns_query_records AAAA "$domain")"; then
            query_status=0
        else
            query_status=$?
        fi
        if [[ "$query_status" -eq 2 ]]; then
            _cdsi_dns_mismatch_result "indeterminate" \
                "无法查询 ${domain} 的 DNS AAAA 记录。"
            return
        fi
        while IFS= read -r record; do
            [[ -n "$record" ]] && ipv6_records+=("${record,,}")
        done <<< "$query_output"
        for record in "${ipv6_records[@]}"; do
            if [[ " ${server_ipv6[*]} " != *" ${record,,} "* ]]; then
                _cdsi_dns_mismatch_result "mismatch" \
                    "${domain} 的 AAAA 记录 ${record} 不属于本服务器；错误 IPv6 会导致证书验证失败。"
                return
            fi
        done
    done

    CDSI_DNS_STATUS="ready"
    CDSI_DNS_MESSAGE="域名 DNS 已指向本服务器。"
    return 0
}

cdsi_domain_state_read() {
    local path="${1:-}"
    [[ -f "$path" ]] || return 1
    head -n1 "$path" 2>/dev/null | tr -d '\r\n'
}

cdsi_domain_state_write() {
    local path="${1:-}"
    local value="${2:-}"
    local directory="" temporary=""

    [[ -n "$path" && -n "$value" ]] || return 1
    directory="$(dirname "$path")"
    mkdir -p "$directory" || return 1
    temporary="$(mktemp "${path}.tmp.XXXXXX")" || return 1
    if ! printf '%s\n' "$value" > "$temporary" \
       || ! chmod 0644 "$temporary" \
       || ! mv -f -- "$temporary" "$path"; then
        rm -f -- "$temporary" 2>/dev/null || true
        return 1
    fi
}
