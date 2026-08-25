#!/bin/sh

# Remote bootstrap for a new CDSI Anchor server. This script prepares only the
# tools needed to obtain Anchor, then hands control to install.sh.

set -eu
umask 077

CDSI_BOOTSTRAP_SYSTEM_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
CDSI_BOOTSTRAP_INSTALLER_PATH="/usr/local/sbin:/usr/local/bin:${CDSI_BOOTSTRAP_SYSTEM_PATH}"
PATH="$CDSI_BOOTSTRAP_SYSTEM_PATH"
export PATH

CDSI_BOOTSTRAP_RETRY_ATTEMPTS="${CDSI_BOOTSTRAP_RETRY_ATTEMPTS:-3}"
CDSI_BOOTSTRAP_RETRY_DELAY="${CDSI_BOOTSTRAP_RETRY_DELAY:-10}"
CDSI_BOOTSTRAP_PACKAGE_TIMEOUT="${CDSI_BOOTSTRAP_PACKAGE_TIMEOUT:-900}"
CDSI_BOOTSTRAP_GIT_TIMEOUT="${CDSI_BOOTSTRAP_GIT_TIMEOUT:-300}"
CDSI_BOOTSTRAP_GITEE_REPOSITORY="https://gitee.com/cdsi/anchor.git"
CDSI_BOOTSTRAP_GITHUB_REPOSITORY="https://github.com/cdsi-project/Anchor.git"
CDSI_BOOTSTRAP_REF="v0.3.5"
CDSI_BOOTSTRAP_BRANCH="anchor-bootstrap"
CDSI_BOOTSTRAP_CANDIDATE_REF="refs/cdsi-anchor/bootstrap-candidate"
CDSI_BOOTSTRAP_DIR="${CDSI_ANCHOR_DIR:-/root/cdsi-Anchor}"
CDSI_BOOTSTRAP_START_INSTALLER=true
CDSI_BOOTSTRAP_TEMP_DIR=""
CDSI_BOOTSTRAP_TEMP_PARENT=""
CDSI_BOOTSTRAP_PLATFORM=""
CDSI_BOOTSTRAP_OS=""
CDSI_BOOTSTRAP_OS_VERSION=""
CDSI_BOOTSTRAP_ARCH=""

bootstrap_log() {
    printf '[CDSI] %s\n' "$*"
}

bootstrap_ok() {
    printf '[ OK ] %s\n' "$*"
}

bootstrap_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

bootstrap_fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

bootstrap_usage() {
    cat <<'EOF'
Usage: sh bootstrap.sh [options]

Options:
  --dir PATH    Install or update Anchor in PATH (default: /root/cdsi-Anchor)
  --no-start    Prepare the checkout without starting install.sh
  -h, --help    Show this help
EOF
}

bootstrap_sudo_available() {
    command -v sudo >/dev/null 2>&1
}

bootstrap_escalate() {
    exec sudo sh "$@"
}

