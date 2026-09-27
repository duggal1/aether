import AgentProtocol
import EngineCore
import EngineRuntime
import Foundation

extension AgentCommandDispatcher {
  /// Agent-facing operations on a page parked by an open handoff fail closed:
  /// state-mutating methods, and methods that can observe live human input
  /// (JS evaluation, snapshots, pixels). Reads that cannot carry entered values
  /// (page info, history, focus) stay available.
  static let handoffGatedPageMethods: Set<AgentMethod> = [
    .pageNavigate, .pageNavigateInput, .pageBack, .pageForward, .pageReload,
    .pageResize, .pageClose, .pageClick, .pageDrag, .pageType, .pageSetValue, .pageFill,
    .pageSubmit, .pagePressKey, .pageSelectOption, .pageHover, .pageFocus,
    .pageBlur, .pageScroll, .pageScrollIntoView, .pageLoadHTML,
    .pageSetLifecycle, .pageRestore, .pageMediaControl,
    .pageEvaluate, .pageRender, .pageCapture, .pageSnapshot, .pageInspect,
    .pageQuery, .pageQueryAll, .pageMutations, .pageFind, .pageWait,
    .pageNodeAtPoint, .pageConsole, .pageNetworkLog, .pageFrame, .pageWorkers,
    .pageDialogs, .pageMedia, .taskVerify, .credentialsFill,
  ]

  static let handoffGatedContextMethods: Set<AgentMethod> = [
    .contextCookies, .contextSetCookie, .contextRemoveCookie, .contextClearCookies,
    .contextStorageOrigins, .contextStorageValues, .contextStorageSet,
    .contextStorageRemove, .contextStorageClear, .contextPermission,
    .contextSetPermission, .contextPermissions, .contextCheckpoint,
    .contextSetCheckpoint, .contextCheckpointValue,
    .credentialsList, .credentialsGet, .credentialsSave, .credentialsDelete,
  ]

  func handoffAutomationBlocked(_ request: AgentRequest, method: AgentMethod) async
    -> AgentResponse?
  {
    do {
      if (method == .contextDestroy || Self.handoffGatedContextMethods.contains(method)),
        let context = request.params["context"]?.exactUInt64
      {
        try await engine.runtime.requireAgentControl(contextID: ContextID(rawValue: context))
        return nil
      }
      if method == .eventsRecent {
        if let context = request.params["context"]?.exactUInt64 {
          try await engine.runtime.requireAgentControl(contextID: ContextID(rawValue: context))
        } else if let page = request.params["page"]?.exactUInt64 {
          try await engine.runtime.requireAgentControl(pageID: PageID(rawValue: page))
        }
        return nil
      }
      let pageID = request.params["page"]?.exactUInt64
        ?? (method == .taskVerify ? request.params["plan"]?["page"]?.exactUInt64 : nil)
      guard Self.handoffGatedPageMethods.contains(method),
        let page = pageID
      else { return nil }
      try await engine.runtime.requireAgentControl(pageID: PageID(rawValue: page))
      return nil
    } catch let error as HumanRequestError {
      return AgentResponse(
        id: request.id, error: AgentError(code: error.code, message: error.description))
    } catch {
      return nil
    }
  }

  private func humanUInt64(_ params: [String: JSONValue], _ key: String) throws -> UInt64 {
    if let exact = params[key]?.exactUInt64 { return exact }
    if let number = params[key]?.number, let value = UInt64(exactly: number) { return value }
    throw HumanRequestError.badParameter(key)
  }

  private func humanRequired(_ params: [String: JSONValue], _ key: String) throws -> String {
    guard let value = params[key]?.string, !value.isEmpty else {
      throw HumanRequestError.badParameter(key)
    }
    return value
  }

  private func humanCategory(_ params: [String: JSONValue]) throws -> HumanRequestCategory {
    guard let raw = params["category"]?.string,
      let category = HumanRequestCategory(rawValue: raw)
    else { throw HumanRequestError.badParameter("category") }
    return category
  }

  private func humanRequestJSON(_ record: HumanRequestRecord) -> JSONValue {
    var object: [String: JSONValue] = [
      "id": .string(record.id),
      "kind": .string(record.kind.rawValue),
      "state": .string(record.state.rawValue),
      "category": .string(record.category.rawValue),
      "agent": .string(record.agent),
      "reason": .string(record.reason),
      "context": .number(Double(record.context.rawValue)),
      "contextName": .string(record.contextName),
      "createdAt": .number(record.createdAt),
      "updatedAt": .number(record.updatedAt),
    ]
    if let page = record.page { object["page"] = .number(Double(page.rawValue)) }
    if let url = record.pageURL { object["pageURL"] = .string(url) }
    if let title = record.pageTitle { object["pageTitle"] = .string(title) }
    if let session = record.session { object["session"] = .number(Double(session.rawValue)) }
    if let branchID = record.branchID { object["branchID"] = .string(branchID) }
    if let checkpointID = record.checkpointID { object["checkpointID"] = .string(checkpointID) }
    if let executionID = record.executionID { object["executionID"] = .string(executionID) }
    if let claimedAt = record.claimedAt { object["claimedAt"] = .number(claimedAt) }
    if let completedAt = record.completedAt { object["completedAt"] = .number(completedAt) }
    if let expiresAt = record.expiresAt { object["expiresAt"] = .number(expiresAt) }
    if let claimedBy = record.claimedBy { object["claimedBy"] = .string(claimedBy) }
    if let completedBy = record.completedBy { object["completedBy"] = .string(completedBy) }
    if let resolution = record.resolution { object["resolution"] = .string(resolution) }
    if let observed = record.observed {
      var evidence: [String: JSONValue] = [
        "title": .string(observed.title),
        "sessionState": .string(observed.sessionState),
        "loaded": .bool(observed.loaded),
        "statusCode": .number(Double(observed.statusCode)),
        "sequence": .number(Double(observed.sequence)),
        "at": .number(observed.at),
      ]
      if let url = observed.url { evidence["url"] = .string(url) }
      if let error = observed.error { evidence["error"] = .string(error) }
      object["observed"] = .object(evidence)
    }
    return .object(object)
  }
}

