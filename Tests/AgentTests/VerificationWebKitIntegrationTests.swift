import BrowserEvents
import BrowserVerification
import EngineCore
import EngineRuntime
import Foundation
import Testing

@Test @MainActor func realWebKitNavigationEventsDriveVerificationOutcomes() async throws {
  let portFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("aether-http-\(UUID().uuidString).port")
  defer { try? FileManager.default.removeItem(at: portFile) }
  let server = Process()
  server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
  server.arguments = ["-c", """
    import http.server, sys, time, urllib.parse
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def reply(self, status, title, body):
            payload = ("<html><head><title>" + title + "</title></head><body>" + body + "</body></html>").encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            if path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/ok")
                self.end_headers()
            elif path == "/ok":
                self.reply(200, "OK", "confirmed")
            elif path == "/error":
                self.reply(500, "Rejected", "server rejected")
            else:
                self.reply(404, "Missing", "not found")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1], "w") as port_file:
        port_file.write(str(server.server_address[1]))
    server.serve_forever()
    """, portFile.path]
  server.standardOutput = Pipe()
  server.standardError = Pipe()
  try server.run()
  defer {
    if server.isRunning {
      server.terminate()
      server.waitUntilExit()
    }
  }

  let deadline = Date().addingTimeInterval(10)
  while !FileManager.default.fileExists(atPath: portFile.path), Date() < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  let portText = try String(contentsOf: portFile, encoding: .utf8)
  let port = try #require(UInt16(portText))
  let baseURL = try #require(URL(string: "http://127.0.0.1:\(port)"))

  let runtime = BrowserRuntime()
  let context = await runtime.createContext(name: "webkit-verification")
  let page = try await runtime.createPage(contextID: context.id)
  let filter = BrowserEventBus.Filter(contexts: [context.id], pages: [page.id])

  func navigateAndCollect(_ path: String) async throws -> (UInt64, [BrowserEvent]) {
    let cursor = await runtime.events.lastSequence
    let stream = await runtime.observeEvents(filter: filter)
    let collector = Task { () -> [BrowserEvent] in
      var observed: [BrowserEvent] = []
      for await event in stream {
        observed.append(event)
        if event.name == "navigation.finished" || event.name == "navigation.failed" { break }
      }
      return observed
    }
    _ = try await runtime.navigate(pageID: page.id, to: baseURL.appending(path: path))
    return (cursor, await collector.value)
  }

  let (successCursor, successEvents) = try await navigateAndCollect("/ok")
  let successNames = successEvents.map(\.name)
  let started = try #require(successNames.firstIndex(of: "navigation.started"))
  let response = try #require(successNames.firstIndex(of: "network.navigationResponse"))
  let committed = try #require(successNames.firstIndex(of: "navigation.committed"))
  let finished = try #require(successNames.firstIndex(of: "navigation.finished"))
  #expect(started < response && response < committed && committed < finished)
  #expect(successEvents.allSatisfy {
    $0.identity.context == context.id && $0.identity.page == page.id
  })
  #expect(zip(successEvents, successEvents.dropFirst()).allSatisfy { $0.sequence < $1.sequence })
  #expect(zip(successEvents, successEvents.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp })
  let successPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "http-200", assertion: .navigationResponse(
          url: .init(baseURL.appending(path: "/ok").absoluteString), statusCode: 200,
          sinceSequence: successCursor)),
      BrowserVerificationCheck(id: "title", assertion: .pageTitle(.init("OK"))),
    ])
  do {
    let result = try await runtime.verify(successPlan)
    #expect(result.status == .verified, "\(result.evidence)")
  } catch {
    Issue.record("Successful WebKit verification threw: \(error)")
  }

  let (errorCursor, errorEvents) = try await navigateAndCollect("/error")
  #expect(errorEvents.contains { $0.name == "network.navigationResponse" })
  let errorPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "http-500", assertion: .navigationResponse(
          url: .init(baseURL.appending(path: "/error").absoluteString), statusCode: 200,
          sinceSequence: errorCursor))
    ])
  #expect(try await runtime.verify(errorPlan).status == .failed)

  let (redirectCursor, redirectEvents) = try await navigateAndCollect("/redirect")
  #expect(redirectEvents.contains { $0.name == "navigation.redirected" })
  let redirectPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "redirect-target", assertion: .navigationResponse(
          url: .init(baseURL.appending(path: "/ok").absoluteString), statusCode: 200,
          sinceSequence: redirectCursor)),
      BrowserVerificationCheck(
        id: "final-url", assertion: .pageURL(
          .init(baseURL.appending(path: "/ok").absoluteString))),
    ])
  #expect(try await runtime.verify(redirectPlan).status == .verified)

  let failureCursor = await runtime.events.lastSequence
  do {
    try await runtime.navigate(pageID: page.id, to: URL(string: "http://127.0.0.1:9/refused")!)
    Issue.record("Restricted-port navigation should fail")
  } catch {
    #expect((error as NSError).domain == "WebKitErrorDomain")
  }
  var failureEvents: [BrowserEvent] = []
  for _ in 0..<50 {
    failureEvents = await runtime.recentEvents(limit: 64, filter: filter, since: failureCursor)
    if failureEvents.contains(where: { $0.name == "navigation.failed" }) { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(failureEvents.contains { $0.name == "navigation.failed" })
  let failurePlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "refused", assertion: .navigationResponse(
          url: .init("http://127.0.0.1:9/refused"), statusCode: 200,
          sinceSequence: failureCursor))
    ])
  #expect(try await runtime.verify(failurePlan).status == .inconclusive)

  try await runtime.closePage(page.id)
  try await runtime.destroyContext(context.id)
}
