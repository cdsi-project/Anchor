#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${TEST_ROOT}/bootstrap.sh"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "$actual" == "$expected" ]] \
        || fail_test "${message}: expected '${expected}', got '${actual}'"
}

CDSI_BOOTSTRAP_SOURCE_ONLY=true
CDSI_BOOTSTRAP_RETRY_DELAY=0
# shellcheck source=../bootstrap.sh
source "$BOOTSTRAP_SCRIPT"

bash -n "$BOOTSTRAP_SCRIPT" \
    || fail_test "bootstrap.sh has invalid Bash syntax"
sh -n "$BOOTSTRAP_SCRIPT" \
    || fail_test "bootstrap.sh has invalid POSIX shell syntax"
grep -Fqx '#!/bin/sh' "$BOOTSTRAP_SCRIPT" \
    || fail_test "bootstrap.sh must run before Bash is installed"
grep -Fq 'CDSI_BOOTSTRAP_REF="v0.3.0"' "$BOOTSTRAP_SCRIPT" \
    || fail_test "bootstrap is not pinned to the v0.3.0 release tag"
posix_shell="$(command -v dash || command -v sh)"
CDSI_BOOTSTRAP_SOURCE_ONLY=true "$posix_shell" -c '
    . "$1"
    CDSI_BOOTSTRAP_DIR=/opt/cdsi-anchor
    bootstrap_validate_settings
    bootstrap_retry true
    bootstrap_repository_allowed https://gitee.com/cdsi/anchor.git
' sh "$BOOTSTRAP_SCRIPT" \
    || fail_test "bootstrap.sh core functions do not run under dash"

root_sudo_marker="${fixture_dir}/root-used-sudo"
(
    id() { printf '%s\n' 0; }
    bootstrap_sudo_available() {
        : > "$root_sudo_marker"
        return 0
    }
    bootstrap_require_root --no-start
)
[[ ! -e "$root_sudo_marker" ]] \
    || fail_test "root bootstrap unexpectedly invoked sudo"

help_root_marker="${fixture_dir}/help-requested-root"
(
    bootstrap_require_root() {
        : > "$help_root_marker"
        return 1
    }
    bootstrap_main --help >/dev/null
)
[[ ! -e "$help_root_marker" ]] \
    || fail_test "bootstrap --help unexpectedly requested root privileges"

sudo_log="${fixture_dir}/sudo.log"
if (
    id() { printf '%s\n' 1000; }
    bootstrap_sudo_available() { return 0; }
    bootstrap_escalate() {
        printf '%s\n' "$*" > "$sudo_log"
        return 73
    }
    bootstrap_require_root --dir /opt/custom-anchor --no-start
) >/dev/null 2>&1; then
    fail_test "non-root bootstrap continued after a failed sudo re-exec"
fi
grep -Fq -- '--dir /opt/custom-anchor --no-start' "$sudo_log" \
    || fail_test "sudo re-exec did not preserve bootstrap arguments"

write_os_release() {
    local path="$1"
    local id="$2"
    local version="$3"
    local name="$4"
    cat > "$path" <<EOF
ID="$id"
VERSION_ID="$version"
NAME="$name"
EOF
}

assert_platform() {
    local id="$1"
    local version="$2"
    local name="$3"
    local expected="$4"
    local os_file="${fixture_dir}/os-${id}-${version}"
    write_os_release "$os_file" "$id" "$version" "$name"
    (
        CDSI_BOOTSTRAP_OS_RELEASE_FILE="$os_file"
        CDSI_BOOTSTRAP_ARCH_OVERRIDE="x86_64"
        bootstrap_detect_platform
        assert_equal "$expected" "$CDSI_BOOTSTRAP_PLATFORM" \
            "unexpected package backend for ${name} ${version}"
    )
}

assert_platform ubuntu 24.04 Ubuntu apt
assert_platform ubuntu 26.04 Ubuntu apt
assert_platform debian 13 Debian apt
assert_platform centos 10 "CentOS Stream" dnf

