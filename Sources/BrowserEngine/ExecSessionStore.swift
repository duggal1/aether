import AgentProtocol
import EngineCore
import EngineRuntime
import Foundation

/// Persistent code-execution state bound to a browser session, not to a connection or a
/// request (directive §5.1). A program naming `session` loads the retained variables,
/// runs, and commits its final variables back; the next program in the same session sees
/// them. The state is bounded in bytes (§5.1.3) and destroyed in constant time (§5.1.4).
///
/// Ownership: one store per `NativeBrowserEngine` — never a process-global singleton — so
/// tests and shards cannot share sessions by accident. The lease registry is the
/// revocation path: each session registers one lease-bound entry whose callback destroys
/// it, so a released, cancelled, or expired workspace cannot leave retained state behind.
public actor ExecSessionStore {
  struct Session {
    var vars: [String: JSONValue] = [:]
    var bytes: Int = 0
    var programs: Int = 0
    var token: LeaseRevocationToken?
    /// A single session runs one program at a time. Concurrent programs on one session
    /// would race the retained variable set (directive §5.3.7).
    var running = false
  }

  private var sessions: [UInt64: Session] = [:]

  public init() {}

  public var liveSessionCount: Int { sessions.count }

  public func exists(_ id: UInt64) -> Bool { sessions[id] != nil }

  /// Loads the retained variables for `id`, creating the session on first use. Throws when
  /// the session has already run its program budget, so a long-lived session cannot grow
  /// without a reset.
  public func loadOrCreate(_ id: UInt64) throws -> [String: JSONValue] {
    if var session = sessions[id] {
      guard !session.running else { throw ExecSessionError.sessionBusy }
      guard session.programs < ExecLimits.maxSessionPrograms else {
        throw ExecSessionError.programLimitExceeded(ExecLimits.maxSessionPrograms)
      }
      session.programs += 1
      session.running = true
      sessions[id] = session
      return session.vars
    }
    sessions[id] = Session(programs: 1, running: true)
    return [:]
  }

  /// Releases the single-flight slot after a program reaches a terminal state. Called on
  /// every terminal path, including cancellation and revocation.
  public func endProgram(_ id: UInt64) {
    guard var session = sessions[id] else { return }
    session.running = false
    sessions[id] = session
  }

  /// Retained bytes and executed programs, or nil when the session does not exist.
  public func stats(_ id: UInt64) -> (bytes: Int, programs: Int)? {
    guard let session = sessions[id] else { return nil }
    return (session.bytes, session.programs)
  }

  public func token(for id: UInt64) -> LeaseRevocationToken? { sessions[id]?.token }

  public func setToken(_ token: LeaseRevocationToken, for id: UInt64) {
    guard var session = sessions[id] else { return }
    session.token = token
    sessions[id] = session
  }

  /// Commits the program's final variables back into the session, enforcing the byte cap.
  /// Throws rather than truncating, so the driver learns the session must be reset.
  @discardableResult
  public func commit(_ id: UInt64, vars: [String: JSONValue]) throws -> Int {
    // A session destroyed mid-program (lease release, cancel, or expiry) must not be
    // resurrected by the program's own commit.
    guard var session = sessions[id] else { return 0 }
    let encoded = try JSONEncoder().encode(vars)
    guard encoded.count <= ExecLimits.maxSessionBytes else {
      throw ExecSessionError.byteLimitExceeded(encoded.count, ExecLimits.maxSessionBytes)
    }
    session.vars = vars
    session.bytes = encoded.count
    sessions[id] = session
    return encoded.count
  }

  /// Constant-time teardown. Frees the retained variable set and drops the registration.
  public func destroy(_ id: UInt64) {
    sessions[id] = nil
  }

  public func destroyAll() {
    sessions.removeAll(keepingCapacity: false)
  }
}

public enum ExecSessionError: Error, Sendable, CustomStringConvertible {
  case byteLimitExceeded(Int, Int)
  case programLimitExceeded(Int)
  case sessionBusy

  public var description: String {
    switch self {
    case .byteLimitExceeded(let actual, let cap):
      return "exec session retained \(actual) bytes, over its \(cap)-byte cap"
    case .programLimitExceeded(let cap):
      return "exec session reached its \(cap)-program budget; reset the session"
    case .sessionBusy:
      return "exec session already has a program in flight (concurrency limit is 1)"
    }
  }
}
