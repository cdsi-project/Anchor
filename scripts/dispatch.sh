#!/bin/sh

if [ "$#" -lt 1 ]; then
    printf '%s\n' 'Usage: dispatch.sh <script> [args...]' >&2
    exit 2
fi

cdsi_script_name=$1
shift
case "$cdsi_script_name" in
    check-env.sh|install-nginx.sh|install-mysql.sh|install-php.sh|install-wordpress.sh|install-certbot.sh)
        ;;
    *)
        printf '[FAIL] Unknown Anchor component entry: %s\n' "$cdsi_script_name" >&2
        exit 2
        ;;
esac

cdsi_scripts_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
cdsi_kernel=$(uname -s 2>/dev/null || printf unknown)
cdsi_platform=""

case "$cdsi_kernel" in
    Linux)
        cdsi_os_id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print tolower($2); exit}' \
            /etc/os-release 2>/dev/null || true)
        cdsi_os_name=$(awk -F= '/^NAME=/{sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit}' \
            /etc/os-release 2>/dev/null || true)
        case "$cdsi_os_id" in
            ubuntu) cdsi_platform="ubuntu" ;;
            debian) cdsi_platform="debian" ;;
            opensuse-leap) cdsi_platform="opensuse-leap" ;;
            centos)
                if [ "$cdsi_os_name" = "CentOS Stream" ]; then
                    cdsi_platform="centos-stream"
                fi
                ;;
        esac
        ;;
esac

if [ -z "$cdsi_platform" ]; then
    printf '[FAIL] Unsupported operating system: %s.\n' "$cdsi_kernel" >&2
    exit 3
fi

cdsi_target="${cdsi_scripts_dir}/${cdsi_platform}/${cdsi_script_name}"
if [ ! -f "$cdsi_target" ]; then
    printf '[FAIL] %s support is planned but not implemented for %s.\n' \
        "$cdsi_script_name" "$cdsi_platform" >&2
    exit 3
fi

exec /bin/sh "$cdsi_target" "$@"
