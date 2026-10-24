"""Deterministic integration checks using the real native downloader and local HTTP.

Fixture encryption uses OpenSSL, independently of the production Mbed TLS decryptor.
No network outside loopback, device, or screen access is needed.
"""
import http.server
import pathlib
import socket
import subprocess
import sys
import threading

binary, work_dir = sys.argv[1:]
work = pathlib.Path(work_dir)
requests = []
counts = {}
key1, key2 = bytes(range(16)), bytes(reversed(range(16)))
plain1, plain2 = b'first decrypted media segment', b'second decrypted media segment!'

def encrypt(data, key, iv, pad=True):
    return subprocess.run(['openssl', 'enc', '-aes-128-cbc', '-K', key.hex(), '-iv', iv.hex(), *([] if pad else ['-nopad'])],
                          input=data, capture_output=True, check=True).stdout

cipher1 = encrypt(plain1, key1, (42).to_bytes(16, 'big'))
cipher2 = encrypt(plain2, key2, (99).to_bytes(16, 'big'))
fixtures = {
    '/cdn/segment.ts': b'transport-stream-body', '/a.ts': b'A', '/b.ts': b'B',
    '/init-a.mp4': b'INIT-A', '/init-b.mp4': b'INIT-B', '/key1': key1, '/key2': key2,
    '/enc1': cipher1, '/enc2': cipher2, '/bad-key': b'short',
    '/bad-padding': encrypt(b'bad-padding' + b'\x00' * 5, key1, (42).to_bytes(16, 'big'), pad=False),
    '/block': encrypt(b'x' * 65536, key1, (42).to_bytes(16, 'big')),
    '/seq43': encrypt(plain2, key1, (43).to_bytes(16, 'big')),
    '/large-key': b'x' * 128,
    '/ranges': b'INITAB', '/enc-ranges': cipher1 + cipher2,
    '/enc-map': encrypt(b'INIT', key1, (42).to_bytes(16, 'big')),
}

def playlist(body):
    return ('#EXTM3U\n#EXT-X-TARGETDURATION:1\n' + body + '\n#EXT-X-ENDLIST\n').encode()

