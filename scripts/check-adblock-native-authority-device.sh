#!/bin/sh

set -eu

DEVICE_TARGET=${HDC_TARGET:-}
REQUEST_COUNT=${AIRA_AUTHORITY_REQUEST_COUNT:-8192}
MIN_SAMPLES=${AIRA_AUTHORITY_MIN_SAMPLES:-$REQUEST_COUNT}
MAX_P95_MS=${AIRA_AUTHORITY_MAX_P95_MS:-5}
PORT=${AIRA_AUTHORITY_TEST_PORT:-18765}
BUNDLE_NAME=com.aira.browser
ABILITY_NAME=EntryAbility
LOG_TAG=AdBlockRuntimeGeneration

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

case "$REQUEST_COUNT" in
  ''|*[!0-9]*) fail "AIRA_AUTHORITY_REQUEST_COUNT must be a positive integer" ;;
esac
case "$MIN_SAMPLES" in
  ''|*[!0-9]*) fail "AIRA_AUTHORITY_MIN_SAMPLES must be a positive integer" ;;
esac
case "$PORT" in
  ''|*[!0-9]*) fail "AIRA_AUTHORITY_TEST_PORT must be a positive integer" ;;
esac
[ "$REQUEST_COUNT" -gt 0 ] || fail "AIRA_AUTHORITY_REQUEST_COUNT must be greater than zero"
[ "$MIN_SAMPLES" -gt 0 ] || fail "AIRA_AUTHORITY_MIN_SAMPLES must be greater than zero"

command -v hdc >/dev/null 2>&1 || fail "hdc was not found in PATH"
command -v node >/dev/null 2>&1 || fail "node was not found in PATH"

if [ -z "$DEVICE_TARGET" ]; then
  DEVICE_TARGET=$(hdc list targets -v | awk '$2 == "USB" && $3 == "Connected" { print $1 }')
  target_count=$(printf '%s\n' "$DEVICE_TARGET" | awk 'NF { count += 1 } END { print count + 0 }')
  [ "$target_count" -eq 1 ] || fail "Set HDC_TARGET; expected exactly one connected USB device"
fi

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/aira-authority-device.XXXXXX")
server_pid=''
reverse_added=false

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  if [ "$reverse_added" = true ]; then
    hdc -t "$DEVICE_TARGET" fport rm "tcp:$PORT" "tcp:$PORT" >/dev/null 2>&1 || true
  fi
  rm -rf "$temporary_dir"
}
trap cleanup EXIT HUP INT TERM

node - "$PORT" "$REQUEST_COUNT" >"$temporary_dir/server.log" 2>&1 <<'NODE' &
const http = require('http');
const port = Number(process.argv[2]);
const requestCount = Number(process.argv[3]);
const pixel = Buffer.from('R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=', 'base64');

