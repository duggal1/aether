import EngineCore
import Foundation
import Synchronization

/// Bounded store for human requests with publish-on-mutation observation.
///
/// All mutations are serialized by the owning `BrowserRuntime` actor; the mutex
/// exists so observation registration and publication stay consistent across the
/// actor hop.
final class HandoffLedger: @unchecked Sendable {
  private let lock = Mutex(State())

  private struct State {
    var records: [String: HumanRequestRecord] = [:]
    var observers: [UUID: AsyncStream<HumanRequestRecord>.Continuation] = [:]
  }

  func observe() -> AsyncStream<HumanRequestRecord> {
    let token = UUID()
    let pair = AsyncStream<HumanRequestRecord>.makeStream(bufferingPolicy: .bufferingNewest(256))
    lock.withLock { $0.observers[token] = pair.continuation }
    pair.continuation.onTermination = { [weak self] _ in
      self?.lock.withLock { $0.observers[token] = nil }
    }
    return pair.stream
  }

  func record(id: String) -> HumanRequestRecord? {
    lock.withLock { $0.records[id] }
  }

  func list(
    context: ContextID?, page: PageID?, state: HumanRequestState?, kind: HumanRequestKind?
  ) -> [HumanRequestRecord] {
    lock.withLock { current in
      current.records.values.filter { record in
        (context == nil || record.context == context)
          && (page == nil || record.page == page)
          && (state == nil || record.state == state)
          && (kind == nil || record.kind == kind)
      }.sorted { $0.createdAt < $1.createdAt }
    }
  }

  func openHandoff(page: PageID) -> HumanRequestRecord? {
    lock.withLock { current in
      current.records.values.first {
        $0.kind == .handoff && $0.page == page && $0.state.blocksAgentControl
      }
    }
  }

  func openHandoff(context: ContextID) -> HumanRequestRecord? {
    lock.withLock { current in
      current.records.values.first {
        $0.kind == .handoff && $0.context == context && $0.state.blocksAgentControl
      }
    }
  }

  func interruptedHandoff(context: ContextID) -> HumanRequestRecord? {
    lock.withLock { current in
      current.records.values.first {
        $0.kind == .handoff && $0.context == context && $0.state == .interrupted
      }
    }
  }

  func insert(_ record: HumanRequestRecord) {
    lock.withLock { current in
      current.records[record.id] = record
      prune(&current)
    }
    publish(record)
  }

  func replace(_ record: HumanRequestRecord) {
    lock.withLock { current in
      current.records[record.id] = record
      prune(&current)
    }
    publish(record)
  }

  /// Adopts records persisted by an earlier process. Live records win; adopted
  /// open requests become `interrupted` and drop their process-scoped page id.
  func adopt(
    stored: [HumanRequestRecord], context: ContextID, contextName: String, now: Double
  ) -> [HumanRequestRecord] {
    var adopted: [HumanRequestRecord] = []
    lock.withLock { current in
      for var record in stored where current.records[record.id] == nil {
        record.context = context
        record.contextName = contextName
        record.page = nil
        if record.state == .pending || record.state == .active {
          record.state = .interrupted
          record.updatedAt = now
        }
        current.records[record.id] = record
        adopted.append(record)
      }
      prune(&current)
    }
    for record in adopted { publish(record) }
    return adopted
  }

  func expire(now: Double) -> [HumanRequestRecord] {
    var expired: [HumanRequestRecord] = []
    lock.withLock { current in
      for (id, var record) in current.records {
        guard record.state == .pending, let expiresAt = record.expiresAt, expiresAt <= now
        else { continue }
        record.state = .expired
        record.updatedAt = now
        current.records[id] = record
        expired.append(record)
      }
    }
    for record in expired { publish(record) }
    return expired
  }

  private func prune(_ current: inout State) {
    guard current.records.count > HumanRequestLimits.maximumRecords else { return }
    let overflow = current.records.count - HumanRequestLimits.maximumRecords
    let removable = current.records.values
      .filter { !$0.state.blocksAgentControl }
      .sorted { $0.createdAt < $1.createdAt }
      .prefix(overflow)
    for record in removable { current.records[record.id] = nil }
  }

  private func publish(_ record: HumanRequestRecord) {
    let observers = lock.withLock { Array($0.observers.values) }
    for observer in observers { observer.yield(record) }
  }
}
