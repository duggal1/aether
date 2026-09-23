import AgentProtocol
import EngineCore
import Foundation

extension AgentCommandDispatcher {
  public func handle(_ request: AgentRequest, principal: AgentPrincipal,
    ownership: AgentOwnershipRegistry) async -> AgentResponse {
    if principal.isHost { return await handle(request) }
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
    if ["context.openProfile", "context.download", "context.setPermission", "page.capture", "dialog.resolve"].contains(method) {
      return denied()
    }
    let context: UInt64?
    if method == "page.create" || method == "page.list" || method.hasPrefix("context.") {
      context = identifier("context")
    } else if method.hasPrefix("page."), let page = identifier("page") {
      context = try? await engine.runtime.pageInfo(PageID(rawValue: page)).contextID.rawValue
    } else { return denied() }
    guard let context, ownership.ownerOfContext(context) == principal.id else { return denied() }
    let response = await handle(request)
    if response.error == nil && method == "context.destroy" { ownership.releaseContext(context) }
    return response
  }
}
