"""Observe production HLS snapshots over slow local transfers, retries and checkpoints."""
import http.server
import pathlib
import socket
import subprocess
import sys
import threading
import time

binary, directory = sys.argv[1:]
work = pathlib.Path(directory)
requests = []
fail_last = False
break_once = False
body = [b'A' * 32768, b'B' * 65536, b'C' * 98304]


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        global break_once
        requests.append(self.path)
        if self.path.endswith('.m3u8'):
            unknown = self.path.startswith('/unknown')
            playlist = '#EXTM3U\n#EXT-X-MAP:URI="/map"\n'
            for index in range(3):
                playlist += f'#EXTINF:1,\n/{"unknown-" if unknown else ""}part-{index}\n'
            data = (playlist + '#EXT-X-ENDLIST\n').encode()
        elif self.path == '/map':
            data = b'INIT'
        else:
            index = int(self.path.rsplit('-', 1)[1])
            if index == 2 and fail_last:
                self.send_error(403)
                return
            data = body[index]
        self.send_response(200)
        if not self.path.startswith('/unknown-part'):
            self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        for offset in range(0, len(data), 4096):
            self.wfile.write(data[offset:offset + 4096])
            self.wfile.flush()
            if self.path == '/part-1' and break_once:
                break_once = False
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            if 'part-' in self.path:
                time.sleep(0.025)


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()


def run(name, manifest='index.m3u8', success=True):
    target = work / (name + '.ts')
    result = subprocess.run([binary, f'http://127.0.0.1:{server.server_port}/{manifest}',
                             str(target), 'hls', '--observe-progress', '--hls-serial'],
                            text=True, capture_output=True, timeout=12)
    assert result.returncode == (0 if success else 1), result.stdout + result.stderr
    snapshots = []
    for line in result.stdout.splitlines():
        if line.startswith('progress '):
            _, state, received, total, fraction, estimate = line.split()
            snapshots.append((state, int(received), int(total), float(fraction), int(estimate)))
    running = [s for s in snapshots if s[0] == 'running']
    assert running and all(s[2] == 0 and s[3] < 1 for s in running), snapshots
    assert any(s[3] > 0 and s[4] > 0 for s in running), snapshots
    # The tiny MAP does not bias the estimate: after one media sample it is 3 * 32768 + 4.
    assert any(s[4] == len(body[0]) * 3 + 4 for s in running), snapshots
    if success:
        expected = b'INIT' + b''.join(body)
        assert target.read_bytes() == expected
        assert snapshots[-1][2:] == (len(expected), 1.0, 0), snapshots[-1]
    return snapshots


try:
    samples = run('progress-known')
    assert any(0.27 < s[3] < 0.49 for s in samples), 'in-flight segments must advance the bar'
    run('progress-unknown', 'unknown.m3u8')
    break_once = True
    samples = run('progress-retry')
    assert max(s[3] for s in samples if s[0] != 'completed') <= 0.99
    fail_last = True
    run('progress-resume', success=False)
    fail_last = False
    before = len(requests)
    # Resume gets its initial fraction and estimate from validated checkpoint parts.
    target = work / 'progress-resume.ts'
    result = subprocess.run([binary, f'http://127.0.0.1:{server.server_port}/index.m3u8',
                             str(target), 'hls', '--observe-progress', '--hls-serial'],
                            text=True, capture_output=True, timeout=12)
    assert result.returncode == 0, result.stdout
    assert '/part-0' not in requests[before:] and '/part-1' not in requests[before:]
    assert any(line.startswith('progress running ') and float(line.split()[4]) >= 0.75 and
               int(line.split()[5]) > 0 for line in result.stdout.splitlines())
    assert target.read_bytes() == b'INIT' + b''.join(body)
    print('PASS HLS progress: in-flight, estimated size, unknown length, retry, checkpoint and final size')
finally:
    server.shutdown()