const server = http.createServer((request, response) => {
  if (request.url === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end(`<!doctype html><meta charset="utf-8"><body><script>
      const blockedOrigins = [
        'https://doubleclick.net',
        'https://pagead2.googlesyndication.com',
        'https://googleadservices.com',
        'https://adservice.google.com'
      ];
      const kinds = ['fetch-get', 'fetch-post', 'xhr', 'image', 'script', 'stylesheet', 'iframe', 'media'];
      function fixtureUrl(index, kind) {
        if (index % 2 === 0) {
          const host = index % 4 === 0 ? '127.0.0.1' : 'localhost';
          return 'http://' + host + ':${port}/content/allowed-' + index + '?kind=' + kind + '&cache=' + index;
        }
        const origin = blockedOrigins[Math.floor(index / 2) % blockedOrigins.length];
        return origin + '/pagead/ads?kind=' + kind + '&cache=' + index;
      }
      function bounded(requestTask) {
        return Promise.race([
          requestTask.catch(() => {}),
          new Promise((resolve) => setTimeout(resolve, 750))
        ]);
      }
      function elementRequest(tagName, url, configure) {
        const element = document.createElement(tagName);
        configure(element, url);
        document.body.appendChild(element);
        setTimeout(() => element.remove(), 2000);
        return Promise.resolve();
      }
      function issueRequest(index) {
        const kind = kinds[index % kinds.length];
        const url = fixtureUrl(index, kind);
        if (kind === 'fetch-get') return bounded(fetch(url, { cache: 'no-store' }));
        if (kind === 'fetch-post') {
          return bounded(fetch(url, { method: 'POST', body: 'fixture=1', cache: 'no-store' }));
        }
        if (kind === 'xhr') {
          return bounded(new Promise((resolve) => {
            const xhr = new XMLHttpRequest();
            xhr.onloadend = resolve;
            xhr.onerror = resolve;
            xhr.open('GET', url);
            xhr.send();
          }));
        }
        if (kind === 'image') return elementRequest('img', url, (element, source) => { element.src = source; });
        if (kind === 'script') return elementRequest('script', url, (element, source) => { element.src = source; });
        if (kind === 'stylesheet') {
          return elementRequest('link', url, (element, source) => {
            element.rel = 'stylesheet';
            element.href = source;
          });
        }
        if (kind === 'iframe') return elementRequest('iframe', url, (element, source) => { element.src = source; });
        return elementRequest('video', url, (element, source) => {
          element.preload = 'metadata';
          element.src = source;
        });
      }
      (async () => {
        const batchSize = 32;
        for (let offset = 0; offset < ${requestCount}; offset += batchSize) {
          const limit = Math.min(offset + batchSize, ${requestCount});
          for (let index = offset; index < limit; index += 1) {
            void issueRequest(index);
          }
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      })();
    </script>`);
    return;
  }
  if (request.url.includes('kind=script')) {
    response.writeHead(200, { 'Content-Type': 'application/javascript', 'Cache-Control': 'no-store' });
    response.end('void 0;');
  } else if (request.url.includes('kind=stylesheet')) {
    response.writeHead(200, { 'Content-Type': 'text/css', 'Cache-Control': 'no-store' });
    response.end('html{}');
  } else if (request.url.includes('kind=iframe')) {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end('<!doctype html><title>fixture</title>');
  } else if (request.url.includes('kind=media')) {
    response.writeHead(200, { 'Content-Type': 'video/mp4', 'Content-Length': '0', 'Cache-Control': 'no-store' });
    response.end();
  } else if (request.url.includes('kind=image')) {
    response.writeHead(200, { 'Content-Type': 'image/gif', 'Cache-Control': 'no-store' });
    response.end(pixel);
  } else {
    response.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store'
    });
    response.end('{}');
  }
});

server.listen(port, '127.0.0.1', () => process.stdout.write('ready\n'));
NODE
server_pid=$!

ready_attempt=0
while [ "$ready_attempt" -lt 50 ]; do
  if grep -q '^ready$' "$temporary_dir/server.log"; then
    break
  fi
  kill -0 "$server_pid" >/dev/null 2>&1 || fail "Local fixture server exited before becoming ready"
  ready_attempt=$((ready_attempt + 1))
  sleep 0.1
done
grep -q '^ready$' "$temporary_dir/server.log" || fail "Timed out starting local fixture server"

hdc -t "$DEVICE_TARGET" rport "tcp:$PORT" "tcp:$PORT" >/dev/null
reverse_added=true
hdc -t "$DEVICE_TARGET" shell hilog -r >/dev/null
hdc -t "$DEVICE_TARGET" shell aa force-stop "$BUNDLE_NAME" >/dev/null 2>&1 || true
hdc -t "$DEVICE_TARGET" shell aa start -a "$ABILITY_NAME" -b "$BUNDLE_NAME" \
  -A ohos.want.action.viewData -U 'aira://home' >/dev/null

build_attempt=0
build_ready=false
while [ "$build_attempt" -lt 120 ]; do
  build_logs=$(hdc -t "$DEVICE_TARGET" shell hilog -x -T "$LOG_TAG" 2>/dev/null || true)
  if printf '%s\n' "$build_logs" | grep -q 'Native authority build_ready: ready=true'; then
    build_ready=true
    break
  fi
  build_attempt=$((build_attempt + 1))
  sleep 0.5
