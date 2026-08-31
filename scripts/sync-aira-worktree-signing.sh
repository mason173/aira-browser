#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="${1:-}"
WORKTREE_PATH="${2:-}"
BUNDLE_NAME="${3:-}"

DEVECO_APP="/Applications/DevEco-Studio.app"
NODE_BIN="${DEVECO_APP}/Contents/tools/node/bin/node"
JAVA_BIN="${DEVECO_APP}/Contents/jbr/Contents/Home/bin/java"
SIGN_TOOL_JAR="${DEVECO_APP}/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"

fail() {
  echo "$1" >&2
  exit 1
}

[ -n "${SOURCE_REPO}" ] || fail "Usage: $0 /path/to/source-repo /path/to/worktree bundle.name"
[ -n "${WORKTREE_PATH}" ] || fail "Missing worktree path."
[ -n "${BUNDLE_NAME}" ] || fail "Missing bundle name."
[ -x "${NODE_BIN}" ] || fail "DevEco Node not found: ${NODE_BIN}"
[ -x "${JAVA_BIN}" ] || fail "DevEco Java not found: ${JAVA_BIN}"
[ -f "${SIGN_TOOL_JAR}" ] || fail "hap-sign-tool not found: ${SIGN_TOOL_JAR}"

TARGET_PROFILE="${WORKTREE_PATH}/AiraBrowser/build-profile.json5"
TARGET_LOCAL_PROFILE="${WORKTREE_PATH}/AiraBrowser/build-profile.local.json5"

profile_file_for_build_profile() {
  local build_profile="$1"
  "${NODE_BIN}" - "$build_profile" <<'NODE'
const fs = require('fs');
const source = fs.readFileSync(process.argv[2], 'utf8');
const data = new Function(`return (${source});`)();
const material = data.app && data.app.signingConfigs && data.app.signingConfigs[0]
  ? data.app.signingConfigs[0].material
  : undefined;
process.stdout.write((material && material.profile) || '');
NODE
}

bundle_for_p7b() {
  local p7b="$1"
  "${JAVA_BIN}" -jar "${SIGN_TOOL_JAR}" verify-profile -inFile "$p7b" 2>&1 \
    | sed -n 's|.*"bundle-name": "\(.*\)",$|\1|p' \
    | head -n 1
}

build_profile_matches_bundle() {
  local build_profile="$1"
  local p7b
  local bundle

  [ -f "$build_profile" ] || return 1
  p7b="$(profile_file_for_build_profile "$build_profile")"
  [ -n "$p7b" ] || return 1
  [ -f "$p7b" ] || return 1
  bundle="$(bundle_for_p7b "$p7b")"
  [ "$bundle" = "$BUNDLE_NAME" ]
}

select_profile() {
  local candidate

  if [ -n "${AIRA_WORKTREE_BUILD_PROFILE:-}" ]; then
    build_profile_matches_bundle "${AIRA_WORKTREE_BUILD_PROFILE}" \
      || fail "AIRA_WORKTREE_BUILD_PROFILE does not match ${BUNDLE_NAME}: ${AIRA_WORKTREE_BUILD_PROFILE}"
    printf '%s\n' "${AIRA_WORKTREE_BUILD_PROFILE}"
    return 0
  fi

  for candidate in \
    "${SOURCE_REPO}/AiraBrowser/build-profile.local.json5" \
    "${SOURCE_REPO}/AiraBrowser/build-profile.json5"; do
    if build_profile_matches_bundle "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

SELECTED_PROFILE="$(select_profile)" || fail "No build-profile JSON found for ${BUNDLE_NAME}. Open DevEco Signing Configs for this bundle once, or rerun with AIRA_WORKTREE_BUILD_PROFILE=/abs/path/to/build-profile.json5."

mkdir -p "$(dirname "${TARGET_PROFILE}")"
cp "${SELECTED_PROFILE}" "${TARGET_PROFILE}"
rm -f "${TARGET_LOCAL_PROFILE}"
echo "Copied signing build profile for ${BUNDLE_NAME}: ${SELECTED_PROFILE}"
echo "  target: ${TARGET_PROFILE}"
