import argparse
import base64
import concurrent.futures
import hashlib
import http.server
import json
import pathlib
import socket
import subprocess
import tempfile
import threading
import time
import zlib
import struct


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\x20\x60\xa0' * 16) * 16)) + chunk(b'IEND', b'')


IMAGE = png()
PIXEL_HTML = b'''<html><head><style>body{margin:0}#paint{height:100px;background-color:#ff0000}</style></head><body><div id="paint">Before JavaScript</div><script>document.getElementById('paint').setAttribute('style','height:100px;background-color:#00ff00');document.getElementById('paint').textContent='After JavaScript';</script></body></html>'''
CSS = b'body{margin:0;background:white;color:#202020}section{height:300px;padding:20px}header{height:100px;background:#eeeeee}footer{height:80px}img{width:16px;height:16px}'
HTML = b'''<!DOCTYPE html><html><head><title>Capture integration</title><link rel="stylesheet" href="/main.css"></head><body><header><h1>Aether capture verification</h1></header><main><section id="one"><h2>First section</h2><img src="/image.png"><p id="live">Original</p><a id="next" href="/next">Next page</a><input id="name" value="alpha"></section><section id="two"><h2>Second section</h2><img src="/missing.png"><svg viewBox="0 0 20 20"><path d="M0 0L20 20"/></svg></section><section id="three"><h2>Third section</h2></section></main><footer>End of document</footer><script>document.getElementById('live').textContent='Updated by JavaScript';localStorage.setItem('loaded','yes');</script></body></html>'''


class FixtureServer(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/')
            self.end_headers()
            return
        if path == '/slow':
            time.sleep(3)
        status, content_type, body = 200, 'text/html', HTML
        if path == '/main.css':
            content_type, body = 'text/css', CSS
        elif path == '/image.png':
            content_type, body = 'image/png', IMAGE
        elif path == '/missing.png':
            status, body = 404, b'missing'
        elif path == '/blocked':
            status, body = 403, b'<html><body>Denied</body></html>'
        elif path == '/pixel':
            body = PIXEL_HTML
        elif path == '/next':
            body = b'<html><head><title>Next</title></head><body><h1>Next page</h1></body></html>'
        elif path == '/download':
            content_type, body = 'application/octet-stream', b'AETHER-DOWNLOAD\x00\xff'
        elif path == '/long':
            body = b'<html><body>' + b'<section style="height:100px">Long page row</section>' * 250 + b'</body></html>'
        elif path == '/timer':
            body = b"<html><body><p id='late'>Pending</p><script>setTimeout(function(){document.getElementById('late').textContent='Timer completed';},50);</script></body></html>"
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'max-age=300')
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


def rpc(socket_file, method, **params):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(45)
        connection.connect(str(socket_file))
        connection.sendall((json.dumps({'id': 'verify', 'method': method, 'params': params}) + '\n').encode())
        data = bytearray()
        while not data.endswith(b'\n'):
            chunk = connection.recv(65536)
            if not chunk:
                raise RuntimeError('daemon disconnected')
            data.extend(chunk)
        response = json.loads(data)
        if response.get('error'):
            raise RuntimeError(response['error'])
        return response.get('result')


