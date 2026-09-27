import BrowserEvents
import EngineCore
import EngineRuntime
import Foundation
import Testing

private func collectUntil(
  _ stream: AsyncStream<BrowserEvent>, timeout: Duration = .seconds(20),
  until: @escaping @Sendable (BrowserEvent) -> Bool
) async -> [BrowserEvent]? {
  await withTaskGroup(of: [BrowserEvent]?.self) { group in
    group.addTask {
      var out: [BrowserEvent] = []
      for await event in stream {
        out.append(event)
        if until(event) { return out }
      }
      return out
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return nil
    }
    let result = await group.next() ?? nil
    group.cancelAll()
    return result
  }
}

struct BrowserEventIntegrationTests {
  @Test @MainActor func navigationEmitsOrderedTypedEvents() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "events")
    let page = try await runtime.createPage(contextID: context.id)
    let stream = await runtime.observeEvents()
    let collector = Task {
      await collectUntil(stream, until: { $0.name == "navigation.finished" })
    }
    _ = try await runtime.loadHTML(
      pageID: page.id,
      html: "<html><head><title>Events</title></head><body>hello</body></html>",
      url: URL(string: "https://events.test/page")!)
    let events = try #require(await collector.value)
    let names = events.map(\.name)
    #expect(names.contains("navigation.started"))
    #expect(names.contains("navigation.committed"))
    #expect(names.contains("navigation.finished"))
    #expect(events.allSatisfy { $0.identity.page == page.id })
    #expect(events.allSatisfy { $0.identity.context == context.id })
    let committed = names.firstIndex(of: "navigation.committed")
    let finished = names.firstIndex(of: "navigation.finished")
    #expect(committed != nil)
    #expect(finished != nil)
    if let committed, let finished { #expect(committed < finished) }
  }

  @Test @MainActor func titleChangeEmitsDocumentEvent() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "title")
    let page = try await runtime.createPage(contextID: context.id)
    let stream = await runtime.observeEvents()
    let collector = Task {
      await collectUntil(stream, until: { $0.name == "document.titleChanged" })
    }
    _ = try await runtime.loadHTML(
      pageID: page.id,
      html: "<html><head><title>Title Event</title></head><body>x</body></html>",
      url: URL(string: "https://title.test/")!)
    let events = try #require(await collector.value)
    let titled = try #require(events.first { $0.name == "document.titleChanged" })
    #expect(titled.details["title"] == "Title Event")
    #expect(titled.family == .document)
    #expect(titled.identity.page == page.id)
  }

  @Test @MainActor func consoleMessagesEmitEventsAndFeedConsoleOutput() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "console")
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.loadHTML(
      pageID: page.id,
      html: "<html><head><title>Console</title></head><body></body></html>",
      url: URL(string: "https://console.test/")!)
    let stream = await runtime.observeEvents()
    let collector = Task {
      await collectUntil(stream, until: { $0.name == "console.message" })
    }
    _ = try await runtime.evaluate(pageID: page.id, source: "console.log('hello', {a:1})")
    let events = try #require(await collector.value)
    let consoleEvent = try #require(events.first { $0.name == "console.message" })
    #expect(consoleEvent.details["level"] == "log")
    #expect(consoleEvent.details["text"] == "hello {\"a\":1}")
    var lines: [String] = []
    for _ in 0..<40 {
      lines = try await runtime.consoleOutput(pageID: page.id)
      if !lines.isEmpty { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(lines == ["hello {\"a\":1}"])
  }

  @Test @MainActor func contextLifecycleEmitsEvents() async throws {
    let runtime = BrowserRuntime()
    let stream = await runtime.observeEvents()
    let collector = Task {
      await collectUntil(stream, until: { $0.name == "context.created" })
    }
    let context = await runtime.createContext(name: "lifecycle")
    let events = try #require(await collector.value)
    let created = try #require(events.first { $0.name == "context.created" })
    #expect(created.identity.context == context.id)
    #expect(created.details["name"] == "lifecycle")
    #expect(created.family == .context)
  }

  @Test @MainActor func pageCreatedEmitsEventWithIdentity() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "pages")
    let stream = await runtime.observeEvents()
    let collector = Task {
      await collectUntil(stream, until: { $0.name == "page.created" })
    }
    let page = try await runtime.createPage(contextID: context.id)
    let events = try #require(await collector.value)
    let created = try #require(events.first { $0.name == "page.created" })
    #expect(created.identity.page == page.id)
    #expect(created.identity.context == context.id)
  }

  @Test @MainActor func recentEventsReplaysWithoutPolling() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "recent")
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.loadHTML(
      pageID: page.id,
      html: "<html><head><title>Recent</title></head><body>recent</body></html>",
      url: URL(string: "https://recent.test/")!)
    let journal = await runtime.recentEvents(limit: 100, filter: BrowserEventBus.Filter(families: [.navigation]))
    let names = journal.map(\.name)
    #expect(names.contains("navigation.finished"))
    #expect(journal.allSatisfy { $0.identity.page == page.id })
    #expect(journal.map(\.sequence) == journal.map(\.sequence).sorted())
  }
}
