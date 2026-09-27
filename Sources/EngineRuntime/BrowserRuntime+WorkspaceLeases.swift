import BrowserEvents
import EngineCore
import Foundation
import Persistence

extension BrowserRuntime {
  public func acquireWorkspaceLease(
    contextID: ContextID, agentID: String, durationSeconds: Double = 300,
    branchID: String? = nil, repositoryRoot: String? = nil, worktreePath: String? = nil
  ) async throws -> BrowserWorkspaceLease {
    await expireWorkspaceLeases(now: nowSeconds())
    let now = nowSeconds()
    let owner = try validatedLeaseText(agentID, field: "agentID", maximumLength: 200)
    let duration = try validatedLeaseDuration(durationSeconds)
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard let profile = context.profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    let profilePath = profile.directory.standardizedFileURL.path
    guard !contexts.contains(where: { otherID, otherContext in
      otherID != contextID && otherContext.profile?.directory.standardizedFileURL.path == profilePath
    }) else {
      throw BrowserRuntimeError.invalidState("A workspace profile cannot be shared across contexts")
    }
    let validatedBranch = try optionalLeaseText(branchID, field: "branchID", maximumLength: 128)
    let validatedRepository = try optionalLeasePath(repositoryRoot, field: "repositoryRoot")
    let validatedWorktree = try optionalLeasePath(worktreePath, field: "worktreePath")

    if let existing = workspaceLeases[contextID] {
      if existing.info.state == .active && existing.info.expiresAt > now
        && existing.runtimeID == workspaceRuntimeID
      {
        guard existing.info.agentID == owner else {
          throw BrowserRuntimeError.invalidState("Workspace is leased by another agent")
        }
        return existing.info
      }
      if existing.info.state == .recoverable && existing.info.agentID != owner {
        throw BrowserRuntimeError.invalidState("Workspace lease recovery belongs to another agent")
      }
    }

    let lease = BrowserWorkspaceLease(
      workspaceID: workspaceLeases[contextID]?.info.workspaceID ?? UUID(), leaseID: UUID(),
      contextID: contextID, agentID: owner, branchID: validatedBranch,
      repositoryRoot: validatedRepository, worktreePath: validatedWorktree, acquiredAt: now,
      expiresAt: now + duration, state: .active)
    let record = WorkspaceLeaseRecord(info: lease, runtimeID: workspaceRuntimeID)
    try persistWorkspaceLease(record, profile: profile)
    workspaceLeases[contextID] = record
    startWorkspaceLeaseReaper()
    await publishWorkspaceLeaseEvent(.leaseAcquired(id: lease.leaseID.uuidString), lease: lease)
    return lease
  }

  public func renewWorkspaceLease(
    contextID: ContextID, leaseID: UUID, agentID: String, durationSeconds: Double = 300
  ) async throws -> BrowserWorkspaceLease {
    let owner = try validatedLeaseText(agentID, field: "agentID", maximumLength: 200)
    let duration = try validatedLeaseDuration(durationSeconds)
    guard var record = workspaceLeases[contextID],
      let profile = contexts[contextID]?.profile,
      record.info.leaseID == leaseID, record.info.agentID == owner,
      record.info.state == .active, record.runtimeID == workspaceRuntimeID,
      record.info.expiresAt > nowSeconds()
    else {
      throw BrowserRuntimeError.invalidState("Workspace lease is not active for this agent")
    }
    record.info.expiresAt = nowSeconds() + duration
    try persistWorkspaceLease(record, profile: profile)
    workspaceLeases[contextID] = record
    startWorkspaceLeaseReaper()
    await publishWorkspaceLeaseEvent(.leaseRenewed(id: leaseID.uuidString), lease: record.info)
    return record.info
  }

  public func releaseWorkspaceLease(
    contextID: ContextID, leaseID: UUID, agentID: String
  ) async throws -> BrowserWorkspaceLease {
    let owner = try validatedLeaseText(agentID, field: "agentID", maximumLength: 200)
    return try await finishWorkspaceLease(
      contextID: contextID, leaseID: leaseID, expectedOwner: owner, state: .released)
  }

