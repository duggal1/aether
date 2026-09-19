import AetherCapture
import AgentProtocol
import DOM
import Diagnostics
import EngineCore
import EngineRuntime
import Foundation

public final class AgentCommandDispatcher: Sendable {
  public let engine: NativeBrowserEngine
  private let requireCapabilities: Bool
  private let authority = ContextAuthority()

  // In-process legacy callers remain compatible; the socket-facing daemon MUST opt in.
  public init(engine: NativeBrowserEngine, requireCapabilities: Bool = false) {
    self.engine = engine
    self.requireCapabilities = requireCapabilities
  }

  public func handle(_ request: AgentRequest) async -> AgentResponse {
    do {
      guard let method = AgentMethod(rawValue: request.method) else {
        return failure(request, code: "method_not_found", message: request.method)
      }
      if requireCapabilities, let denied = await denyUnauthorized(request, method: method) {
        return denied
      }
      let result: JSONValue
      switch method {
      case .ping:
        result = .object(["ok": .bool(true), "engine": .string("NativeBrowserEngine")])
      case .contextCreate:
        let info = await engine.runtime.createContext(name: request.params["name"]?.string ?? "")
        var object = contextJSON(info).object ?? [:]
        if requireCapabilities {
          object["capability"] = .string(await authority.issue(for: info.id))
        }
        result = .object(object)
      case .contextDestroy:
        let context = ContextID(rawValue: try uint64(request, "context"))
        try await engine.runtime.destroyContext(context)
        if requireCapabilities { await authority.revoke(context: context) }
        result = .object(["ok": .bool(true)])
      case .contextList:
        let contexts = await engine.runtime.listContexts()
        if requireCapabilities {
          let allowed = await authority.permittedContexts(for: request.params["capability"]?.string ?? "")
          result = .array(contexts.filter { allowed.contains($0.id) }.map(contextJSON))
        } else {
          result = .array(contexts.map(contextJSON))
        }
      case .pageCreate:
        let context = ContextID(rawValue: try uint64(request, "context"))
        let width = request.params["width"]?.number ?? 1280
        let height = request.params["height"]?.number ?? 800
        result = pageJSON(
          try await engine.runtime.createPage(
            contextID: context, viewport: Size(width: width, height: height)))
      case .pageNavigate:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let raw = request.params["url"]?.string, let url = URL(string: raw) else {
          throw DispatchError.badParameter("url")
        }
        result = pageJSON(try await engine.runtime.navigate(pageID: page, to: url))
      case .pageBack:
        result = pageJSON(
          try await engine.runtime.goBack(pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageForward:
        result = pageJSON(
          try await engine.runtime.goForward(pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageReload:
        let page = PageID(rawValue: try uint64(request, "page"))
        result = pageJSON(
          try await engine.runtime.reload(
            pageID: page, bypassCache: request.params["bypassCache"]?.bool ?? false))
      case .pageResize:
        let page = PageID(rawValue: try uint64(request, "page"))
        let width = request.params["width"]?.number ?? 1280
        let height = request.params["height"]?.number ?? 800
        result = pageJSON(
          try await engine.runtime.resize(
            pageID: page, viewport: Size(width: width, height: height)))
      case .pageClose:
        try await engine.runtime.closePage(PageID(rawValue: try uint64(request, "page")))
        result = .object(["ok": .bool(true)])
      case .pageList:
        let context = ContextID(rawValue: try uint64(request, "context"))
        result = .array(try await engine.runtime.listPages(contextID: context).map(pageJSON))
      case .pageInspect:
        let inspection = try await engine.runtime.inspect(
          pageID: PageID(rawValue: try uint64(request, "page")))
        result = .object([
          "page": pageJSON(inspection.page), "nodes": .array(inspection.nodes.map(nodeJSON)),
        ])
      case .pageSnapshot:
        result = snapshotJSON(
          try await engine.runtime.snapshot(pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageQuery:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let selector = request.params["selector"]?.string else {
          throw DispatchError.badParameter("selector")
        }
        result =
          try await engine.runtime.query(pageID: page, selector: selector).map(nodeJSON) ?? .null
      case .pageQueryAll:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let selector = request.params["selector"]?.string else {
          throw DispatchError.badParameter("selector")
        }
        result = .array(
          try await engine.runtime.queryAll(pageID: page, selector: selector).map(nodeJSON))
      case .pageWait:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let selector = request.params["selector"]?.string else {
          throw DispatchError.badParameter("selector")
        }
        let condition =
          SelectorWaitCondition(rawValue: request.params["condition"]?.string ?? "visible")
          ?? .visible
        let timeout = try unsigned(request.params, "timeoutMs", default: 5_000)
        let node = try await engine.runtime.waitForSelector(
          pageID: page, selector: selector, condition: condition, timeoutMilliseconds: timeout)
        result = node.map(nodeJSON) ?? .null
      case .pageMutations:
        let page = PageID(rawValue: try uint64(request, "page"))
        let version = try unsigned(request.params, "since", default: 0)
        result = .array(
          try await engine.runtime.mutations(pageID: page, since: version).map(mutationJSON))
      case .pageClick:
        let page = PageID(rawValue: try uint64(request, "page"))
        result = pageJSON(try await engine.runtime.click(pageID: page, nodeID: try nodeID(request)))
      case .pageType:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let text = request.params["text"]?.string else {
          throw DispatchError.badParameter("text")
        }
        try await engine.runtime.type(
          pageID: page, nodeID: try nodeID(request), text: text,
          append: request.params["append"]?.bool ?? false)
        result = .object(["ok": .bool(true)])
      case .pageSetValue:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let value = request.params["value"]?.string else {
          throw DispatchError.badParameter("value")
        }
        try await engine.runtime.setValue(pageID: page, nodeID: try nodeID(request), value: value)
        result = .object(["ok": .bool(true)])
      case .pageEvaluate:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let source = request.params["source"]?.string else {
          throw DispatchError.badParameter("source")
        }
        let value = try await engine.runtime.evaluate(pageID: page, source: source)
        result = .object([
          "value": .string(value.value), "console": .array(value.console.map(JSONValue.string)),
        ])
      case .pageRender:
        let page = PageID(rawValue: try uint64(request, "page"))
        let buffer = try await engine.runtime.render(pageID: page)
        if let path = request.params["path"]?.string {
          try buffer.write(to: URL(fileURLWithPath: path))
          result = .object([
            "path": .string(path), "width": .number(Double(buffer.width)),
            "height": .number(Double(buffer.height)),
          ])
        } else {
          result = .object([
            "format": .string("ppm"), "data": .string(buffer.ppmData().base64EncodedString()),
            "width": .number(Double(buffer.width)), "height": .number(Double(buffer.height)),
          ])
        }
      case .pageMetrics:
        result = metricsJSON(
          try await engine.runtime.metrics(pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageLoadHTML:
        let page = PageID(rawValue: try uint64(request, "page"))
        guard let html = request.params["html"]?.string,
          let raw = request.params["url"]?.string, let url = URL(string: raw)
        else { throw DispatchError.badParameter("html/url") }
        result = pageJSON(try await engine.runtime.loadHTML(pageID: page, html: html, url: url))
      case .pageLifecycle:
        result = .object([
          "lifecycle": .string(
            try await engine.runtime.lifecycleState(pageID: PageID(rawValue: try uint64(request, "page")))
              .rawValue)
        ])
      case .pageSetLifecycle:
        guard let raw = request.params["lifecycle"]?.string,
          let state = PageLifecycleState(rawValue: raw)
        else { throw DispatchError.badParameter("lifecycle") }
        result = pageJSON(
          try await engine.runtime.setLifecycle(
            pageID: PageID(rawValue: try uint64(request, "page")), state: state))
      case .pageRestore:
        result = pageJSON(
          try await engine.runtime.restorePage(pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageHover:
        let node = try await engine.runtime.hover(
          pageID: PageID(rawValue: try uint64(request, "page")), nodeID: try nodeID(request))
        result = node.map(nodeJSON) ?? .null
      case .pageFocus:
        result = pageJSON(
          try await engine.runtime.focus(
            pageID: PageID(rawValue: try uint64(request, "page")), nodeID: try nodeID(request)))
      case .pageBlur:
        result = pageJSON(
          try await engine.runtime.blur(pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageFocused:
        let node = try await engine.runtime.focusedNode(
          pageID: PageID(rawValue: try uint64(request, "page")))
        result = node.map(nodeJSON) ?? .null
      case .pageHovered:
        let node = try await engine.runtime.hoveredNode(
          pageID: PageID(rawValue: try uint64(request, "page")))
        result = node.map(nodeJSON) ?? .null
      case .pageScroll:
        let page = PageID(rawValue: try uint64(request, "page"))
        let x = request.params["x"]?.number ?? 0
        let y = request.params["y"]?.number ?? 0
        result = pointJSON(try await engine.runtime.scrollTo(pageID: page, x: x, y: y))
      case .pageScrollOffset:
        result = pointJSON(
          try await engine.runtime.scrollOffset(
            pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageScrollIntoView:
        result = pointJSON(
          try await engine.runtime.scrollIntoView(
            pageID: PageID(rawValue: try uint64(request, "page")), nodeID: try nodeID(request)))
      case .pageNodeAtPoint:
        let page = PageID(rawValue: try uint64(request, "page"))
        let x = request.params["x"]?.number ?? 0
        let y = request.params["y"]?.number ?? 0
        result =
          try await engine.runtime.nodeAtPoint(pageID: page, x: x, y: y).map(nodeJSON) ?? .null
      case .pagePressKey:
        guard let key = request.params["key"]?.string else {
          throw DispatchError.badParameter("key")
        }
        result = .object([
          "value": .string(
            try await engine.runtime.pressKey(
              pageID: PageID(rawValue: try uint64(request, "page")), key: key))
        ])
      case .pageSelectOption:
        guard let value = request.params["value"]?.string else {
          throw DispatchError.badParameter("value")
        }
        try await engine.runtime.selectOption(
          pageID: PageID(rawValue: try uint64(request, "page")), selectNodeID: try nodeID(request),
          value: value)
        result = .object(["ok": .bool(true)])
      case .pageFill:
        guard let value = request.params["value"]?.string else {
          throw DispatchError.badParameter("value")
        }
        try await engine.runtime.fill(
          pageID: PageID(rawValue: try uint64(request, "page")), nodeID: try nodeID(request),
          value: value)
        result = .object(["ok": .bool(true)])
      case .pageSubmit:
        result = pageJSON(
          try await engine.runtime.submitForm(
            pageID: PageID(rawValue: try uint64(request, "page")), formNodeID: try nodeID(request)))
      case .pageHistory:
        result = .array(
          try await engine.runtime.historyEntries(
            pageID: PageID(rawValue: try uint64(request, "page"))
          ).map(historyJSON))
      case .pageConsole:
        result = .object([
          "lines": .array(
            try await engine.runtime.consoleOutput(
              pageID: PageID(rawValue: try uint64(request, "page"))).map(JSONValue.string))
        ])
      case .pageNetworkLog:
        result = .array(
          try await engine.runtime.networkLogEntries(
            pageID: PageID(rawValue: try uint64(request, "page"))
          ).map(networkLogJSON))
      case .pageFrame:
        result = frameJSON(
          try await engine.runtime.mainFrame(
            pageID: PageID(rawValue: try uint64(request, "page"))))
      case .pageWorkers:
        result = .array(
          try await engine.runtime.listWorkers(
            pageID: PageID(rawValue: try uint64(request, "page"))
          ).map { .number(Double($0.rawValue)) })
      case .pageDialogs:
        result = .array(
          try await engine.runtime.pendingDialogs(
            pageID: PageID(rawValue: try uint64(request, "page"))
          ).map(dialogJSON))
      case .dialogResolve:
        let id = DialogID(rawValue: try uint64(request, "dialog"))
        result = .object([
          "accepted": .bool(
            try await engine.runtime.resolveDialog(
              id: id, accept: request.params["accept"]?.bool ?? false,
              promptText: request.params["promptText"]?.string))
        ])
      case .contextCookies:
        result = .array(
          try await engine.runtime.listCookies(
            contextID: ContextID(rawValue: try uint64(request, "context"))
          ).map(cookieJSON))
      case .contextSetCookie:
        let context = ContextID(rawValue: try uint64(request, "context"))
        guard let name = request.params["name"]?.string,
          let value = request.params["value"]?.string,
          let domain = request.params["domain"]?.string
        else { throw DispatchError.badParameter("name/value/domain") }
        try await engine.runtime.setCookie(
          contextID: context,
          cookie: CookieInfo(
            name: name, value: value, domain: domain,
            path: request.params["path"]?.string ?? "/",
            secure: request.params["secure"]?.bool ?? false,
            httpOnly: request.params["httpOnly"]?.bool ?? false,
            sameSite: request.params["sameSite"]?.string))
        result = .object(["ok": .bool(true)])
      case .contextRemoveCookie:
        guard let name = request.params["name"]?.string,
          let domain = request.params["domain"]?.string
        else { throw DispatchError.badParameter("name/domain") }
        try await engine.runtime.removeCookie(
          contextID: ContextID(rawValue: try uint64(request, "context")), name: name,
          domain: domain, path: request.params["path"]?.string ?? "/")
        result = .object(["ok": .bool(true)])
      case .contextClearCookies:
        try await engine.runtime.clearCookies(
          contextID: ContextID(rawValue: try uint64(request, "context")))
        result = .object(["ok": .bool(true)])
      case .contextStorageOrigins:
        result = .array(
          try await engine.runtime.storageOrigins(
            contextID: ContextID(rawValue: try uint64(request, "context"))
          ).map(JSONValue.string))
      case .contextStorageValues:
        guard let origin = request.params["origin"]?.string else {
          throw DispatchError.badParameter("origin")
        }
        result = .object(
          try await engine.runtime.storageValues(
            contextID: ContextID(rawValue: try uint64(request, "context")), origin: origin
          ).mapValues(JSONValue.string))
      case .contextStorageSet:
        guard let origin = request.params["origin"]?.string,
          let key = request.params["key"]?.string,
          let value = request.params["value"]?.string
        else { throw DispatchError.badParameter("origin/key/value") }
        try await engine.runtime.storageSet(
          contextID: ContextID(rawValue: try uint64(request, "context")), origin: origin, key: key,
          value: value)
        result = .object(["ok": .bool(true)])
      case .contextStorageRemove:
        guard let origin = request.params["origin"]?.string,
          let key = request.params["key"]?.string
        else { throw DispatchError.badParameter("origin/key") }
        try await engine.runtime.storageRemove(
          contextID: ContextID(rawValue: try uint64(request, "context")), origin: origin, key: key)
        result = .object(["ok": .bool(true)])
      case .contextStorageClear:
        guard let origin = request.params["origin"]?.string else {
          throw DispatchError.badParameter("origin")
        }
        try await engine.runtime.storageClear(
          contextID: ContextID(rawValue: try uint64(request, "context")), origin: origin)
        result = .object(["ok": .bool(true)])
      case .contextPermission:
        guard let permission = request.params["permission"]?.string,
          let origin = request.params["origin"]?.string
        else { throw DispatchError.badParameter("permission/origin") }
        result = .object([
          "decision": .string(
            try await engine.runtime.permissionDecision(
              contextID: ContextID(rawValue: try uint64(request, "context")),
              permission: permission, origin: origin))
        ])
      case .contextSetPermission:
        guard let permission = request.params["permission"]?.string,
          let origin = request.params["origin"]?.string,
          let decision = request.params["decision"]?.string
        else { throw DispatchError.badParameter("permission/origin/decision") }
        try await engine.runtime.setPermission(
          contextID: ContextID(rawValue: try uint64(request, "context")), permission: permission,
          origin: origin, decision: decision)
        result = .object(["ok": .bool(true)])
      case .contextPermissions:
        result = .array(
          try await engine.runtime.listPermissions(
            contextID: ContextID(rawValue: try uint64(request, "context"))
          ).map(permissionJSON))
      case .contextDownload:
        guard let raw = request.params["url"]?.string else {
          throw DispatchError.badParameter("url")
        }
        result = downloadJSON(
          try await engine.runtime.startDownload(
            contextID: ContextID(rawValue: try uint64(request, "context")), url: raw,
            path: request.params["path"]?.string))
      case .contextDownloads:
        result = .array(
          try await engine.runtime.listDownloads(
            contextID: ContextID(rawValue: try uint64(request, "context"))
          ).map(downloadJSON))
      case .contextClearDownloads:
        try await engine.runtime.clearDownloads(
          contextID: ContextID(rawValue: try uint64(request, "context")))
        result = .object(["ok": .bool(true)])
      case .contextOpenProfile:
        guard let directory = request.params["directory"]?.string else {
          throw DispatchError.badParameter("directory")
        }
        try await engine.runtime.openProfile(
          contextID: ContextID(rawValue: try uint64(request, "context")),
          directory: URL(fileURLWithPath: directory))
        result = .object(["ok": .bool(true)])
      case .contextCheckpoint:
        try await engine.runtime.checkpoint(
          contextID: ContextID(rawValue: try uint64(request, "context")))
        result = .object(["ok": .bool(true)])
      case .contextProfileUsage:
        result = profileJSON(
          try await engine.runtime.profileUsage(
            contextID: ContextID(rawValue: try uint64(request, "context"))))
      case .contextSetCheckpoint:
        guard let key = request.params["key"]?.string,
          let encoded = request.params["value"]?.string,
          let value = Data(base64Encoded: encoded)
        else { throw DispatchError.badParameter("key/value") }
        try await engine.runtime.setCheckpoint(
          contextID: ContextID(rawValue: try uint64(request, "context")), key: key, value: value)
        result = .object(["ok": .bool(true)])
      case .contextCheckpointValue:
        guard let key = request.params["key"]?.string else {
          throw DispatchError.badParameter("key")
        }
        result =
          try await engine.runtime.checkpointValue(
            contextID: ContextID(rawValue: try uint64(request, "context")), key: key
          ).map { .string($0.base64EncodedString()) } ?? .null
      case .sessionCreate:
        result = sessionJSON(
          await engine.runtime.createSession(name: request.params["name"]?.string ?? ""))
      case .sessionList:
        result = .array(await engine.runtime.listSessions().map(sessionJSON))
      case .sessionDestroy:
        try await engine.runtime.deleteSession(SessionID(rawValue: try uint64(request, "session")))
        result = .object(["ok": .bool(true)])
      case .sessionPages:
        result = .array(
          try await engine.runtime.sessionPages(
            SessionID(rawValue: try uint64(request, "session"))
          ).map(fleetPageJSON))
      case .fleetStats:
        result = fleetStatsJSON(await engine.runtime.fleetStats())
      case .fleetPages:
        result = .array(await engine.runtime.fleetPages().map(fleetPageJSON))
      case .fleetSweep:
        var maxActive: Int?
        if request.params["maxActive"] != nil { maxActive = try integer(request.params, "maxActive") }
        var budget: Int?
        if request.params["memoryBudgetBytes"] != nil { budget = try integer(request.params, "memoryBudgetBytes") }
        result = .object(
          try await engine.runtime.sweepFleet(maxActive: maxActive, memoryBudgetBytes: budget)
            .reduce(into: [String: JSONValue]()) { partial, entry in
              partial[String(entry.key.rawValue)] = .string(entry.value.rawValue)
            })
      case .pageCapture:
        guard let raw = request.params["url"]?.string, let url = URL(string: raw),
          let path = request.params["path"]?.string
        else { throw DispatchError.badParameter("url/path") }
        let options = try captureOptions(from: request.params)
        let capture = try await engine.capturePage(
          url: url, into: URL(fileURLWithPath: path), options: options)
        let manifestData = try JSONEncoder().encode(capture.manifest)
        guard case .object(var manifest) = try JSONDecoder().decode(JSONValue.self, from: manifestData)
        else { throw DispatchError.badParameter("manifest") }
        manifest["directory"] = .string(capture.directory.path)
        result = .object(manifest)
      }
      return AgentResponse(id: request.id, result: result)
    } catch {
      return failure(request, code: "engine_error", message: String(describing: error))
    }
  }

  // This guard runs BEFORE the dispatcher touches BrowserRuntime or sensitive state.
  // A self-reported owner, session name or page number is not proof of authority.
  private func denyUnauthorized(_ request: AgentRequest, method: AgentMethod) async -> AgentResponse? {
    switch method {
    case .ping, .contextCreate:
      return nil
    case .pageCapture, .dialogResolve, .sessionCreate, .sessionList, .sessionDestroy,
      .sessionPages, .fleetStats, .fleetPages, .fleetSweep, .contextOpenProfile:
      // These operations need an explicit principal-scoped contract before exposure.
      return failure(request, code: "unauthorized", message: "Operation requires scoped authorization")
    default:
      break
    }
    guard let token = request.params["capability"]?.string, !token.isEmpty else {
      return failure(request, code: "unauthorized", message: "Missing context capability")
    }
    if method == .contextList { return nil }
    if method == .contextDownload, request.params["path"]?.string != nil {
      return failure(request, code: "unauthorized", message: "Caller-selected download paths are not authorized")
    }
    if method == .contextSetPermission,
      let decision = request.params["decision"]?.string?.lowercased(),
      decision == "allow" || decision == "grant" || decision == "granted"
    {
      return failure(request, code: "unauthorized", message: "Agent cannot self-approve privileged permissions")
    }

    let context: ContextID
    if method.rawValue.hasPrefix("context.") {
      guard let number = request.params["context"]?.number,
        let id = UInt64(exactly: number)
      else {
        return failure(request, code: "unauthorized", message: "Missing valid context")
      }
      context = ContextID(rawValue: id)
    } else if method.rawValue.hasPrefix("page.") {
      guard let number = request.params["page"]?.number,
        let id = UInt64(exactly: number),
        let info = try? await engine.runtime.pageInfo(PageID(rawValue: id))
      else {
        return failure(request, code: "unauthorized", message: "Page unavailable")
      }
      context = info.contextID
    } else {
      return failure(request, code: "unauthorized", message: "Operation is not scoped to a context")
    }
    guard await authority.permits(token, context: context) else {
      return failure(request, code: "unauthorized", message: "Context capability rejected")
    }
    return nil
  }

  private func uint64(_ request: AgentRequest, _ key: String) throws -> UInt64 {
    try unsigned(request.params, key)
  }

  private func unsigned(_ params: [String: JSONValue], _ key: String, default fallback: UInt64? = nil) throws -> UInt64 {
    if params[key] == nil, let fallback { return fallback }
    guard let number = params[key]?.number, let value = UInt64(exactly: number) else {
      throw DispatchError.badParameter(key)
    }
    return value
  }

  private func integer(_ params: [String: JSONValue], _ key: String) throws -> Int {
    guard let number = params[key]?.number, let value = Int(exactly: number), value >= 0 else {
      throw DispatchError.badParameter(key)
    }
    return value
  }

  private func nodeID(_ request: AgentRequest) throws -> NodeID {
    guard let index = request.params["nodeIndex"]?.number,
      let generation = request.params["nodeGeneration"]?.number,
      let exactIndex = UInt32(exactly: index), let exactGeneration = UInt32(exactly: generation)
    else { throw DispatchError.badParameter("nodeIndex/nodeGeneration") }
    return NodeID(index: exactIndex, generation: exactGeneration)
  }

  private func contextJSON(_ info: BrowserContextInfo) -> JSONValue {
    .object([
      "id": .number(Double(info.id.rawValue)), "name": .string(info.name),
      "pageCount": .number(Double(info.pageCount)),
    ])
  }

  private func pageJSON(_ info: BrowserPageInfo) -> JSONValue {
    var object: [String: JSONValue] = [
      "id": .number(Double(info.id.rawValue)),
      "context": .number(Double(info.contextID.rawValue)),
      "title": .string(info.title),
      "loaded": .bool(info.loaded),
      "width": .number(info.viewport.width),
      "height": .number(info.viewport.height),
      "historyIndex": .number(Double(info.historyIndex)),
      "historyCount": .number(Double(info.historyCount)),
      "canGoBack": .bool(info.canGoBack),
      "canGoForward": .bool(info.canGoForward),
    ]
    if let url = info.url { object["url"] = .string(url.absoluteString) }
    return .object(object)
  }

  private func nodeJSON(_ node: InspectedNode) -> JSONValue {
    var object: [String: JSONValue] = [
      "index": .number(Double(node.id.index)),
      "generation": .number(Double(node.id.version)),
      "role": .string(node.role),
      "name": .string(node.name),
      "enabled": .bool(node.enabled),
      "editable": .bool(node.editable),
      "visible": .bool(node.visible),
    ]
    if let value = node.value { object["value"] = .string(value) }
    if let href = node.href { object["href"] = .string(href) }
    if let bounds = node.bounds { object["bounds"] = rectJSON(bounds) }
    return .object(object)
  }

  private func snapshotJSON(_ snapshot: PageSnapshot) -> JSONValue {
    .object([
      "page": pageJSON(snapshot.page),
      "document": .number(Double(snapshot.documentID.rawValue)),
      "mutationVersion": .number(Double(snapshot.mutationVersion)),
      "nodes": .array(
        snapshot.nodes.map { node in
          var object: [String: JSONValue] = [
            "index": .number(Double(node.id.index)),
            "generation": .number(Double(node.id.version)),
            "kind": .string(node.kind),
            "name": .string(node.name),
            "visible": .bool(node.visible),
            "enabled": .bool(node.enabled),
            "editable": .bool(node.editable),
            "children": .array(
              node.children.map {
                .object([
                  "index": .number(Double($0.index)), "generation": .number(Double($0.version)),
                ])
              }),
            "attributes": .object(node.attributes.mapValues(JSONValue.string)),
          ]
          if let parent = node.parent {
            object["parent"] = .object([
              "index": .number(Double(parent.index)), "generation": .number(Double(parent.version)),
            ])
          }
          if let tag = node.tag { object["tag"] = .string(tag) }
          if let text = node.text { object["text"] = .string(text) }
          if let role = node.role { object["role"] = .string(role) }
          if let bounds = node.bounds { object["bounds"] = rectJSON(bounds) }
          return .object(object)
        }),
    ])
  }

  private func mutationJSON(_ mutation: DOMMutation) -> JSONValue {
    var object: [String: JSONValue] = [
      "version": .number(Double(mutation.version)),
      "type": .string(mutation.type.rawValue),
      "target": .object([
        "index": .number(Double(mutation.target.index)),
        "generation": .number(Double(mutation.target.version)),
      ]),
    ]
    if let related = mutation.relatedNode {
      object["related"] = .object([
        "index": .number(Double(related.index)), "generation": .number(Double(related.version)),
      ])
    }
    if let attribute = mutation.attributeName { object["attribute"] = .string(attribute) }
    return .object(object)
  }

  private func rectJSON(_ bounds: Rect) -> JSONValue {
    .object([
      "x": .number(bounds.minX), "y": .number(bounds.minY), "width": .number(bounds.width),
      "height": .number(bounds.height),
    ])
  }

  private func pointJSON(_ point: Point) -> JSONValue {
    .object(["x": .number(point.x), "y": .number(point.y)])
  }

  private func historyJSON(_ entry: HistoryEntry) -> JSONValue {
    .object([
      "index": .number(Double(entry.index)), "url": .string(entry.url),
      "current": .bool(entry.current),
    ])
  }

  private func networkLogJSON(_ entry: NetworkLogEntry) -> JSONValue {
    var object: [String: JSONValue] = [
      "request": .number(Double(entry.request.rawValue)), "url": .string(entry.url),
      "status": .number(Double(entry.statusCode)),
      "durationMs": .number(entry.durationMilliseconds), "fromCache": .bool(entry.fromCache),
    ]
    if let navigation = entry.navigation { object["navigation"] = .number(Double(navigation.rawValue)) }
    return .object(object)
  }

  private func frameJSON(_ frame: AgentFrameInfo) -> JSONValue {
    var object: [String: JSONValue] = [
      "frame": .number(Double(frame.id.rawValue)), "page": .number(Double(frame.page.rawValue)),
      "title": .string(frame.title),
    ]
    if let url = frame.url { object["url"] = .string(url) }
    return .object(object)
  }

  private func cookieJSON(_ cookie: CookieInfo) -> JSONValue {
    var object: [String: JSONValue] = [
      "name": .string(cookie.name), "value": .string(cookie.value),
      "domain": .string(cookie.domain), "path": .string(cookie.path),
      "secure": .bool(cookie.secure), "httpOnly": .bool(cookie.httpOnly),
    ]
    if let sameSite = cookie.sameSite { object["sameSite"] = .string(sameSite) }
    return .object(object)
  }

  private func permissionJSON(_ permission: PermissionInfo) -> JSONValue {
    .object([
      "origin": .string(permission.origin), "permission": .string(permission.permission),
      "decision": .string(permission.decision),
    ])
  }

  private func dialogJSON(_ dialog: AgentDialogInfo) -> JSONValue {
    var object: [String: JSONValue] = [
      "id": .number(Double(dialog.id.rawValue)), "page": .number(Double(dialog.page.rawValue)),
      "kind": .string(dialog.kind), "message": .string(dialog.message),
    ]
    if let prompt = dialog.defaultPrompt { object["defaultPrompt"] = .string(prompt) }
    return .object(object)
  }

  private func downloadJSON(_ download: AgentDownloadInfo) -> JSONValue {
    var object: [String: JSONValue] = [
      "id": .number(Double(download.id.rawValue)), "url": .string(download.url),
      "state": .string(download.state), "bytes": .number(Double(download.bytes)),
    ]
    if let page = download.page { object["page"] = .number(Double(page.rawValue)) }
    if let path = download.path { object["path"] = .string(path) }
    return .object(object)
  }

  private func sessionJSON(_ session: BrowserSessionInfo) -> JSONValue {
    .object([
      "id": .number(Double(session.id.rawValue)), "name": .string(session.name),
      "contexts": .number(Double(session.contextCount)),
      "createdAt": .number(session.createdAt),
    ])
  }

  private func fleetStatsJSON(_ stats: FleetStats) -> JSONValue {
    .object([
      "contexts": .number(Double(stats.totalContexts)), "pages": .number(Double(stats.totalPages)),
      "active": .number(Double(stats.active)), "background": .number(Double(stats.background)),
      "suspended": .number(Double(stats.suspended)), "frozen": .number(Double(stats.frozen)),
      "discarded": .number(Double(stats.discarded)),
      "estimatedBytes": .number(Double(stats.estimatedBytes)),
    ])
  }

  private func fleetPageJSON(_ entry: FleetPageInfo) -> JSONValue {
    .object([
      "page": pageJSON(entry.page), "lifecycle": .string(entry.lifecycle.rawValue),
      "importance": .number(entry.importance),
      "estimatedBytes": .number(Double(entry.estimatedBytes)),
    ])
  }

  private func profileJSON(_ usage: ProfileUsage) -> JSONValue {
    .object([
      "databaseBytes": .number(Double(usage.databaseBytes)),
      "blobBytes": .number(Double(usage.blobBytes)),
      "totalBytes": .number(Double(usage.totalBytes)),
    ])
  }

  private func metricsJSON(_ metrics: EngineMetrics) -> JSONValue {
    .object([
      "networkMs": .number(metrics.networkMilliseconds),
      "parseMs": .number(metrics.parseMilliseconds),
      "styleMs": .number(metrics.styleMilliseconds),
      "layoutMs": .number(metrics.layoutMilliseconds),
      "displayListMs": .number(metrics.displayListMilliseconds),
      "renderMs": .number(metrics.renderMilliseconds),
      "totalMs": .number(metrics.totalMilliseconds),
      "domNodes": .number(Double(metrics.domNodes)),
      "displayCommands": .number(Double(metrics.displayCommands)),
      "responseBytes": .number(Double(metrics.responseBytes)),
    ])
  }

  private func failure(_ request: AgentRequest, code: String, message: String) -> AgentResponse {
    AgentResponse(id: request.id, error: AgentError(code: code, message: message))
  }

  private func captureOptions(from params: [String: JSONValue]) throws -> CaptureOptions {
    var options = CaptureOptions()
    if let raw = params["format"]?.string {
      guard let format = CaptureFormat(rawValue: raw.lowercased()) else {
        throw DispatchError.badParameter("format")
      }
      options.preferredFormat = format
    }
    if let quality = params["quality"]?.number { options.quality = quality }
    if params["width"] != nil { options.viewport.width = try integer(params, "width") }
    if params["height"] != nil { options.viewport.height = try integer(params, "height") }
    if params["maxScrollSteps"] != nil { options.maximumScrollSteps = try integer(params, "maxScrollSteps") }
    if let collect = params["collectAssets"]?.bool { options.collectAssets = collect }
    if let collect = params["collectComputedStyles"]?.bool {
      options.collectComputedStyles = collect
    }
    if let sections = params["captureSections"]?.bool { options.captureSections = sections }
    if let redact = params["redactSensitive"]?.bool { options.redactSensitiveContent = redact }
    try options.validate()
    return options
  }
}

private enum DispatchError: Error, CustomStringConvertible {
  case badParameter(String)
  var description: String {
    switch self {
    case .badParameter(let value): return "Invalid or missing parameter: \(value)"
    }
  }
}
