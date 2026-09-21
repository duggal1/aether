import json
import socket
from pathlib import Path


class AppClient:
    def __init__(self, directory: Path, timeout: float = 10):
        self.directory = directory
        self.timeout = timeout

    def call(self, method: str, **params):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(self.timeout)
            connection.connect(str(self.directory / 'browser.sock'))
            with connection.makefile('rwb', buffering=0) as stream:
                token = (self.directory / 'access.token').read_text().strip()
                stream.write((token + '\n').encode())
                handshake = json.loads(stream.readline())
                if handshake.get('error'):
                    raise RuntimeError(f"Authentication: {handshake['error']}")
                request = {'id': 'benchmark', 'method': method, 'params': params}
                stream.write((json.dumps(request) + '\n').encode())
                response = json.loads(stream.readline())
                if response.get('id') != 'benchmark':
                    raise RuntimeError('Unexpected response ID')
                if response.get('error'):
                    raise RuntimeError(f"{method}: {response['error']}")
                return response['result']

    def evaluate(self, page: int, source: str):
        return json.loads(self.call('page.evaluate', page=page, source=source)['value'])