unsupported_os="${fixture_dir}/os-debian-12"
write_os_release "$unsupported_os" debian 12 Debian
if (
    CDSI_BOOTSTRAP_OS_RELEASE_FILE="$unsupported_os"
    CDSI_BOOTSTRAP_ARCH_OVERRIDE="x86_64"
    bootstrap_detect_platform
) >/dev/null 2>&1; then
    fail_test "Debian 12 unexpectedly passed bootstrap platform detection"
fi
if (
    CDSI_BOOTSTRAP_OS_RELEASE_FILE="$unsupported_os"
    CDSI_BOOTSTRAP_ARCH_OVERRIDE="riscv64"
    bootstrap_detect_platform
) >/dev/null 2>&1; then
    fail_test "unsupported platform and architecture unexpectedly passed"
fi

supported_os="${fixture_dir}/os-debian-13"
write_os_release "$supported_os" debian 13 Debian
if (
    CDSI_BOOTSTRAP_OS_RELEASE_FILE="$supported_os"
    CDSI_BOOTSTRAP_ARCH_OVERRIDE="riscv64"
    bootstrap_detect_platform
) >/dev/null 2>&1; then
    fail_test "unsupported architecture unexpectedly passed bootstrap detection"
fi

if (
    bootstrap_systemd_ready() { return 0; }
    bootstrap_has_tty() { return 1; }
    CDSI_BOOTSTRAP_START_INSTALLER=true
    bootstrap_preflight
) >/dev/null 2>&1; then
    fail_test "bootstrap preflight accepted an installer run without a TTY"
fi
(
    bootstrap_systemd_ready() { return 0; }
    bootstrap_has_tty() { return 1; }
    CDSI_BOOTSTRAP_START_INSTALLER=false
    bootstrap_preflight >/dev/null \
        || fail_test "--no-start bootstrap unexpectedly required a TTY"
)

command_log="${fixture_dir}/package-commands.log"
export CDSI_BOOTSTRAP_COMMAND_LOG="$command_log"

bootstrap_apt_available() { return 0; }
bootstrap_apt_get() {
    printf 'apt-get %s\n' "$*" >> "$CDSI_BOOTSTRAP_COMMAND_LOG"
}
bootstrap_dnf_available() { return 0; }
bootstrap_dnf() {
    printf 'dnf %s\n' "$*" >> "$CDSI_BOOTSTRAP_COMMAND_LOG"
}

: > "$command_log"
CDSI_BOOTSTRAP_PLATFORM=apt
CDSI_BOOTSTRAP_OS=debian
bootstrap_prepare_apt >/dev/null
assert_equal "2" "$(wc -l < "$command_log" | tr -d '[:space:]')" \
    "APT bootstrap must run exactly metadata refresh and package installation"
grep -Fq \
    'apt-get -o DPkg::Lock::Timeout=120 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update' \
    "$command_log" || fail_test "APT bootstrap does not refresh package indexes safely"
grep -Fq \
    'install -y --no-install-recommends bash ca-certificates coreutils curl git' \
    "$command_log" || fail_test "APT bootstrap tool set is incomplete"

: > "$command_log"
CDSI_BOOTSTRAP_PLATFORM=dnf
CDSI_BOOTSTRAP_OS=centos
bootstrap_prepare_dnf >/dev/null
assert_equal "2" "$(wc -l < "$command_log" | tr -d '[:space:]')" \
    "DNF bootstrap must run exactly metadata refresh and package installation"
grep -Fq 'makecache --refresh' "$command_log" \
    || fail_test "DNF bootstrap does not refresh repository metadata"
grep -Fq 'install bash ca-certificates coreutils curl git' "$command_log" \
    || fail_test "DNF bootstrap tool set is incomplete"
if grep -Eiq 'epel|remi|(^| )update( |$)|(^| )upgrade( |$)' "$command_log"; then
    fail_test "bootstrap must not enable third-party repositories or upgrade the system"