def validate_kit(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    assert manifest['screenshots'], 'no screenshots'
    y = 0
    for tile in manifest['screenshots']:
        assert abs(tile['cssY'] - y) < 0.01, (y, tile)
        y += tile['cssHeight']
        assert (directory / tile['file']).stat().st_size > 20
    if not manifest['truncated']:
        assert abs(y - manifest['documentCSSHeight']) < 1
    for section in manifest['sections']:
        for part in section['screenshotParts']:
            assert (directory / part).is_file()
    for asset in manifest['assets']:
        if asset['status'] == 'saved':
            assert (directory / asset['file']).stat().st_size == asset['byteCount']
    for name in ['website.html', 'design-reference.md', 'styles/index.json', 'computed-styles.json', 'sections.json']:
        assert (directory / name).is_file(), name
    return manifest


def ppm_pixel(result, x, y):
    assert result['format'] == 'ppm', 'unexpected raster transport'
    raw = base64.b64decode(result['data'], validate=True)
    header, pixels = raw.split(b'\n255\n', 1)
    tokens = header.split()
    assert tokens[0] == b'P6', 'unexpected image encoding'
    width, height = map(int, tokens[1:3])
    assert len(pixels) == width * height * 3, 'truncated raster'
    offset = (y * width + x) * 3
    return tuple(pixels[offset:offset + 3])


def png_pixel(path, x, y):
    data = path.read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), 'capture is not PNG'
    cursor, compressed, width, height, channels = 8, bytearray(), 0, 0, 0
    while cursor < len(data):
        size = struct.unpack_from('>I', data, cursor)[0]
        kind = data[cursor + 4:cursor + 8]
        payload = data[cursor + 8:cursor + 8 + size]
        cursor += 12 + size
        if kind == b'IHDR':
            width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', payload)
            assert depth == 8 and color in (2, 6) and interlace == 0, 'unsupported PNG pixel layout'
            channels = 3 if color == 2 else 4
        elif kind == b'IDAT':
            compressed.extend(payload)
        elif kind == b'IEND':
            break
    assert 0 <= x < width and 0 <= y < height, 'pixel outside image'
    stride = width * channels
    raw = zlib.decompress(compressed)
    previous = bytearray(stride)
    cursor = 0
    for row in range(y + 1):
        filtering = raw[cursor]
        current = bytearray(raw[cursor + 1:cursor + 1 + stride])
        cursor += stride + 1
        for i in range(stride):
            left = current[i - channels] if i >= channels else 0
            above = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filtering == 1:
                prediction = left
            elif filtering == 2:
                prediction = above
            elif filtering == 3:
                prediction = (left + above) // 2
            elif filtering == 4:
                candidate = left + above - upper_left
                distances = (abs(candidate - left), abs(candidate - above), abs(candidate - upper_left))
                prediction = (left, above, upper_left)[distances.index(min(distances))]
            else:
                assert filtering == 0, 'unknown PNG row filter'
                prediction = 0
            current[i] = (current[i] + prediction) & 255
        previous = current
    return tuple(previous[x * channels:x * channels + 3])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin', default='.build/out/Products/Debug')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), FixtureServer)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}'
    socket_path = pathlib.Path(tempfile.gettempdir()) / ('aether-verify-' + str(server.server_port) + '.sock')
    results = []
    metrics = []
    log = (output / 'daemon.log').open('w')
    daemon = subprocess.Popen([str(pathlib.Path(args.bin).resolve() / 'browserd'), '--socket', str(socket_path)], stdout=log, stderr=log)
    stop = threading.Event()

    def monitor():
        while not stop.wait(0.2):
            row = subprocess.run(['ps', '-o', 'rss=,%cpu=', '-p', str(daemon.pid)], capture_output=True, text=True).stdout.split()
            if len(row) == 2:
                metrics.append({'seconds': time.monotonic(), 'rssKiB': int(row[0]), 'cpuPercent': float(row[1])})

    threading.Thread(target=monitor, daemon=True).start()
    def check(name, operation):
        start = time.monotonic()
        try:
            detail = operation()
            results.append({'name': name, 'passed': True, 'seconds': time.monotonic() - start, 'detail': detail})
        except Exception as error:
            results.append({'name': name, 'passed': False, 'seconds': time.monotonic() - start, 'error': str(error)})
        print(json.dumps(results[-1]), flush=True)
    def call(method, **params):
        return rpc(socket_path, method, **params)
    def require(value, message):
        assert value, message
    try:
        deadline = time.monotonic() + 10
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        check('daemon ping', lambda: call('ping'))
        context = call('context.create', name='verification')['id']
        page = call('page.create', context=context, width=400, height=300)['id']
        check('navigation and redirect', lambda: require(call('page.navigate', page=page, url=base + '/redirect')['url'] == base + '/', 'redirect URL incorrect'))
        check('script executed', lambda: require(call('page.query', page=page, selector='#live')['name'] == 'Updated by JavaScript', 'DOM not updated'))
        check('local storage', lambda: require(call('page.evaluate', page=page, source="localStorage.getItem('loaded')")['value'] == 'yes', 'storage missing'))
        node = call('page.query', page=page, selector='#name')
        check('fill input', lambda: (call('page.fill', page=page, nodeIndex=node['index'], nodeGeneration=node['generation'], value='beta'), require(call('page.query', page=page, selector='#name')['value'] == 'beta', 'fill failed')))
        check('scroll', lambda: (call('page.scroll', page=page, x=0, y=320), require(call('page.scrollOffset', page=page)['y'] == 320, 'offset incorrect')))
        check('render', lambda: call('page.render', page=page, path=str(output / 'viewport.png')))
        check('resize', lambda: require(call('page.resize', page=page, width=640, height=480)['width'] == 640, 'resize failed'))
        def dynamic_pixels():
            call('page.navigate', page=page, url=base + '/pixel')
            node = call('page.query', page=page, selector='#paint')
            require(node['name'] == 'After JavaScript', 'dynamic DOM text was not rendered')
            rgb = ppm_pixel(call('page.render', page=page), 10, 10)
            require(rgb == (0, 255, 0), f'expected JS-updated green pixel, got {rgb}')
            return {'observedRGB': rgb, 'page': page}
        check('dynamic DOM-to-raster pixels', dynamic_pixels)
        def typed_input():
            result = call('page.navigateInput', page=page, input=f'127.0.0.1:{server.server_port}/pixel')
            require(result['kind'] == 'url', 'address interpreted as a search')
            require(result['page']['url'] == base + '/pixel', 'typed input did not navigate the live page')
            return {'kind': result['kind'], 'url': result['url']}
        check('typed address uses live page', typed_input)
        def history():
            call('page.navigate', page=page, url=base)
            call('page.navigate', page=page, url=base + '/next')
            require(call('page.back', page=page)['title'] == 'Capture integration', 'back failed')
            require(call('page.forward', page=page)['title'] == 'Next', 'forward failed')
            require(call('page.reload', page=page, bypassCache=True)['title'] == 'Next', 'reload failed')
        check('history and reload', history)
        def download():
            result = call('context.download', context=context, url=base + '/download', path=str(output / 'download.bin'))
            require((output / 'download.bin').read_bytes() == b'AETHER-DOWNLOAD\x00\xff', 'download corrupted')
            return result
        check('download bytes', download)
        def profile():
            call('context.openProfile', context=context, directory=str(output / 'profile'))
            call('context.storageSet', context=context, origin=base, key='persist', value='value')
            call('context.checkpoint', context=context)
            call('context.destroy', context=context)
            restored = call('context.create', name='verification')['id']
            call('context.openProfile', context=restored, directory=str(output / 'profile'))
            require(call('context.storageValues', context=restored, origin=base)['persist'] == 'value', 'profile data lost')
            pages = call('page.list', context=restored)
            require(len(pages) == 1 and not pages[0]['loaded'], 'session page missing')
            recovered = call('page.restore', page=pages[0]['id'])
            require(recovered['title'] == 'Next', 'session restore wrong history entry')
            call('context.destroy', context=restored)
        check('profile checkpoint and reopen', profile)
        def sessions():
            first = call('context.create', name='first')['id']
            second = call('context.create', name='second')['id']
            call('context.storageSet', context=first, origin=base, key='private', value='secret')
            require('private' not in call('context.storageValues', context=second, origin=base), 'storage leaked')
            for ctx in [first, second]:
                tab = call('page.create', context=ctx)['id']
                call('page.navigate', page=tab, url=base)
                for state in ['suspended', 'frozen', 'discarded']:
                    call('page.setLifecycle', page=tab, lifecycle=state)
                call('page.restore', page=tab)
                require(call('page.query', page=tab, selector='#live') is not None, 'restore failed')
                call('page.close', page=tab)
                call('context.destroy', context=ctx)
            require(call('fleet.stats')['pages'] == 0, 'pages leaked')
        check('tabs isolation lifecycle cleanup', sessions)
        def capture(name, path='/', **options):
            directory = output / name
            call('page.capture', url=base + path, path=str(directory), width=400, height=300, **options)
            return validate_kit(directory)
        for format_name in ['webp', 'jpeg', 'png']:
            def run(format_name=format_name):
                manifest = capture('kit-' + format_name, format=format_name)
                require(not manifest['truncated'], 'unexpected truncation')
                image = next(asset for asset in manifest['assets'] if asset['sourceURL'].endswith('/image.png'))
                require((output / ('kit-' + format_name) / image['file']).read_bytes() == IMAGE, 'image asset corrupted')
                require('Updated by JavaScript' in (output / ('kit-' + format_name) / 'website.html').read_text(), 'live HTML stale')
                require(call('fleet.stats')['pages'] == 0, 'capture leaked page')
                return {'tiles': len(manifest['screenshots']), 'height': manifest['documentCSSHeight'], 'formats': sorted(set(t['format'] for t in manifest['screenshots'])), 'warnings': manifest['warnings']}
            check('capture ' + format_name, run)
        check('large page bounded capture', lambda: {'truncated': capture('kit-long', '/long', maxScrollSteps=3)['truncated']})
        def timer():
            capture('kit-timer', '/timer')
            require('Timer completed' in (output / 'kit-timer' / 'website.html').read_text(), 'timer never pumped during capture')
        check('delayed JavaScript capture', timer)
        def dynamic_capture_pixels():
            directory = output / 'kit-pixel'
            manifest = capture('kit-pixel', '/pixel', format='png')
            require('After JavaScript' in (directory / 'website.html').read_text(),
                    'captured DOM omitted JavaScript mutation')
            first = manifest['screenshots'][0]
            require(first['format'] == 'png', 'PNG capture unsupported on this host')
            rgb = png_pixel(directory / first['file'], 10, 10)
            require(rgb == (0, 255, 0), f'captured pixel is not JS-updated green: {rgb}')
            return {'observedRGB': rgb, 'screenshot': first['file']}
        check('dynamic capture DOM and pixel', dynamic_capture_pixels)
        def refused(path):
            try:
                call('page.capture', url=base + path, path=str(output / ('failed-' + path[1:])))
                raise AssertionError('capture unexpectedly succeeded')
            except RuntimeError:
                pass
            require(call('fleet.stats')['pages'] == 0, 'failed capture leaked page')
        check('blocked navigation cleanup', lambda: refused('/blocked'))
        def parallel():
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                manifests = list(pool.map(lambda i: capture(f'parallel-{i}'), range(3)))
            require(call('fleet.stats')['pages'] == 0, 'parallel captures leaked')
            return {'captures': len(manifests)}
        check('parallel captures', parallel)
        check('final fleet', lambda: call('fleet.stats'))
    finally:
        stop.set()
        daemon.terminate()
        try:
            daemon.wait(timeout=5)
        except subprocess.TimeoutExpired:
            daemon.kill()
            daemon.wait()
        log.close()
        socket_path.unlink(missing_ok=True)
        server.shutdown()
        (output / 'results.json').write_text(json.dumps({'results': results, 'metrics': metrics, 'peakDaemonRSSKiB': max((m['rssKiB'] for m in metrics), default=0)}, indent=2))
    raise SystemExit(0 if all(r['passed'] for r in results) else 1)


if __name__ == '__main__':
    main()