bootstrap_require_root() {
    bootstrap_uid="$(id -u 2>/dev/null || printf 'unknown')"
    [ "$bootstrap_uid" = "0" ] && return 0

    if bootstrap_sudo_available && [ -f "$0" ]; then
        case "$0" in
            /*) bootstrap_script_path="$0" ;;
            *) bootstrap_script_path="$(pwd)/$0" ;;
        esac
        bootstrap_log "Requesting root privileges with sudo..."
        bootstrap_escalate "$bootstrap_script_path" "$@"
        bootstrap_fail "sudo could not start the Anchor bootstrap."
    fi

    bootstrap_fail \
        "Root privileges are required. Download the script, then run: sudo sh bootstrap.sh"
}

bootstrap_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dir)
                [ "$#" -ge 2 ] || bootstrap_fail "--dir requires an absolute path."
                CDSI_BOOTSTRAP_DIR="$2"
                shift 2
                ;;
            --no-start)
                CDSI_BOOTSTRAP_START_INSTALLER=false
                shift
                ;;
            -h|--help)
                bootstrap_usage
                exit 0
                ;;
            *)
                bootstrap_fail "Unknown bootstrap option: $1"
                ;;
        esac
    done
}

bootstrap_validate_settings() {
    case "$CDSI_BOOTSTRAP_DIR" in
        /*) ;;
        *) bootstrap_fail "Anchor directory must be an absolute path: ${CDSI_BOOTSTRAP_DIR}" ;;
    esac
    CDSI_BOOTSTRAP_DIR="${CDSI_BOOTSTRAP_DIR%/}"
    case "$CDSI_BOOTSTRAP_DIR" in
        ""|/|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/root|/sbin|/srv|/usr|/var)
            bootstrap_fail "Refusing unsafe Anchor directory: ${CDSI_BOOTSTRAP_DIR:-/}"
            ;;
        */../*|*/..|*/./*|*/.)
            bootstrap_fail "Anchor directory must not contain dot path segments."
            ;;
    esac
    case "$CDSI_BOOTSTRAP_REF" in
        ""|*[!A-Za-z0-9._/-]*)
            bootstrap_fail "Invalid Anchor Git ref: ${CDSI_BOOTSTRAP_REF}"
            ;;
    esac
    case "$CDSI_BOOTSTRAP_RETRY_ATTEMPTS:$CDSI_BOOTSTRAP_RETRY_DELAY:$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT:$CDSI_BOOTSTRAP_GIT_TIMEOUT" in
        *[!0-9:]*|0:*|*:|*::*)
            bootstrap_fail "Invalid bootstrap retry configuration."
            ;;
    esac
    if [ "$CDSI_BOOTSTRAP_RETRY_ATTEMPTS" -lt 1 ] \
       || [ "$CDSI_BOOTSTRAP_RETRY_ATTEMPTS" -gt 10 ] \
       || [ "$CDSI_BOOTSTRAP_RETRY_DELAY" -gt 60 ] \
       || [ "$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT" -lt 30 ] \
       || [ "$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT" -gt 1800 ] \
       || [ "$CDSI_BOOTSTRAP_GIT_TIMEOUT" -lt 30 ] \
       || [ "$CDSI_BOOTSTRAP_GIT_TIMEOUT" -gt 1800 ]; then
        bootstrap_fail "Invalid bootstrap retry configuration."
    fi
}

bootstrap_check_target_path() {
    if [ ! -e "$CDSI_BOOTSTRAP_DIR" ] && [ ! -L "$CDSI_BOOTSTRAP_DIR" ]; then
        return 0
    fi
    [ ! -L "$CDSI_BOOTSTRAP_DIR" ] \
        || bootstrap_fail \
            "A symbolic link already exists at the Anchor path; it was not changed: ${CDSI_BOOTSTRAP_DIR}"
    [ -d "$CDSI_BOOTSTRAP_DIR" ] \
        || bootstrap_fail \
            "A file already exists at the Anchor path; it was not overwritten: ${CDSI_BOOTSTRAP_DIR}"
    [ -d "$CDSI_BOOTSTRAP_DIR/.git" ] \
        || bootstrap_fail \
            "A non-Git directory already exists at the Anchor path; it was not overwritten: ${CDSI_BOOTSTRAP_DIR}"
}

bootstrap_has_tty() {
    if bootstrap_stdin_is_tty; then
        return 0
    fi
    [ -c /dev/tty ] || return 1
    (: </dev/tty) 2>/dev/null
}

bootstrap_stdin_is_tty() {
    [ -t 0 ]
}

bootstrap_systemd_ready() {
    [ -d /run/systemd/system ]
}

