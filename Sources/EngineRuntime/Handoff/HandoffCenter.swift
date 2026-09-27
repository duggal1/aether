import BrowserEvents
import EngineCore
import Foundation

extension BrowserRuntime {
  // MARK: - Observation

  public func observeHumanRequests() -> AsyncStream<HumanRequestRecord> {
    handoffs.observe()
  }

  // MARK: - Requests

  @discardableResult
  public func requestHandoff(
    pageID: PageID, category: HumanRequestCategory, reason: String,
    agent: String? = nil, sessionID: SessionID? = nil, branchID: String? = nil,
    executionID: String? = nil, ttlSeconds: Double? = nil
  ) async throws -> HumanRequestRecord {
    guard let contextID = contextID(containing: pageID) else {
      throw HumanRequestError.notFound("Page not found: \(pageID.rawValue)")
    }
    expireHumanRequests(now: Date().timeIntervalSince1970)
    if let existing = handoffs.openHandoff(page: pageID) {
      throw HumanRequestError.illegalState(
        "A \(existing.kind.rawValue) is already open for this page: \(existing.id)")
    }
    let checkpointID: String?
    if webEphemeral.contains(contextID) {
      checkpointID = nil
    } else {
      checkpointID = try await checkpointBranch(contextID: contextID).id.description
    }
    let now = Date().timeIntervalSince1970
    let state = webStates[pageID]
    let record = HumanRequestRecord(
      id: UUID().uuidString, kind: .handoff, state: .pending, category: category,
      agent: try normalizedAgent(agent), reason: try validatedReason(reason),
      context: contextID, contextName: contexts[contextID]?.name ?? "",
      page: pageID, pageURL: safeHandoffURL(state?.url), pageTitle: state?.title,
      session: sessionID, branchID: try optionalText(branchID, field: "branchID"),
      checkpointID: checkpointID,
      executionID: try optionalText(executionID, field: "executionID"),
      createdAt: now, updatedAt: now,
      expiresAt: try expiry(from: ttlSeconds, defaultSeconds: nil, now: now))
    try persistHumanRequests(contextID: contextID, including: record)
    handoffs.insert(record)
    await publishHandoff(.handoffRequested(reason: record.reason), record: record)
    await publishHandoff(.handoffParked, record: record)
    return record
  }

  @discardableResult
  public func requestApproval(
    contextID: ContextID?, pageID: PageID?, category: HumanRequestCategory, reason: String,
    agent: String? = nil, ttlSeconds: Double? = nil
  ) async throws -> HumanRequestRecord {
    let owner: ContextID
    if let pageID {
      guard let containing = self.contextID(containing: pageID) else {
        throw HumanRequestError.notFound("Page not found: \(pageID.rawValue)")
      }
      owner = containing
    } else if let contextID, contexts[contextID] != nil {
      owner = contextID
    } else {
      throw HumanRequestError.badParameter("A context or page is required")
    }
    expireHumanRequests(now: Date().timeIntervalSince1970)
    let now = Date().timeIntervalSince1970
    let state = pageID.flatMap { webStates[$0] }
    let record = HumanRequestRecord(
      id: UUID().uuidString, kind: .approval, state: .pending, category: category,
      agent: try normalizedAgent(agent), reason: try validatedReason(reason),
      context: owner, contextName: contexts[owner]?.name ?? "",
      page: pageID, pageURL: safeHandoffURL(state?.url), pageTitle: state?.title,
      session: nil, branchID: nil, executionID: nil, createdAt: now, updatedAt: now,
      expiresAt: try expiry(
        from: ttlSeconds, defaultSeconds: HumanRequestLimits.defaultApprovalSeconds,
        now: now))
    try persistHumanRequests(contextID: owner, including: record)
    handoffs.insert(record)
    return record
  }

  // MARK: - Inspection

  public func listHumanRequests(
    contextID: ContextID? = nil, pageID: PageID? = nil, state: HumanRequestState? = nil,
    kind: HumanRequestKind? = nil, id: String? = nil
  ) -> [HumanRequestRecord] {
    expireHumanRequests(now: Date().timeIntervalSince1970)
    if let id, let record = handoffs.record(id: id) { return [record] }
    return handoffs.list(context: contextID, page: pageID, state: state, kind: kind)
  }

