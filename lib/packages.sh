#!/usr/bin/env bash

# Package operations for supported system package sources.

cdsi_packages_update() {
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt) cdsi_apt_get update -qq ;;
        dnf) cdsi_dnf makecache -q --refresh ;;
        *) return 1 ;;
    esac
}

cdsi_packages_install() {
    [[ $# -gt 0 ]] || return 2
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt) cdsi_apt_get install -y -qq "$@" ;;
        dnf) cdsi_dnf install -y -q "$@" ;;
        *) return 1 ;;
    esac
}

cdsi_package_available() {
    local package="$1"
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt)
            local candidate
            candidate="$(LC_ALL=C apt-cache policy "$package" 2>/dev/null \
                | awk '/Candidate:/ {print $2; exit}')"
            [[ -n "$candidate" && "$candidate" != "(none)" ]]
            ;;
        dnf)
            rpm -q --quiet "$package" >/dev/null 2>&1 \
                || cdsi_dnf_query -q list --available "$package" \
                    >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

cdsi_package_installed() {
    local package="$1"
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt)
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
                | grep -Fq 'install ok installed'
            ;;
        dnf)
            rpm -q --quiet "$package" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

cdsi_packages_remove() {
    [[ $# -gt 0 ]] || return 2
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt) cdsi_apt_get purge -y "$@" ;;
        dnf) cdsi_dnf remove -y -q "$@" ;;
        *) return 1 ;;
    esac
}

cdsi_packages_autoremove() {
    cdsi_platform_init
    case "$CDSI_PACKAGE_BACKEND" in
        apt) cdsi_apt_get autoremove --purge -y ;;
        dnf) cdsi_dnf autoremove -y -q ;;
        *) return 1 ;;
    esac
}

cdsi_record_epel_added() {
    local marker="${CDSI_EPEL_MARKER:-/etc/cdsi/epel-added}"
    local marker_dir="${marker%/*}"
    local -a root_cmd=()
    if [[ "${EUID}" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || return 1
        root_cmd=(sudo)
    fi
    "${root_cmd[@]}" mkdir -p "$marker_dir" || return 1
    printf 'epel-release\n' \
        | "${root_cmd[@]}" tee "$marker" >/dev/null || return 1
    "${root_cmd[@]}" chmod 0644 "$marker"
}

cdsi_epel_extras_repo() {
    local repo
    for repo in extras-common extras; do
        if cdsi_dnf_query -q --disablerepo='*' "--enablerepo=${repo}" \
            list --available epel-release >/dev/null 2>&1; then
            printf '%s\n' "$repo"
            return 0
        fi
    done
    return 1
}

cdsi_enable_epel() {
    cdsi_platform_init
    cdsi_is_centos_stream || return 1
    [[ "$CDSI_PACKAGE_BACKEND" == "dnf" ]] || return 1
    if cdsi_package_installed epel-release; then
        return 0
    fi

    local extras_repo
    extras_repo="$(cdsi_epel_extras_repo)" || return 1
    cdsi_dnf install -y -q --disablerepo='*' \
        "--enablerepo=${extras_repo}" epel-release || return 1
    if ! cdsi_record_epel_added; then
        cdsi_dnf remove -y -q epel-release >/dev/null 2>&1 || true
        return 1
    fi
}
