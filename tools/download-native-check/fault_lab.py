"""Fault injection through the production native core; all requests stay on loopback."""
import http.server
import os
import pathlib
import socket
import subprocess
import sys
import threading
import time

binary, work_dir = sys.argv[1:]
work = pathlib.Path(work_dir)
hits = {}
headers_seen = {}
data = b'abcdefghij'

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, status, body=b'', **headers):
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name.replace('_', '-'), value)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        count = hits[self.path] = hits.get(self.path, 0) + 1
        headers_seen.setdefault(self.path, []).append(dict(self.headers))
        if self.path == '/unresolved-redirect':
            self.send(302, b'not a file')
        elif self.path == '/not-modified':
            self.send(304)
        elif self.path in ('/temporary', '/rate-limited', '/hls-rate.m3u8', '/segment-rate') and count == 1:
            self.send(503 if self.path == '/temporary' else 429, Retry_After='1')
        elif self.path == '/busy':
            self.send(503)
        elif self.path in ('/cancel-retry', '/pause-retry'):
            self.send(503, Retry_After='3')
        elif self.path == '/long-wait':
            self.send(503, Retry_After='3600')
        elif self.path == '/forbidden':
            self.send(403)
        elif self.path == '/write-hls.m3u8':
            self.send(200, b'#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\n/disk-hls\n#EXT-X-ENDLIST\n')
        elif self.path in ('/hls-rate.m3u8', '/hls-segment-rate.m3u8'):
            segment = b'/segment-rate' if self.path == '/hls-segment-rate.m3u8' else b'/normal-segment'
            self.send(200, b'#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\n' + segment + b'\n#EXT-X-ENDLIST\n')
        elif self.path == '/redirect-change':
            self.send(302, Location='/entity-a' if count == 1 else '/entity-b')
        elif self.path == '/entity-b':
            if self.headers.get('Range'):
                self.send(206, data.upper()[5:], Content_Range='bytes 5-9/10', ETag='"v1"')
            else:
                self.send(200, data.upper(), ETag='"v1"')
        elif self.path in ('/partial', '/unvalidated', '/changed', '/entity-a') and count == 1:
            self.send_response(200)
            self.send_header('Content-Length', '10')
            if self.path != '/unvalidated':
                self.send_header('ETag', '"v1"')
            self.end_headers()
            self.wfile.write(data[:5]); self.wfile.flush()
            self.connection.shutdown(socket.SHUT_RDWR); self.connection.close()
        elif self.headers.get('Range') and self.path != '/changed':
            self.send(206, data[5:], Content_Range='bytes 5-9/10', ETag='"v1"')
        else:
            self.send(200, data.upper() if self.path == '/changed' else data, ETag='"v2"' if self.path == '/changed' else '"v1"')

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f'http://127.0.0.1:{server.server_port}'
failures = []

def check(name, endpoint, success=True, expected=data, limit=None, max_hits=None, min_delay=0, action=None):
    target = work / (name + '.bin')
    started = time.monotonic()
    env = os.environ.copy()
    if limit is not None:
        env['AIRA_DOWNLOAD_TEST_FILE_LIMIT'] = str(limit)
    result = subprocess.run([binary, base + endpoint, str(target), 'hls' if endpoint.endswith('.m3u8') else 'http',
                             *([f'--{action}-retry'] if action else [])],
                            capture_output=True, text=True, timeout=12, env=env)
    elapsed = time.monotonic() - started
    passed = (result.returncode == 0) == success
    if success:
        passed = passed and target.read_bytes() == expected
    if max_hits is not None:
        passed = passed and hits[endpoint] <= max_hits
    passed = passed and elapsed >= min_delay
    if action:
        passed = passed and elapsed < 2 and result.stdout.startswith('canceled' if action == 'cancel' else 'paused')
    print(('PASS ' if passed else 'FAIL ') + name)
    if not passed:
        failures.append(name)
        print(f'  hits={hits[endpoint]} elapsed={elapsed:.2f} {result.stdout.strip()}')

try:
    check('unresolved-redirect-is-not-a-file', '/unresolved-redirect', success=False, max_hits=1)
    check('304-is-not-an-empty-download', '/not-modified', success=False, max_hits=1)
    check('temporary-server-error-recovers', '/temporary', min_delay=1)
    check('rate-limit-honors-retry-after', '/rate-limited', min_delay=1)
    check('partial-file-resumes-with-validator', '/partial')
    check('unvalidated-partial-restarts', '/unvalidated')
    check('changed-file-restarts-without-mixing', '/changed', expected=data.upper())
    check('changed-redirect-target-does-not-reuse-another-entity-etag', '/redirect-change', expected=data.upper())
    check('retry-budget-is-bounded', '/busy', success=False, max_hits=3)
    check('long-retry-after-is-not-shortened', '/long-wait', success=False, max_hits=1)
    check('access-denial-is-not-retried', '/forbidden', success=False, max_hits=1)
    check('buffered-disk-write-failure-is-not-completion', '/disk-full', success=False, limit=2)
    check('hls-buffered-write-failure-is-not-completion', '/write-hls.m3u8', success=False, limit=2)
    check('hls-manifest-honors-retry-after', '/hls-rate.m3u8', min_delay=1)
    check('hls-segment-honors-retry-after', '/hls-segment-rate.m3u8', min_delay=1)
    check('cancel-interrupts-retry-wait', '/cancel-retry', success=False, max_hits=1, action='cancel')
    check('pause-interrupts-retry-wait', '/pause-retry', success=False, max_hits=1, action='pause')
    if hits.get('/partial', 0) > 1 and headers_seen['/partial'][1].get('If-Range') != '"v1"':
        failures.append('missing-validator')
    if any(header.get('Range') for header in headers_seen.get('/unvalidated', [])):
        failures.append('unsafe-unvalidated-resume')
finally:
    server.shutdown()
if failures:
    print(f'{len(failures)} native fault checks failed')
    sys.exit(1)
print('native fault checks passed')