fi
grep -Fq 'timeout --foreground "$CDSI_BOOTSTRAP_PACKAGE_TIMEOUT"' \
    "$BOOTSTRAP_SCRIPT" \
    || fail_test "bootstrap package operations do not have a total timeout"

retry_calls=0
retry_probe() {
    retry_calls=$((retry_calls + 1))
    [[ "$retry_calls" -ge 3 ]]
}
CDSI_BOOTSTRAP_RETRY_ATTEMPTS=3
CDSI_BOOTSTRAP_RETRY_DELAY=0
bootstrap_retry retry_probe 2>/dev/null \
    || fail_test "bounded bootstrap retry did not recover"
assert_equal "3" "$retry_calls" "bootstrap retry count changed"

if (
    CDSI_BOOTSTRAP_DIR="/"
    bootstrap_validate_settings
) >/dev/null 2>&1; then
    fail_test "bootstrap accepted the filesystem root as its checkout"
fi
if (
    CDSI_BOOTSTRAP_DIR="relative/path"
    bootstrap_validate_settings
) >/dev/null 2>&1; then
    fail_test "bootstrap accepted a relative checkout path"
fi
if (
    CDSI_BOOTSTRAP_DIR="/opt/cdsi-anchor"
    CDSI_BOOTSTRAP_RETRY_ATTEMPTS=0
    bootstrap_validate_settings
) >/dev/null 2>&1; then
    fail_test "bootstrap accepted a zero retry budget"
fi
if (
    bootstrap_git() { printf '%s\n' commit; }
    bootstrap_release_tag_valid /tmp/anchor
) >/dev/null 2>&1; then
    fail_test "bootstrap accepted a lightweight release tag"
fi

clone_parent="${fixture_dir}/clone-fallback"
clone_target="${clone_parent}/anchor"
clone_log="${fixture_dir}/clone.log"
mkdir -p "$clone_parent"
(
    CDSI_BOOTSTRAP_DIR="$clone_target"
    CDSI_BOOTSTRAP_TEMP_DIR=""
    CDSI_BOOTSTRAP_TEMP_PARENT=""
    bootstrap_git() {
        printf '%s\n' "$*" >> "$clone_log"
        if [[ "$1" == clone ]]; then
            local repository="$3"
            local target="$4"
            mkdir -p "$target/.git" "$target/lib"
            printf '%s\n' "$repository" > "$target/.mock-repository"
            : > "$target/bootstrap.sh"
            : > "$target/install.sh"
            : > "$target/lib/bootstrap.sh"
            return 0
        fi
        if [[ "$*" == *'cat-file -t refs/tags/'* ]]; then
            if [[ "$(<"$2/.mock-repository")" == "$CDSI_BOOTSTRAP_GITEE_REPOSITORY" ]]; then
                printf '%s\n' commit
            else
                printf '%s\n' tag
            fi
        fi
        if [[ "$*" == *'rev-parse --verify HEAD'* ]]; then
            printf '%s\n' '0123456789abcdef'
        fi
        return 0
    }
    bootstrap_clone_checkout >/dev/null 2>&1
)
[[ -f "$clone_target/install.sh" ]] \
    || fail_test "GitHub fallback did not activate the Anchor checkout"
grep -Fq "$CDSI_BOOTSTRAP_GITEE_REPOSITORY" "$clone_log" \
    || fail_test "bootstrap did not try Gitee first"
grep -Fq "$CDSI_BOOTSTRAP_GITHUB_REPOSITORY" "$clone_log" \
    || fail_test "bootstrap did not fall back to GitHub"
grep -Fq 'cat-file -t refs/tags/v0.3.0' "$clone_log" \
    || fail_test "bootstrap did not validate the release before accepting a mirror"

