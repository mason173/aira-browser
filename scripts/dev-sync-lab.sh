#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB_DIR="${REPO_ROOT}/.tmp-sync-lab"
RUN_DIR="${LAB_DIR}/run"
LOG_DIR="${LAB_DIR}/logs"
WEBDAV_ROOT="${LAB_DIR}/webdav-root"

WEBDAV_PORT="${WEBDAV_PORT:-8787}"
WEBDAV_USERNAME="${WEBDAV_USERNAME:-1}"
WEBDAV_PASSWORD="${WEBDAV_PASSWORD:-1}"

WEBDAV_PID_FILE="${RUN_DIR}/webdav.pid"
WEBDAV_LOG="${LOG_DIR}/webdav.log"

mkdir -p "${RUN_DIR}" "${LOG_DIR}" "${WEBDAV_ROOT}"

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

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    fail "找不到 node。请先安装 Node.js。"
    exit 1
  fi
}

pid_is_running() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] || return 1
  local pid
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" >/dev/null 2>&1
}

read_pid() {
  local pid_file="$1"
  cat "${pid_file}" 2>/dev/null || true
}

remove_stale_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]] && ! pid_is_running "${pid_file}"; then
    rm -f "${pid_file}"
  fi
}

port_listener() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
}

first_listener_pid() {
  local port="$1"
  port_listener "${port}" | awk 'NR == 2 {print $2}'
}

port_is_free_or_owned_by_pid() {
  local port="$1"
  local expected_pid="$2"
  local listeners
  listeners="$(port_listener "${port}")"
  [[ -z "${listeners}" ]] && return 0
  [[ -n "${expected_pid}" ]] && printf '%s\n' "${listeners}" | awk 'NR > 1 {print $2}' | grep -qx "${expected_pid}"
}

local_ipv4_addresses() {
  if command -v ipconfig >/dev/null 2>&1; then
    for iface in $(ifconfig -l 2>/dev/null); do
      ipconfig getifaddr "${iface}" 2>/dev/null || true
    done | awk 'NF && $1 !~ /^127\\./ {print $1}' | sort -u
    return
  fi
  hostname -I 2>/dev/null | tr ' ' '\n' | awk 'NF && $1 !~ /^127\\./ {print $1}' | sort -u || true
}

print_urls() {
  local ips
  ips="$(local_ipv4_addresses)"
  echo
  ok "本机测试地址"
  echo "  WebDAV localhost:  http://127.0.0.1:${WEBDAV_PORT}/"
  echo "  WebDAV 账号密码:   ${WEBDAV_USERNAME} / ${WEBDAV_PASSWORD}"
  echo "  WebDAV 数据目录:   ${WEBDAV_ROOT}"
  if [[ -n "${ips}" ]]; then
    echo
    ok "局域网设备用这些地址"
    while IFS= read -r ip; do
      [[ -n "${ip}" ]] || continue
      echo "  WebDAV:  http://${ip}:${WEBDAV_PORT}/"
    done <<< "${ips}"
  else
    warn "没检测到局域网 IPv4 地址。你可能没连 Wi-Fi/网线，或系统没有暴露接口地址。"
  fi
}

start_webdav() {
  require_node
  remove_stale_pid "${WEBDAV_PID_FILE}"
  if pid_is_running "${WEBDAV_PID_FILE}"; then
    ok "WebDAV 已经在运行，pid=$(read_pid "${WEBDAV_PID_FILE}")"
    return
  fi
  local existing_pid
  existing_pid="$(first_listener_pid "${WEBDAV_PORT}")"
  if [[ -n "${existing_pid}" ]]; then
    local existing_command
    existing_command="$(ps -p "${existing_pid}" -o command= 2>/dev/null || true)"
    if [[ "${existing_command}" == *"dev-webdav-server.js"* ]]; then
      echo "${existing_pid}" > "${WEBDAV_PID_FILE}"
      ok "检测到已有 WebDAV，接管 pid=${existing_pid}"
      return
    fi
    fail "端口 ${WEBDAV_PORT} 已被占用："
    port_listener "${WEBDAV_PORT}"
    return 1
  fi
  mkdir -p "${WEBDAV_ROOT}"
  info "启动本地 WebDAV..."
  (
    cd "${REPO_ROOT}"
    WEBDAV_ROOT="${WEBDAV_ROOT}" \
      WEBDAV_PORT="${WEBDAV_PORT}" \
      WEBDAV_USERNAME="${WEBDAV_USERNAME}" \
      WEBDAV_PASSWORD="${WEBDAV_PASSWORD}" \
      node scripts/dev-webdav-server.js
  ) >"${WEBDAV_LOG}" 2>&1 &
  echo $! > "${WEBDAV_PID_FILE}"
  sleep 0.5
  local listener_pid
  listener_pid="$(first_listener_pid "${WEBDAV_PORT}")"
  if [[ -n "${listener_pid}" ]]; then
    echo "${listener_pid}" > "${WEBDAV_PID_FILE}"
    ok "WebDAV 已启动，pid=${listener_pid}"
  else
    fail "WebDAV 启动失败，日志：${WEBDAV_LOG}"
    tail -60 "${WEBDAV_LOG}" || true
    return 1
  fi
}

start_all() {
  start_webdav
  print_urls
}

