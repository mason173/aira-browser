#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${HDC_BIN:-}" ]; then
  HDC_BIN="$(command -v hdc 2>/dev/null || true)"
fi
if [ -z "${HDC_BIN}" ]; then
  DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
  HDC_BIN="${DEVECO_SDK_HOME}/default/openharmony/toolchains/hdc"
fi

if [ -z "${HDC_TARGET:-}" ] && [ -x "${HDC_BIN}" ]; then
  USB_TARGETS="$("${HDC_BIN}" list targets -v 2>/dev/null |
    awk '$2 == "USB" && $3 == "Connected" { print $1 }' |
    sed '/^[[:space:]]*$/d')"
  USB_TARGET_COUNT="$(printf '%s\n' "${USB_TARGETS}" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  if [ "${USB_TARGET_COUNT}" = "1" ]; then
    export HDC_TARGET="$(printf '%s\n' "${USB_TARGETS}" | sed -n '1p')"
    echo "Auto-selected USB install target: ${HDC_TARGET}"
  fi
fi

exec "${SCRIPT_DIR}/build-aira-browser.sh"
