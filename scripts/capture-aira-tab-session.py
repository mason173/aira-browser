#!/usr/bin/env python3
"""Tag-only HiLog capture for the tab-session forensics probe.

Bounded by --seconds, reads only the TabSession tag, never clears logs or inspects the screen.
The capture file is written outside the repository so no device data can be committed.
"""
import argparse
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

PREFIX = '[TAB-SESSION-9d2b]'
DEFAULT_HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def resolve_target(hdc):
    configured = os.environ.get('HDC_TARGET', '')
    if configured:
        return configured
    result = subprocess.run([hdc, 'list', 'targets'], capture_output=True, text=True, check=True)
    targets = [line.strip() for line in result.stdout.splitlines()
               if line.strip() and line.strip() != '[Empty]']
    if len(targets) != 1:
        raise SystemExit('Connect exactly one phone, or select it with HDC_TARGET.')
    return targets[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=300)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 1800:
        parser.error('--seconds must be 1..1800')
    hdc = os.environ.get('HDC_BIN', DEFAULT_HDC)
    target = resolve_target(hdc)
    output = args.output or Path(tempfile.gettempdir()) / f'aira-tab-session-{int(time.time())}.log'
    output = output.expanduser().resolve()
    repo = Path(__file__).resolve().parent.parent
    if output == repo or repo in output.parents:
        parser.error('--output must be outside the repository (default: temporary directory).')

    count = 0
    pending = b''
    with output.open('x', encoding='utf-8') as log:
        os.chmod(output, 0o600)
        process = subprocess.Popen(
            [hdc, '-t', target, 'shell', 'hilog', '-T', 'TabSession', '-v', 'epoch'],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + args.seconds
        print(f'READY: {output}', flush=True)
        print('Now reproduce: use the app and open several tabs -> background it -> kill the app -> '
              'relaunch. Capture ends in '
              f'{args.seconds}s.', flush=True)
        try:
            while time.monotonic() < deadline:
                if not selector.select(timeout=min(1, max(0, deadline - time.monotonic()))):
                    if process.poll() is not None:
                        break
                    continue
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                pending += chunk
                lines = pending.split(b'\n')
                pending = lines.pop()[-65536:]
                for raw in lines:
                    line = raw.decode('utf-8', errors='replace')
                    if PREFIX not in line:
                        continue
                    payload = line.split(PREFIX, 1)[1].strip()
                    log.write(PREFIX + ' ' + payload + '\n')
                    count += 1
                log.flush()
        except KeyboardInterrupt:
            pass
        finally:
            selector.close()
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    print(f'Saved {count} tab-session events: {output}', flush=True)
    if not count:
        print('No events captured: confirm the probe build is installed and the app was used once.')
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