extension AgentCommandDispatcher {
  func humanRequestResponse(_ request: AgentRequest, method: AgentMethod) async -> AgentResponse {
    do {
      let result: JSONValue
      switch method {
      case .handoffRequest:
        let page = PageID(rawValue: try humanUInt64(request.params, "page"))
        let session = request.params["session"]?.exactUInt64.map { SessionID(rawValue: $0) }
        let record = try await engine.runtime.requestHandoff(
          pageID: page, category: try humanCategory(request.params),
          reason: try humanRequired(request.params, "reason"),
          agent: request.params["agent"]?.string, sessionID: session,
          branchID: request.params["branchID"]?.string,
          executionID: request.params["executionID"]?.string,
          ttlSeconds: request.params["ttlSeconds"]?.number)
        result = humanRequestJSON(record)
      case .handoffList, .approvalList:
        let kind: HumanRequestKind? =
          method == .approvalList
          ? .approval
          : request.params["kind"]?.string.flatMap(HumanRequestKind.init(rawValue:))
        let records = await engine.runtime.listHumanRequests(
          contextID: request.params["context"]?.exactUInt64.map { ContextID(rawValue: $0) },
          pageID: request.params["page"]?.exactUInt64.map { PageID(rawValue: $0) },
          state: request.params["state"]?.string.flatMap(HumanRequestState.init(rawValue:)),
          kind: kind, id: request.params["id"]?.string)
        result = .array(records.map(humanRequestJSON))
      case .handoffClaim:
        let record = try await engine.runtime.claimHandoff(
          id: try humanRequired(request.params, "id"), by: request.params["human"]?.string)
        result = humanRequestJSON(record)
      case .handoffComplete:
        let record = try await engine.runtime.completeHandoff(
          id: try humanRequired(request.params, "id"),
          pageID: request.params["page"]?.exactUInt64.map { PageID(rawValue: $0) },
          outcome: request.params["outcome"]?.string, by: request.params["human"]?.string)
        result = humanRequestJSON(record)
      case .handoffCancel, .approvalCancel:
        let record = try await engine.runtime.cancelHumanRequest(
          id: try humanRequired(request.params, "id"), by: request.params["actor"]?.string)
        result = humanRequestJSON(record)
      case .handoffResume:
        let record = try await engine.runtime.resumeHandoff(
          id: try humanRequired(request.params, "id"),
          pageID: request.params["page"]?.exactUInt64.map { PageID(rawValue: $0) },
          by: request.params["agent"]?.string)
        result = humanRequestJSON(record)
      case .handoffWait, .approvalWait:
        let timeout = request.params["timeoutMilliseconds"]?.exactInt64.map { Int($0) }
          ?? HumanRequestLimits.defaultWaitMilliseconds
        let record = try await engine.runtime.waitForHumanRequest(
          id: try humanRequired(request.params, "id"), timeoutMilliseconds: timeout)
        result = humanRequestJSON(record)
      case .approvalRequest:
        let record = try await engine.runtime.requestApproval(
          contextID: request.params["context"]?.exactUInt64.map { ContextID(rawValue: $0) },
          pageID: request.params["page"]?.exactUInt64.map { PageID(rawValue: $0) },
          category: try humanCategory(request.params),
          reason: try humanRequired(request.params, "reason"),
          agent: request.params["agent"]?.string,
          ttlSeconds: request.params["ttlSeconds"]?.number)
        result = humanRequestJSON(record)
      case .approvalResolve:
        guard let approved = request.params["approved"]?.bool else {
          throw HumanRequestError.badParameter("approved")
        }
        let record = try await engine.runtime.resolveApproval(
          id: try humanRequired(request.params, "id"), approved: approved,
          note: request.params["note"]?.string, by: request.params["human"]?.string)
        result = humanRequestJSON(record)
      default:
        return AgentResponse(
          id: request.id,
          error: AgentError(code: "method_not_found", message: request.method))
      }
      return AgentResponse(id: request.id, result: result)
    } catch let error as HumanRequestError {
      return AgentResponse(
        id: request.id, error: AgentError(code: error.code, message: error.description))
    } catch {
      return AgentResponse(
        id: request.id,
        error: AgentError(code: "engine_error", message: String(describing: error)))
    }
  }
}