fixtures.update({
    '/cdn/index.m3u8': playlist('#EXTINF:1,\nsegment.ts'),
    '/crypto.m3u8': playlist('#EXT-X-MEDIA-SEQUENCE:42\n#EXT-X-KEY:METHOD=AES-128,URI="key1"\n#EXTINF:1,\nenc1\n#EXT-X-KEY:METHOD=AES-128,URI="key2",IV=0x63\n#EXTINF:1,\nenc2\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:1,\na.ts'),
    '/crypto-map.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="key1",IV=0X2A\n#EXT-X-MAP:URI="enc-map"\n#EXTINF:1,\nenc1'),
    '/bad-key.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="bad-key",IV=0x2a\n#EXTINF:1,\nenc1'),
    '/bad-padding.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="key1",IV=0x2a\n#EXTINF:1,\nbad-padding'),
    '/drm.m3u8': playlist('#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key1"\n#EXTINF:1,\na.ts'),
    '/map-no-iv.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="key1"\n#EXT-X-MAP:URI="enc-map"\n#EXTINF:1,\nenc1'),
    '/maps.m3u8': playlist('#EXT-X-MAP:URI="init-a.mp4"\n#EXTINF:1,\na.ts\n#EXT-X-DISCONTINUITY\n#EXT-X-MAP:URI="init-b.mp4"\n#EXTINF:1,\nb.ts'),
    '/ranges.m3u8': playlist('#EXT-X-MAP:URI="ranges",BYTERANGE="4@0"\n#EXT-X-BYTERANGE:1@4\n#EXTINF:1,\nranges\n#EXT-X-BYTERANGE:1\n#EXTINF:1,\nranges'),
    '/block.m3u8': playlist('#EXT-X-MEDIA-SEQUENCE:42\n#EXT-X-KEY:METHOD=AES-128,URI="key1"\n#EXTINF:1,\nblock'),
    '/sequence.m3u8': playlist('#EXT-X-MEDIA-SEQUENCE:42\n#EXT-X-KEY:METHOD=AES-128,URI="key1"\n#EXTINF:1,\nenc1\n#EXTINF:1,\nseq43'),
    '/invalid-iv.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="key1",IV=0xZZ\n#EXTINF:1,\nenc1'),
    '/large-key.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="large-key",IV=0x2a\n#EXTINF:1,\nenc1'),
    '/drm-format.m3u8': playlist('#EXT-X-KEY:METHOD=AES-128,URI="key1",KEYFORMAT="com.example.drm"\n#EXTINF:1,\nenc1'),
    '/bad-range.m3u8': playlist('#EXT-X-BYTERANGE:1\n#EXTINF:1,\nranges'),
    '/ignored-range.m3u8': playlist('#EXT-X-BYTERANGE:2@0\n#EXTINF:1,\nfile'),
    '/encrypted-ranges.m3u8': playlist(f'#EXT-X-KEY:METHOD=AES-128,URI="key1",IV=0x2a\n#EXT-X-BYTERANGE:{len(cipher1)}@0\n#EXTINF:1,\nenc-ranges\n#EXT-X-KEY:METHOD=AES-128,URI="key2",IV=0x63\n#EXT-X-BYTERANGE:{len(cipher2)}\n#EXTINF:1,\nenc-ranges'),
    '/master.m3u8': b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhls-redirect.m3u8\n',
    '/audio.m3u8': b'#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",URI="audio-track.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="audio"\ncdn/index.m3u8\n',
})

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
        requests.append((self.path, dict(self.headers)))
        counts[self.path] = counts.get(self.path, 0) + 1
        if self.path == '/file':
            self.send(200, b'abcdefghij')
        elif self.path == '/redirect':
            self.send(302, Location='/file')
        elif self.path == '/cookie-redirect':
            self.send(302, Location='/cookie-file', Set_Cookie='ticket=valid; Path=/')
        elif self.path == '/cookie-file':
            self.send(200 if self.headers.get('Cookie') == 'ticket=valid' else 403, b'abcdefghij')
        elif self.path == '/auth-hls.m3u8':
            if self.headers.get('Authorization') != 'Bearer fixture':
                self.send(403)
            else:
                self.send(200, playlist(f'#EXTINF:1,\n/auth-same\n#EXTINF:1,\nhttp://localhost:{self.server.server_port}/auth-cross'))
        elif self.path in ('/auth-same', '/auth-cross'):
            expected = 'Bearer fixture' if self.path == '/auth-same' else None
            self.send(200 if self.headers.get('Authorization') == expected else 403, b'OK')
        elif self.path == '/cookie-hls.m3u8':
            self.send(302, Location='/gated/index.m3u8', Set_Cookie='ticket=valid; Path=/')
        elif self.path.startswith('/gated/'):
            if self.headers.get('Cookie') != 'ticket=valid':
                self.send(403)
            elif self.path.endswith('index.m3u8'):
                self.send(200, playlist('#EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x2a\n#EXTINF:1,\nsegment'))
            elif self.path.endswith('/key'):
                self.send(200, key1)
            else:
                self.send(200, cipher1)
        elif self.path == '/hls-redirect.m3u8':
            self.send(302, Location='/cdn/index.m3u8')
        elif self.path == '/unsolicited-range':
            self.send(206, b'fghij', Content_Range='bytes 5-9/10')
        elif self.path.startswith('/interrupted'):
            changed = 'changed' in self.path
            unvalidated = 'no-validator' in self.path
            if counts[self.path] == 1:
                self.send_response(200)
                self.send_header('Content-Length', '10')
                if not unvalidated:
                    self.send_header('ETag', '"v1"')
                self.end_headers()
                self.wfile.write(b'abcde')
                self.wfile.flush()
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
            else:
                tag = '"v2"' if changed else '"v1"'
                data = b'ABCDEFGHIJ' if changed else b'abcdefghij'
                offset = 0
                if self.headers.get('Range') and self.headers.get('If-Range') in (None, tag):
                    offset = int(self.headers['Range'].split('=')[1].split('-')[0])
                if offset and 'short-range' in self.path:
                    self.send(206, data[offset:offset + 2], Content_Range=f'bytes {offset}-9/10', ETag=tag)
                elif offset:
                    self.send(206, data[offset:], Content_Range=f'bytes {offset}-9/10', ETag=tag)
                else:
                    self.send(200, data, ETag=tag)
        elif self.path in fixtures:
            data = fixtures[self.path]
            if self.headers.get('Range'):
                start, end = map(int, self.headers['Range'].split('=')[1].split('-'))
                self.send(206, data[start:end + 1], Content_Range=f'bytes {start}-{end}/{len(data)}')
            else:
                self.send(200, data)
        else:
            self.send(404)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f'http://127.0.0.1:{server.server_port}'
