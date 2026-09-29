import AgentProtocol
import EngineCore
import Foundation

extension AgentCommandDispatcher {
  public func handle(_ request: AgentRequest, principal: AgentPrincipal,
    ownership: AgentOwnershipRegistry) async -> AgentResponse {
    if principal.isHost {
      let response = await handle(request)
      if response.error == nil, request.method == "workspace.lease.acquire",
        let context = request.params["context"]?.exactUInt64,
        let agentID = request.params["agentID"]?.string
      {
        ownership.bindContext(context, to: agentID)
      }
      if response.error == nil, request.method == "context.destroy",
        let context = request.params["context"]?.exactUInt64
      {
        ownership.releaseContext(context)
      }
      return response
    }
    func denied() -> AgentResponse {
      AgentResponse(id: request.id, error: AgentError(code: "unauthorized", message: "Operation requires ownership of this context"))
    }
    func identifier(_ key: String) -> UInt64? {
      request.params[key]?.exactUInt64
    }
    let method = request.method
    if method == "ping" { return await handle(request) }
    if method == "context.list" {
      let contexts = await engine.runtime.listContexts().filter { ownership.ownerOfContext($0.id.rawValue) == principal.id }
      return AgentResponse(id: request.id, result: .array(contexts.map {
        .object(["id": .number(Double($0.id.rawValue)), "name": .string($0.name), "pageCount": .number(Double($0.pageCount))])
      }))
    }
    if method == "context.create" {
      let response = await handle(request)
      if let id = response.result?["id"]?.exactUInt64 {
        ownership.bindContext(id, to: principal.id)
      }
      return response
    }
    if method == "agent.exec" {
      let owned = Set(
        await engine.runtime.listContexts().filter {
          ownership.ownerOfContext($0.id.rawValue) == principal.id
        }.map { $0.id.rawValue })
      return await handleExecRequest(request, allowedContexts: owned)
    }
    if ["context.openProfile", "context.download", "context.setPermission", "page.capture", "dialog.resolve"].contains(method) {
      return denied()
    }
    if method == "workspace.lease.cancel" { return denied() }
    let context: UInt64?
    if method == "task.verify",
      let page = request.params["plan"]?["page"]?.exactUInt64
    {
      context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
    } else if method == "events.recent", let page = identifier("page") {
      context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
    } else if method == "page.create" || method == "page.list" || method.hasPrefix("context.") {
      context = identifier("context")
    } else if method == "events.recent" {
      context = identifier("context")
    } else if method.hasPrefix("workspace.lease.") {
      context = identifier("context")
    } else if method.hasPrefix("extension."), let page = identifier("page") {
      context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
    } else if method.hasPrefix("credentials."), let page = identifier("page") {
      context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
    } else if method.hasPrefix("credentials.") {
      // `credentials.fill` carries a page and is handled above; every other
      // `credentials.*` call is scoped by an explicit context.
      context = identifier("context")
    } else if method == "workspace.lease.list" {
      // A list scoped by an explicit context is authorized by the guard below. With no
      // context the caller may only observe leases held on contexts it owns, so the
      // runtime result is filtered rather than rejected.
      if let explicit = identifier("context") {
        context = explicit
      } else {
        let owned = Set(
          await engine.runtime.listContexts().filter {
            ownership.ownerOfContext($0.id.rawValue) == principal.id
          }.map { $0.id.rawValue })
        let response = await handle(request)
        guard let items = response.result?.array else { return response }
        return AgentResponse(id: request.id, result: .array(items.filter { item in
          item["context"]?.exactUInt64.map { owned.contains($0) } ?? false
        }))
      }
    } else if method.hasPrefix("page."), let page = identifier("page") {
      context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
    } else if method.hasPrefix("session."), let session = identifier("session") {
      // Session-scoped calls authorize against the session's owning principal.
      guard ownership.ownerOfSession(session) == principal.id else { return denied() }
      return await handle(request)
    } else if method.hasPrefix("session.") {
      // `session.create` mints a new session owned by the caller; `session.list` is
      // answered from the ownership registry rather than the full runtime listing.
      if method == "session.create" {
        let response = await handle(request)
        if response.error == nil, let id = response.result?["id"]?.exactUInt64 {
          ownership.bindSession(id, to: principal.id)
        }
        return response
      }
      return denied()
    } else if method.hasPrefix("fleet.") {
      // Fleet aggregates are cross-context, so they are only observable by a principal
      // that owns at least one context.
      let owned = Set(
        await engine.runtime.listContexts().filter {
          ownership.ownerOfContext($0.id.rawValue) == principal.id
        }.map { $0.id.rawValue })
      guard !owned.isEmpty else { return denied() }
      return await handle(request)
    } else if method.hasPrefix("handoff.") || method.hasPrefix("approval.") {
      if let value = identifier("context") {
        context = value
      } else if let page = identifier("page") {
        context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
      } else if let id = request.params["id"]?.string {
        context = await engine.runtime.humanRequestContext(id: id)?.rawValue
      } else { return denied() }
    } else { return denied() }
    guard let context, ownership.ownerOfContext(context) == principal.id else { return denied() }
    if let lease = await engine.runtime.workspaceLease(contextID: ContextID(rawValue: context)) {
      guard lease.state == .active, lease.agentID == principal.id else { return denied() }
    }
    var scopedRequest = request
    if method == "workspace.lease.acquire" || method == "workspace.lease.renew"
      || method == "workspace.lease.release"
    {
      scopedRequest.params["agentID"] = .string(principal.id)
    }
    let response = await handle(scopedRequest)
    if response.error == nil && method == "context.destroy" { ownership.releaseContext(context) }
    return response
  }
}