failed_parent="${fixture_dir}/clone-failed"
failed_target="${failed_parent}/anchor"
mkdir -p "$failed_parent"
if (
    CDSI_BOOTSTRAP_DIR="$failed_target"
    CDSI_BOOTSTRAP_TEMP_DIR=""
    CDSI_BOOTSTRAP_TEMP_PARENT=""
    bootstrap_git() { return 1; }
    bootstrap_clone_checkout
) >/dev/null 2>&1; then
    fail_test "bootstrap clone unexpectedly succeeded when both mirrors failed"
fi
[[ ! -e "$failed_target" ]] \
    || fail_test "failed bootstrap clone left a checkout target"
if find "$failed_parent" -maxdepth 1 -name '.anchor-bootstrap.*' -print -quit \
    | grep -q .; then
    fail_test "failed bootstrap clone retained a staging directory"
fi

conflict_target="${fixture_dir}/existing-directory"
mkdir -p "$conflict_target"
: > "${conflict_target}/keep.txt"
if (
    CDSI_BOOTSTRAP_DIR="$conflict_target"
    bootstrap_prepare_checkout
) >/dev/null 2>&1; then
    fail_test "bootstrap accepted an existing non-Git directory"
fi
[[ -f "${conflict_target}/keep.txt" ]] \
    || fail_test "bootstrap changed an existing non-Git directory"

dirty_target="${fixture_dir}/dirty-checkout"
dirty_fetch_marker="${fixture_dir}/dirty-fetch-called"
mkdir -p "$dirty_target/.git" "$dirty_target/lib"
: > "$dirty_target/bootstrap.sh"
: > "$dirty_target/install.sh"
: > "$dirty_target/lib/bootstrap.sh"
: > "$dirty_target/keep.txt"
if (
    CDSI_BOOTSTRAP_DIR="$dirty_target"
    bootstrap_git() {
        case "$*" in
            *'remote get-url origin'*)
                printf '%s\n' "$CDSI_BOOTSTRAP_GITEE_REPOSITORY"
                ;;
            *'config --bool --get anchor.bootstrapManaged'*)
                printf '%s\n' true
                ;;
            *'symbolic-ref --quiet --short HEAD'*)
                printf '%s\n' anchor-bootstrap
                ;;
            *'status --porcelain'*)
                printf '%s\n' ' M README.md'
                ;;
            *' fetch '*)
                : > "$dirty_fetch_marker"
                ;;
        esac
        return 0
    }
    bootstrap_update_checkout
) >/dev/null 2>&1; then
    fail_test "bootstrap updated a checkout with local changes"
fi
[[ ! -e "$dirty_fetch_marker" ]] \
    || fail_test "bootstrap fetched before rejecting a dirty checkout"
[[ -f "$dirty_target/keep.txt" ]] \
    || fail_test "bootstrap changed a dirty checkout"

unknown_target="${fixture_dir}/unknown-origin"
mkdir -p "$unknown_target/.git" "$unknown_target/lib"
: > "$unknown_target/bootstrap.sh"
: > "$unknown_target/install.sh"
: > "$unknown_target/lib/bootstrap.sh"
if (
    CDSI_BOOTSTRAP_DIR="$unknown_target"
    bootstrap_git() {
        if [[ "$*" == *'remote get-url origin'* ]]; then
            printf '%s\n' 'https://example.com/untrusted/anchor.git'
        fi
        return 0
    }
    bootstrap_update_checkout
) >/dev/null 2>&1; then
    fail_test "bootstrap accepted an unknown checkout origin"
fi

invalid_fetch_merge_marker="${fixture_dir}/invalid-fetch-merged"
(
    CDSI_BOOTSTRAP_DIR="$dirty_target"
    bootstrap_git() {
        if [[ "$*" == *' merge --ff-only refs/cdsi-anchor/'* ]]; then
            : > "$invalid_fetch_merge_marker"
        fi
        return 0
    }
    bootstrap_release_tag_valid() { return 0; }
    bootstrap_commit_valid() { return 1; }
    if bootstrap_fetch_checkout "$CDSI_BOOTSTRAP_GITEE_REPOSITORY" \
        >/dev/null 2>&1; then
        fail_test "invalid fetched release unexpectedly succeeded"
    else
        assert_equal "2" "$?" "invalid fetched release status changed"
    fi
)
[[ ! -e "$invalid_fetch_merge_marker" ]] \
    || fail_test "bootstrap modified the checkout before validating the fetched release"

