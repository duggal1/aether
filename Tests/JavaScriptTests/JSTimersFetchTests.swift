import Foundation
import HTML
import JavaScript
import Storage
import Testing

final class StubTimers: JSTimerHost {
  struct Entry {
    var id: Double
    var fireAt: Double
    var interval: Double?
    var callback: JSFunction
  }

  weak var runtime: JSRuntime?
  var now = 0.0
  var entries: [Double: Entry] = [:]
  var nextID = 1.0

  func setTimeout(milliseconds: Double, repeats: Bool, callback: JSFunction) -> Double {
    let id = nextID
    nextID += 1
    let delay = max(0, milliseconds)
    entries[id] = Entry(
      id: id, fireAt: now + delay, interval: repeats ? delay : nil, callback: callback)
    return id
  }

  func clearTimeout(id: Double) {
    entries.removeValue(forKey: id)
  }

  @discardableResult
  func fireDue(now: Double) -> Int {
    self.now = now
    var fired = 0
    var done = Set<Double>()
    while fired < 1000 {
      let candidate = entries.values
        .filter { $0.fireAt <= now && !done.contains($0.id) }
        .min {
          if $0.fireAt != $1.fireAt { return $0.fireAt < $1.fireAt }
          return $0.id < $1.id
        }
      guard let entry = candidate else { break }
      let id = entry.id
      done.insert(id)
      guard entries[id] != nil, let runtime else { continue }
      if let interval = entry.interval {
        entries[id]?.fireAt = entry.fireAt + interval
      } else {
        entries.removeValue(forKey: id)
      }
      runtime.invokeTimerCallback(entry.callback)
      fired += 1
    }
    return fired
  }
}

private final class SeenBox: @unchecked Sendable {
  var value = ""
}

private func makeTimedRuntime() -> (JSRuntime, StubTimers) {
  let runtime = JSRuntime()
  let timers = StubTimers()
  timers.runtime = runtime
  runtime.timerHost = timers
  return (runtime, timers)
}

private func settle(_ runtime: JSRuntime, timeout: Double = 5.0) async {
  let deadline = Date().timeIntervalSince1970 + timeout
  while Date().timeIntervalSince1970 < deadline {
    runtime.drainCompletions()
    runtime.drainMicrotasks()
    if !runtime.hasPendingMicrotasks && runtime.pendingFetchCount == 0 { break }
    try? await Task.sleep(for: .milliseconds(5))
  }
  runtime.drainCompletions()
  runtime.drainMicrotasks()
}

@Test func timerCallbacksFireInDelayOrder() throws {
  let (runtime, timers) = makeTimedRuntime()
  _ = try runtime.evaluate("log = [];")
  _ = try runtime.evaluate("setTimeout(function() { log.push('slow'); }, 10000);")
  _ = try runtime.evaluate("setTimeout(function() { log.push('fast'); }, 5000);")
  #expect(try runtime.evaluate("log.length").description == "0")
  #expect(timers.fireDue(now: 5000) == 1)
  #expect(try runtime.evaluate("log.join(',')").description == "fast")
  #expect(timers.fireDue(now: 10000) == 1)
  #expect(try runtime.evaluate("log.join(',')").description == "fast,slow")
}

@Test func timerIDsAreNumericAndClearable() throws {
  let (runtime, timers) = makeTimedRuntime()
  _ = try runtime.evaluate("log = [];")
  let id = try runtime.evaluate("setTimeout(function() { log.push('x'); }, 1000)")
  #expect(id.description == "1")
  _ = try runtime.evaluate("clearTimeout(1);")
  #expect(timers.fireDue(now: 100000) == 0)
  #expect(try runtime.evaluate("log.length").description == "0")
}

@Test func timerPassesExtraArguments() throws {
  let (runtime, timers) = makeTimedRuntime()
  _ = try runtime.evaluate(
    "seen = ''; setTimeout(function(a, b) { seen = a + b; }, 0, 'x', 41);")
  #expect(timers.fireDue(now: 0) == 1)
  #expect(try runtime.evaluate("seen").description == "x41")
}

