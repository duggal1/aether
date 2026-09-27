import BrowserEvents
import EngineCore
import Foundation
import Testing

private func collect(
  _ stream: AsyncStream<BrowserEvent>, count: Int, timeout: Duration = .seconds(2)
) async -> [BrowserEvent] {
  await withTaskGroup(of: [BrowserEvent].self) { group in
    group.addTask {
      var out: [BrowserEvent] = []
      for await event in stream {
        out.append(event)
        if out.count >= count { break }
      }
      return out
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return []
    }
    let first = await group.next() ?? []
    group.cancelAll()
    return first
  }
}

struct BrowserEventBusTests {
  @Test func sequenceIsMonotonicAcrossPublishers() async {
    let bus = BrowserEventBus()
    let first = await bus.publish(.navigationStarted(url: "https://a.test/"))
    let second = await bus.publish(.navigationCommitted(url: "https://a.test/", statusCode: 200))
    let third = await bus.publish(.navigationFinished(url: "https://a.test/", title: "A"))
    #expect(first.sequence == 1)
    #expect(second.sequence == 2)
    #expect(third.sequence == 3)
    #expect(await bus.lastSequence == 3)
  }

  @Test func subscriberReceivesPublishedEventsInOrder() async {
    let bus = BrowserEventBus()
    let stream = await bus.subscribe()
    await bus.publish(.consoleMessage(level: "log", text: "one"))
    await bus.publish(.consoleMessage(level: "error", text: "two"))
    let events = await collect(stream, count: 2)
    #expect(events.map(\.name) == ["console.message", "console.message"])
    #expect(events.map(\.sequence) == [1, 2])
    #expect(events[1].details["level"] == "error")
  }

  @Test func familyFilterDropsOtherFamilies() async {
    let bus = BrowserEventBus()
    let stream = await bus.subscribe(filter: BrowserEventBus.Filter(families: [.console]))
    await bus.publish(.navigationStarted(url: "https://a.test/"))
    await bus.publish(.consoleMessage(level: "log", text: "kept"))
    await bus.publish(.titleChanged(title: "dropped"))
    let events = await collect(stream, count: 1)
    #expect(events.count == 1)
    #expect(events.first?.kind == .consoleMessage(level: "log", text: "kept"))
  }

  @Test func pageFilterMatchesOnlyThatPage() async {
    let bus = BrowserEventBus()
    let page = PageID(rawValue: 7)
    let stream = await bus.subscribe(filter: BrowserEventBus.Filter(pages: [page]))
    await bus.publish(.pageClosed(reason: "other"), identity: BrowserEventIdentity(page: PageID(rawValue: 1)))
    await bus.publish(.pageClosed(reason: "wanted"), identity: BrowserEventIdentity(page: page))
    let events = await collect(stream, count: 1)
    #expect(events.count == 1)
    #expect(events.first?.details["reason"] == "wanted")
  }

  @Test func replayDeliversRecentJournal() async {
    let bus = BrowserEventBus()
    for index in 0..<5 {
      await bus.publish(.consoleMessage(level: "log", text: "line-\(index)"))
    }
    let stream = await bus.subscribe(replay: 2)
    let events = await collect(stream, count: 2)
    #expect(events.map { $0.details["text"] } == ["line-3", "line-4"])
  }

  @Test func recentRespectsSinceSequence() async {
    let bus = BrowserEventBus()
    for index in 0..<5 {
      await bus.publish(.consoleMessage(level: "log", text: "line-\(index)"))
    }
    let recent = await bus.recent(since: 3)
    #expect(recent.map(\.sequence) == [4, 5])
  }

  @Test func journalIsBounded() async {
    let bus = BrowserEventBus(journalLimit: 3)
    for index in 0..<10 {
      await bus.publish(.consoleMessage(level: "log", text: "line-\(index)"))
    }
    let recent = await bus.recent(limit: 100)
    #expect(recent.count == 3)
    #expect(recent.map(\.sequence) == [8, 9, 10])
  }

  @Test func identityCarriesContextPageAndBranch() async {
    let bus = BrowserEventBus()
    let identity = BrowserEventIdentity(
      context: ContextID(rawValue: 2), page: PageID(rawValue: 5), branch: "branch-a")
    let event = await bus.publish(.branchCreated(parent: "main"), identity: identity)
    #expect(event.identity.context == ContextID(rawValue: 2))
    #expect(event.identity.page == PageID(rawValue: 5))
    #expect(event.identity.branch == "branch-a")
    #expect(event.family == .branch)
  }
}
