#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "${AIRA_FAKE_HDC_MODE:-0}" = '1' ]; then
  state_file="${AIRA_FAKE_HDC_STATE_FILE:?missing fake HDC state file}"
  command_line="$*"
  case "${command_line}" in
    *"param get const.product.name"*|*"param get const.product.model"*)
      echo "${AIRA_FAKE_HDC_DEVICE_NAME:-Emulator}"
      ;;
    *"hilog -r"*)
      printf '0\n' > "${state_file}"
      ;;
    *"hilog -x"*)
      poll_count="$(sed -n '1p' "${state_file}")"
      poll_count=$((poll_count + 1))
      printf '%s\n' "${poll_count}" > "${state_file}"
      case "${poll_count}" in
        1)
          echo '[BROWSING-IDENTITY-DIAG] policy tab=tab-test host=shengxuxu.info winner=applicable_default identity=aira_default presentation=mobile uaMode=known_preset hints=known_metadata private=0'
          echo '[BROWSING-IDENTITY-DIAG] prepare tab=tab-test tx=1 kind=app_load winner=applicable_default identity=aira_default presentation=mobile status=unchanged'
          ;;
        2)
          if [ "${AIRA_FAKE_HDC_INCLUDE_PROMPT:-1}" = '1' ]; then
            echo 'WebCapabilityPrompt: https-first fallback presented tab=tab-test attempt=1'
            echo 'WebCapabilityPrompt: https-first fallback confirmed tab=tab-test attempt=1'
          fi
          ;;
        *)
          echo 'page_end url=http://m.shengxuxu.info/'
          ;;
      esac
      ;;
    *)
      ;;
  esac
  exit 0
fi

state_file="$(mktemp "${TMPDIR:-/tmp}/aira-mobile-presentation-hdc.XXXXXX")"
trap 'rm -f "${state_file}"' EXIT HUP INT TERM
printf '0\n' > "${state_file}"

run_device_case() {
  selected_case="$1"
  include_prompt="$2"
  AIRA_FAKE_HDC_MODE=1 \
  AIRA_FAKE_HDC_STATE_FILE="${state_file}" \
  AIRA_FAKE_HDC_INCLUDE_PROMPT="${include_prompt}" \
  AIRA_TEST_ONLY_CASE="${selected_case}" \
  AIRA_TEST_POLL_INTERVAL_SECONDS=0 \
  AIRA_TEST_RESET_APP_DATA=0 \
  HDC_BIN="${SCRIPT_DIR}/test-aira-mobile-presentation-device-script.sh" \
  HDC_TARGET='127.0.0.1:5555' \
    "${SCRIPT_DIR}/test-aira-mobile-presentation-device.sh"
}

output=''
if ! output="$(run_device_case 'root-first-confirmation' 1 2>&1)"; then
  printf '%s\n' "${output}" >&2
  echo 'FAIL device script did not retain evidence across hilog polls.' >&2
  exit 1
fi

printf '%s\n' "${output}" | rg -q '^PASS root-first-confirmation$'
if printf '%s\n' "${output}" | rg -q '^===== (www|mobile|dawenks|xinhua)-'; then
  echo 'FAIL focused device-script run executed an unselected case.' >&2
  exit 1
fi

output=''
if ! output="$(run_device_case 'root-exact-host-after-restart' 0 2>&1)"; then
  printf '%s\n' "${output}" >&2
  echo 'FAIL device script rejected a remembered-HTTP trace without a prompt.' >&2
  exit 1
fi
printf '%s\n' "${output}" | rg -q '^PASS root-exact-host-after-restart$'

if output="$(run_device_case 'not-a-real-case' 0 2>&1)"; then
  printf '%s\n' "${output}" >&2
  echo 'FAIL device script accepted an unknown focused case.' >&2
  exit 1
fi
printf '%s\n' "${output}" | rg -q '^FAIL unknown mobile-presentation case: not-a-real-case$'

if output="$(AIRA_FAKE_HDC_DEVICE_NAME='PhysicalPhone' run_device_case \
  'root-first-confirmation' 1 2>&1)"; then
  printf '%s\n' "${output}" >&2
  echo 'FAIL device script accepted a non-emulator target.' >&2
  exit 1
fi
printf '%s\n' "${output}" | rg -q '^Refusing to run: target 127.0.0.1:5555 is not an emulator\.$'

echo 'PASS mobile-presentation device script feedback loop'