@Test func intervalRepeatsUntilCleared() throws {
  let (runtime, timers) = makeTimedRuntime()
  _ = try runtime.evaluate("count = 0;")
  _ = try runtime.evaluate("id = setInterval(function() { count += 1; }, 1000);")
  #expect(timers.fireDue(now: 1000) == 1)
  #expect(timers.fireDue(now: 2000) == 1)
  #expect(try runtime.evaluate("count").description == "2")
  _ = try runtime.evaluate("clearInterval(id);")
  #expect(timers.fireDue(now: 9000) == 0)
  #expect(try runtime.evaluate("count").description == "2")
}

@Test func throwingTimerCallbackIsReportedAndIsolated() throws {
  let (runtime, timers) = makeTimedRuntime()
  _ = try runtime.evaluate("ok = false;")
  _ = try runtime.evaluate("setTimeout(function() { throw new Error('boom'); }, 1);")
  _ = try runtime.evaluate("setTimeout(function() { ok = true; }, 1);")
  #expect(timers.fireDue(now: 1) == 2)
  #expect(try runtime.evaluate("ok").description == "true")
  #expect(runtime.consoleOutput.contains { $0.contains("boom") })
}

@Test func timersWithoutHostThrow() throws {
  let runtime = JSRuntime()
  do {
    _ = try runtime.evaluate("setTimeout(function() {}, 0);")
    Issue.record("expected timer to throw without a host")
  } catch {
    #expect(String(describing: error).contains("Timers are not available"))
  }
}

@Test func stringTimerCallbackIsRejected() throws {
  let (runtime, _) = makeTimedRuntime()
  do {
    _ = try runtime.evaluate("setTimeout('1 + 1', 0);")
    Issue.record("expected string callback to throw")
  } catch {
    #expect(String(describing: error).contains("must be a function"))
  }
}

@Test func fetchResolvesResponseFields() async throws {
  let runtime = JSRuntime()
  runtime.asyncFetch = { url, method, _, _ in
    (201, ["Content-Type": "application/json", "X-Multi": "a"], Data("{\"a\":1}".utf8))
  }
  _ = try runtime.evaluate(
    "result = ''; fetch('https://example.com/items').then(function(r) { result = r.status + ':' + r.ok + ':' + r.url; });"
  )
  await settle(runtime)
  #expect(try runtime.evaluate("result").description == "201:true:https://example.com/items")
}

@Test func fetchTextAndJsonBodies() async throws {
  let runtime = JSRuntime()
  runtime.asyncFetch = { _, _, _, _ in (200, [:], Data("{\"n\":7}".utf8)) }
  _ = try runtime.evaluate(
    "text = ''; num = 0; fetch('https://example.com/x').then(function(r) { return r.text(); }).then(function(t) { text = t; });"
  )
  _ = try runtime.evaluate(
    "fetch('https://example.com/x').then(function(r) { return r.json(); }).then(function(j) { num = j.n; });"
  )
  await settle(runtime)
  #expect(try runtime.evaluate("text").description == "{\"n\":7}")
  #expect(try runtime.evaluate("num").description == "7")
}

@Test func fetchRejectsNetworkFailuresAsTypeError() async throws {
  struct Boom: Error {}
  let runtime = JSRuntime()
  runtime.asyncFetch = { _, _, _, _ in throw Boom() }
  _ = try runtime.evaluate(
    "verdict = ''; fetch('https://example.com/x').then(function() { verdict = 'ok'; }, function(e) { verdict = (e instanceof TypeError) + ':' + e.message; });"
  )
  await settle(runtime)
  #expect(try runtime.evaluate("verdict").description.hasPrefix("true:fetch failed:"))
}