valid_fetch_merge_marker="${fixture_dir}/valid-fetch-merged"
(
    CDSI_BOOTSTRAP_DIR="$dirty_target"
    bootstrap_git() {
        if [[ "$*" == *' merge --ff-only refs/cdsi-anchor/'* ]]; then
            : > "$valid_fetch_merge_marker"
        fi
        return 0
    }
    bootstrap_release_tag_valid() { return 0; }
    bootstrap_commit_valid() { return 0; }
    bootstrap_fetch_checkout "$CDSI_BOOTSTRAP_GITEE_REPOSITORY"
)
[[ -e "$valid_fetch_merge_marker" ]] \
    || fail_test "validated fetched release was not fast-forwarded"

fallback_update_log="${fixture_dir}/fallback-update.log"
fallback_update_merge_marker="${fixture_dir}/fallback-update-merged"
(
    CDSI_BOOTSTRAP_DIR="$dirty_target"
    last_fetch_repository=""
    bootstrap_git() {
        printf '%s\n' "$*" >> "$fallback_update_log"
        case "$*" in
            *'remote get-url origin'*)
                printf '%s\n' "$CDSI_BOOTSTRAP_GITEE_REPOSITORY"
                ;;
            *'config --bool --get anchor.bootstrapManaged'*)
                printf '%s\n' true
                ;;
            *'symbolic-ref --quiet --short HEAD'*)
                printf '%s\n' anchor-bootstrap
                ;;
            *'status --porcelain'*)
                ;;
            *'fetch --no-tags'*)
                if [[ "$*" == *"$CDSI_BOOTSTRAP_GITEE_REPOSITORY"* ]]; then
                    last_fetch_repository="$CDSI_BOOTSTRAP_GITEE_REPOSITORY"
                else
                    last_fetch_repository="$CDSI_BOOTSTRAP_GITHUB_REPOSITORY"
                fi
                ;;
            *'merge --ff-only refs/cdsi-anchor/'*)
                : > "$fallback_update_merge_marker"
                ;;
        esac
        return 0
    }
    bootstrap_release_tag_valid() { return 0; }
    bootstrap_commit_valid() {
        [[ "$last_fetch_repository" == "$CDSI_BOOTSTRAP_GITHUB_REPOSITORY" ]]
    }
    bootstrap_update_checkout >/dev/null 2>&1
)
[[ -e "$fallback_update_merge_marker" ]] \
    || fail_test "update did not accept the validated fallback release"
grep -Fq "$CDSI_BOOTSTRAP_GITEE_REPOSITORY" "$fallback_update_log" \
    || fail_test "update did not try its configured Gitee origin"
grep -Fq "$CDSI_BOOTSTRAP_GITHUB_REPOSITORY" "$fallback_update_log" \
    || fail_test "update did not try GitHub after invalid Gitee content"
grep -Fq \
    'refs/tags/v0.3.0:refs/cdsi-anchor/bootstrap-candidate' \
    "$fallback_update_log" \
    || fail_test "update fetched a candidate directly into the canonical tag ref"
grep -Fq 'update-ref --no-deref -d refs/cdsi-anchor/bootstrap-candidate' \
    "$fallback_update_log" \
    || fail_test "candidate ref cleanup could dereference a symbolic ref"

