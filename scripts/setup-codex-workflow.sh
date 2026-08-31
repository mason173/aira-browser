#!/usr/bin/env bash
# Check and explain the repo-local Codex workflow setup on a new machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

color() {
  local code="$1"
  shift
  printf '\033[%sm%s\033[0m\n' "${code}" "$*"
}

info() {
  color "36" "$*"
}

ok() {
  color "32" "$*"
}

warn() {
  color "33" "$*"
}

fail() {
  color "31" "$*"
}

missing=0

require_path() {
  local path="$1"
  local description="$2"
  if [[ -e "${REPO_ROOT}/${path}" ]]; then
    ok "OK: ${description} (${path})"
  else
    fail "缺少: ${description} (${path})"
    missing=$((missing + 1))
  fi
}

resolve_codex() {
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi

  local app_codex="/Applications/Codex.app/Contents/Resources/codex"
  if [[ -x "${app_codex}" ]]; then
    printf '%s\n' "${app_codex}"
    return 0
  fi

  return 1
}

check_hook_event() {
  local event="$1"
  if grep -q "\"${event}\"" "${REPO_ROOT}/.codex/hooks.json" 2>/dev/null; then
    ok "OK: hook event ${event}"
  else
    fail "缺少 hook event: ${event}"
    missing=$((missing + 1))
  fi
}

cd "${REPO_ROOT}"

info "Aira Codex workflow setup check"
echo "Repo: ${REPO_ROOT}"
echo

require_path "AGENTS.md" "repo agent rules"
require_path ".codex/hooks.json" "project Codex hooks config"
require_path ".codex/hooks" "project Codex hook scripts"
require_path ".codex/skills/harmonyos-native/SKILL.md" "Aira HarmonyOS native skill"
require_path ".codex/skills/planning-with-files/SKILL.md" "planning-with-files skill"
require_path ".codex/skills/planning-with-files/SOURCE.md" "planning-with-files source note"

if [[ -f "${REPO_ROOT}/.codex/hooks.json" ]]; then
  echo
  info "Checking expected hook events"
  for event in SessionStart UserPromptSubmit PreToolUse PermissionRequest PostToolUse PreCompact Stop; do
    check_hook_event "${event}"
  done
fi

echo
if codex_bin="$(resolve_codex)"; then
  ok "OK: Codex CLI found: ${codex_bin}"
  if "${codex_bin}" features list 2>/dev/null | awk '$1 == "hooks" && $3 == "true" { found = 1 } END { exit found ? 0 : 1 }'; then
    ok "OK: Codex hooks feature is enabled"
  else
    warn "Codex CLI is present, but 'hooks true' was not detected from 'features list'."
    warn "Update Codex if hooks do not appear in the /hooks UI."
  fi
else
  warn "没有找到 codex 命令。安装/打开 Codex 桌面客户端后再运行本脚本。"
  codex_bin="codex"
fi

echo
if [[ "${missing}" -eq 0 ]]; then
  ok "Repo workflow files look ready."
else
  fail "发现 ${missing} 个缺失项。先 git pull/同步完整仓库，再重新运行本脚本。"
  exit 1
fi

cat <<EOF

下一步（每台电脑只需要做一次）：

1. 进入本仓库：
   cd "${REPO_ROOT}"

2. 打开 Codex CLI：
   "${codex_bin}"

3. 在 Codex 里输入：
   /hooks

4. Review hooks，然后 Trust all / 开启 7 个 hooks：
   SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest,
   PostToolUse, PreCompact, Stop

说明：
- .codex/ 和 AGENTS.md 跟随仓库同步；另一台电脑 git pull 后就有能力本体。
- hooks 的信任状态是每台电脑本地保存的，不能也不应该由脚本强行绕过。
- .planning/ 是本机任务草稿目录，已被 .gitignore 忽略，不会自动同步到其他电脑。
EOF
