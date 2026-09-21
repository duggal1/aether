import importlib.util
from pathlib import Path
import subprocess
import threading
import time
import json
import sys

path = Path(__file__).with_name('sequential_harness.py')
spec = importlib.util.spec_from_file_location('aether_sequential', path)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)
samples = []
stop = threading.Event()

def monitor():
    while not stop.wait(1):
        daemon = harness.DAEMON['proc']
        if daemon is None or daemon.poll() is not None:
            continue
        fields = subprocess.run(['ps', '-o', 'rss=,%cpu=', '-p', str(daemon.pid)],
                                capture_output=True, text=True).stdout.split()
        if len(fields) == 2:
            samples.append({'rss_kib': int(fields[0]), 'cpu_percent': float(fields[1])})

threading.Thread(target=monitor, daemon=True).start()
try:
    harness.main()
finally:
    stop.set()
    daemon = harness.DAEMON['proc']
    exit_before_cleanup = daemon.poll() if daemon is not None else None
    if daemon is not None and daemon.poll() is None:
        daemon.terminate()
        try:
            daemon.wait(timeout=5)
        except subprocess.TimeoutExpired:
            daemon.kill()
            daemon.wait()
    Path(sys.argv[sys.argv.index('--output') + 1]).with_suffix('.resources.json').write_text(json.dumps({
        'scope': 'daemon only; excludes WebKit subprocesses and does not establish total browser memory',
        'exit_before_cleanup': exit_before_cleanup,
        'samples': samples,
        'peak_daemon_rss_kib': max((s['rss_kib'] for s in samples), default=0)
    }, indent=2))
