#!/bin/sh
cdsi_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
export CDSI_PLATFORM_ROUTE=ubuntu
exec /bin/sh "${cdsi_root}/lib/bootstrap.sh" "${cdsi_root}/scripts/common/install-certbot.sh" "$@"
