import argparse
import concurrent.futures
import hashlib
import http.server
import json
import math
from pathlib import Path
import socket
import statistics
import subprocess
import tempfile
import threading
import time

HTML = ("<!doctype html><title>Performance fixture</title><style>body{margin:0}button{display:block;height:24px}</style>"
        "<input id='field' aria-label='Name'><input type='password' value='secret' id='secret'>"
        "<button id='apply' onclick=\"document.querySelector('#result').textContent=document.querySelector('#field').value\">Apply</button>"
        "<p id='result'>Initial</p>" + ''.join(f"<button class='row'>Row {i}</button>" for i in range(500))).encode()

class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.startswith('/slow'):
            time.sleep(0.4)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(HTML)))
        self.end_headers()
        try:
            self.wfile.write(HTML)
        except (BrokenPipeError, ConnectionResetError):
            pass


def request(path, method, **params):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(20)
        client.connect(str(path))
        client.sendall((json.dumps({'id': 'bench', 'method': method, 'params': params}) + '\n').encode())
        data = bytearray()
        while not data.endswith(b'\n'):
            block = client.recv(65536)
            if not block:
                raise RuntimeError('Daemon disconnected')
            data.extend(block)
        message = json.loads(data)
        if message.get('error'):
            raise RuntimeError(message['error'])
        return message['result']


def summary(values):
    ordered = sorted(values)
    return {'n': len(values), 'median_ms': statistics.median(values),
            'p95_ms': ordered[math.ceil(len(values) * .95) - 1], 'max_ms': max(values)}


def run(binary, output):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}'
    path = Path(tempfile.gettempdir()) / f'aether-perf-{server.server_port}.sock'
    result = {'binary': str(Path(binary).resolve()), 'sha256': hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
              'checks': [], 'benchmarks': {}, 'memory_scope': 'daemon RSS only; excludes WebKit services'}
    with output.with_suffix('.log').open('w') as log:
        daemon = subprocess.Popen([binary, '--socket', str(path), '--no-auth'], stdout=log, stderr=log)
        def call(method, **params):
            return request(path, method, **params)
        try:
            deadline = time.monotonic() + 15
            while not path.exists():
                if time.monotonic() > deadline or daemon.poll() is not None:
                    raise RuntimeError('Daemon failed to start')
                time.sleep(.05)
            context = call('context.create', name='local-performance')['id']
            pages = []
            for workers in (1, 4, 8):
                while len(pages) < workers:
                    pages.append(call('page.create', context=context)['id'])
                start = time.perf_counter()
                with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                    loaded = list(pool.map(lambda p: call('page.navigate', page=p, url=base), pages[:workers]))
                assert all(p['title'] == 'Performance fixture' for p in loaded), loaded
                result['benchmarks'][f'navigation_{workers}_makespan_ms'] = (time.perf_counter() - start) * 1000
                def queries(page):
                    values = []
                    for i in range(60):
                        start = time.perf_counter()
                        found = call('page.query', page=page, selector='#apply')
                        values.append((time.perf_counter() - start) * 1000)
                        assert found['name'] == 'Apply'
                    return values
                with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                    values = [v for group in pool.map(queries, pages[:workers]) for v in group]
                result['benchmarks'][f'query_{workers}'] = summary(values)
                print(json.dumps({f'query_{workers}': summary(values)}), flush=True)
            page = pages[0]
            field = call('page.query', page=page, selector='#field')
            button = call('page.query', page=page, selector='#apply')
            call('page.fill', page=page, nodeIndex=field['index'], nodeGeneration=field['generation'], value='Updated')
            call('page.click', page=page, nodeIndex=button['index'], nodeGeneration=button['generation'])
            assert call('page.query', page=page, selector='#result')['name'] == 'Updated'
            assert call('page.query', page=page, selector='#secret')['value'] == '[redacted]'
            assert len(call('page.queryAll', page=page, selector='.row')) == 500
            result['checks'].append('query, queryAll, fill, click, and password redaction')
            times = []
            for i in range(20):
                start = time.perf_counter()
                snapshot = call('page.snapshot', page=page, limit=200)
                times.append((time.perf_counter() - start) * 1000)
                assert len(snapshot['nodes']) == 200
            result['benchmarks']['snapshot_200'] = summary(times)
            result['checks'].append('snapshot limit and decoding')
            call('page.reload', page=page)
            try:
                call('page.click', page=page, nodeIndex=button['index'], nodeGeneration=button['generation'])
            except RuntimeError:
                result['checks'].append('stale node rejected after reload')
            else:
                raise AssertionError('Stale node accepted')
            result['daemon_rss_kib'] = int(subprocess.check_output(['ps', '-o', 'rss=', '-p', str(daemon.pid)], text=True).strip())
            for page in pages[1:]:
                call('page.close', page=page)
            for attempt in range(5):
                with socket.socket(socket.AF_UNIX) as abandoned:
                    abandoned.connect(str(path))
                    abandoned.sendall((json.dumps({'id': 'abandoned', 'method': 'page.navigate',
                                                 'params': {'page': pages[0], 'url': base + '/slow'}}) + '\n').encode())
                    time.sleep(.1)
                time.sleep(.6)
                if daemon.poll() is not None:
                    break
                call('ping')
            result['abandoned_client'] = {'attempts': attempt + 1, 'daemon_exit': daemon.poll(), 'survived': daemon.poll() is None}
            if daemon.poll() is None:
                call('page.close', page=pages[0])
                call('context.destroy', context=context)
                result['final_fleet'] = call('fleet.stats')
            print(json.dumps(result['abandoned_client']), flush=True)
        except Exception as error:
            result['error'] = repr(error)
            raise
        finally:
            if daemon.poll() is None:
                daemon.terminate()
                try:
                    daemon.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    daemon.wait()
            path.unlink(missing_ok=True)
            server.shutdown()
            output.write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    run(args.binary, args.output)