  public func cancelWorkspaceLease(
    contextID: ContextID, leaseID: UUID
  ) async throws -> BrowserWorkspaceLease {
    try await finishWorkspaceLease(
      contextID: contextID, leaseID: leaseID, expectedOwner: nil, state: .cancelled)
  }

  public func listWorkspaceLeases(contextID: ContextID? = nil) async -> [BrowserWorkspaceLease] {
    await expireWorkspaceLeases(now: nowSeconds())
    return workspaceLeases.values.map(\.info).filter {
      contextID == nil || $0.contextID == contextID
    }.sorted {
      if $0.contextID.rawValue != $1.contextID.rawValue {
        return $0.contextID.rawValue < $1.contextID.rawValue
      }
      return $0.acquiredAt < $1.acquiredAt
    }
  }

  public func workspaceLease(contextID: ContextID) async -> BrowserWorkspaceLease? {
    await expireWorkspaceLeases(now: nowSeconds())
    return workspaceLeases[contextID]?.info
  }

  func restoreWorkspaceLease(contextID: ContextID, profile: ProfileStore) throws {
    guard let data = try profile.getKV(scope: "workspace", key: "lease.v1") else { return }
    guard var record = try? JSONDecoder().decode(WorkspaceLeaseRecord.self, from: data) else {
      throw BrowserRuntimeError.invalidState("Stored workspace lease record is invalid")
    }
    let now = nowSeconds()
    record.info.contextID = contextID
    if record.runtimeID != workspaceRuntimeID && record.info.state == .active {
      record.info.state = .recoverable
    } else if record.info.state == .active && record.info.expiresAt <= now {
      record.info.state = .expired
    }
    record.runtimeID = workspaceRuntimeID
    try persistWorkspaceLease(record, profile: profile)
    workspaceLeases[contextID] = record
    if record.info.state == .active { startWorkspaceLeaseReaper() }
  }

  func finishWorkspaceLease(
    contextID: ContextID, leaseID: UUID, expectedOwner: String?,
    state: BrowserWorkspaceLeaseState
  ) async throws -> BrowserWorkspaceLease {
    guard var record = workspaceLeases[contextID],
      let profile = contexts[contextID]?.profile,
      record.info.leaseID == leaseID,
      expectedOwner == nil || record.info.agentID == expectedOwner
    else {
      throw BrowserRuntimeError.invalidState("Workspace lease was not found or is not owned by this agent")
    }
    guard record.info.state == .active || record.info.state == .recoverable else {
      return record.info
    }
    record.info.state = state
    record.info.expiresAt = nowSeconds()
    record.runtimeID = workspaceRuntimeID
    try persistWorkspaceLease(record, profile: profile)
    workspaceLeases[contextID] = record
    await revokeLeaseBoundExecutions(inContexts: [contextID])
    await publishWorkspaceLeaseEvent(
      state == .cancelled ? .leaseCancelled(id: leaseID.uuidString) : .leaseReleased(id: leaseID.uuidString),
      lease: record.info)
    await suspendWorkspace(contextID: contextID)
    return record.info
  }

  func expireWorkspaceLeases(now: Double) async {
    let expired = workspaceLeases.compactMap { contextID, record in
      record.info.state == .active && record.info.expiresAt <= now ? contextID : nil
    }
    for contextID in expired {
      guard var record = workspaceLeases[contextID], let profile = contexts[contextID]?.profile
      else { continue }
      record.info.state = .expired
      record.runtimeID = workspaceRuntimeID
      do {
        try persistWorkspaceLease(record, profile: profile)
        workspaceLeases[contextID] = record
      } catch {
        continue
      }
      // Revoke and publish before suspending: a consumer that observes the expired lease
      // state must be able to find `lease.expired` in the journal, and the lease's program
      // must stop even if the checkpoint below is slow.
      await revokeLeaseBoundExecutions(inContexts: [contextID])
      await publishWorkspaceLeaseEvent(
        .leaseExpired(id: record.info.leaseID.uuidString), lease: record.info)
      await suspendWorkspace(contextID: contextID)
    }
  }