bootstrap_detect_platform() {
    bootstrap_os_release="${CDSI_BOOTSTRAP_OS_RELEASE_FILE:-/etc/os-release}"
    [ -r "$bootstrap_os_release" ] \
        || bootstrap_fail "Cannot read operating-system metadata: ${bootstrap_os_release}"

    ID=""
    VERSION_ID=""
    NAME=""
    # shellcheck disable=SC1090
    . "$bootstrap_os_release"
    CDSI_BOOTSTRAP_OS="${ID:-unknown}"
    CDSI_BOOTSTRAP_OS_VERSION="${VERSION_ID:-unknown}"

    case "${ID:-}:${VERSION_ID:-}" in
        ubuntu:24.04|ubuntu:26.04)
            CDSI_BOOTSTRAP_PLATFORM="apt"
            ;;
        debian:13)
            CDSI_BOOTSTRAP_PLATFORM="apt"
            ;;
        opensuse-leap:16.0)
            CDSI_BOOTSTRAP_PLATFORM="zypper"
            ;;
        centos:10)
            case "${NAME:-}" in
                "CentOS Stream"*) CDSI_BOOTSTRAP_PLATFORM="dnf" ;;
                *) bootstrap_fail "CentOS Linux is not supported; use CentOS Stream 10." ;;
            esac
            ;;
        *)
            bootstrap_fail \
                "Unsupported operating system: ${NAME:-${ID:-unknown}} ${VERSION_ID:-unknown}."
            ;;
    esac

    CDSI_BOOTSTRAP_ARCH="${CDSI_BOOTSTRAP_ARCH_OVERRIDE:-$(uname -m)}"
    case "$CDSI_BOOTSTRAP_ARCH" in
        x86_64|aarch64) ;;
        *) bootstrap_fail "Unsupported CPU architecture: ${CDSI_BOOTSTRAP_ARCH}." ;;
    esac
}

bootstrap_preflight() {
    bootstrap_systemd_ready \
        || bootstrap_fail "A server running systemd is required."
    command -v timeout >/dev/null 2>&1 \
        || bootstrap_fail "GNU timeout from coreutils is required."
    if [ "$CDSI_BOOTSTRAP_START_INSTALLER" = true ] && ! bootstrap_has_tty; then
        bootstrap_fail \
            "An interactive terminal is required. Reconnect with SSH TTY support and retry."
    fi
}

bootstrap_retry() {
    bootstrap_attempt=1
    bootstrap_status=1
    while [ "$bootstrap_attempt" -le "$CDSI_BOOTSTRAP_RETRY_ATTEMPTS" ]; do
        if "$@"; then
            return 0
        else
            bootstrap_status=$?
        fi
        if [ "$bootstrap_attempt" -ge "$CDSI_BOOTSTRAP_RETRY_ATTEMPTS" ]; then
            break
        fi
        bootstrap_warn \
            "Command failed (attempt ${bootstrap_attempt}/${CDSI_BOOTSTRAP_RETRY_ATTEMPTS}); retrying in ${CDSI_BOOTSTRAP_RETRY_DELAY}s..."
        sleep "$CDSI_BOOTSTRAP_RETRY_DELAY"
        bootstrap_attempt=$((bootstrap_attempt + 1))
    done
    return "$bootstrap_status"
}

bootstrap_apt_available() {
    command -v apt-get >/dev/null 2>&1
}