@Test func fetchWithoutHookThrowsTypeError() throws {
  let runtime = JSRuntime()
  do {
    _ = try runtime.evaluate("fetch('https://example.com/');")
    Issue.record("expected fetch to throw without a hook")
  } catch {
    #expect(String(describing: error).contains("fetch is not available"))
  }
}

@Test func fetchValidatesURLMethodAndBody() throws {
  let runtime = JSRuntime()
  runtime.asyncFetch = { url, _, _, _ in (200, [:], Data()) }
  for source in [
    "fetch(':::not a url:::');",
    "fetch('https://example.com/', { method: 'TRACE' });",
    "fetch('https://example.com/', { method: 'GET', body: 'x' });",
    "new Request('');",
  ] {
    do {
      _ = try runtime.evaluate(source)
      Issue.record("expected throw for \(source)")
    } catch {
    }
  }
}

@Test func fetchResolvesRelativeURLAgainstPage() async throws {
  let runtime = JSRuntime()
  runtime.hostHooks.currentURL = { "https://example.com/dir/page" }
  let seen = SeenBox()
  runtime.asyncFetch = { url, _, _, _ in
    seen.value = url
    return (200, [:], Data())
  }
  _ = try runtime.evaluate("fetch('/api/v1');")
  await settle(runtime)
  #expect(seen.value == "https://example.com/api/v1")
}

@Test func headersRequestResponseRoundTrip() async throws {
  let runtime = JSRuntime()
  runtime.asyncFetch = { url, method, headers, body in
    let echo = "\(method) \(url) \(headers["x-a"] ?? "-") \(body ?? "-")"
    return (200, [:], Data(echo.utf8))
  }
  _ = try runtime.evaluate(
    "h = new Headers({ 'X-A': '1' }); h.append('X-A', '2'); h.set('X-B', '3'); h.delete('X-B');"
  )
  #expect(try runtime.evaluate("h.get('x-a')").description == "1, 2")
  #expect(try runtime.evaluate("h.has('X-B')").description == "false")
  #expect(try runtime.evaluate("h instanceof Headers").description == "true")
  _ = try runtime.evaluate(
    "req = new Request('https://example.com/submit', { method: 'POST', headers: h, body: 'hi' });"
  )
  #expect(try runtime.evaluate("req instanceof Request").description == "true")
  _ = try runtime.evaluate(
    "echo = ''; fetch(req).then(function(r) { return r.text(); }).then(function(t) { echo = t; });"
  )
  await settle(runtime)
  #expect(try runtime.evaluate("echo").description == "POST https://example.com/submit 1, 2 hi")
  _ = try runtime.evaluate("res = new Response('hi', { status: 201 });")
  #expect(try runtime.evaluate("res.status").description == "201")
  #expect(try runtime.evaluate("res.ok").description == "true")
  #expect(try runtime.evaluate("res instanceof Response").description == "true")
  do {
    _ = try runtime.evaluate("new Response('x', { status: 204 });")
    Issue.record("expected null-status body to throw")
  } catch {
  }
}

@Test func responseBodySingleUse() async throws {
  let runtime = JSRuntime()
  runtime.asyncFetch = { _, _, _, _ in (200, [:], Data("abc".utf8)) }
  _ = try runtime.evaluate(
    "second = ''; fetch('https://example.com/').then(function(r) { return r.text().then(function() { return r.text(); }); }).then(function() {}, function(e) { second = e.message; });"
  )
  await settle(runtime)
  #expect(try runtime.evaluate("second").description == "Response body has already been used")
}

@Test func windowMirrorsTimerAndFetchGlobals() throws {
  let document = HTMLParser.parse("<main></main>").document
  let runtime = JSRuntime(document: document)
  #expect(try runtime.evaluate("typeof window.setTimeout").description == "function")
  #expect(try runtime.evaluate("typeof window.fetch").description == "function")
  #expect(try runtime.evaluate("typeof window.Headers").description == "function")
  #expect(try runtime.evaluate("window.setTimeout === setTimeout").description == "true")
}
