import BrowserEngine
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

struct WebKitNavigationReliabilityTests {
  private static let serverScript = """
    import http.server, sys, time, urllib.parse
    port = int(sys.argv[1])
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass
        def send_html(self, title, body):
            payload = ("<html><head><title>" + title + "</title></head><body>" + body + "</body></html>").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            if path == "/fast":
                self.send_html("Fast", "fast-ok")
            elif path == "/target":
                self.send_html("Target", "target-ok")
            elif path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/target")
                self.end_headers()
            elif path == "/slow":
                time.sleep(6)
                self.send_html("Slow", "slow-ok")
            elif path == "/lag":
                time.sleep(0.3)
                self.send_html("Lag", "lag-ok")
            elif path == "/slow.js":
                time.sleep(3)
                payload = b"globalThis.__slowReady = true;"
                self.send_response(200)
                self.send_header("Content-Type", "application/javascript")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            elif path == "/withslow":
                self.send_html("WithSlow", 'withslow-ok<script src="/slow.js" defer></script>')
            elif path == "/framed":
                self.send_html("Framed", 'framed-ok<iframe src="http://127.0.0.1:9/dead-frame"></iframe>')
            elif path == "/download":
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Disposition", 'attachment; filename="fixture.bin"')
                self.end_headers()
                self.wfile.write(b"fixture")
            else:
                self.send_response(404)
                self.end_headers()
    http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
    """