bootstrap_apt_get() {
    timeout --foreground "$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT" \
        env DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

bootstrap_dnf_available() {
    command -v dnf >/dev/null 2>&1
}

bootstrap_dnf() {
    timeout --foreground "$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT" dnf "$@"
}

bootstrap_zypper_available() {
    command -v zypper >/dev/null 2>&1
}

bootstrap_zypper() {
    timeout --foreground "$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT" \
        zypper --non-interactive "$@"
}

bootstrap_prepare_apt() {
    bootstrap_apt_available \
        || bootstrap_fail "apt-get is required on ${CDSI_BOOTSTRAP_OS}."
    bootstrap_log "Refreshing the configured APT package indexes..."
    bootstrap_retry bootstrap_apt_get \
        -o DPkg::Lock::Timeout=120 -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update \
        || bootstrap_fail "apt-get update failed."
    bootstrap_log "Installing the Anchor bootstrap tools from the configured APT sources..."
    bootstrap_retry bootstrap_apt_get \
        -o DPkg::Lock::Timeout=120 -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
        install -y --no-install-recommends bash ca-certificates coreutils curl git \
        || bootstrap_fail "Could not install the Anchor bootstrap tools."
}

bootstrap_prepare_dnf() {
    bootstrap_dnf_available \
        || bootstrap_fail "dnf is required on CentOS Stream."
    bootstrap_log "Refreshing the configured DNF repository metadata..."
    bootstrap_retry bootstrap_dnf -y --setopt=retries=3 --setopt=timeout=30 \
        makecache --refresh \
        || bootstrap_fail "dnf makecache failed."
    bootstrap_log "Installing the Anchor bootstrap tools from BaseOS/AppStream..."
    bootstrap_retry bootstrap_dnf -y --setopt=retries=3 --setopt=timeout=30 \
        install bash ca-certificates coreutils curl git \
        || bootstrap_fail "Could not install the Anchor bootstrap tools."
}

bootstrap_prepare_zypper() {
    bootstrap_zypper_available \
        || bootstrap_fail "zypper is required on openSUSE Leap."
    bootstrap_log "Refreshing the configured Zypper repository metadata..."
    bootstrap_retry bootstrap_zypper refresh \
        || bootstrap_fail "zypper refresh failed."
    bootstrap_log "Installing the Anchor bootstrap tools from the configured openSUSE repositories..."
    bootstrap_retry bootstrap_zypper install --no-recommends \
        bash ca-certificates coreutils curl git \
        || bootstrap_fail "Could not install the Anchor bootstrap tools."
}

bootstrap_prepare_packages() {
    case "$CDSI_BOOTSTRAP_PLATFORM" in
        apt) bootstrap_prepare_apt ;;
        dnf) bootstrap_prepare_dnf ;;
        zypper) bootstrap_prepare_zypper ;;
        *) bootstrap_fail "Bootstrap package backend is not initialized." ;;
    esac
    command -v bash >/dev/null 2>&1 \
        && command -v git >/dev/null 2>&1 \
        && command -v timeout >/dev/null 2>&1 \
        || bootstrap_fail "Required bootstrap tools are still unavailable after installation."
    bootstrap_ok "Bootstrap tools are ready."
}

bootstrap_git() {
    GIT_TERMINAL_PROMPT=0 \
    timeout --foreground "$CDSI_BOOTSTRAP_GIT_TIMEOUT" \
        git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 "$@"
}

bootstrap_repository_allowed() {
    case "$1" in
        "$CDSI_BOOTSTRAP_GITEE_REPOSITORY"|"$CDSI_BOOTSTRAP_GITHUB_REPOSITORY")
            return 0
            ;;
        *) return 1 ;;
    esac
}

bootstrap_cleanup() {
    [ -n "$CDSI_BOOTSTRAP_TEMP_DIR" ] || return 0
    case "$CDSI_BOOTSTRAP_TEMP_DIR" in
        "$CDSI_BOOTSTRAP_TEMP_PARENT"/.anchor-bootstrap.*)
            [ ! -e "$CDSI_BOOTSTRAP_TEMP_DIR" ] \
                || rm -rf -- "$CDSI_BOOTSTRAP_TEMP_DIR"
            ;;
    esac
    CDSI_BOOTSTRAP_TEMP_DIR=""
}

bootstrap_checkout_valid() {
    bootstrap_checkout="$1"
    [ -d "$bootstrap_checkout/.git" ] \
        && [ -f "$bootstrap_checkout/bootstrap.sh" ] \
        && [ -f "$bootstrap_checkout/install.sh" ] \
        && [ -f "$bootstrap_checkout/lib/bootstrap.sh" ] \
        && bootstrap_git -C "$bootstrap_checkout" rev-parse --verify HEAD >/dev/null 2>&1 \
        && sh -n "$bootstrap_checkout/bootstrap.sh" \
        && bash -n "$bootstrap_checkout/install.sh" \
        && sh -n "$bootstrap_checkout/lib/bootstrap.sh"
}

bootstrap_release_tag_valid() {
    bootstrap_tag_checkout="$1"
    bootstrap_tag_ref="${2:-refs/tags/${CDSI_BOOTSTRAP_REF}}"
    bootstrap_tag_type="$(
        bootstrap_git -C "$bootstrap_tag_checkout" \
            cat-file -t "$bootstrap_tag_ref" 2>/dev/null
    )" || return 1
    [ "$bootstrap_tag_type" = tag ]
}

