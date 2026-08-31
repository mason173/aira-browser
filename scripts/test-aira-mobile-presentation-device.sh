#!/bin/sh

set -eu

HDC_BIN="${HDC_BIN:-hdc}"
DEVICE_TARGET="${HDC_TARGET:-127.0.0.1:5555}"
BUNDLE_NAME="com.aira.browser"
ABILITY_NAME="EntryAbility"
DEFAULT_URL="http://shengxuxu.info/"
TRACE_PATTERN='BROWSING-IDENTITY-DIAG|HttpsFirstNav|WebCapabilityPrompt|page_begin url=|page_end url=|shengxuxu\.info'
RESET_APP_DATA="${AIRA_TEST_RESET_APP_DATA:-1}"
ONLY_CASE="${AIRA_TEST_ONLY_CASE:-}"
POLL_INTERVAL_SECONDS="${AIRA_TEST_POLL_INTERVAL_SECONDS:-1}"
selected_case_ran=0

device_name="$(${HDC_BIN} -t "${DEVICE_TARGET}" shell "param get const.product.name" | tr -d '\r' | tr -d ' ')"
device_model="$(${HDC_BIN} -t "${DEVICE_TARGET}" shell "param get const.product.model" | tr -d '\r' | tr -d ' ')"
if ! printf '%s\n%s\n' "${device_name}" "${device_model}" | rg -qi '^emulator$'; then
  echo "Refusing to run: target ${DEVICE_TARGET} is not an emulator." >&2
  exit 2
fi

read_trace() {
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell "hilog -x -t app" | rg "${TRACE_PATTERN}" || true
}

confirm_http_if_needed() {
  if printf '%s\n' "$1" | rg -q 'require_http_confirmation|https-first fallback presented'; then
    ${HDC_BIN} -t "${DEVICE_TARGET}" shell "uitest uiInput keyEvent 2049" >/dev/null
    ${HDC_BIN} -t "${DEVICE_TARGET}" shell "uitest uiInput keyEvent 2049" >/dev/null
    ${HDC_BIN} -t "${DEVICE_TARGET}" shell "uitest uiInput keyEvent 2054" >/dev/null
  fi
}

complete_startup_intro_after_reset() {
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell aa force-stop "${BUNDLE_NAME}" >/dev/null 2>&1 || true
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell "hilog -r" >/dev/null
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell \
    "aa start -a ${ABILITY_NAME} -b ${BUNDLE_NAME}" >/dev/null

  startup_trace=''
  attempt=0
  while [ "${attempt}" -lt 15 ]; do
    sleep 1
    startup_trace="$(${HDC_BIN} -t "${DEVICE_TARGET}" shell "hilog -x")"
    if printf '%s\n' "${startup_trace}" | rg -q \
      'Initial content loaded: app/pages/StartupWelcomeIntroPage'; then
      break
    fi
    attempt=$((attempt + 1))
  done
  if ! printf '%s\n' "${startup_trace}" | rg -q \
    'Initial content loaded: app/pages/StartupWelcomeIntroPage'; then
    echo 'FAIL reset: startup welcome intro was not presented.' >&2
    return 1
  fi

  viewport_line="$(printf '%s\n' "${startup_trace}" | \
    rg 'UpdateViewportConfig Viewport config: size:' | tail -1)"
  viewport_values="$(printf '%s\n' "${viewport_line}" | sed -E \
    's/.*size: \(([0-9]+), ([0-9]+)\).*density: ([0-9.]+).*/\1 \2 \3/')"
  set -- ${viewport_values}
  if [ "$#" -ne 3 ]; then
    echo 'FAIL reset: emulator viewport could not be resolved from startup logs.' >&2
    return 1
  fi
  action_x=$(( $1 / 2 ))
  action_y="$(awk -v height="$2" -v density="$3" \
    'BEGIN { printf "%.0f", height - density * 50 }')"
  step=0
  while [ "${step}" -lt 4 ]; do
    ${HDC_BIN} -t "${DEVICE_TARGET}" shell \
      "uitest uiInput click ${action_x} ${action_y}" >/dev/null
    sleep 1
    step=$((step + 1))
  done
}

