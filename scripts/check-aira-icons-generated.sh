#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NODE_BIN="${NODE_BIN:-node}"

"${NODE_BIN}" "${REPO_ROOT}/scripts/check-aira-icon-catalog.js"
"${NODE_BIN}" "${REPO_ROOT}/scripts/generate-aira-icons-from-source.js" --check
"${NODE_BIN}" "${REPO_ROOT}/scripts/check-aira-icon-groups.js"
