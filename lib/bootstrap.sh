#!/bin/sh

# POSIX bootstrap for entry points that are implemented in Bash.

if [ "$#" -lt 1 ]; then
    printf '%s\n' 'Usage: bootstrap.sh <script> [args...]' >&2
    exit 2
fi

cdsi_bootstrap_target=$1
shift

if command -v bash >/dev/null 2>&1; then
    exec "$(command -v bash)" "$cdsi_bootstrap_target" "$@"
fi

printf '%s\n' '[FAIL] Bash is required to run Anchor.' >&2
exit 1
