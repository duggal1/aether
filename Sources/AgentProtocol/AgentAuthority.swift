import Foundation
import Synchronization

public final class AgentOwnershipRegistry: @unchecked Sendable {
  private let lock = Mutex(State())

  private struct State {
    var contextOwners: [UInt64: String] = [:]
    var pageContexts: [UInt64: UInt64] = [:]
    var sessionOwners: [UInt64: String] = [:]
  }

  public init() {}

  public func bindContext(_ context: UInt64, to principal: String) {
    lock.withLock { $0.contextOwners[context] = principal }
  }

  public func ownerOfContext(_ context: UInt64) -> String? {
    lock.withLock { $0.contextOwners[context] }
  }

  public func bindPage(_ page: UInt64, toContext context: UInt64) {
    lock.withLock { $0.pageContexts[page] = context }
  }

  public func contextOfPage(_ page: UInt64) -> UInt64? {
    lock.withLock { $0.pageContexts[page] }
  }

  public func bindSession(_ session: UInt64, to principal: String) {
    lock.withLock { $0.sessionOwners[session] = principal }
  }

  public func ownerOfSession(_ session: UInt64) -> String? {
    lock.withLock { $0.sessionOwners[session] }
  }

  public func releaseContext(_ context: UInt64) {
    lock.withLock { state in
      state.contextOwners[context] = nil
      state.pageContexts = state.pageContexts.filter { $0.value != context }
    }
  }

  public func releasePage(_ page: UInt64) {
    lock.withLock { $0.pageContexts[page] = nil }
  }

  public func releaseSession(_ session: UInt64) {
    lock.withLock { $0.sessionOwners[session] = nil }
  }
}

public struct ControlEventRecord: Sendable, Codable, Equatable {
  public var sequence: UInt64
  public var timestamp: Double
  public var actor: String
  public var method: String
  public var page: UInt64?
  public var context: UInt64?
  public var outcome: String
  public var detail: String?

  public init(
    sequence: UInt64, timestamp: Double, actor: String, method: String, page: UInt64?,
    context: UInt64?, outcome: String, detail: String?
  ) {
    self.sequence = sequence
    self.timestamp = timestamp
    self.actor = actor
    self.method = method
    self.page = page
    self.context = context
    self.outcome = outcome
    self.detail = detail
  }
}

public final class ControlEventLedger: @unchecked Sendable {
  private let lock = Mutex(State())
  public let capacity: Int

  private struct State {
    var nextSequence: UInt64 = 1
    var events: [ControlEventRecord] = []
  }

  public init(capacity: Int = 1000) {
    self.capacity = max(16, capacity)
  }

  public func record(
    actor: String, method: String, page: UInt64?, context: UInt64?, outcome: String,
    detail: String?
  ) -> ControlEventRecord {
    lock.withLock { state in
      let record = ControlEventRecord(
        sequence: state.nextSequence, timestamp: Date().timeIntervalSince1970, actor: actor,
        method: method, page: page, context: context, outcome: outcome, detail: detail)
      state.nextSequence += 1
      state.events.append(record)
      if state.events.count > capacity { state.events.removeFirst(state.events.count - capacity) }
      return record
    }
  }

  public func events(since sequence: UInt64, limit: Int) -> [ControlEventRecord] {
    lock.withLock { state in
      let filtered = state.events.filter { $0.sequence > sequence }
      let bounded = limit > 0 ? Array(filtered.suffix(limit)) : filtered
      return bounded
    }
  }

  public func lastSequence() -> UInt64 {
    lock.withLock { $0.nextSequence - 1 }
  }
}

public struct InputLease: Sendable, Codable, Equatable {
  public var holder: String
  public var expiresAt: Double

  public init(holder: String, expiresAt: Double) {
    self.holder = holder
    self.expiresAt = expiresAt
  }
}

public final class InputLeaseTable: @unchecked Sendable {
  private let lock = Mutex<[UInt64: InputLease]>([:])
  public let defaultSeconds: Double

  public init(defaultSeconds: Double = 30) {
    self.defaultSeconds = defaultSeconds
  }

  public func acquire(page: UInt64, holder: String, seconds: Double?, force: Bool) -> InputLease? {
    lock.withLock { state in
      let now = Date().timeIntervalSince1970
      if let existing = state[page], existing.expiresAt > now, existing.holder != holder,
        !force
      {
        return nil
      }
      let duration = seconds ?? defaultSeconds
      let lease = InputLease(holder: holder, expiresAt: now + max(1, duration))
      state[page] = lease
      return lease
    }
  }

  public func release(page: UInt64, holder: String) -> Bool {
    lock.withLock { state in
      guard let lease = state[page], lease.holder == holder else { return false }
      state[page] = nil
      return true
    }
  }

  public func activeHolder(page: UInt64, now: Double = Date().timeIntervalSince1970) -> String? {
    lock.withLock { state in
      guard let lease = state[page], lease.expiresAt > now else { return nil }
      return lease.holder
    }
  }

  public func releaseAll(holder: String) {
    lock.withLock { state in
      state = state.filter { $0.value.holder != holder }
    }
  }
}