done
[ "$build_ready" = true ] || fail "Native authority engine did not become ready after cold start"

hdc -t "$DEVICE_TARGET" shell aa start -a "$ABILITY_NAME" -b "$BUNDLE_NAME" \
  -A ohos.want.action.viewData -U "http://127.0.0.1:$PORT/" >/dev/null

delivery_attempt=0
while [ "$delivery_attempt" -lt 10 ]; do
  delivery_logs=$(hdc -t "$DEVICE_TARGET" shell hilog -x -T "$LOG_TAG" 2>/dev/null || true)
  if printf '%s\n' "$delivery_logs" | grep -q 'Native authority query:'; then
    break
  fi
  delivery_attempt=$((delivery_attempt + 1))
  sleep 0.5
done
if [ "$delivery_attempt" -ge 10 ]; then
  hdc -t "$DEVICE_TARGET" shell aa start -a "$ABILITY_NAME" -b "$BUNDLE_NAME" \
    -A ohos.want.action.viewData -U "http://127.0.0.1:$PORT/" >/dev/null
fi

attempt=0
latest=''
while [ "$attempt" -lt 360 ]; do
  logs=$(hdc -t "$DEVICE_TARGET" shell hilog -x -T "$LOG_TAG" 2>/dev/null || true)
  latest=$(printf '%s\n' "$logs" | grep 'Native authority query:' | tail -n 1 || true)
  if [ -n "$latest" ]; then
    queries=$(printf '%s\n' "$latest" | sed -n 's/.* queries=\([0-9][0-9]*\).*/\1/p')
    if [ -n "$queries" ] && [ "$queries" -ge "$MIN_SAMPLES" ]; then
      break
    fi
  fi
  attempt=$((attempt + 1))
  sleep 0.5
done

[ -n "$latest" ] || fail "No native authority query metrics were emitted"

metric() {
  printf '%s\n' "$latest" | sed -n "s/.* $1=\\([^ ]*\\).*/\\1/p"
}

ready=$(metric ready)
backend=$(metric backend)
rules=$(metric rules)
builds=$(metric builds)
build_failures=$(metric buildFailures)
eligible=$(metric eligible)
queries=$(metric queries)
query_failures=$(metric queryFailures)
blocked=$(metric blocked)
allowed=$(metric allowed)
p50=$(metric p50)
p95=$(metric p95)
p99=$(metric p99)

[ "$ready" = true ] || fail "Native authority engine was not ready"
[ "$builds" -ge 1 ] || fail "Native authority engine did not build"
[ "$build_failures" -eq 0 ] || fail "Native authority build failures: $build_failures"
[ "$queries" -ge "$MIN_SAMPLES" ] || fail "Only $queries authority queries completed; expected at least $MIN_SAMPLES"
[ "$queries" -eq "$eligible" ] || fail "Rust authority covered $queries/$eligible eligible requests"
[ "$query_failures" -eq 0 ] || fail "Native authority query failures: $query_failures"
[ "$blocked" -gt 0 ] || fail "Native authority did not exercise a blocking decision"
[ "$allowed" -gt 0 ] || fail "Native authority did not exercise an allow decision"
awk -v actual="$p95" -v maximum="$MAX_P95_MS" 'BEGIN { exit !(actual <= maximum) }' || \
  fail "Native authority P95 ${p95} ms exceeded ${MAX_P95_MS} ms"

hdc -t "$DEVICE_TARGET" shell aa start -a "$ABILITY_NAME" -b "$BUNDLE_NAME" \
  -A ohos.want.action.viewData -U 'aira://home' >/dev/null 2>&1 || true

echo "PASS: native ad-block authority device test"
echo "suite=fetch-get,fetch-post,xhr,image,script,stylesheet,iframe,media allowedOrigins=2 blockedOrigins=4"
echo "device=$DEVICE_TARGET backend=$backend rules=$rules eligible=$eligible queries=$queries"
echo "blocked=$blocked allowed=$allowed queryFailures=$query_failures"
echo "p50=${p50}ms p95=${p95}ms p99=${p99}ms thresholdP95=${MAX_P95_MS}ms"
