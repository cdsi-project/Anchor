#!/bin/sh
cdsi_scripts_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
exec /bin/sh "${cdsi_scripts_dir}/dispatch.sh" "$(basename "$0")" "$@"