bootstrap_commit_valid() {
    bootstrap_commit="$1"
    bootstrap_commit_temp=""
    bootstrap_commit_status=0

    bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
        cat-file -e "${bootstrap_commit}^{commit}" >/dev/null 2>&1 \
        || return 1
    for bootstrap_commit_path in bootstrap.sh install.sh lib/bootstrap.sh; do
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
            cat-file -e "${bootstrap_commit}:${bootstrap_commit_path}" \
            >/dev/null 2>&1 || return 1
    done

    bootstrap_commit_temp="$(mktemp -d /tmp/cdsi-anchor-commit.XXXXXX)" \
        || return 1
    bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
        show "${bootstrap_commit}:bootstrap.sh" \
        > "${bootstrap_commit_temp}/bootstrap.sh" \
        || bootstrap_commit_status=1
    bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
        show "${bootstrap_commit}:install.sh" \
        > "${bootstrap_commit_temp}/install.sh" \
        || bootstrap_commit_status=1
    bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
        show "${bootstrap_commit}:lib/bootstrap.sh" \
        > "${bootstrap_commit_temp}/entry-bootstrap.sh" \
        || bootstrap_commit_status=1
    if [ "$bootstrap_commit_status" -eq 0 ]; then
        sh -n "${bootstrap_commit_temp}/bootstrap.sh" \
            && bash -n "${bootstrap_commit_temp}/install.sh" \
            && sh -n "${bootstrap_commit_temp}/entry-bootstrap.sh" \
            || bootstrap_commit_status=1
    fi
    case "$bootstrap_commit_temp" in
        /tmp/cdsi-anchor-commit.*)
            rm -rf -- "$bootstrap_commit_temp" \
                || bootstrap_commit_status=1
            ;;
    esac
    [ "$bootstrap_commit_status" -eq 0 ]
}