  private func suspendWorkspace(contextID: ContextID) async {
    guard let context = contexts[contextID] else { return }
    for pageID in context.pages.keys {
      await stopNavigation(pageID: pageID)
    }
    try? await checkpoint(contextID: contextID)
    for pageID in context.pages.keys {
      _ = try? await setLifecycle(pageID: pageID, state: .frozen)
    }
  }

  func startWorkspaceLeaseReaper() {
    guard workspaceLeaseReaper == nil else { return }
    workspaceLeaseReaper = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let self else { return }
        await self.expireWorkspaceLeases(now: Date().timeIntervalSince1970)
      }
    }
  }

  func persistWorkspaceLease(_ record: WorkspaceLeaseRecord, profile: ProfileStore)
    throws
  {
    try profile.setKV(
      scope: "workspace", key: "lease.v1", value: try JSONEncoder().encode(record))
  }

  private func validatedLeaseDuration(_ duration: Double) throws -> Double {
    guard duration.isFinite, duration >= 1, duration <= 604_800 else {
      throw BrowserRuntimeError.invalidState("Lease duration must be between 1 and 604800 seconds")
    }
    return duration
  }

  private func validatedLeaseText(_ raw: String, field: String, maximumLength: Int) throws
    -> String
  {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= maximumLength,
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw BrowserRuntimeError.invalidState("Invalid \(field)")
    }
    return value
  }

  private func optionalLeaseText(_ raw: String?, field: String, maximumLength: Int) throws
    -> String?
  {
    guard let raw else { return nil }
    return try validatedLeaseText(raw, field: field, maximumLength: maximumLength)
  }

  private func optionalLeasePath(_ raw: String?, field: String) throws -> String? {
    guard let raw else { return nil }
    let value = try validatedLeaseText(raw, field: field, maximumLength: 4096)
    guard value.hasPrefix("/") else {
      throw BrowserRuntimeError.invalidState("\(field) must be an absolute path")
    }
    return URL(fileURLWithPath: value).standardizedFileURL.path
  }

  func publishWorkspaceLeaseEvent(_ kind: BrowserEventKind, lease: BrowserWorkspaceLease)
    async
  {
    await events.publish(
      kind,
      identity: BrowserEventIdentity(context: lease.contextID, branch: lease.branchID))
  }

  // MARK: - Lease-bound work revocation

  /// Registers in-flight work authorized by a workspace lease. The runtime revokes it as
  /// soon as any of `contexts` stops being leased (release, cancel, or expiry), so a
  /// revoked workspace can never keep being driven by the agent that lost it. Callers
  /// unregister on normal completion.
  @discardableResult
  public func registerLeaseBoundExecution(
    contexts: Set<ContextID>, revoke: @escaping @Sendable () async -> Void
  ) -> LeaseRevocationToken {
    let token = LeaseRevocationToken()
    leaseBoundExecutions[token] = LeaseBoundExecution(contexts: contexts, revoke: revoke)
    return token
  }

  public func unregisterLeaseBoundExecution(_ token: LeaseRevocationToken) {
    leaseBoundExecutions[token] = nil
  }

  public func expandLeaseBoundExecution(_ token: LeaseRevocationToken, context: ContextID) {
    guard var entry = leaseBoundExecutions[token] else { return }
    entry.contexts.insert(context)
    leaseBoundExecutions[token] = entry
  }

  /// Number of registered in-flight executions still confined to leases.
  public var leaseBoundExecutionCount: Int { leaseBoundExecutions.count }

  /// Revokes every execution confined to any of `contexts`. Revocation is delivered to
  /// the work's own cancellation hook; the runtime does not wait for it to observe it.
  func revokeLeaseBoundExecutions(inContexts contexts: Set<ContextID>) async {
    let matches = leaseBoundExecutions.filter { !$0.value.contexts.isDisjoint(with: contexts) }
    for (token, execution) in matches {
      leaseBoundExecutions[token] = nil
      await execution.revoke()
    }
  }
}