  public func humanRequest(id: String) throws -> HumanRequestRecord {
    expireHumanRequests(now: Date().timeIntervalSince1970)
    guard let record = handoffs.record(id: id) else {
      throw HumanRequestError.notFound("Human request not found: \(id)")
    }
    return record
  }

  public func humanRequestContext(id: String) -> ContextID? {
    handoffs.record(id: id)?.context
  }
}

extension BrowserRuntime {
  // MARK: - Transitions

  @discardableResult
  public func claimHandoff(id: String, by human: String? = nil) async throws -> HumanRequestRecord {
    var record = try humanRequest(id: id)
    guard record.kind == .handoff else {
      throw HumanRequestError.illegalState("Not a handoff: \(id)")
    }
    guard record.state == .pending else {
      throw HumanRequestError.illegalState(
        "Cannot claim a handoff in state \(record.state.rawValue)")
    }
    let now = Date().timeIntervalSince1970
    record.state = .active
    record.claimedAt = now
    record.updatedAt = now
    record.claimedBy = try optionalText(human, field: "human")
    try persistHumanRequests(contextID: record.context, including: record)
    handoffs.replace(record)
    return record
  }

  @discardableResult
  public func completeHandoff(
    id: String, pageID: PageID? = nil, outcome: String? = nil, by human: String? = nil
  ) async throws -> HumanRequestRecord {
    var record = try humanRequest(id: id)
    guard record.kind == .handoff else {
      throw HumanRequestError.illegalState("Not a handoff: \(id)")
    }
    guard record.state == .pending || record.state == .active || record.state == .interrupted else {
      throw HumanRequestError.illegalState(
        "Cannot complete a handoff in state \(record.state.rawValue)")
    }
    let now = Date().timeIntervalSince1970
    if let pageID {
      guard let containing = contextID(containing: pageID), containing == record.context else {
        throw HumanRequestError.badParameter("Page must belong to the handoff context")
      }
      record.page = pageID
    } else if record.state == .interrupted {
      throw HumanRequestError.badParameter("page is required to complete an interrupted handoff")
    }
    record.state = .completed
    record.completedAt = now
    record.updatedAt = now
    record.completedBy = try optionalText(human, field: "human")
    if let outcome { record.resolution = try optionalText(outcome, field: "outcome") }
    if let page = record.page, let state = webStates[page] {
      record.pageURL = safeHandoffURL(state.url)
      record.pageTitle = state.title
    }
    record.observed = observation(for: record.page, now: now)
    try persistHumanRequests(contextID: record.context, including: record)
    handoffs.replace(record)
    await publishHandoff(.handoffCompleted, record: record)
    return record
  }

  @discardableResult
  public func resolveApproval(
    id: String, approved: Bool, note: String? = nil, by human: String? = nil
  ) async throws -> HumanRequestRecord {
    var record = try humanRequest(id: id)
    guard record.kind == .approval else {
      throw HumanRequestError.illegalState("Not an approval: \(id)")
    }
    guard record.state == .pending else {
      throw HumanRequestError.illegalState(
        "Cannot resolve an approval in state \(record.state.rawValue)")
    }
    let now = Date().timeIntervalSince1970
    record.state = approved ? .approved : .denied
    record.completedAt = now
    record.updatedAt = now
    record.completedBy = try optionalText(human, field: "human")
    if let note { record.resolution = try optionalText(note, field: "note") }
    try persistHumanRequests(contextID: record.context, including: record)
    handoffs.replace(record)
    return record
  }

  @discardableResult
  public func cancelHumanRequest(id: String, by actor: String? = nil) async throws
    -> HumanRequestRecord
  {
    var record = try humanRequest(id: id)
    guard record.state.isOpen || record.state == .interrupted else {
      throw HumanRequestError.illegalState(
        "Cannot cancel a request in state \(record.state.rawValue)")
    }
    let now = Date().timeIntervalSince1970
    record.state = .cancelled
    record.updatedAt = now
    record.completedAt = now
    record.completedBy = try optionalText(actor, field: "actor")
    try persistHumanRequests(contextID: record.context, including: record)
    handoffs.replace(record)
    if record.kind == .handoff { await publishHandoff(.handoffCancelled, record: record) }
    return record
  }

