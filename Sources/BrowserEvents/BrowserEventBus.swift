import EngineCore
import Foundation

public actor BrowserEventBus {
  public struct Filter: Sendable, Equatable {
    public var families: Set<BrowserEventFamily>?
    public var contexts: Set<ContextID>?
    public var pages: Set<PageID>?

    public init(
      families: Set<BrowserEventFamily>? = nil, contexts: Set<ContextID>? = nil,
      pages: Set<PageID>? = nil
    ) {
      self.families = families
      self.contexts = contexts
      self.pages = pages
    }

    public static let all = Filter()

    public static func family(_ family: BrowserEventFamily) -> Filter {
      Filter(families: [family])
    }

    func matches(_ event: BrowserEvent) -> Bool {
      if let families, !families.contains(event.family) { return false }
      if let contexts {
        guard let context = event.identity.context, contexts.contains(context) else { return false }
      }
      if let pages {
        guard let page = event.identity.page, pages.contains(page) else { return false }
      }
      return true
    }
  }

  private var nextSequence: UInt64 = 0
  private var journal: [BrowserEvent] = []
  private var subscribers: [UUID: (Filter, AsyncStream<BrowserEvent>.Continuation)] = [:]
  private var droppedTotal = 0
  private var droppedBySubscriber: [UUID: Int] = [:]
  private let journalLimit: Int

  public init(journalLimit: Int = 2048) {
    self.journalLimit = max(1, journalLimit)
  }

  @discardableResult
  public func publish(_ kind: BrowserEventKind, identity: BrowserEventIdentity = .none) -> BrowserEvent {
    nextSequence &+= 1
    let event = BrowserEvent(
      sequence: nextSequence, timestamp: Date(), identity: identity, kind: kind)
    journal.append(event)
    if journal.count > journalLimit { journal.removeFirst(journal.count - journalLimit) }
    for (token, subscriber) in subscribers where subscriber.0.matches(event) {
      if case .dropped = subscriber.1.yield(event) {
        droppedTotal += 1
        droppedBySubscriber[token, default: 0] += 1
      }
    }
    return event
  }

  public func subscribe(filter: Filter = .all, replay: Int = 0) -> AsyncStream<BrowserEvent> {
    subscribeWithToken(filter: filter, replay: replay).stream
  }

  /// Subscription that also returns the subscriber token, so a slow consumer can
  /// ask `droppedEventCount(forSubscriber:)` whether it lost events while it was
  /// not reading. Sequences alone cannot prove loss for filtered subscribers
  /// (filtered-out events also look like gaps), but the per-subscriber drop count
  /// is exact, and anything still inside the journal is recoverable with
  /// `recent(since:)`.
  public func subscribeWithToken(filter: Filter = .all, replay: Int = 0) -> (
    token: UUID, stream: AsyncStream<BrowserEvent>
  ) {
    let token = UUID()
    let pair = AsyncStream<BrowserEvent>.makeStream(bufferingPolicy: .bufferingNewest(512))
    if replay > 0 {
      for event in journal.suffix(replay) where filter.matches(event) {
        pair.continuation.yield(event)
      }
    }
    subscribers[token] = (filter, pair.continuation)
    pair.continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(token) }
    }
    return (token, pair.stream)
  }

  public func recent(limit: Int = 200, filter: Filter = .all, since sequence: UInt64 = 0) -> [BrowserEvent] {
    let bounded = max(1, min(limit, journalLimit))
    return Array(journal.lazy.filter { $0.sequence > sequence && filter.matches($0) }.suffix(bounded))
  }

  public var lastSequence: UInt64 { nextSequence }

  /// Events dropped because a subscriber's bounded buffer (newest 512) was full when they
  /// were published. A slow subscriber therefore loses the *oldest* buffered events; the
  /// loss is observable here, detectable from the monotonic `sequence`, and recoverable
  /// through `recent(since:)` while the event is still inside the journal.
  public var droppedEventTotal: Int { droppedTotal }

  public func droppedEventCount(forSubscriber token: UUID) -> Int {
    droppedBySubscriber[token] ?? 0
  }

  private func removeSubscriber(_ token: UUID) {
    subscribers[token] = nil
    droppedBySubscriber[token] = nil
  }
}
