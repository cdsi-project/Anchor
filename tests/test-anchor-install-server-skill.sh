#!/usr/bin/env bash

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="${TEST_ROOT}/.agents/skills/anchor-install-server"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
RUNBOOK_FILE="${SKILL_DIR}/references/install-runbook.md"
OPENAI_FILE="${SKILL_DIR}/agents/openai.yaml"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for required_file in "$SKILL_FILE" "$RUNBOOK_FILE" "$OPENAI_FILE"; do
    [[ -f "$required_file" ]] \
        || fail_test "missing Anchor install skill file: ${required_file}"
done

grep -Fqx 'name: anchor-install-server' "$SKILL_FILE" \
    || fail_test "skill frontmatter name is missing"
grep -Fq 'display_name: "Anchor Server Installer"' "$OPENAI_FILE" \
    || fail_test "skill UI metadata is missing"
grep -Fq 'Use $anchor-install-server' "$OPENAI_FILE" \
    || fail_test "default prompt does not explicitly invoke the skill"
grep -Fq 'password already exposed in chat' "$RUNBOOK_FILE" \
    || fail_test "skill does not reject a password exposed in chat"
grep -Fq 'cannot waive this clean-server gate' "$RUNBOOK_FILE" \
    || fail_test "skill allows confirmation to override the clean-server gate"
grep -Fq '`partially completed` when the base node passes local checks' \
    "$SKILL_FILE" \
    || fail_test "skill does not classify failed public reachability"

skill_release="$(
    sed -n 's/^ANCHOR_RELEASE=\([^[:space:]]*\)$/\1/p' "$RUNBOOK_FILE"
)"
skill_commit="$(
    sed -n 's/^ANCHOR_RELEASE_COMMIT=\([0-9a-f]*\)$/\1/p' "$RUNBOOK_FILE"
)"
skill_bootstrap_sha256="$(
    sed -n 's/^ANCHOR_BOOTSTRAP_SHA256=\([0-9a-f]*\)$/\1/p' "$RUNBOOK_FILE"
)"
bootstrap_release="$(
    sed -n 's/^CDSI_BOOTSTRAP_REF="\([^"]*\)"$/\1/p' \
        "${TEST_ROOT}/bootstrap.sh"
)"
installer_version="$(
    sed -n 's/^readonly CDSI_VERSION="\([^"]*\)"$/\1/p' \
        "${TEST_ROOT}/lib/common.sh"
)"

[[ "$skill_release" == "$bootstrap_release" ]] \
    || fail_test "skill release and bootstrap release diverged"
[[ "$skill_release" == "v${installer_version}" ]] \
    || fail_test "skill release and installer version diverged"
[[ "$skill_commit" =~ ^[0-9a-f]{40}$ ]] \
    || fail_test "skill release commit is not a full Git object ID"
[[ "$skill_bootstrap_sha256" =~ ^[0-9a-f]{64}$ ]] \
    || fail_test "skill bootstrap SHA-256 is invalid"
[[ "$(sha256sum "${TEST_ROOT}/bootstrap.sh" | awk '{print $1}')" \
    == "$skill_bootstrap_sha256" ]] \
    || fail_test "skill bootstrap SHA-256 does not match bootstrap.sh"

if [[ -d "${TEST_ROOT}/.git" ]]; then
    [[ "$(git -C "$TEST_ROOT" rev-parse "${skill_release}^{commit}")" \
        == "$skill_commit" ]] \
        || fail_test "skill release commit does not match the pinned tag"
fi

grep -Fq 'bash scripts/install-nginx.sh' "$RUNBOOK_FILE" \
    && grep -Fq 'bash scripts/install-mysql.sh >/dev/null' "$RUNBOOK_FILE" \
    && grep -Fq 'bash scripts/install-php.sh' "$RUNBOOK_FILE" \
    && grep -Fq 'CDSI_INSTALL_CONTEXT=all CDSI_SERVER_IP=' "$RUNBOOK_FILE" \
    && grep -Fq 'bash scripts/install-wordpress.sh >/dev/null' "$RUNBOOK_FILE" \
    || fail_test "skill does not preserve the non-interactive base install order"

if grep -Eiq 'raw/(main|master)/|refs/heads/(main|master)' \
    "$SKILL_FILE" "$RUNBOOK_FILE"; then
    fail_test "skill references a mutable bootstrap branch"
fi
if grep -Eiq '(curl|wget)[^|]*\|[[:space:]]*(ba)?sh' "$RUNBOOK_FILE"; then
    fail_test "skill pipes network content directly to a shell"
fi
grep -Fq 'set -eu' "$RUNBOOK_FILE" \
    && grep -Fq '| sha256sum -c -' "$RUNBOOK_FILE" \
    || fail_test "bootstrap verification is not fail-closed"
if grep -Eiq 'uninstall\.sh[[:space:]]+(--yes|-y)|reset[[:space:]]+--hard' \
    "$SKILL_FILE" "$RUNBOOK_FILE"; then
    fail_test "skill contains a destructive automatic recovery path"
fi

printf 'PASS: Anchor install skill release, security, and orchestration contracts\n'
