import BrowserEvents
import EngineCore
import EngineRuntime
import Foundation
import Testing

/// Testing Agent 1 — validation of the browser event system.
/// Events are produced by real WebKit navigation and page scripts, never by
/// calling event-emission helpers directly (except the explicit bus-level
/// backpressure test, which is labelled as such).
private func collectEvents(
  _ stream: AsyncStream<BrowserEvent>, timeout: Duration,
  until: @escaping @Sendable ([BrowserEvent]) -> Bool
) async -> [BrowserEvent] {
  await withTaskGroup(of: [BrowserEvent].self) { group in
    group.addTask {
      var out: [BrowserEvent] = []
      for await event in stream {
        out.append(event)
        if until(out) { return out }
      }
      return out
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return []
    }
    let result = await group.next() ?? []
    group.cancelAll()
    return result
  }
}

struct EventSystemValidationTests {
  @Test @MainActor func navigationLifecycleEmitsOrderedTypedIdentities() async throws {
    let server = try ValidationFixtureServer.start(port: 18941)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-nav")
    let page = try await runtime.createPage(contextID: context.id)
    let stream = await runtime.observeEvents()
    let collector = Task {
      await collectEvents(stream, timeout: .seconds(15), until: { events in
        events.filter { $0.name == "navigation.finished" }.count >= 2
      })
    }
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18941, "/fast"))
    _ = try await runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(18941, "/redirect"))
    let events = await collector.value
    let names = events.map(\.name)
    // Monotonic sequence across the ordered page channel.
    #expect(events.map(\.sequence) == events.map(\.sequence).sorted())
    // Every navigation has started -> committed -> finished, in order.
    for _ in 0..<2 {
      let started = names.firstIndex(of: "navigation.started")
      let committed = names.firstIndex(of: "navigation.committed")
      let finished = names.firstIndex(of: "navigation.finished")
      guard let started, let committed, let finished else {
        Issue.record("missing navigation lifecycle event in \(names)")
        continue
      }
      #expect(started < committed)
      #expect(committed < finished)
    }
    // Redirect produced a redirect event and the final URL is the target.
    #expect(names.contains("navigation.redirected"))
    let lastFinished = try #require(events.last { $0.name == "navigation.finished" })
    #expect(lastFinished.details["url"]?.hasSuffix("/fast") == true)
    // Identity is present and correct on every event.
    #expect(events.allSatisfy { $0.identity.page == page.id })
    #expect(events.allSatisfy { $0.identity.context == context.id })
    // Timestamps are non-decreasing with sequence.
    let timestamps = events.map(\.timestamp)
    #expect(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test @MainActor func rapidSupersedingNavigationsKeepMonotonicOrdering() async throws {
    let server = try ValidationFixtureServer.start(port: 18942)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-rapid")
    let page = try await runtime.createPage(contextID: context.id)
    let stream = await runtime.observeEvents()
    let collector = Task { await collectEvents(stream, timeout: .seconds(15), until: { _ in false }) }

    for attempt in 0..<6 {
      let slow = Task {
        try? await runtime.navigate(
          pageID: page.id, to: ValidationFixtureServer.url(18942, "/slow?attempt=\(attempt)"))
      }
      try await Task.sleep(for: .milliseconds(40))
      _ = try await runtime.navigate(
        pageID: page.id, to: ValidationFixtureServer.url(18942, "/fast?attempt=\(attempt)"))
      _ = await slow.result
    }
    try await Task.sleep(for: .seconds(1))
    collector.cancel()
    let events = await collector.value
    // The single-ordered-channel design must never let sequence numbers reorder.
    #expect(events.map(\.sequence) == events.map(\.sequence).sorted())
    let navigation = events.filter { $0.family == .navigation }
    // Every start/commit/finish triple stays internally ordered.
    var started = 0
    var committed = 0
    var finished = 0
    for event in navigation {
      switch event.name {
      case "navigation.started": started += 1
      case "navigation.committed":
        #expect(committed + 1 <= started)
        committed += 1
      case "navigation.finished":
        #expect(finished + 1 <= committed)
        finished += 1
      default: break
      }
    }
    #expect(started > 0)
  }

  @Test @MainActor func consoleSpamDeliversEveryLineInOrder() async throws {
    let server = try ValidationFixtureServer.start(port: 18943)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-console")
    let page = try await runtime.createPage(contextID: context.id)
    let total = 300
    _ = try await runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(18943, "/console-spam?n=\(total)"))

    var lines: [String] = []
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      lines = try await runtime.consoleOutput(pageID: page.id)
      if lines.count >= total { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(lines.count >= total, "only received \(lines.count) of \(total) console lines")
    #expect(Array(lines.prefix(total)) == (0..<total).map { "line-\($0)" })

    let events = await runtime.recentEvents(limit: 2_048, filter: .family(.console))
    #expect(events.map(\.sequence) == events.map(\.sequence).sorted())
    let texts = events.map { $0.details["text"] ?? "" }
    #expect(texts.contains("line-0"))
    #expect(texts.contains("line-\(total - 1)"))
    #expect(events.allSatisfy { $0.details["level"] == "log" })
  }

  @Test @MainActor func documentAndFocusEventsComeFromRealPageBehavior() async throws {
    let server = try ValidationFixtureServer.start(port: 18944)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-document")
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.loadHTML(
      pageID: page.id,
      html: "<html><head><title>Doc</title></head><body><input id='field'></body></html>",
      url: ValidationFixtureServer.url(18944, "/fast"))
    _ = try await runtime.evaluate(pageID: page.id, source: "document.getElementById('field').focus()")
    _ = try await runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(18944, "/mutate"))

    // document.mutated must fire for a semantic DOM change on a real page.
    var mutated = false
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline {
      let documentEvents = await runtime.recentEvents(limit: 200, filter: .family(.document))
      if documentEvents.contains(where: { $0.name == "document.mutated" }) { mutated = true; break }
      try await Task.sleep(for: .milliseconds(150))
    }
    #expect(mutated, "no document.mutated event after real DOM mutation")
    let focusEvents = await runtime.recentEvents(limit: 200, filter: .family(.focus))
    #expect(focusEvents.contains { $0.name == "focus.changed" && $0.details["focused"] == "true" })
  }

  @Test @MainActor func networkNavigationResponseCarriesStatusCode() async throws {
    let server = try ValidationFixtureServer.start(port: 18945)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-network")
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18945, "/fast"))
    let network = await runtime.recentEvents(limit: 200, filter: .family(.network))
    let response = try #require(network.last { $0.name == "network.navigationResponse" })
    #expect(response.details["statusCode"] == "200")
    #expect(response.details["url"]?.hasSuffix("/fast") == true)
    #expect(response.details["mimeType"]?.contains("html") == true)
  }

  @Test @MainActor func navigationFailureEmitsFailedEvent() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-fail")
    let page = try await runtime.createPage(contextID: context.id)
    // Port 9 refuses connections: a genuine navigation failure.
    do {
      _ = try await runtime.navigate(
        pageID: page.id, to: URL(string: "http://127.0.0.1:9/refused")!)
      Issue.record("connection-refused navigation unexpectedly succeeded")
    } catch {}
    let failures = await runtime.recentEvents(limit: 200, filter: .family(.navigation))
      .filter { $0.name == "navigation.failed" }
    let failed = try #require(failures.last)
    #expect(failed.details["benign"] == "false")
    #expect((failed.details["error"] ?? "").isEmpty == false)
    #expect(failed.identity.page == page.id)
  }

  @Test @MainActor func pageAndContextLifecycleEmitOnRealClose() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-lifecycle")
    let page = try await runtime.createPage(contextID: context.id)
    try await runtime.closePage(page.id)
    let pageEvents = await runtime.recentEvents(limit: 100, filter: .family(.page))
    #expect(pageEvents.contains { $0.name == "page.created" && $0.identity.page == page.id })
    #expect(pageEvents.contains { $0.name == "page.closed" && $0.identity.page == page.id })
    try await runtime.destroyContext(context.id)
    let contextEvents = await runtime.recentEvents(limit: 100, filter: .family(.context))
    #expect(contextEvents.contains { $0.name == "context.destroyed" && $0.identity.context == context.id })
  }

  @Test @MainActor func multipleSubscribersReceiveIdenticalOrderedStreams() async throws {
    let server = try ValidationFixtureServer.start(port: 18946)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events-fanout")
    let page = try await runtime.createPage(contextID: context.id)
    let a = await runtime.observeEvents()
    let b = await runtime.observeEvents()
    let collectorA = Task {
      await collectEvents(a, timeout: .seconds(12), until: { $0.contains { $0.name == "navigation.finished" } })
    }
    let collectorB = Task {
      await collectEvents(b, timeout: .seconds(12), until: { $0.contains { $0.name == "navigation.finished" } })
    }
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18946, "/fast"))
    let eventsA = await collectorA.value
    let eventsB = await collectorB.value
    #expect(eventsA.contains { $0.name == "navigation.finished" })
    #expect(eventsB.contains { $0.name == "navigation.finished" })
    // Both subscribers observe the same sequences — no event delivered to one only.
    let sequencesA = Set(eventsA.map(\.sequence))
    let sequencesB = Set(eventsB.map(\.sequence))
    let shared = sequencesA.intersection(sequencesB)
    #expect(shared.contains(where: { sequence in
      eventsA.first { $0.sequence == sequence }?.identity.page == page.id
    }))
    // Each subscriber sees each sequence at most once (no duplicate delivery).
    #expect(eventsA.count == sequencesA.count)
    #expect(eventsB.count == sequencesB.count)
  }

  /// Bus-level characterization of subscriber backpressure. Documents a real
  /// limitation: per-subscriber buffering is `bufferingNewest(512)`, so a burst
  /// larger than the buffer silently drops the oldest events with no gap signal.
  @Test func subscriberBackpressureSilentlyDropsOldestBeyondBuffer() async throws {
    let bus = BrowserEventBus(journalLimit: 4_096)
    let stream = await bus.subscribe(filter: .all, replay: 0)
    for index in 1...700 {
      await bus.publish(.consoleMessage(level: "log", text: "m\(index)"))
    }
    var received: [BrowserEvent] = []
    for await event in stream {
      received.append(event)
      if received.count == 512 { break }
    }
    #expect(received.count == 512, "buffer size changed; review drop semantics")
    #expect(received.first?.details["text"] == "m189")
    #expect(received.last?.details["text"] == "m700")
    #expect(received.map(\.sequence) == received.map(\.sequence).sorted())
  }

  /// Losing events must be observable and recoverable, not silent (TISSUE-006). The bus
  /// counts what it dropped, the hole is visible in the monotonic sequence, and the
  /// bounded journal still serves the dropped prefix back for catch-up.
  @Test func slowSubscriberDropIsObservableAndRecoverableFromJournal() async throws {
    let bus = BrowserEventBus(journalLimit: 4_096)
    let stream = await bus.subscribe(filter: .all, replay: 0)
    #expect(await bus.droppedEventTotal == 0)
    for index in 1...700 {
      await bus.publish(.consoleMessage(level: "log", text: "m\(index)"))
    }
    #expect(await bus.droppedEventTotal == 188, "188 events had to be dropped to keep 512")

    var received: [BrowserEvent] = []
    for await event in stream {
      received.append(event)
      if received.count == 512 { break }
    }
    // The consumer can see exactly what it missed from the sequence numbers alone.
    #expect(received.first?.sequence == 189)
    let gap = (received.last?.sequence ?? 0) - (received.first?.sequence ?? 0) + 1
    #expect(gap == 512)

    // Catch-up: everything dropped is still in the journal and served by sequence.
    let catchUp = await bus.recent(limit: 4_096, filter: .all, since: 0)
    #expect(catchUp.map(\.sequence) == Array(1...700))
    let missing = Set(1...188).subtracting(received.map(\.sequence))
    #expect(catchUp.map(\.sequence).filter { missing.contains($0) }.count == 188)
  }

  /// A filtered subscriber cannot use sequence gaps (filtered-out events look the
  /// same), so the bus exposes an exact per-subscriber drop count (TISSUE-006).
  @Test func filteredSubscriberLossIsCountedPerSubscriber() async throws {
    let bus = BrowserEventBus(journalLimit: 4_096)
    let (token, stream) = await bus.subscribeWithToken(filter: .family(.console), replay: 0)
    #expect(await bus.droppedEventCount(forSubscriber: token) == 0)
    for index in 1...700 {
      await bus.publish(.consoleMessage(level: "log", text: "m\(index)"))
    }
    #expect(await bus.droppedEventCount(forSubscriber: token) == 188)
    var received = 0
    for await _ in stream {
      received += 1
      if received == 512 { break }
    }
    #expect(received == 512)
  }
}