run_case() {
  case_name="$1"
  target_url="$2"
  expected_final_pattern="$3"
  prompt_policy="$4"
  max_attempts="${5:-25}"

  ${HDC_BIN} -t "${DEVICE_TARGET}" shell aa force-stop "${BUNDLE_NAME}" >/dev/null 2>&1 || true
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell "hilog -r" >/dev/null
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell \
    "aa start -a ${ABILITY_NAME} -b ${BUNDLE_NAME} -U ${target_url}" >/dev/null

  confirmed=0
  case_trace=''
  latest_trace=''
  attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    sleep "${POLL_INTERVAL_SECONDS}"
    latest_trace="$(read_trace)"
    if [ -n "${latest_trace}" ]; then
      case_trace="$(printf '%s\n%s\n' "${case_trace}" "${latest_trace}" | awk 'NF && !seen[$0]++')"
    fi
    if [ "${confirmed}" -eq 0 ]; then
      confirm_http_if_needed "${latest_trace}"
      if printf '%s\n' "${latest_trace}" | rg -q 'require_http_confirmation|https-first fallback presented'; then
        confirmed=1
      fi
    fi
    if printf '%s\n' "${case_trace}" | rg -q "${expected_final_pattern}"; then
      break
    fi
    attempt=$((attempt + 1))
  done

  echo "===== ${case_name} ====="
  printf '%s\n' "${case_trace}"

  if ! printf '%s\n' "${case_trace}" | rg -q "${expected_final_pattern}"; then
    echo "FAIL ${case_name}: final mobile page was not committed." >&2
    return 1
  fi
  if ! printf '%s\n' "${case_trace}" | rg -q \
    'policy .*winner=applicable_default identity=aira_default presentation=mobile'; then
    echo "FAIL ${case_name}: physical-phone default mobile identity was not selected." >&2
    return 1
  fi
  if ! printf '%s\n' "${case_trace}" | rg -q \
    '(prepare|redirect-reuse) .*identity=aira_default presentation=mobile status=(custom_applied|unchanged)'; then
    echo "FAIL ${case_name}: mobile identity was not applied to the ArkWeb Controller." >&2
    return 1
  fi
  if [ "${prompt_policy}" = 'require' ] && ! printf '%s\n' "${case_trace}" | rg -q \
    'https-first fallback presented'; then
    echo "FAIL ${case_name}: first exact-Host HTTP navigation did not request confirmation." >&2
    return 1
  fi
  if [ "${prompt_policy}" = 'require' ] && ! printf '%s\n' "${case_trace}" | rg -q \
    'https-first fallback confirmed'; then
    echo "FAIL ${case_name}: required HTTP confirmation was not completed." >&2
    return 1
  fi
  if [ "${prompt_policy}" = 'forbid' ] && printf '%s\n' "${case_trace}" | rg -q \
    'https-first fallback presented|require_http_confirmation'; then
    echo "FAIL ${case_name}: remembered HTTP navigation prompted again." >&2
    return 1
  fi
  echo "PASS ${case_name}"
}

run_selected_case() {
  case_name="$1"
  shift
  if [ -n "${ONLY_CASE}" ] && [ "${ONLY_CASE}" != "${case_name}" ]; then
    return 0
  fi
  selected_case_ran=1
  run_case "${case_name}" "$@"
}

echo "Testing Aira mobile presentation on emulator ${DEVICE_TARGET}."
if [ "${RESET_APP_DATA}" = '1' ]; then
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell aa force-stop "${BUNDLE_NAME}" >/dev/null 2>&1 || true
  ${HDC_BIN} -t "${DEVICE_TARGET}" shell bm clean -n "${BUNDLE_NAME}" -d >/dev/null
  echo "Reset Aira app data on emulator ${DEVICE_TARGET}."
  complete_startup_intro_after_reset
fi
run_selected_case 'root-first-confirmation' "${DEFAULT_URL}" 'page_end url=http://m\.shengxuxu\.info/?' 'require'
run_selected_case 'root-exact-host-after-restart' "${DEFAULT_URL}" 'page_end url=http://m\.shengxuxu\.info/?' 'forbid'
run_selected_case 'www-first-confirmation' 'http://www.shengxuxu.info/' \
  'page_end url=http://m\.shengxuxu\.info/?' 'require'
run_selected_case 'www-exact-host-after-restart' 'http://www.shengxuxu.info/' \
  'page_end url=http://m\.shengxuxu\.info/?' 'forbid'
run_selected_case 'mobile-first-confirmation' 'http://m.shengxuxu.info/' \
  'page_end url=http://m\.shengxuxu\.info/?' 'require'
run_selected_case 'mobile-exact-host-after-restart' 'http://m.shengxuxu.info/' \
  'page_end url=http://m\.shengxuxu\.info/?' 'forbid'
run_selected_case 'dawenks-first-confirmation' 'http://www.dawenks.com/' \
  'page_end url=http://www\.dawenks\.com/?' 'require' 60
run_selected_case 'dawenks-exact-host-after-restart' 'http://www.dawenks.com/' \
  'page_end url=http://www\.dawenks\.com/?' 'forbid' 40
run_selected_case 'xinhua-english-mobile-route' 'https://english.news.cn/' \
  'page_end url=https://english\.news\.cn/mobile/index\.htm' 'forbid' 35
if [ -n "${ONLY_CASE}" ] && [ "${selected_case_ran}" -eq 0 ]; then
  echo "FAIL unknown mobile-presentation case: ${ONLY_CASE}" >&2
  exit 2
fi
echo 'PASS mobile-presentation device matrix'
