#!/bin/sh

set -eu

usage() {
  echo "Usage: $0 ordinary <log-file> <target-regex>"
  echo "       $0 popup <log-file>"
  echo "       $0 return <log-file>"
  echo "       $0 ithome-history <log-file>"
}

fail() {
  echo "RED: $1"
  exit 1
}

pass() {
  echo "GREEN: $1"
}

require_pattern() {
  pattern="$1"
  file="$2"
  message="$3"
  if ! rg -q -i "$pattern" "$file"; then
    fail "$message"
  fi
}

reject_pattern() {
  pattern="$1"
  file="$2"
  message="$3"
  if rg -q -i "$pattern" "$file"; then
    fail "$message"
  fi
}

mode="${1:-}"
log_file="${2:-}"

if [ -z "$mode" ] || [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
  usage
  exit 2
fi

case "$mode" in
  ordinary)
    target_regex="${3:-}"
    if [ -z "$target_regex" ]; then
      usage
      exit 2
    fi
    require_pattern 'window_new_received' "$log_file" 'ordinary link never reached onWindowNew'
    require_pattern 'target_tab_created' "$log_file" 'ordinary link did not create a managed child tab'
    require_pattern 'window_open_event_consumed_by_page_controller.*completion=child_controller' "$log_file" 'ordinary child did not consume the stored popup event with its controller'
    require_pattern "page_begin.*$target_regex" "$log_file" 'ordinary child never began loading the target URL'
    reject_pattern "page_begin.*restore=manual_reload.*$target_regex" "$log_file" 'ordinary target only began after a manual reload'
    pass 'ordinary child opened its target without manual reload'
    ;;
  popup)
    require_pattern 'window_new_received.*accounts\.google\.com' "$log_file" 'Google OAuth never reached onWindowNew'
    require_pattern 'NotifyPopupWindowResult result: *1' "$log_file" 'ArkWeb did not accept the popup controller'
    require_pattern 'PopupWindowCallbackImpl Continue' "$log_file" 'ArkWeb popup callback did not continue'
    reject_pattern 'OnBeforePopup nweb is null' "$log_file" 'ArkWeb popup child has no NWeb/browser host'
    reject_pattern 'GSI_LOGGER.*Failed to open popup window' "$log_file" 'Google GSI rejected the returned WindowProxy'
    require_pattern 'page_begin.*accounts\.google\.com' "$log_file" 'Google OAuth child never began navigation'
    pass 'Google OAuth popup has a valid ArkWeb child and begins navigation'
    ;;
  return)
    require_pattern 'window_open_child_terminal_back' "$log_file" 'terminal Back did not enter the window-open child owner'
    reject_pattern 'user_return_home_closed_current_tab|step=show_home_surface' "$log_file" 'terminal Back bypassed the opener and revealed Browser Home'
    reject_pattern 'policy_background_contract_violation' "$log_file" 'background runtime protection contract was violated'
    pass 'terminal Back returned through the child-to-opener path'
    ;;
  ithome-history)
    require_pattern 'web_history_user_command.*status=native_issued.*reason=native_history' "$log_file" 'IT之家 Back did not use ArkWeb native history'
    reject_pattern 'CanEnterBFCache canStore:0.*hasDiffUserAgent:1' "$log_file" 'IT之家 system-default UA was still recorded as different and blocked BFCache'
    require_pattern 'fromBFCache:1' "$log_file" 'IT之家 refreshed-list Back did not restore the homepage document from BFCache'
    reject_pattern 'policy_background_contract_violation' "$log_file" 'background runtime protection contract was violated'
    pass 'IT之家 refreshed-list Back restored the homepage document through ArkWeb BFCache'
    ;;
  *)
    usage
    exit 2
    ;;
esac