  @discardableResult
  public func resumeHandoff(
    id: String, pageID: PageID? = nil, by agent: String? = nil
  ) async throws -> HumanRequestRecord {
    var record = try humanRequest(id: id)
    guard record.kind == .handoff else {
      throw HumanRequestError.illegalState("Not a handoff: \(id)")
    }
    guard record.state == .completed || record.state == .interrupted else {
      throw HumanRequestError.illegalState(
        "Cannot resume a handoff in state \(record.state.rawValue)")
    }
    let now = Date().timeIntervalSince1970
    guard let resumedPage = pageID ?? record.page else {
      throw HumanRequestError.badParameter("page is required to resume a handoff after restart")
    }
    guard let containing = contextID(containing: resumedPage) else {
      throw HumanRequestError.notFound("Page not found: \(resumedPage.rawValue)")
    }
    guard containing == record.context else {
      throw HumanRequestError.badParameter("Page belongs to a different context")
    }
    record.page = resumedPage
    if let state = webStates[resumedPage] {
      record.pageURL = safeHandoffURL(state.url)
      record.pageTitle = state.title
    }
    record.observed = observation(for: resumedPage, now: now)
    record.state = .resumed
    record.updatedAt = now
    if record.completedBy == nil {
      record.completedBy = try optionalText(agent, field: "agent")
    }
    try persistHumanRequests(contextID: record.context, including: record)
    handoffs.replace(record)
    await publishHandoff(.handoffResumed, record: record)
    return record
  }

  /// Waits until the request is settled (or `interrupted` after a restart) and
  /// returns the final record; throws `timeout` if it is still open at the deadline.
  public func waitForHumanRequest(id: String, timeoutMilliseconds: Int) async throws
    -> HumanRequestRecord
  {
    guard timeoutMilliseconds > 0,
      timeoutMilliseconds <= HumanRequestLimits.maximumWaitMilliseconds
    else {
      throw HumanRequestError.badParameter(
        "timeoutMilliseconds must be 1 through \(HumanRequestLimits.maximumWaitMilliseconds)")
    }
    let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
    while true {
      let record = try humanRequest(id: id)
      if record.state.isSettled || record.state == .interrupted { return record }
      if Date() >= deadline {
        throw HumanRequestError.timeout(
          "Human request \(id) is still \(record.state.rawValue) after \(timeoutMilliseconds) ms")
      }
      try await Task.sleep(for: .milliseconds(100))
    }
  }
}


extension BrowserRuntime {
  // MARK: - Agent control gate

  public func openHandoff(pageID: PageID) -> HumanRequestRecord? {
    expireHumanRequests(now: Date().timeIntervalSince1970)
    return handoffs.openHandoff(page: pageID)
  }

  public func openHandoff(contextID: ContextID) -> HumanRequestRecord? {
    expireHumanRequests(now: Date().timeIntervalSince1970)
    return handoffs.openHandoff(context: contextID)
  }

  public func requireAgentControl(pageID: PageID) throws {
    let pageHandoff = openHandoff(pageID: pageID)
    let interrupted = contextID(containing: pageID).flatMap {
      handoffs.interruptedHandoff(context: $0)
    }
    guard let record = pageHandoff ?? interrupted else { return }
    throw HumanRequestError.blocked(
      "Page \(pageID.rawValue) is parked by \(record.kind.rawValue) \(record.id) in state \(record.state.rawValue)")
  }

  public func requireAgentControl(contextID: ContextID) throws {
    guard let record = openHandoff(contextID: contextID) else { return }
    throw HumanRequestError.blocked(
      "Context \(contextID.rawValue) holds an open \(record.kind.rawValue) \(record.id) in state \(record.state.rawValue)")
  }

  // MARK: - Persistence