bootstrap_clone_checkout() {
    CDSI_BOOTSTRAP_TEMP_PARENT="$(dirname "$CDSI_BOOTSTRAP_DIR")"
    mkdir -p "$CDSI_BOOTSTRAP_TEMP_PARENT" \
        || bootstrap_fail "Could not create ${CDSI_BOOTSTRAP_TEMP_PARENT}."
    CDSI_BOOTSTRAP_TEMP_DIR="$(
        mktemp -d "${CDSI_BOOTSTRAP_TEMP_PARENT}/.anchor-bootstrap.XXXXXX"
    )" || bootstrap_fail "Could not create a temporary Anchor checkout."
    trap 'bootstrap_cleanup' 0
    trap 'bootstrap_cleanup; exit 1' 1 2 15

    bootstrap_clone_target="${CDSI_BOOTSTRAP_TEMP_DIR}/checkout"
    bootstrap_cloned=false
    for bootstrap_repository in \
        "$CDSI_BOOTSTRAP_GITEE_REPOSITORY" \
        "$CDSI_BOOTSTRAP_GITHUB_REPOSITORY"; do
        bootstrap_log "Cloning Anchor from ${bootstrap_repository}..."
        if bootstrap_git clone --no-checkout \
            "$bootstrap_repository" "$bootstrap_clone_target"; then
            if bootstrap_release_tag_valid "$bootstrap_clone_target" \
               && bootstrap_git -C "$bootstrap_clone_target" checkout -B \
                    "$CDSI_BOOTSTRAP_BRANCH" "${CDSI_BOOTSTRAP_REF}^{commit}" \
               && bootstrap_checkout_valid "$bootstrap_clone_target" \
               && bootstrap_git -C "$bootstrap_clone_target" \
                    config --local anchor.bootstrapManaged true; then
                bootstrap_cloned=true
                break
            fi
            bootstrap_warn \
                "Anchor release ${CDSI_BOOTSTRAP_REF} failed validation from ${bootstrap_repository}."
        else
            bootstrap_warn "Anchor clone failed from ${bootstrap_repository}."
        fi
        case "$bootstrap_clone_target" in
            "$CDSI_BOOTSTRAP_TEMP_DIR"/*)
                [ ! -e "$bootstrap_clone_target" ] \
                    || rm -rf -- "$bootstrap_clone_target"
                ;;
        esac
    done
    [ "$bootstrap_cloned" = true ] \
        || bootstrap_fail \
            "Could not obtain a valid Anchor release from Gitee or GitHub."
    [ ! -e "$CDSI_BOOTSTRAP_DIR" ] && [ ! -L "$CDSI_BOOTSTRAP_DIR" ] \
        || bootstrap_fail "Anchor directory appeared during bootstrap: ${CDSI_BOOTSTRAP_DIR}"
    mv "$bootstrap_clone_target" "$CDSI_BOOTSTRAP_DIR" \
        || bootstrap_fail "Could not activate the Anchor checkout."
    bootstrap_cleanup
    trap - 0 1 2 15
    bootstrap_ok "Anchor cloned to ${CDSI_BOOTSTRAP_DIR}."
}

bootstrap_fetch_checkout() {
    bootstrap_fetch_repository="$1"
    bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" update-ref --no-deref -d \
        "$CDSI_BOOTSTRAP_CANDIDATE_REF" >/dev/null 2>&1 \
        || return 1
    if ! bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" fetch --no-tags \
        "$bootstrap_fetch_repository" \
        "refs/tags/${CDSI_BOOTSTRAP_REF}:${CDSI_BOOTSTRAP_CANDIDATE_REF}"; then
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" update-ref --no-deref -d \
            "$CDSI_BOOTSTRAP_CANDIDATE_REF" >/dev/null 2>&1 || true
        return 1
    fi
    if ! bootstrap_release_tag_valid "$CDSI_BOOTSTRAP_DIR" \
            "$CDSI_BOOTSTRAP_CANDIDATE_REF" \
       || ! bootstrap_commit_valid "$CDSI_BOOTSTRAP_CANDIDATE_REF"; then
        bootstrap_warn \
            "Fetched Anchor release failed validation from ${bootstrap_fetch_repository}."
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" update-ref --no-deref -d \
            "$CDSI_BOOTSTRAP_CANDIDATE_REF" >/dev/null 2>&1 || true
        return 2
    fi
    if ! bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" merge --ff-only \
        "${CDSI_BOOTSTRAP_CANDIDATE_REF}^{commit}"; then
        bootstrap_warn \
            "Anchor release from ${bootstrap_fetch_repository} is not a fast-forward update."
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" update-ref --no-deref -d \
            "$CDSI_BOOTSTRAP_CANDIDATE_REF" >/dev/null 2>&1 || true
        return 3
    fi
    bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" update-ref --no-deref -d \
        "$CDSI_BOOTSTRAP_CANDIDATE_REF" >/dev/null 2>&1 \
        || bootstrap_warn "Could not remove the temporary Anchor release reference."
    return 0
}

bootstrap_update_checkout() {
    [ ! -L "$CDSI_BOOTSTRAP_DIR" ] \
        || bootstrap_fail "Refusing a symbolic-link Anchor directory: ${CDSI_BOOTSTRAP_DIR}"
    [ -d "$CDSI_BOOTSTRAP_DIR/.git" ] \
        || bootstrap_fail \
            "Existing Anchor directory is not a Git checkout: ${CDSI_BOOTSTRAP_DIR}"
    bootstrap_origin="$(
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" remote get-url origin 2>/dev/null
    )" || bootstrap_fail "The existing Anchor checkout has no origin remote."
    bootstrap_repository_allowed "$bootstrap_origin" \
        || bootstrap_fail "Refusing an unexpected Anchor origin: ${bootstrap_origin}"
    bootstrap_managed="$(
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
            config --bool --get anchor.bootstrapManaged 2>/dev/null
    )" || bootstrap_managed=false
    [ "$bootstrap_managed" = true ] \
        || bootstrap_fail \
            "Existing checkout is not bootstrap-managed; run its install.sh directly."
    bootstrap_branch="$(
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" \
            symbolic-ref --quiet --short HEAD 2>/dev/null
    )" || bootstrap_branch=""
    [ "$bootstrap_branch" = "$CDSI_BOOTSTRAP_BRANCH" ] \
        || bootstrap_fail \
            "Existing Anchor checkout is on ${bootstrap_branch:-a detached HEAD}, not ${CDSI_BOOTSTRAP_BRANCH}."
    bootstrap_changes="$(
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" status --porcelain 2>/dev/null
    )" || bootstrap_fail "Could not inspect the existing Anchor checkout."
    [ -z "$bootstrap_changes" ] \
        || bootstrap_fail \
            "Existing Anchor checkout has local changes; it was not updated."

    bootstrap_log "Updating the existing Anchor checkout with a fast-forward merge..."
    if bootstrap_fetch_checkout "$bootstrap_origin"; then
        bootstrap_ok "Existing Anchor checkout updated."
        return 0
    fi
    bootstrap_warn \
        "The configured Anchor origin did not provide a valid release; trying the mirrors."
    for bootstrap_repository in \
        "$CDSI_BOOTSTRAP_GITEE_REPOSITORY" \
        "$CDSI_BOOTSTRAP_GITHUB_REPOSITORY"; do
        [ "$bootstrap_repository" = "$bootstrap_origin" ] && continue
        if bootstrap_fetch_checkout "$bootstrap_repository"; then
            bootstrap_ok "Existing Anchor checkout updated from the fallback mirror."
            return 0
        fi
    done
    bootstrap_fail "Could not update Anchor from Gitee or GitHub."
}

bootstrap_prepare_checkout() {
    if [ -e "$CDSI_BOOTSTRAP_DIR" ] || [ -L "$CDSI_BOOTSTRAP_DIR" ]; then
        bootstrap_update_checkout
    else
        bootstrap_clone_checkout
    fi
    bootstrap_checkout_valid "$CDSI_BOOTSTRAP_DIR" \
        || bootstrap_fail "Anchor checkout validation failed: ${CDSI_BOOTSTRAP_DIR}"
    bootstrap_revision="$(
        bootstrap_git -C "$CDSI_BOOTSTRAP_DIR" rev-parse --short HEAD
    )" || bootstrap_fail "Could not read the Anchor revision."
    bootstrap_ok "Anchor revision: ${bootstrap_revision}"
}

bootstrap_start_installer() {
    bootstrap_log "Starting the Anchor installer..."
    cd "$CDSI_BOOTSTRAP_DIR" \
        || bootstrap_fail "Could not enter ${CDSI_BOOTSTRAP_DIR}."
    if bootstrap_stdin_is_tty; then
        if bootstrap_exec_installer; then
            return 0
        else
            return $?
        fi
    fi
    if bootstrap_has_tty; then
        if bootstrap_exec_installer </dev/tty; then
            return 0
        else
            return $?
        fi
    fi
    bootstrap_fail \
        "No interactive terminal is available. Run: sudo bash ${CDSI_BOOTSTRAP_DIR}/install.sh"
}

bootstrap_exec_installer() {
    bootstrap_bash="$(command -v bash)" \
        || bootstrap_fail "Bash is unavailable after bootstrap preparation."
    PATH="$CDSI_BOOTSTRAP_INSTALLER_PATH"
    export PATH
    exec "$bootstrap_bash" ./install.sh
}

bootstrap_main() {
    case "${1:-}" in
        -h|--help)
            bootstrap_usage
            return 0
            ;;
    esac
    bootstrap_require_root "$@"
    bootstrap_parse_args "$@"
    bootstrap_validate_settings
    bootstrap_detect_platform
    bootstrap_preflight
    bootstrap_check_target_path
    bootstrap_log \
        "Preparing Anchor on ${CDSI_BOOTSTRAP_OS} ${CDSI_BOOTSTRAP_OS_VERSION} (${CDSI_BOOTSTRAP_ARCH})..."
    bootstrap_prepare_packages
    bootstrap_prepare_checkout
    if [ "$CDSI_BOOTSTRAP_START_INSTALLER" = false ]; then
        bootstrap_ok "Bootstrap complete. Start with: sudo bash ${CDSI_BOOTSTRAP_DIR}/install.sh"
        return 0
    fi
    bootstrap_start_installer
}

if [ "${CDSI_BOOTSTRAP_SOURCE_ONLY:-false}" != true ]; then
    bootstrap_main "$@"
fi
