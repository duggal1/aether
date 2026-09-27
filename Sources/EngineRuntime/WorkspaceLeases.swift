import EngineCore
import Foundation

public enum BrowserWorkspaceLeaseState: String, Sendable, Codable, CaseIterable {
  case active
  case released
  case cancelled
  case expired
  case recoverable
}

public struct BrowserWorkspaceLease: Hashable, Sendable, Codable {
  public var workspaceID: UUID
  public var leaseID: UUID
  public var contextID: ContextID
  public var agentID: String
  public var branchID: String?
  public var repositoryRoot: String?
  public var worktreePath: String?
  public var acquiredAt: Double
  public var expiresAt: Double
  public var state: BrowserWorkspaceLeaseState

  public init(
    workspaceID: UUID, leaseID: UUID, contextID: ContextID, agentID: String,
    branchID: String?, repositoryRoot: String?, worktreePath: String?, acquiredAt: Double,
    expiresAt: Double, state: BrowserWorkspaceLeaseState
  ) {
    self.workspaceID = workspaceID
    self.leaseID = leaseID
    self.contextID = contextID
    self.agentID = agentID
    self.branchID = branchID
    self.repositoryRoot = repositoryRoot
    self.worktreePath = worktreePath
    self.acquiredAt = acquiredAt
    self.expiresAt = expiresAt
    self.state = state
  }
}

struct WorkspaceLeaseRecord: Codable, Sendable {
  var info: BrowserWorkspaceLease
  var runtimeID: UUID
}

/// Handle for work registered against workspace leases through
/// `BrowserRuntime.registerLeaseBoundExecution`. The runtime revokes the work when a
/// lease covering one of its contexts ends; the holder unregisters when it finishes.
public struct LeaseRevocationToken: Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// One piece of in-flight work confined to leased contexts, with the callback that makes
/// it stop. The callback must be idempotent and must not block: it is invoked on the
/// runtime actor while a lease transition is in progress.
struct LeaseBoundExecution: Sendable {
  var contexts: Set<ContextID>
  var revoke: @Sendable () async -> Void
}