  func persistHumanRequests(contextID: ContextID) throws {
    guard !webEphemeral.contains(contextID) else { return }
    guard let profile = contexts[contextID]?.profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    let records = handoffs.list(context: contextID, page: nil, state: nil, kind: nil)
    try profile.setKV(scope: "handoffs", key: "all", value: try JSONEncoder().encode(records))
  }

  private func persistHumanRequests(
    contextID: ContextID, including record: HumanRequestRecord
  ) throws {
    guard !webEphemeral.contains(contextID) else { return }
    guard let profile = contexts[contextID]?.profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    var records = handoffs.list(context: contextID, page: nil, state: nil, kind: nil)
    if let index = records.firstIndex(where: { $0.id == record.id }) {
      records[index] = record
    } else {
      records.append(record)
    }
    try profile.setKV(scope: "handoffs", key: "all", value: try JSONEncoder().encode(records))
  }

  func restoreHumanRequests(contextID: ContextID) {
    guard let profile = contexts[contextID]?.profile else { return }
    guard let data = try? profile.getKV(scope: "handoffs", key: "all"),
      let stored = try? JSONDecoder().decode([HumanRequestRecord].self, from: data),
      !stored.isEmpty
    else { return }
    let adopted = handoffs.adopt(
      stored: stored, context: contextID, contextName: contexts[contextID]?.name ?? "",
      now: Date().timeIntervalSince1970)
    guard adopted.contains(where: { $0.state == .interrupted }) else { return }
    try? persistHumanRequests(contextID: contextID)
  }

  func expireHumanRequests(now: Double) {
    let expired = handoffs.expire(now: now)
    guard !expired.isEmpty else { return }
    for record in expired { try? persistHumanRequests(contextID: record.context) }
  }

  private func publishHandoff(_ kind: BrowserEventKind, record: HumanRequestRecord) async {
    await events.publish(
      kind,
      identity: BrowserEventIdentity(
        context: record.context, page: record.page, branch: record.branchID,
        session: record.session))
  }

  // MARK: - Helpers

  private func observation(for pageID: PageID?, now: Double) -> HumanRequestObservation? {
    guard let pageID, let state = webStates[pageID] else { return nil }
    return HumanRequestObservation(
      url: safeHandoffURL(state.url), title: state.title,
      sessionState: sessionAuthState(pageID: pageID).rawValue, loaded: state.loaded,
      statusCode: state.statusCode, error: state.error, sequence: state.sequence, at: now)
  }

  private func safeHandoffURL(_ url: URL?) -> String? {
    guard let url,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    components.user = nil
    components.password = nil
    components.query = nil
    components.fragment = nil
    return components.string
  }

  private func normalizedAgent(_ agent: String?) throws -> String {
    guard let agent, !agent.isEmpty else { return "unknown" }
    guard agent.count <= HumanRequestLimits.maximumAgentLength else {
      throw HumanRequestError.badParameter(
        "agent must be at most \(HumanRequestLimits.maximumAgentLength) characters")
    }
    return agent
  }

  private func validatedReason(_ reason: String) throws -> String {
    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw HumanRequestError.badParameter("reason is required")
    }
    guard trimmed.count <= HumanRequestLimits.maximumReasonLength else {
      throw HumanRequestError.badParameter(
        "reason must be at most \(HumanRequestLimits.maximumReasonLength) characters")
    }
    return trimmed
  }

  private func optionalText(_ value: String?, field: String) throws -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.count <= HumanRequestLimits.maximumNoteLength else {
      throw HumanRequestError.badParameter(
        "\(field) must be at most \(HumanRequestLimits.maximumNoteLength) characters")
    }
    return trimmed
  }

  private func expiry(from ttlSeconds: Double?, defaultSeconds: Double?, now: Double) throws
    -> Double?
  {
    let seconds = ttlSeconds ?? defaultSeconds
    guard let seconds else { return nil }
    guard seconds > 0, seconds.isFinite, seconds <= 86_400 else {
      throw HumanRequestError.badParameter("ttlSeconds must be 1 through 86400")
    }
    return now + seconds
  }
}