stop_one() {
  local name="$1"
  local pid_file="$2"
  local port="${3:-}"
  local listener_pid=""
  if [[ -n "${port}" ]]; then
    listener_pid="$(first_listener_pid "${port}")"
    if [[ -n "${listener_pid}" ]]; then
      echo "${listener_pid}" > "${pid_file}"
    fi
  fi
  if ! pid_is_running "${pid_file}"; then
    rm -f "${pid_file}"
    warn "${name} 没有在运行。"
    return
  fi
  local pid
  pid="$(read_pid "${pid_file}")"
  info "停止 ${name}，pid=${pid}..."
  kill "${pid}" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
  if kill -0 "${pid}" >/dev/null 2>&1; then
    warn "${name} 没正常退出，强制停止。"
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pid_file}"
  ok "${name} 已停止。"
}

stop_all() {
  stop_one "WebDAV" "${WEBDAV_PID_FILE}" "${WEBDAV_PORT}"
}

status() {
  remove_stale_pid "${WEBDAV_PID_FILE}"
  echo
  ok "运行状态"
  if pid_is_running "${WEBDAV_PID_FILE}"; then
    echo "  WebDAV: 运行中 pid=$(read_pid "${WEBDAV_PID_FILE}") port=${WEBDAV_PORT}"
  else
    echo "  WebDAV: 未运行"
  fi
  echo
  echo "端口监听："
  port_listener "${WEBDAV_PORT}" || true
  print_urls
}

show_logs() {
  tail -120 "${WEBDAV_LOG}" 2>/dev/null || warn "还没有 WebDAV 日志。"
}

clear_webdav_data() {
  warn "这会删除 WebDAV 测试数据目录：${WEBDAV_ROOT}"
  read -r -p "确认删除？输入 yes: " answer
  [[ "${answer}" == "yes" ]] || return
  rm -rf "${WEBDAV_ROOT}"
  mkdir -p "${WEBDAV_ROOT}"
  ok "WebDAV 测试数据已清空。"
}

clear_all_data() {
  warn "这会清空 WebDAV 测试数据。"
  read -r -p "确认删除全部？输入 yes: " answer
  [[ "${answer}" == "yes" ]] || return
  stop_all
  rm -rf "${WEBDAV_ROOT}"
  mkdir -p "${WEBDAV_ROOT}"
  ok "全部测试数据已清空。"
}

show_webdav_data() {
  echo
  ok "WebDAV 数据"
  echo "  root: ${WEBDAV_ROOT}"
  if [[ ! -d "${WEBDAV_ROOT}" ]]; then
    warn "WebDAV 数据目录不存在。"
    return
  fi
  local file_count
  file_count="$(find "${WEBDAV_ROOT}" -type f | wc -l | tr -d ' ')"
  echo "  文件数: ${file_count}"
  echo
  echo "目录概览："
  find "${WEBDAV_ROOT}" -maxdepth 4 -print | sed "s#${WEBDAV_ROOT}#.#" | sort | sed -n '1,160p'
  if [[ -f "${WEBDAV_ROOT}/aira/v1/bookmarks/head.json" ]]; then
    echo
    echo "aira/v1/bookmarks/head.json:"
    sed -n '1,80p' "${WEBDAV_ROOT}/aira/v1/bookmarks/head.json"
  fi
}

show_data() {
  show_webdav_data
}

health_check() {
  echo
  ok "健康检查"
  if command -v curl >/dev/null 2>&1; then
    echo "WebDAV:"
    curl -sS -i -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" -X OPTIONS "http://127.0.0.1:${WEBDAV_PORT}/" | sed -n '1,10p' || true
    echo
    echo "WebDAV 错误密码应返回 401:"
    curl -sS -i -u "wrong:wrong" -X OPTIONS "http://127.0.0.1:${WEBDAV_PORT}/" | sed -n '1,6p' || true
  else
    warn "找不到 curl，跳过 HTTP 健康检查。"
  fi
}

open_shell_info() {
  cat <<EOF

可直接配置到手机 App：
  WebDAV 地址:  http://<下面局域网 IP>:${WEBDAV_PORT}/
  WebDAV 用户:  ${WEBDAV_USERNAME}
  WebDAV 密码:  ${WEBDAV_PASSWORD}

常用命令：
  ./scripts/dev-sync-lab.sh start
  ./scripts/dev-sync-lab.sh stop
  ./scripts/dev-sync-lab.sh status
  ./scripts/dev-sync-lab.sh data
  ./scripts/dev-sync-lab.sh clear-webdav

EOF
  print_urls
}

menu() {
  while true; do
    echo
    ok "Aira WebDAV 同步测试实验室"
    echo "1) 启动 WebDAV"
    echo "2) 停止 WebDAV"
    echo "3) 查看状态/地址"
    echo "4) 查看数据"
    echo "5) 查看日志"
    echo "6) 健康检查"
    echo "7) 清空 WebDAV 数据"
    echo "8) 清空全部测试数据"
    echo "10) 打印 App 配置信息"
    echo "0) 退出"
    read -r -p "选择: " choice
    case "${choice}" in
      1) start_all ;;
      2) stop_all ;;
      3) status ;;
      4) show_data ;;
      5) show_logs ;;
      6) health_check ;;
      7) clear_webdav_data ;;
      8) clear_all_data ;;
      10) open_shell_info ;;
      0) exit 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

case "${1:-menu}" in
  start) start_all ;;
  stop) stop_all ;;
  restart) stop_all; start_all ;;
  status) status ;;
  data) show_data ;;
  logs) show_logs ;;
  health) health_check ;;
  clear-webdav) clear_webdav_data ;;
  clear-all) clear_all_data ;;
  info) open_shell_info ;;
  menu) menu ;;
  *)
    cat <<EOF
用法: $0 [start|stop|restart|status|data|logs|health|clear-webdav|clear-all|info]
不带参数时进入交互菜单。
EOF
    exit 1
    ;;
esac