release_source="${fixture_dir}/release-source"
release_target="${fixture_dir}/release-target"
mkdir -p "$release_source/lib"
git -C "$release_source" init -q --initial-branch=master
git -C "$release_source" config user.name "Anchor Bootstrap Test"
git -C "$release_source" config user.email "anchor-bootstrap@example.invalid"
cp "$BOOTSTRAP_SCRIPT" "$release_source/bootstrap.sh"
cat > "$release_source/install.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
EOF
cat > "$release_source/lib/bootstrap.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
git -C "$release_source" add bootstrap.sh install.sh lib/bootstrap.sh
git -C "$release_source" commit -q -m "release fixture v0.3.0"
git -C "$release_source" tag -a v0.3.0 -m "release fixture v0.3.0"
(
    CDSI_BOOTSTRAP_GITEE_REPOSITORY="$release_source"
    CDSI_BOOTSTRAP_GITHUB_REPOSITORY="$release_source"
    CDSI_BOOTSTRAP_REF="v0.3.0"
    CDSI_BOOTSTRAP_DIR="$release_target"
    CDSI_BOOTSTRAP_TEMP_DIR=""
    CDSI_BOOTSTRAP_TEMP_PARENT=""
    bootstrap_clone_checkout >/dev/null
)
assert_equal "anchor-bootstrap" \
    "$(git -C "$release_target" symbolic-ref --short HEAD)" \
    "real release clone did not create the managed branch"
assert_equal "true" \
    "$(git -C "$release_target" config --bool --get anchor.bootstrapManaged)" \
    "real release clone did not record bootstrap ownership"
assert_equal "$(git -C "$release_source" rev-parse 'v0.3.0^{commit}')" \
    "$(git -C "$release_target" rev-parse HEAD)" \
    "real release clone did not pin the annotated tag"

: > "$release_source/release-marker"
git -C "$release_source" add release-marker
git -C "$release_source" commit -q -m "release fixture v0.3.1"
git -C "$release_source" tag -a v0.3.1 -m "release fixture v0.3.1"
(
    CDSI_BOOTSTRAP_GITEE_REPOSITORY="$release_source"
    CDSI_BOOTSTRAP_GITHUB_REPOSITORY="$release_source"
    CDSI_BOOTSTRAP_REF="v0.3.1"
    CDSI_BOOTSTRAP_DIR="$release_target"
    bootstrap_update_checkout >/dev/null
)
assert_equal "$(git -C "$release_source" rev-parse 'v0.3.1^{commit}')" \
    "$(git -C "$release_target" rev-parse HEAD)" \
    "validated release did not fast-forward the managed checkout"
[[ -f "$release_target/release-marker" ]] \
    || fail_test "fast-forwarded release content is missing"

handoff_dir="${fixture_dir}/handoff"
handoff_log="${fixture_dir}/handoff.log"
mkdir -p "$handoff_dir"
: > "$handoff_dir/install.sh"
set +e
(
    CDSI_BOOTSTRAP_DIR="$handoff_dir"
    bootstrap_stdin_is_tty() { return 0; }
    bootstrap_exec_installer() {
        printf '%s\n' "$PWD" >> "$handoff_log"
        return 37
    }
    bootstrap_start_installer >/dev/null
)
handoff_status=$?
set -e
assert_equal "37" "$handoff_status" "installer exit status was not preserved"
assert_equal "1" "$(wc -l < "$handoff_log" | tr -d '[:space:]')" \
    "bootstrap invoked install.sh more than once"
assert_equal "$handoff_dir" "$(tr -d '\r\n' < "$handoff_log")" \
    "bootstrap did not enter the Anchor checkout before handoff"

if grep -Eq 'reset[[:space:]]+--hard|checkout[[:space:]]+-f' "$BOOTSTRAP_SCRIPT"; then
    fail_test "bootstrap contains a destructive Git update"
fi
grep -Fq 'merge --ff-only' "$BOOTSTRAP_SCRIPT" \
    || fail_test "existing bootstrap checkout is not updated with fast-forward only"
grep -Fq 'bootstrap_exec_installer </dev/tty' "$BOOTSTRAP_SCRIPT" \
    || fail_test "piped bootstrap does not restore the interactive terminal"

printf 'PASS: remote bootstrap platform, package, mirror, and checkout safety contracts\n'
