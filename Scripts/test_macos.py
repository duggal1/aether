import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--timeout', type=float, default=300)
    parser.add_argument('--maximum-rss-mib', type=int, default=2048)
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    swift = subprocess.check_output(['xcrun', '--find', 'swift'], text=True).strip()
    plugins = Path(swift).parent.parent / 'lib/swift/host/plugins/testing'
    command = [swift, 'test', '-j', '1', '--no-parallel']
    if plugins.is_dir():
        command += ['-Xswiftc', '-plugin-path', '-Xswiftc', str(plugins)]
    for directory in [developer / 'Library/Developer/Frameworks', developer / 'Library/Developer/usr/lib']:
        if directory.is_dir():
            command += ['-Xlinker', '-rpath', '-Xlinker', str(directory)]
    command += args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    started = time.monotonic()
    process = subprocess.Popen(command, start_new_session=True)
    os.setpriority(os.PRIO_PROCESS, process.pid, 10)
    peak = 0
    reason = None
    try:
        while process.poll() is None:
            rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss='], text=True)
            entries = [tuple(map(int, row.split())) for row in rows.splitlines() if row.strip()]
            tree = {process.pid}
            while True:
                expanded = tree | {pid for pid, parent, _ in entries if parent in tree}
                if expanded == tree:
                    break
                tree = expanded
            rss = sum(rss for pid, _, rss in entries if pid in tree)
            peak = max(peak, rss)
            if rss > args.maximum_rss_mib * 1024:
                reason = 'memory limit'
                break
            if time.monotonic() - started > args.timeout:
                reason = 'time limit'
                break
            time.sleep(0.25)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    print(json.dumps({'command': command, 'seconds': round(time.monotonic() - started, 3), 'peakTreeRSSMiB': round(peak / 1024, 2), 'exitCode': process.returncode, 'stopped': reason}), flush=True)
    raise SystemExit(process.returncode if reason is None else 124)


if __name__ == '__main__':
    main()