  private func startServer(port: UInt16) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", Self.serverScript, "\(port)"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if !process.isRunning { throw BrowserRuntimeError.timeout("fixture server exited early") }
      let probe = Process()
      probe.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
      probe.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://127.0.0.1:\(port)/fast"]
      let pipe = Pipe()
      probe.standardOutput = pipe
      probe.standardError = Pipe()
      try? probe.run()
      probe.waitUntilExit()
      let code = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      if code == "200" { return process }
      Thread.sleep(forTimeInterval: 0.2)
    }
    process.terminate()
    throw BrowserRuntimeError.timeout("fixture server never became reachable")
  }

  private func makePage() async throws -> (BrowserRuntime, PageID) {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "reliability")
    let page = try await runtime.createPage(contextID: context.id)
    return (runtime, page.id)
  }

  @Test func navigationErrorClassificationIsStable() {
    let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(cancelled) == .benign)
    let interrupted = NSError(domain: "WebKitErrorDomain", code: 102, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(interrupted) == .benign)
    // Modern WebKit reports the same interruption under WKErrorDomain, which
    // used to fall through as a genuine failure and replace a rendered page.
    let interruptedWK = NSError(domain: "WKErrorDomain", code: 102, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(interruptedWK) == .benign)
    #expect(WebKitNavigationErrorClass.isFrameLoadInterrupted(interruptedWK))
    let pluginWK = NSError(domain: "WKErrorDomain", code: 204, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(pluginWK) == .benign)
    // A cancellation is a cancellation regardless of the reporting domain.
    #expect(WebKitNavigationErrorClass.isCancellation(CancellationError()))
    #expect(WebKitNavigationErrorClass.isCancellation(interruptedWK) == false)
    let offline = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(offline) == .genuine)
    let dns = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(dns) == .genuine)
    let refused = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(refused) == .genuine)
    let timedOut = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
    #expect(WebKitNavigationErrorClass.classify(timedOut) == .genuine)
  }

  @Test @MainActor func genuineFailureSurfacesThenClearsOnSuccess() async throws {
    let server = try startServer(port: 18811)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    do {
      try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:9/refused")!)
      Issue.record("connection-refused navigation unexpectedly succeeded")
    } catch {}
    let failed = try await runtime.pageState(pageID: page)
    #expect(failed.error != nil)
    let info = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18811/fast")!)
    #expect(info.url?.path == "/fast")
    let recovered = try await runtime.pageState(pageID: page)
    #expect(recovered.error == nil)
    #expect(recovered.contentReady == true)
    #expect(recovered.loading == false)
  }

  @Test @MainActor func redirectDoesNotProduceFailure() async throws {
    let server = try startServer(port: 18812)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    let info = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18812/redirect")!)
    #expect(info.url?.path == "/target")
    let state = try await runtime.pageState(pageID: page)
    #expect(state.error == nil)
    #expect(state.loading == false)
  }

  @Test @MainActor func supersededNavigationCannotCorruptSuccessor() async throws {
    let server = try startServer(port: 18813)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    let slow = Task {
      try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:18813/slow")!)
    }
    try await Task.sleep(for: .milliseconds(500))
    let info = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18813/fast")!)
    _ = await slow.result
    #expect(info.url?.path == "/fast")
    try await Task.sleep(for: .seconds(1))
    let state = try await runtime.pageState(pageID: page)
    #expect(state.error == nil)
    #expect(state.loading == false)
    #expect(state.target?.path == "/fast")
  }

  @Test @MainActor func subframeFailureDoesNotReplaceRenderedPage() async throws {
    let server = try startServer(port: 18814)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    let info = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18814/framed")!)
    #expect(info.url?.path == "/framed")
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline {
      let state = try await runtime.pageState(pageID: page)
      #expect(state.error == nil)
      if state.loading == false {
        try await Task.sleep(for: .milliseconds(1500))
        #expect(try await runtime.pageState(pageID: page).error == nil)
        return
      }
      try await Task.sleep(for: .milliseconds(200))
    }
    Issue.record("framed page never finished loading")
  }

  @Test @MainActor func firstContentIsReadyAtCommit() async throws {
    let server = try startServer(port: 18815)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    _ = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18815/withslow")!, settle: .commit)
    let committed = try await runtime.pageState(pageID: page)
    #expect(committed.error == nil)
    #expect(committed.contentReady == true)
    _ = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18815/withslow")!, settle: .complete)
    let finished = try await runtime.pageState(pageID: page)
    #expect(finished.error == nil)
    #expect(finished.contentReady == true)
    #expect(finished.loading == false)
  }

  @Test @MainActor func contentIsUsableBeforeResourcesFinish() async throws {
    let server = try startServer(port: 18817)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    _ = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18817/withslow")!, settle: .commit)
    let committed = try await runtime.pageState(pageID: page)
    #expect(committed.error == nil)
    #expect(committed.contentReady == true)
    #expect(committed.loading == true)
    let deadline = Date().addingTimeInterval(12)
    while Date() < deadline {
      let state = try await runtime.pageState(pageID: page)
      #expect(state.error == nil)
      #expect(state.contentReady == true)
      if state.loading == false { return }
      try await Task.sleep(for: .milliseconds(200))
    }
    Issue.record("deferred script never finished")
  }

  @Test @MainActor func retryAfterGenuineFailureLeavesNoResidue() async throws {
    let server = try startServer(port: 18818)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    do {
      _ = try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:9/refused")!)
      Issue.record("connection-refused navigation unexpectedly succeeded")
    } catch {}
    let failed = try await runtime.pageState(pageID: page)
    #expect(failed.error != nil)
    #expect(failed.page.historyCount == 0)
    let info = try await runtime.navigate(
      pageID: page, to: URL(string: "http://127.0.0.1:18818/fast")!)
    #expect(info.url?.path == "/fast")
    let retried = try await runtime.pageState(pageID: page)
    #expect(retried.error == nil)
    #expect(retried.loading == false)
    #expect(retried.contentReady == true)
    #expect(retried.page.historyCount == 1)
  }

  @Test @MainActor func stoppedNavigationReportsNoError() async throws {
    let server = try startServer(port: 18816)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    let slow = Task {
      try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:18816/slow")!)
    }
    try await Task.sleep(for: .milliseconds(500))
    await runtime.stopNavigation(pageID: page)
    _ = await slow.result
    let state = try await runtime.pageState(pageID: page)
    #expect(state.error == nil)
    #expect(state.loading == false)
  }

  @Test @MainActor func interruptedDownloadWithoutReplacementDoesNotWaitForDeadline() async throws {
    let server = try startServer(port: 18819)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    var finished = false
    let navigation = Task { @MainActor in
      defer { finished = true }
      _ = try? await runtime.navigate(
        pageID: page, to: URL(string: "http://127.0.0.1:18819/download")!)
    }
    try await Task.sleep(for: .seconds(3))
    let state = try await runtime.pageState(pageID: page)
    #expect(finished)
    #expect(state.loading == false)
    #expect(state.error == nil)
    if !finished { await runtime.stopNavigation(pageID: page) }
    _ = await navigation.result
  }

  @Test @MainActor func rapidReplacementsKeepTheLastDocument() async throws {
    let server = try startServer(port: 18820)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    for index in 0..<10 {
      let pending = Task {
        try? await runtime.navigate(
          pageID: page, to: URL(string: "http://127.0.0.1:18820/lag?attempt=\(index)")!)
      }
      try await Task.sleep(for: .milliseconds(25))
      let expected = URL(string: "http://127.0.0.1:18820/fast?attempt=\(index)")!
      let info = try await runtime.navigate(pageID: page, to: expected)
      _ = await pending.result
      #expect(info.url == expected)
      let state = try await runtime.pageState(pageID: page)
      #expect(state.target == expected)
      #expect(state.error == nil)
      #expect(state.contentReady)
      #expect(!state.loading)
    }
  }

  @Test @MainActor func backForwardAndReloadKeepNavigationState() async throws {
    let server = try startServer(port: 18821)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    _ = try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:18821/fast")!)
    _ = try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:18821/target")!)
    #expect(try await runtime.goBack(pageID: page).url?.path == "/fast")
    #expect(try await runtime.goForward(pageID: page).url?.path == "/target")
    #expect(try await runtime.reload(pageID: page).url?.path == "/target")
    let state = try await runtime.pageState(pageID: page)
    #expect(state.error == nil)
    #expect(state.contentReady)
    #expect(!state.loading)
  }

  @Test @MainActor func svgNamespacedHrefNeverBreaksInspection() async throws {
    let (runtime, page) = try await makePage()
    let html = """
      <html><head><title>SVG</title></head><body>
      <svg xmlns="http://www.w3.org/2000/svg"><a href="https://example.com/svg-pricing"><text>Pricing</text></a><use href="#icon"></use></svg>
      <a href="https://example.com/plain">Plain</a>
      </body></html>
      """
    _ = try await runtime.loadHTML(pageID: page, html: html, url: URL(string: "https://fixture.test/")!)
    let snap = try await runtime.snapshot(pageID: page)
    #expect(!snap.nodes.isEmpty)
    let nodes = try await runtime.queryAll(pageID: page, selector: "a")
    #expect(nodes.count >= 2)
    #expect(nodes.contains { $0.href == "https://example.com/plain" })
    #expect(nodes.allSatisfy { $0.href == nil || $0.href!.hasPrefix("http") })
  }

  @Test @MainActor func processTerminationCallbackReportsGenuineFailure() async throws {
    let server = try startServer(port: 18822)
    defer { server.terminate() }
    let (runtime, page) = try await makePage()
    _ = try await runtime.navigate(pageID: page, to: URL(string: "http://127.0.0.1:18822/fast")!)
    let webPage = try await runtime.webPage(page)
    webPage.webViewWebContentProcessDidTerminate(webPage.view)
    _ = try await runtime.synchronizedWebInfo(page)
    let state = try await runtime.pageState(pageID: page)
    #expect(state.error?.contains("process stopped") == true)
    #expect(!state.contentReady)
    #expect(!state.loading)
  }
}
