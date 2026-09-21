import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time

with tempfile.TemporaryDirectory(prefix='aether-auth-') as directory:
    path = Path(directory) / 'agent.sock'
    log = Path('agents/codex/webkit-performance/results/auth-disconnect.log').open('w')
    process = subprocess.Popen(['.build/release/browserd', '--socket', str(path)], stdout=log, stderr=log)
    def line(client):
        data = bytearray()
        while not data.endswith(b'\n'):
            chunk = client.recv(65536)
            if not chunk:
                raise RuntimeError('Disconnected')
            data.extend(chunk)
        return json.loads(data)
    try:
        deadline = time.monotonic() + 10
        while not path.exists():
            assert time.monotonic() < deadline
            time.sleep(.05)
        token = Path(str(path) + '.token').read_text().strip()
        for index in range(12):
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(5)
                client.connect(str(path))
                client.sendall((token + '\n').encode())
                assert 'error' not in line(client)
                client.sendall(b'{"id":"ping","method":"ping","params":{}}\n')
                if index % 2 == 0:
                    assert line(client)['result']['ok']
            time.sleep(.05)
            assert process.poll() is None, process.returncode
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            client.connect(str(path))
            client.sendall(b'invalid-token\n')
            assert line(client)['error']['code'] == 'unauthorized'
        assert process.poll() is None
        Path('agents/codex/webkit-performance/results/auth-disconnect.json').write_text(json.dumps({
            'authenticated_connections': 12, 'abandoned_responses': 6,
            'completed_requests': 6, 'invalid_token_rejected': True, 'daemon_survived': True
        }, indent=2))
    finally:
        process.terminate()
        process.wait(timeout=5)
        log.close()
