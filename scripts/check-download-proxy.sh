#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/aira-download-proxy.XXXXXX")
log_file="$work/proxy.log"
port_file="$work/ports"
user="aira"
password='p@ss word'
python_pid=""

cleanup() {
  if [ -n "$python_pid" ]; then
    kill "$python_pid" 2>/dev/null || true
    wait "$python_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

python3 "$root/tools/download-proxy-check/proxy_lab.py" \
  --port-file "$port_file" \
  --log-file "$log_file" \
  --user "$user" \
  --password "$password" &
python_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [ -s "$port_file" ]; then
    break
  fi
  sleep 0.1
done
if [ ! -s "$port_file" ]; then
  echo "proxy lab did not publish ports" >&2
  exit 1
fi

origin_port=$(sed -n 's/^origin=//p' "$port_file")
http_port=$(sed -n 's/^http_proxy=//p' "$port_file")
socks_port=$(sed -n 's/^socks=//p' "$port_file")

"$root/tools/download-native-check/build-host.sh" "$work" \
  "$root/tools/download-proxy-check/download_proxy_host_test.cpp"

"$work/download_host_test" \
  "$origin_port" \
  "$http_port" \
  "$socks_port" \
  "$log_file" \
  "$work" \
  "$user" \
  "$password"

echo "proxy log:"
sed 's/^/  /' "$log_file"
