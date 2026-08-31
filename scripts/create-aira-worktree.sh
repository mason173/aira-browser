#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORKTREE_PATH="${1:-${HOME}/Desktop/aira-browser-translation}"
BRANCH_NAME="${2:-codex/translation-worktree}"
BASE_REF="${AIRA_WORKTREE_BASE:-main}"
PRODUCTION_BUNDLE_NAME="com.aira.browser"
PRODUCTION_APP_NAME="Aira"

fail() {
  echo "$1" >&2
  exit 1
}

if [ -e "${WORKTREE_PATH}" ]; then
  fail "Worktree path already exists: ${WORKTREE_PATH}"
fi

if git -C "${REPO_ROOT}" show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  git -C "${REPO_ROOT}" worktree add "${WORKTREE_PATH}" "${BRANCH_NAME}"
else
  git -C "${REPO_ROOT}" worktree add -b "${BRANCH_NAME}" "${WORKTREE_PATH}" "${BASE_REF}"
fi

"${REPO_ROOT}/scripts/sync-aira-worktree-signing.sh" "${REPO_ROOT}" "${WORKTREE_PATH}" "${PRODUCTION_BUNDLE_NAME}"

echo
echo "Created Aira worktree:"
echo "  path: ${WORKTREE_PATH}"
echo "  branch: ${BRANCH_NAME}"
echo "  bundleName: ${PRODUCTION_BUNDLE_NAME}"
echo "  appName: ${PRODUCTION_APP_NAME}"
echo
echo "Open this folder in DevEco Studio for parallel development:"
echo "  ${WORKTREE_PATH}/AiraBrowser"
