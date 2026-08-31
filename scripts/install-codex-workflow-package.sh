#!/usr/bin/env bash
# Install the packaged Aira Codex workflow files into an AiraBrowser checkout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_ROOT="${1:-$(pwd)}"

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

usage() {
  cat <<EOF
Usage:
  $0 /path/to/AiraBrowser

If no path is provided, the current directory is used as the target repo.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "${TARGET_ROOT}" ]]; then
  fail "目标目录不存在: ${TARGET_ROOT}"
  usage
  exit 1
fi

SOURCE_ROOT="$(cd "${SOURCE_ROOT}" && pwd)"
TARGET_ROOT="$(cd "${TARGET_ROOT}" && pwd)"

if [[ "${SOURCE_ROOT}" == "${TARGET_ROOT}" ]]; then
  warn "源目录和目标目录相同，不需要安装。"
  exit 0
fi

required_sources=(
  ".codex/hooks.json"
  ".codex/hooks"
  ".codex/skills/planning-with-files/SKILL.md"
  ".codex/skills/harmonyos-native/SKILL.md"
  "AGENTS.md"
  ".gitignore"
  "scripts/setup-codex-workflow.sh"
)

missing=0
for path in "${required_sources[@]}"; do
  if [[ ! -e "${SOURCE_ROOT}/${path}" ]]; then
    fail "安装包缺少: ${path}"
    missing=$((missing + 1))
  fi
done

if [[ "${missing}" -gt 0 ]]; then
  fail "安装包不完整，已停止。"
  exit 1
fi

if [[ ! -f "${TARGET_ROOT}/AGENTS.md" && ! -d "${TARGET_ROOT}/AiraBrowser" ]]; then
  warn "目标目录看起来不像 AiraBrowser 仓库: ${TARGET_ROOT}"
  warn "如果路径正确，可以继续；否则按 Ctrl+C 取消。"
  sleep 3
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="${TARGET_ROOT}/.codex-workflow-backups/${timestamp}"

backup_existing() {
  local path="$1"
  local dst="${TARGET_ROOT}/${path}"
  if [[ -e "${dst}" ]]; then
    mkdir -p "${backup_root}/$(dirname "${path}")"
    cp -R "${dst}" "${backup_root}/${path}"
    ok "已备份: ${path}"
  fi
}

install_path() {
  local path="$1"
  local src="${SOURCE_ROOT}/${path}"
  local dst="${TARGET_ROOT}/${path}"

  backup_existing "${path}"
  rm -rf "${dst}"
  mkdir -p "$(dirname "${dst}")"
  cp -R "${src}" "${dst}"
  ok "已安装: ${path}"
}

info "Installing Aira Codex workflow"
echo "Source: ${SOURCE_ROOT}"
echo "Target: ${TARGET_ROOT}"
echo

paths_to_install=(
  ".codex/hooks.json"
  ".codex/hooks"
  ".codex/skills/planning-with-files"
  ".codex/skills/harmonyos-native"
  "AGENTS.md"
  ".gitignore"
  "scripts/setup-codex-workflow.sh"
  "scripts/install-codex-workflow-package.sh"
)

for path in "${paths_to_install[@]}"; do
  install_path "${path}"
done

chmod +x "${TARGET_ROOT}/scripts/setup-codex-workflow.sh" 2>/dev/null || true
chmod +x "${TARGET_ROOT}/scripts/install-codex-workflow-package.sh" 2>/dev/null || true
find "${TARGET_ROOT}/.codex/hooks" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
find "${TARGET_ROOT}/.codex/skills/planning-with-files/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

echo
ok "安装完成。"
if [[ -d "${backup_root}" ]]; then
  echo "备份目录: ${backup_root}"
fi

echo
info "Running setup check..."
"${TARGET_ROOT}/scripts/setup-codex-workflow.sh"
