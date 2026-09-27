import EngineRuntime
import Foundation

/// Real local HTTP fixture used by validation-agent tests. No WebKit mocking: pages
/// are fetched over loopback, scripts run in the page, cookies/localStorage are real.
enum ValidationFixtureServer {
  private static let portOffset = UInt16.random(in: 30_000...40_000)

  static let script = """
    import http.server, os, sys, threading, time, urllib.parse
    port = int(sys.argv[1])
    media_path = sys.argv[2]
    requests = []

    # Watchdog: when the test process dies (including SIGKILL, where no defer runs) this
    # server is reparented to launchd. Exit instead of leaking a listener that would
    # collide with a later run's port and break unrelated suites.
    def _watch_parent():
        original = os.getppid()
        while True:
            time.sleep(0.5)
            if os.getppid() != original:
                os._exit(0)
    threading.Thread(target=_watch_parent, daemon=True).start()

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def send_html(self, title, body, status=200):
            payload = ("<html><head><title>" + title + "</title></head><body>" + body + "</body></html>").encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def send_text(self, text, ctype="text/plain", status=200):
            payload = text.encode()
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            requests.append(path)
            qs = urllib.parse.parse_qs(parsed.query)
            if path == "/requests":
                self.send_text(",".join(requests))
            elif path == "/fast":
                self.send_html("Fast", "fast-ok")
            elif path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/fast")
                self.end_headers()
            elif path == "/bignodes":
                n = int(qs.get("n", ["500"])[0])
                rows = "".join("<li class='row' data-i='%d'>Item %d</li>" % (i, i) for i in range(n))
                self.send_html("BigNodes", "<ul id='list'>" + rows + "</ul>")
            elif path == "/slow":
                time.sleep(6)
                self.send_html("Slow", "slow-ok")
            elif path == "/state":
                self.send_html(
                    "State",
                    "state-ok<script>localStorage.setItem('token','parent-value');"
                    "document.cookie='session=abc; path=/';</script>")
            elif path == "/set-cookie-only":
                self.send_html(
                    "CookieOnly",
                    "cookie-only<script>document.cookie='session=abc; path=/';</script>")
            elif path == "/state-read":
                self.send_html(
                    "StateRead",
                    "<span id='v'></span><script>"
                    "document.getElementById('v').textContent="
                    "localStorage.getItem('token')||'none';</script>")
            elif path == "/mutate":
                self.send_html(
                    "Mutate",
                    "<div id='x'>start</div><script>setTimeout(function(){"
                    "document.title='Mutated';"
                    "document.getElementById('x').textContent='changed'},200)</script>")
            elif path == "/console-spam":
                n = int(qs.get("n", ["200"])[0])
                self.send_html(
                    "Spam",
                    "<script>for(var i=0;i<%d;i++){console.log('line-'+i)}</script>" % n)
            elif path == "/popup":
                self.send_html(
                    "Popup", "<script>window.open('/fast','_blank')</script>")
            elif path == "/download":
                payload = b"artifact-bytes"
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Disposition", 'attachment; filename="artifact.bin"')
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            elif path == "/sample.mp4":
                with open(media_path, "rb") as media_file:
                    payload = media_file.read()
                status = 200
                content_range = None
                requested_range = self.headers.get("Range")
                if requested_range and requested_range.startswith("bytes="):
                    first, last = requested_range[6:].split("-", 1)
                    if first:
                        start = int(first)
                        end = int(last) if last else len(payload) - 1
                    else:
                        suffix_length = int(last)
                        start = max(0, len(payload) - suffix_length)
                        end = len(payload) - 1
                    if start >= len(payload) or end < start:
                        self.send_response(416)
                        self.send_header("Content-Range", "bytes */%d" % len(payload))
                        self.end_headers()
                        return
                    end = min(end, len(payload) - 1)
                    content_range = "bytes %d-%d/%d" % (start, end, len(payload))
                    payload = payload[start:end + 1]
                    status = 206
                self.send_response(status)
                self.send_header("Content-Type", "video/mp4")
                self.send_header("Accept-Ranges", "bytes")
                if content_range:
                    self.send_header("Content-Range", content_range)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            elif path == "/media":
                self.send_html(
                    "Media", '<video id="v" muted preload="auto" src="/sample.mp4"></video>')
            elif path == "/permission":
                self.send_html(
                    "Permission",
                    "<script>navigator.geolocation.getCurrentPosition("
                    "function(){document.title='Granted'},function(){document.title='Denied'})</script>")
            else:
                self.send_response(404)
                self.end_headers()
    http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
    """

  static func randomPort() -> UInt16 { UInt16.random(in: 19_100...19_999) }

  /// Starts the fixture server and returns the process once its unique port answers 200.
  static func start(port: UInt16) throws -> Process {
    let actualPort = port &+ portOffset
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    let mediaPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/media/sample.mp4").path
    process.arguments = ["-c", script, "\(actualPort)", mediaPath]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if !process.isRunning { throw BrowserRuntimeError.timeout("fixture server exited early") }
      if probe(port: actualPort) { return process }
      Thread.sleep(forTimeInterval: 0.2)
    }
    process.terminate()
    throw BrowserRuntimeError.timeout("fixture server never became reachable on \(actualPort)")
  }

  static func probe(port: UInt16) -> Bool {
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    probe.arguments = [
      "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://127.0.0.1:\(port)/fast",
    ]
    let pipe = Pipe()
    probe.standardOutput = pipe
    probe.standardError = Pipe()
    try? probe.run()
    probe.waitUntilExit()
    let code = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return code == "200"
  }

  static func url(_ port: UInt16, _ path: String) -> URL {
    URL(string: "http://127.0.0.1:\(port &+ portOffset)\(path)")!
  }
}