failures = []

def run(name, path, expected=None, error=None, headers=(), existing=False):
    output = work / (name + '.bin')
    if not existing:
        output.unlink(missing_ok=True)
    result = subprocess.run([binary, base + path, str(output), 'hls' if '.m3u8' in path else 'http', *headers],
                            capture_output=True, text=True, timeout=12)
    actual = output.read_bytes() if output.exists() else b''
    passed = result.returncode == 0 and actual == expected if error is None else result.returncode != 0 and error in result.stdout
    print(('PASS ' if passed else 'FAIL ') + name)
    if not passed:
        failures.append(name)
        print(f'  expected={expected!r} actual={actual!r}\n  {result.stdout.strip()}')
    return result

try:
    run('get', '/file', b'abcdefghij')
    run('redirect', '/redirect', b'abcdefghij')
    run('unsolicited-incomplete-range', '/unsolicited-range', error='partial file')
    run('cookie-redirect', '/cookie-redirect', b'abcdefghij')
    run('cookie-replacement', '/cookie-redirect', b'abcdefghij', headers=['Cookie: ticket=expired'])
    run('hls-direct', '/cdn/index.m3u8', b'transport-stream-body')
    run('hls-redirect', '/hls-redirect.m3u8', b'transport-stream-body')
    for mode in ['stable', 'changed', 'no-validator', 'short-range']:
        name, path = 'resume-' + mode, '/interrupted-' + mode
        run(name, path, error='partial file')
        start = len(requests)
        run(name, path, b'ABCDEFGHIJ' if mode == 'changed' else b'abcdefghij', existing=True)
        request_headers = requests[start][1]
        safe = (request_headers.get('If-Range') == '"v1"') if mode != 'no-validator' else not request_headers.get('Range')
        if not safe:
            failures.append(name + '-validator')
            print('FAIL ' + name + '-validator ' + str(request_headers))
    run('aes-rotation-iv-none', '/crypto.m3u8', plain1 + plain2 + b'A')
    run('aes-map', '/crypto-map.m3u8', b'INIT' + plain1)
    run('aes-sequence-increments', '/sequence.m3u8', plain1 + plain2)
    run('aes-full-block-streaming-padding', '/block.m3u8', b'x' * 65536)
    run('aes-ranges', '/encrypted-ranges.m3u8', plain1 + plain2)
    run('hls-cookie-key-segment', '/cookie-hls.m3u8', plain1, headers=['Cookie: ticket=expired'])
    run('master-variant-redirect', '/master.m3u8', b'transport-stream-body')
    run('hls-authorization-origin-boundary', '/auth-hls.m3u8', b'OKOK', headers=['Authorization: Bearer fixture'])
    run('invalid-iv', '/invalid-iv.m3u8', error='IV')
    run('oversized-key', '/large-key.m3u8', error='密钥')
    run('drm-keyformat-rejected', '/drm-format.m3u8', error='DRM')
    run('implicit-range-without-predecessor', '/bad-range.m3u8', error='字节范围')
    run('server-ignored-range', '/ignored-range.m3u8', error='字节范围')
    run('bad-key', '/bad-key.m3u8', error='密钥')
    run('bad-padding', '/bad-padding.m3u8', error='填充')
    run('sample-aes-rejected', '/drm.m3u8', error='SAMPLE-AES')
    run('encrypted-map-needs-iv', '/map-no-iv.m3u8', error='IV')
    run('maps-in-order', '/maps.m3u8', b'INIT-AAINIT-BB')
    run('byte-ranges', '/ranges.m3u8', b'INITAB')
    run('external-audio-rejected', '/audio.m3u8', error='独立音轨')
finally:
    server.shutdown()
if failures:
    print(f'{len(failures)} download native checks failed')
    sys.exit(1)
print('download native checks passed')
