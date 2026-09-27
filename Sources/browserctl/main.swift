import AetherCapture
import AgentProtocol
import BrowserVerification
import BrowserEngine
import DOM
import EngineCore
import EngineRuntime
import Foundation

@main
struct BrowserControl {
  static func main() async {
    var args = Array(CommandLine.arguments.dropFirst())
    do {
      if args.first == "--app" {
        args.removeFirst()
        let path = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock").path
        try runRemote(args, socket: path, token: nil)
      } else if args.first == "--socket" {
        guard args.count >= 3 else { throw CLIError.usage }
        let path = args[1]
        args.removeFirst(2)
        var token: String?
        if args.first == "--token-file" {
          guard args.count >= 3 else { throw CLIError.usage }
          token = try AgentAuth.readTokenFile(from: args[1])
          args.removeFirst(2)
        }
        try runRemote(args, socket: path, token: token)
      } else {
        try await runLocal(args)
      }
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      if let cliError = error as? CLIError, case .usage = cliError {
        FileHandle.standardError.write(Data("\n\(usage)\n".utf8))
        Foundation.exit(2)
      }
      Foundation.exit(1)
    }
  }

  private static func runLocal(_ args: [String]) async throws {
    guard let command = args.first else { throw CLIError.usage }
    let engine = NativeBrowserEngine()
    switch command {
    case "inspect":
      guard args.count >= 2, let url = URL(string: args[1]) else { throw CLIError.usage }
      let (_, page) = try await open(url, engine: engine)
      let inspection = try await engine.runtime.inspect(pageID: page.id)
      printInspection(inspection)
    case "render":
      guard args.count >= 3, let url = URL(string: args[1]) else { throw CLIError.usage }
      let width = args.count > 3 ? Double(args[3]) ?? 1280 : 1280
      let height = args.count > 4 ? Double(args[4]) ?? 800 : 800
      let (_, page) = try await open(
        url, engine: engine, viewport: Size(width: width, height: height))
      let buffer = try await engine.runtime.render(pageID: page.id)
      let output = URL(fileURLWithPath: args[2])
      try buffer.write(to: output)
      print("\(output.path) \(buffer.width)x\(buffer.height)")
    case "eval":
      guard args.count >= 3, let url = URL(string: args[1]) else { throw CLIError.usage }
      let (_, page) = try await open(url, engine: engine)
      let result = try await engine.runtime.evaluate(
        pageID: page.id, source: args.dropFirst(2).joined(separator: " "))
      print(result.value)
      for line in result.console { FileHandle.standardError.write(Data("console: \(line)\n".utf8)) }
    case "shell":
      guard args.count >= 2, let url = URL(string: args[1]) else { throw CLIError.usage }
      let (_, page) = try await open(url, engine: engine)
      try await shell(engine: engine, pageID: page.id)
    case "capture":
      guard args.count >= 3, let url = URL(string: args[1]) else { throw CLIError.usage }
      let options = try captureOptions(from: Array(args.dropFirst(3)))
      let result = try await engine.capturePage(
        url: url, into: URL(fileURLWithPath: args[2]), options: options)
      let codes = result.manifest.warnings.map(\.code).joined(separator: ",")
      print("\(result.directory.path)\nfinalURL: \(result.manifest.finalURL)\nwarnings: \(codes)")
    case "bench-info":
      print("Run .build/release/enginebench")
    default:
      throw CLIError.usage
    }
  }

  private static func runRemote(_ args: [String], socket: String, token: String?) throws {
    guard let command = args.first else { throw CLIError.usage }
    let client = AgentSocketClient(path: socket)
    func send(_ request: AgentRequest) throws -> AgentResponse {
      if let token { return try client.send(request, token: token) }
      return try client.send(request)
    }
    let request: AgentRequest
    switch command {
    case "app-status", "app-tabs":
      request = AgentRequest(method: command.replacingOccurrences(of: "-", with: "."))
    case "app-open":
      guard args.count == 2 else { throw CLIError.usage }
      request = AgentRequest(method: "app.open", params: ["url": .string(args[1])])
    case "app-navigate":
      guard args.count == 3 else { throw CLIError.usage }
      request = AgentRequest(method: "app.navigate", params: ["tab": .string(args[1]), "url": .string(args[2])])
    case "app-select", "app-close", "app-back", "app-forward", "app-reload", "app-metrics":
      guard args.count == 2 else { throw CLIError.usage }
      request = AgentRequest(method: command.replacingOccurrences(of: "-", with: "."), params: ["tab": .string(args[1])])
    case "ping": request = AgentRequest(method: .ping)
    case "context-create":
      request = AgentRequest(
        method: .contextCreate, params: ["name": .string(args.count > 1 ? args[1] : "")])
    case "context-list": request = AgentRequest(method: .contextList)
    case "page-open":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      let create = try send(
        AgentRequest(method: .pageCreate, params: ["context": .number(context)]))
      try printResponse(create)
      guard let page = create.result?.object?["id"]?.number else { return }
      var navigateParams: [String: JSONValue] = ["page": .number(page), "url": .string(args[2])]
      if args.count > 3 { navigateParams["settle"] = .string(args[3]) }
      request = AgentRequest(method: .pageNavigate, params: navigateParams)
    case "page-navigate":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      var navigateOnlyParams: [String: JSONValue] = [
        "page": .number(page), "url": .string(args[2]),
      ]
      if args.count > 3 { navigateOnlyParams["settle"] = .string(args[3]) }
      request = AgentRequest(method: .pageNavigate, params: navigateOnlyParams)
    case "page-navigate-input":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      let inputWords = args.dropFirst(2).filter { $0 != "--commit" && $0 != "--complete" }
      var navigateInputParams: [String: JSONValue] = [
        "page": .number(page),
        "input": .string(inputWords.joined(separator: " ")),
      ]
      if args.contains("--commit") { navigateInputParams["settle"] = .string("commit") }
      else if args.contains("--complete") { navigateInputParams["settle"] = .string("complete") }
      request = AgentRequest(method: .pageNavigateInput, params: navigateInputParams)
    case "page-inspect":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageInspect, params: ["page": .number(page)])
    case "page-snapshot":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      var snapshotParams: [String: JSONValue] = ["page": .number(page)]
      if args.count > 2, let limit = Double(args[2]) { snapshotParams["limit"] = .number(limit) }
      request = AgentRequest(method: .pageSnapshot, params: snapshotParams)
    case "page-query":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageQuery, params: ["page": .number(page), "selector": .string(args[2])])
    case "page-find":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageFind,
        params: ["page": .number(page), "query": .string(args.dropFirst(2).joined(separator: " "))])
    case "page-query-all":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageQueryAll, params: ["page": .number(page), "selector": .string(args[2])])
    case "page-back":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageBack, params: ["page": .number(page), "settle": .string(settleArg(args))])
    case "page-forward":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageForward, params: ["page": .number(page), "settle": .string(settleArg(args))])
    case "page-reload":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageReload,
        params: [
          "page": .number(page), "bypassCache": .bool(args.dropFirst(2).contains("--bypass-cache")),
          "settle": .string(settleArg(args)),
        ])
    case "page-resize":
      guard args.count >= 4, let page = Double(args[1]), let width = Double(args[2]),
        let height = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageResize,
        params: ["page": .number(page), "width": .number(width), "height": .number(height)])
    case "page-wait":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      var params: [String: JSONValue] = ["page": .number(page), "selector": .string(args[2])]
      if args.count > 3 { params["condition"] = .string(args[3]) }
      if args.count > 4, let timeout = Double(args[4]) { params["timeoutMs"] = .number(timeout) }
      request = AgentRequest(method: .pageWait, params: params)
    case "page-mutations":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      let since = args.count > 2 ? Double(args[2]) ?? 0 : 0
      request = AgentRequest(
        method: .pageMutations, params: ["page": .number(page), "since": .number(since)])
    case "page-click":
      guard args.count >= 4, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageClick,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
        ])
    case "page-type":
      guard args.count >= 5, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageType,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
          "text": .string(args.dropFirst(4).joined(separator: " ")),
        ])
    case "page-set-value":
      guard args.count >= 5, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageSetValue,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
          "value": .string(args.dropFirst(4).joined(separator: " ")),
        ])
    case "page-eval":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageEvaluate,
        params: [
          "page": .number(page), "source": .string(args.dropFirst(2).joined(separator: " ")),
        ])
    case "page-render":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageRender, params: ["page": .number(page), "path": .string(args[2])])
    case "page-metrics":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageMetrics, params: ["page": .number(page)])
    case "context-destroy":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextDestroy, params: ["context": .number(context)])
    case "page-create":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      var params: [String: JSONValue] = ["context": .number(context)]
      if args.count > 2, let width = Double(args[2]) { params["width"] = .number(width) }
      if args.count > 3, let height = Double(args[3]) { params["height"] = .number(height) }
      request = AgentRequest(method: .pageCreate, params: params)
    case "page-close":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageClose, params: ["page": .number(page)])
    case "page-list":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageList, params: ["context": .number(context)])
    case "page-load-html":
      guard args.count >= 4, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageLoadHTML,
        params: [
          "page": .number(page), "url": .string(args[2]),
          "html": .string(args.dropFirst(3).joined(separator: " ")),
        ])
    case "page-lifecycle":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageLifecycle, params: ["page": .number(page)])
    case "page-set-lifecycle":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageSetLifecycle,
        params: ["page": .number(page), "lifecycle": .string(args[2])])
    case "page-restore":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageRestore, params: ["page": .number(page)])
    case "page-hover":
      guard args.count >= 4, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageHover,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
        ])
    case "page-focus":
      guard args.count >= 4, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageFocus,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
        ])
    case "page-blur":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageBlur, params: ["page": .number(page)])
    case "page-focused":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageFocused, params: ["page": .number(page)])
    case "page-hovered":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageHovered, params: ["page": .number(page)])
    case "page-scroll":
      guard args.count >= 4, let page = Double(args[1]), let x = Double(args[2]),
        let y = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageScroll, params: ["page": .number(page), "x": .number(x), "y": .number(y)])
    case "page-scroll-offset":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageScrollOffset, params: ["page": .number(page)])
    case "page-scroll-into-view":
      guard args.count >= 4, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageScrollIntoView,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
        ])
    case "page-node-at-point":
      guard args.count >= 4, let page = Double(args[1]), let x = Double(args[2]),
        let y = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageNodeAtPoint, params: ["page": .number(page), "x": .number(x), "y": .number(y)])
    case "page-press-key":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .pagePressKey,
        params: ["page": .number(page), "key": .string(args.dropFirst(2).joined(separator: " "))])
    case "page-select-option":
      guard args.count >= 5, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageSelectOption,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
          "value": .string(args.dropFirst(4).joined(separator: " ")),
        ])
    case "page-fill":
      guard args.count >= 5, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageFill,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
          "value": .string(args.dropFirst(4).joined(separator: " ")),
        ])
    case "page-submit":
      guard args.count >= 4, let page = Double(args[1]), let index = Double(args[2]),
        let generation = Double(args[3])
      else { throw CLIError.usage }
      request = AgentRequest(
        method: .pageSubmit,
        params: [
          "page": .number(page), "nodeIndex": .number(index), "nodeGeneration": .number(generation),
        ])
    case "page-history":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageHistory, params: ["page": .number(page)])
    case "page-console":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageConsole, params: ["page": .number(page)])
    case "page-network-log":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageNetworkLog, params: ["page": .number(page)])
    case "page-frame":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageFrame, params: ["page": .number(page)])
    case "page-workers":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageWorkers, params: ["page": .number(page)])
    case "page-dialogs":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageDialogs, params: ["page": .number(page)])
    case "page-media":
      guard args.count >= 2, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .pageMedia, params: ["page": .number(page)])
    case "page-media-control":
      guard args.count >= 6, let page = Double(args[1]),
        let nodeIndex = Double(args[2]), let nodeGeneration = Double(args[3])
      else { throw CLIError.usage }
      var mediaParams: [String: JSONValue] = [
        "page": .number(page), "nodeIndex": .number(nodeIndex),
        "nodeGeneration": .number(nodeGeneration), "action": .string(args[4]),
      ]
      if args.count > 5, let number = Double(args[5]) {
        mediaParams["time"] = .number(number)
        mediaParams["value"] = .number(number)
        mediaParams["rate"] = .number(number)
      }
      if args.contains("--muted") { mediaParams["muted"] = .bool(true) }
      request = AgentRequest(method: .pageMediaControl, params: mediaParams)
    case "dialog-resolve":
      guard args.count >= 2, let dialog = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .dialogResolve,
        params: ["dialog": .number(dialog), "accept": .bool(args.contains("--accept"))])
    case "context-cookies":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextCookies, params: ["context": .number(context)])
    case "context-set-cookie":
      guard args.count >= 5, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextSetCookie,
        params: [
          "context": .number(context), "name": .string(args[2]), "value": .string(args[3]),
          "domain": .string(args[4]), "path": .string(args.count > 5 ? args[5] : "/"),
        ])
    case "context-remove-cookie":
      guard args.count >= 4, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextRemoveCookie,
        params: [
          "context": .number(context), "name": .string(args[2]), "domain": .string(args[3]),
          "path": .string(args.count > 4 ? args[4] : "/"),
        ])
    case "context-clear-cookies":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextClearCookies, params: ["context": .number(context)])
    case "context-storage-origins":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextStorageOrigins, params: ["context": .number(context)])
    case "context-storage-values":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextStorageValues,
        params: ["context": .number(context), "origin": .string(args[2])])
    case "context-storage-set":
      guard args.count >= 5, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextStorageSet,
        params: [
          "context": .number(context), "origin": .string(args[2]), "key": .string(args[3]),
          "value": .string(args.dropFirst(4).joined(separator: " ")),
        ])
    case "context-storage-clear":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextStorageClear,
        params: ["context": .number(context), "origin": .string(args[2])])
    case "context-permission":
      guard args.count >= 4, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextPermission,
        params: [
          "context": .number(context), "permission": .string(args[2]), "origin": .string(args[3]),
        ])
    case "context-set-permission":
      guard args.count >= 5, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextSetPermission,
        params: [
          "context": .number(context), "permission": .string(args[2]), "origin": .string(args[3]),
          "decision": .string(args[4]),
        ])
    case "context-permissions":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextPermissions, params: ["context": .number(context)])
    case "context-download":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      var params: [String: JSONValue] = ["context": .number(context), "url": .string(args[2])]
      if args.count > 3 { params["path"] = .string(args[3]) }
      request = AgentRequest(method: .contextDownload, params: params)
    case "context-downloads":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextDownloads, params: ["context": .number(context)])
    case "context-clear-downloads":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextClearDownloads, params: ["context": .number(context)])
    case "context-open-profile":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextOpenProfile,
        params: ["context": .number(context), "directory": .string(args[2])])
    case "context-checkpoint":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextCheckpoint, params: ["context": .number(context)])
    case "context-blocking":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      var blockingParams: [String: JSONValue] = [
        "context": .number(context), "enabled": .bool(args[2].lowercased() != "off"),
      ]
      if args.count > 3 { blockingParams["rules"] = .string(args[3...].joined(separator: "\n")) }
      request = AgentRequest(method: .contextBlocking, params: blockingParams)
    case "context-profile-usage":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextProfileUsage, params: ["context": .number(context)])
    case "context-bookmark-add":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      var bookmarkParams: [String: JSONValue] = [
        "context": .number(context), "url": .string(args[2]),
      ]
      if args.count > 3 { bookmarkParams["title"] = .string(args[3]) }
      request = AgentRequest(method: .contextBookmarkAdd, params: bookmarkParams)
    case "context-bookmarks":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .contextBookmarks, params: ["context": .number(context)])
    case "context-bookmark-remove":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextBookmarkRemove,
        params: ["context": .number(context), "url": .string(args[2])])
    case "credentials-list":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      var listParams: [String: JSONValue] = ["context": .number(context)]
      if args.count > 2 { listParams["origin"] = .string(args[2]) }
      request = AgentRequest(method: .credentialsList, params: listParams)
    case "credentials-get":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .credentialsGet,
        params: ["context": .number(context), "credential": .string(args[2])])
    case "credentials-save":
      guard args.count >= 5, let context = Double(args[1]) else { throw CLIError.usage }
      var saveParams: [String: JSONValue] = [
        "context": .number(context), "origin": .string(args[2]),
        "username": .string(args[3]), "password": .string(args[4]),
      ]
      if args.count > 5 { saveParams["label"] = .string(args[5]) }
      request = AgentRequest(method: .credentialsSave, params: saveParams)
    case "credentials-delete":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .credentialsDelete,
        params: ["context": .number(context), "credential": .string(args[2])])
    case "credentials-fill":
      guard args.count >= 3, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .credentialsFill,
        params: ["page": .number(page), "credential": .string(args[2])])
    case "context-suggest":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      var suggestParams: [String: JSONValue] = [
        "context": .number(context), "prefix": .string(args[2]),
      ]
      for argument in args.dropFirst(3) {
        if argument == "--local" { suggestParams["network"] = .bool(false) }
        else if let limit = Int(argument) { suggestParams["limit"] = .number(Double(limit)) }
        else { throw CLIError.usage }
      }
      request = AgentRequest(method: .contextSuggest, params: suggestParams)
    case "context-search-provider":
      guard args.count >= 2, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextSearchProvider, params: ["context": .number(context)])
    case "context-set-search-provider":
      guard args.count >= 3, let context = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .contextSetSearchProvider,
        params: ["context": .number(context), "endpoint": .string(args[2])])
    case "session-create":
      request = AgentRequest(
        method: .sessionCreate, params: ["name": .string(args.count > 1 ? args[1] : "")])
    case "session-list": request = AgentRequest(method: .sessionList)
    case "session-destroy":
      guard args.count >= 2, let session = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .sessionDestroy, params: ["session": .number(session)])
    case "session-pages":
      guard args.count >= 2, let session = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(method: .sessionPages, params: ["session": .number(session)])
    case "fleet-stats": request = AgentRequest(method: .fleetStats)
    case "fleet-pages": request = AgentRequest(method: .fleetPages)
    case "fleet-sweep":
      var params: [String: JSONValue] = [:]
      if args.count > 1, let maxActive = Double(args[1]) { params["maxActive"] = .number(maxActive) }
      if args.count > 2, let budget = Double(args[2]) { params["memoryBudgetBytes"] = .number(budget) }
      request = AgentRequest(method: .fleetSweep, params: params)
    case "workspace-lease-acquire":
      guard args.count >= 3, let context = UInt64(args[1]), context > 0 else {
        throw CLIError.usage
      }
      var params: [String: JSONValue] = [
        "context": .uint(context), "agentID": .string(args[2]),
      ]
      if args.count > 3 {
        guard let duration = Double(args[3]) else { throw CLIError.usage }
        params["leaseSeconds"] = .number(duration)
      }
      if args.count > 4 { params["branchID"] = .string(args[4]) }
      if args.count > 5 { params["repositoryRoot"] = .string(args[5]) }
      if args.count > 6 { params["worktreePath"] = .string(args[6]) }
      guard args.count <= 7 else { throw CLIError.usage }
      request = AgentRequest(method: .workspaceLeaseAcquire, params: params)
    case "workspace-lease-renew":
      guard args.count >= 4, let context = UInt64(args[1]), context > 0,
        UUID(uuidString: args[2]) != nil
      else { throw CLIError.usage }
      var params: [String: JSONValue] = [
        "context": .uint(context), "leaseID": .string(args[2]), "agentID": .string(args[3]),
      ]
      if args.count > 4 {
        guard let duration = Double(args[4]) else { throw CLIError.usage }
        params["leaseSeconds"] = .number(duration)
      }
      guard args.count <= 5 else { throw CLIError.usage }
      request = AgentRequest(method: .workspaceLeaseRenew, params: params)
    case "workspace-lease-release", "workspace-lease-cancel":
      guard args.count >= 3, let context = UInt64(args[1]), context > 0,
        UUID(uuidString: args[2]) != nil
      else { throw CLIError.usage }
      var params: [String: JSONValue] = [
        "context": .uint(context), "leaseID": .string(args[2]),
      ]
      let method: AgentMethod
      if command == "workspace-lease-cancel" {
        method = .workspaceLeaseCancel
        guard args.count == 3 else { throw CLIError.usage }
      } else {
        method = .workspaceLeaseRelease
        guard args.count == 4 else { throw CLIError.usage }
        params["agentID"] = .string(args[3])
      }
      request = AgentRequest(method: method, params: params)
    case "workspace-lease-list":
      var params: [String: JSONValue] = [:]
      if args.count > 1 {
        guard args.count == 2, let context = UInt64(args[1]), context > 0 else {
          throw CLIError.usage
        }
        params["context"] = .uint(context)
      }
      request = AgentRequest(method: .workspaceLeaseList, params: params)
    case "page-capture":
      guard args.count >= 3 else { throw CLIError.usage }
      let options = try captureOptions(from: Array(args.dropFirst(3)))
      request = AgentRequest(
        method: .pageCapture,
        params: [
          "url": .string(args[1]), "path": .string(args[2]),
          "format": .string(options.preferredFormat.rawValue),
          "quality": .number(options.quality),
          "width": .number(Double(options.viewport.width)),
          "height": .number(Double(options.viewport.height)),
          "maxScrollSteps": .number(Double(options.maximumScrollSteps)),
          "collectAssets": .bool(options.collectAssets),
          "collectComputedStyles": .bool(options.collectComputedStyles),
          "captureSections": .bool(options.captureSections),
          "redactSensitive": .bool(options.redactSensitiveContent),
        ])
    case "handoff-request":
      guard args.count >= 4, let page = Double(args[1]) else { throw CLIError.usage }
      request = AgentRequest(
        method: .handoffRequest,
        params: [
          "page": .number(page), "category": .string(args[2]),
          "reason": .string(args.dropFirst(3).joined(separator: " ")),
        ])
    case "handoff-list":
      request = AgentRequest(method: .handoffList, params: try humanRequestListParams(args))
    case "handoff-claim":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2 { params["human"] = .string(args.dropFirst(2).joined(separator: " ")) }
      request = AgentRequest(method: .handoffClaim, params: params)
    case "handoff-complete":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2 { params["outcome"] = .string(args.dropFirst(2).joined(separator: " ")) }
      request = AgentRequest(method: .handoffComplete, params: params)
    case "handoff-cancel":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2 { params["actor"] = .string(args.dropFirst(2).joined(separator: " ")) }
      request = AgentRequest(method: .handoffCancel, params: params)
    case "handoff-resume":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2, let page = Double(args[2]) { params["page"] = .number(page) }
      request = AgentRequest(method: .handoffResume, params: params)
    case "handoff-wait":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2, let timeout = Double(args[2]) { params["timeoutMilliseconds"] = .number(timeout) }
      request = AgentRequest(method: .handoffWait, params: params)
    case "approval-request":
      request = AgentRequest(method: .approvalRequest, params: try approvalRequestParams(args))
    case "approval-list":
      request = AgentRequest(method: .approvalList, params: try humanRequestListParams(args))
    case "approval-resolve":
      guard args.count >= 3, args[2] == "approve" || args[2] == "deny" else {
        throw CLIError.usage
      }
      var params: [String: JSONValue] = ["id": .string(args[1]), "approved": .bool(args[2] == "approve")]
      if args.count > 3 { params["note"] = .string(args.dropFirst(3).joined(separator: " ")) }
      request = AgentRequest(method: .approvalResolve, params: params)
    case "approval-cancel":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2 { params["actor"] = .string(args.dropFirst(2).joined(separator: " ")) }
      request = AgentRequest(method: .approvalCancel, params: params)
    case "approval-wait":
      var params: [String: JSONValue] = ["id": .string(try identifierArgument(args))]
      if args.count > 2, let timeout = Double(args[2]) { params["timeoutMilliseconds"] = .number(timeout) }
      request = AgentRequest(method: .approvalWait, params: params)
    case "exec":
      guard args.count >= 2 else { throw CLIError.usage }
      let programData = try Data(
        contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
      let programValue = try JSONDecoder().decode(JSONValue.self, from: programData)
      var execParams: [String: JSONValue] = ["program": programValue]
      var flagIndex = 2
      while flagIndex < args.count {
        guard args[flagIndex] == "--timeout-ms", flagIndex + 1 < args.count,
          let timeout = Double(args[flagIndex + 1])
        else { throw CLIError.usage }
        execParams["timeoutMs"] = .number(timeout)
        flagIndex += 2
      }
      request = AgentRequest(method: .exec, params: execParams)
    case "task-verify":
      guard args.count == 2 else { throw CLIError.usage }
      let plan = try JSONDecoder().decode(
        BrowserVerificationPlan.self,
        from: Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe))
      let input = TaskVerify.Input(plan: plan)
      try input.validate()
      request = AgentRequest(
        method: .taskVerify, params: try AgentProcedureCodec.encodeParams(input))
    case "events-recent":
      var params: [String: JSONValue] = [:]
      var index = 1
      while index < args.count {
        guard index + 1 < args.count else { throw CLIError.usage }
        let value = args[index + 1]
        switch args[index] {
        case "--context":
          guard let context = UInt64(value), context > 0 else { throw CLIError.usage }
          params["context"] = .uint(context)
        case "--page":
          guard let page = UInt64(value), page > 0 else { throw CLIError.usage }
          params["page"] = .uint(page)
        case "--family":
          params["family"] = .string(value)
        case "--since":
          guard let sequence = UInt64(value) else { throw CLIError.usage }
          params["since"] = .uint(sequence)
        case "--limit":
          guard let limit = Int(value) else { throw CLIError.usage }
          params["limit"] = .integer(Int64(limit))
        default: throw CLIError.usage
        }
        index += 2
      }
      request = AgentRequest(method: .eventsRecent, params: params)
    default: throw CLIError.usage
    }
    try printResponse(send(request))
  }

  private static func open(
    _ url: URL, engine: NativeBrowserEngine, viewport: Size = Size(width: 1280, height: 800)
  ) async throws -> (BrowserContextInfo, BrowserPageInfo) {
    let context = await engine.runtime.createContext(name: "local")
    let page = try await engine.runtime.createPage(contextID: context.id, viewport: viewport)
    let loaded = try await engine.runtime.navigate(pageID: page.id, to: url)
    return (context, loaded)
  }

  private static func shell(engine: NativeBrowserEngine, pageID: PageID) async throws {
    print(
      "page \(pageID.rawValue). commands: inspect, snapshot, query <selector>, query-all <selector>, open <url>, back, forward, reload, click <index> <generation>, type <index> <generation> <text>, eval <js>, render <path>, metrics, info, exit"
    )
    while true {
      FileHandle.standardOutput.write(Data("> ".utf8))
      guard let line = readLine() else { return }
      let parts = splitCommand(line)
      guard let command = parts.first else { continue }
      do {
        switch command {
        case "exit", "quit": return
        case "inspect": printInspection(try await engine.runtime.inspect(pageID: pageID))
        case "snapshot":
          let snapshot = try await engine.runtime.snapshot(pageID: pageID)
          let data = try JSONEncoder().encode(snapshot)
          print(String(decoding: data, as: UTF8.self))
        case "query":
          guard parts.count >= 2 else { throw CLIError.usage }
          if let node = try await engine.runtime.query(pageID: pageID, selector: parts[1]) {
            printNode(node)
          } else {
            print("null")
          }
        case "query-all":
          guard parts.count >= 2 else { throw CLIError.usage }
          for node in try await engine.runtime.queryAll(pageID: pageID, selector: parts[1]) {
            printNode(node)
          }
        case "open":
          guard parts.count >= 2, let url = URL(string: parts[1]) else { throw CLIError.usage }
          print(
            try await engine.runtime.navigate(pageID: pageID, to: url).url?.absoluteString ?? "")
        case "back":
          print(try await engine.runtime.goBack(pageID: pageID).url?.absoluteString ?? "")
        case "forward":
          print(try await engine.runtime.goForward(pageID: pageID).url?.absoluteString ?? "")
        case "reload":
          print(try await engine.runtime.reload(pageID: pageID).url?.absoluteString ?? "")
        case "click":
          guard parts.count >= 3, let index = UInt32(parts[1]), let generation = UInt32(parts[2])
          else { throw CLIError.usage }
          let page = try await engine.runtime.click(
            pageID: pageID, nodeID: NodeID(index: index, generation: generation))
          print(page.url?.absoluteString ?? "ok")
        case "type":
          guard parts.count >= 4, let index = UInt32(parts[1]), let generation = UInt32(parts[2])
          else { throw CLIError.usage }
          try await engine.runtime.type(
            pageID: pageID, nodeID: NodeID(index: index, generation: generation),
            text: parts.dropFirst(3).joined(separator: " "))
          print("ok")
        case "eval":
          let result = try await engine.runtime.evaluate(
            pageID: pageID, source: parts.dropFirst().joined(separator: " "))
          print(result.value)
        case "render":
          guard parts.count >= 2 else { throw CLIError.usage }
          let buffer = try await engine.runtime.render(pageID: pageID)
          try buffer.write(to: URL(fileURLWithPath: parts[1]))
          print(parts[1])
        case "metrics":
          print(try await engine.runtime.metrics(pageID: pageID))
        case "info": print(try await engine.runtime.pageInfo(pageID))
        default: print("unknown command")
        }
      } catch { print("error: \(error)") }
    }
  }

  private static func printInspection(_ inspection: PageInspection) {
    print("\(inspection.page.title) \(inspection.page.url?.absoluteString ?? "")")
    for node in inspection.nodes { printNode(node) }
  }

  private static func printNode(_ node: InspectedNode) {
    let bounds =
      node.bounds.map { " [\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))]" }
      ?? ""
    let target = node.href.map { " href=\($0)" } ?? ""
    print("\(node.id.index):\(node.id.version) \(node.role) \"\(node.name)\"\(target)\(bounds)")
  }

  private static func printResponse(_ response: AgentResponse) throws {
    let data = try JSONEncoder().encode(response)
    print(String(decoding: data, as: UTF8.self))
    if let error = response.error {
      throw CLIError.remote("\(error.code): \(error.message)")
    }
  }

  private static func settleArg(_ args: [String]) -> String {
    if args.contains("--commit") { return "commit" }
    return "complete"
  }

  private static func captureOptions(from flags: [String]) throws -> CaptureOptions {
    var options = CaptureOptions()
    var index = flags.startIndex
    while index < flags.endIndex {
      let flag = flags[index]
      index = flags.index(after: index)
      switch flag {
      case "--format":
        guard index < flags.endIndex else { throw CLIError.usage }
        let raw = flags[index].lowercased() == "jpg" ? "jpeg" : flags[index].lowercased()
        guard let format = CaptureFormat(rawValue: raw) else { throw CLIError.usage }
        options.preferredFormat = format
        index = flags.index(after: index)
      case "--quality":
        guard index < flags.endIndex, let quality = Double(flags[index]) else {
          throw CLIError.usage
        }
        options.quality = quality
        index = flags.index(after: index)
      case "--width":
        guard index < flags.endIndex, let width = Int(flags[index]) else { throw CLIError.usage }
        options.viewport.width = width
        index = flags.index(after: index)
      case "--height":
        guard index < flags.endIndex, let height = Int(flags[index]) else { throw CLIError.usage }
        options.viewport.height = height
        index = flags.index(after: index)
      case "--max-steps":
        guard index < flags.endIndex, let steps = Int(flags[index]) else { throw CLIError.usage }
        options.maximumScrollSteps = steps
        index = flags.index(after: index)
      case "--no-assets": options.collectAssets = false
      case "--no-computed-styles": options.collectComputedStyles = false
      case "--no-sections": options.captureSections = false
      case "--no-redact": options.redactSensitiveContent = false
      default: throw CLIError.usage
      }
    }
    try options.validate()
    return options
  }

  private static func identifierArgument(_ args: [String]) throws -> String {
    guard args.count >= 2, !args[1].isEmpty else { throw CLIError.usage }
    return args[1]
  }

  private static func humanRequestListParams(_ args: [String]) throws -> [String: JSONValue] {
    var params: [String: JSONValue] = [:]
    var index = 1
    while index < args.count {
      guard index + 1 < args.count else { throw CLIError.usage }
      switch args[index] {
      case "--context":
        guard let value = Double(args[index + 1]) else { throw CLIError.usage }
        params["context"] = .number(value)
      case "--page":
        guard let value = Double(args[index + 1]) else { throw CLIError.usage }
        params["page"] = .number(value)
      case "--state", "--kind", "--id":
        params[String(args[index].dropFirst(2))] = .string(args[index + 1])
      default: throw CLIError.usage
      }
      index += 2
    }
    return params
  }

  private static func approvalRequestParams(_ args: [String]) throws -> [String: JSONValue] {
    guard args.count >= 3 else { throw CLIError.usage }
    var params: [String: JSONValue] = [
      "category": .string(args[1]), "reason": .string(args[2]),
    ]
    var index = 3
    while index < args.count {
      guard index + 1 < args.count else { throw CLIError.usage }
      switch args[index] {
      case "--context":
        guard let value = Double(args[index + 1]) else { throw CLIError.usage }
        params["context"] = .number(value)
      case "--page":
        guard let value = Double(args[index + 1]) else { throw CLIError.usage }
        params["page"] = .number(value)
      case "--agent":
        params["agent"] = .string(args[index + 1])
      case "--ttl-seconds":
        guard let value = Double(args[index + 1]) else { throw CLIError.usage }
        params["ttlSeconds"] = .number(value)
      default: throw CLIError.usage
      }
      index += 2
    }
    return params
  }

  private static func splitCommand(_ line: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    for character in line {
      if let q = quote {
        if character == q { quote = nil } else { current.append(character) }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character.isWhitespace {
        if !current.isEmpty {
          result.append(current)
          current = ""
        }
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty { result.append(current) }
    return result
  }

  private enum CLIError: Error, CustomStringConvertible {
    case usage
    case remote(String)

    var description: String {
      switch self {
      case .usage: "Invalid command"
      case .remote(let message): message
      }
    }
  }

  private static let usage = """
    browserctl --app app-status
    browserctl --app app-tabs
    browserctl --app app-open <url>
    browserctl --app app-navigate <tab-uuid> <url>
    browserctl --app app-select|app-close|app-back|app-forward|app-reload|app-metrics <tab-uuid>
    Use --app in place of --socket <path> for any command against the running app. No token required.
    Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
    browserctl inspect <url>
    browserctl render <url> <output.ppm|output.png> [width] [height]
    browserctl eval <url> <javascript>
    browserctl shell <url>
    browserctl capture <url> <output-dir> [capture-flags]
    browserctl --socket <path> ping
    browserctl --socket <path> context-create <name>
    browserctl --socket <path> context-list
    browserctl --socket <path> page-open <context> <url> [commit|complete]
    browserctl --socket <path> page-navigate <page> <url> [commit|complete]
    browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit|--complete]
    browserctl --socket <path> page-inspect <page>
    browserctl --socket <path> page-snapshot <page> [limit]
    browserctl --socket <path> page-query <page> <selector>
    browserctl --socket <path> page-query-all <page> <selector>
    browserctl --socket <path> page-find <page> <text>
    browserctl --socket <path> page-wait <page> <selector> [attached|visible|hidden|detached] [timeout-ms]
    browserctl --socket <path> page-back <page> [--commit|--complete]
    browserctl --socket <path> page-forward <page> [--commit|--complete]
    browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit|--complete]
    browserctl --socket <path> page-resize <page> <width> <height>
    browserctl --socket <path> page-mutations <page> [since-version]
    browserctl --socket <path> page-click <page> <node-index> <generation>
    browserctl --socket <path> page-type <page> <node-index> <generation> <text>
    browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
    browserctl --socket <path> page-eval <page> <javascript>
    browserctl --socket <path> page-render <page> <path>
    browserctl --socket <path> page-metrics <page>
    browserctl --socket <path> context-destroy <context>
    browserctl --socket <path> page-create <context> [width height]
    browserctl --socket <path> page-close <page>
    browserctl --socket <path> page-list <context>
    browserctl --socket <path> page-load-html <page> <url> <html>
    browserctl --socket <path> page-lifecycle <page>
    browserctl --socket <path> page-set-lifecycle <page> <active|background|suspended|frozen|discarded>
    browserctl --socket <path> page-restore <page>
    browserctl --socket <path> page-hover <page> <node-index> <generation>
    browserctl --socket <path> page-focus <page> <node-index> <generation>
    browserctl --socket <path> page-blur <page>
    browserctl --socket <path> page-focused <page>
    browserctl --socket <path> page-hovered <page>
    browserctl --socket <path> page-scroll <page> <x> <y>
    browserctl --socket <path> page-scroll-offset <page>
    browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
    browserctl --socket <path> page-node-at-point <page> <x> <y>
    browserctl --socket <path> page-press-key <page> <key>
    browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
    browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
    browserctl --socket <path> page-submit <page> <node-index> <generation>
    browserctl --socket <path> page-history <page>
    browserctl --socket <path> page-console <page>
    browserctl --socket <path> page-network-log <page>
    browserctl --socket <path> page-frame <page>
    browserctl --socket <path> page-workers <page>
    browserctl --socket <path> page-dialogs <page>
    browserctl --socket <path> page-media <page>
    browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play|pause|seek|setVolume|setMuted|setRate|load> [number] [--muted]
    browserctl --socket <path> dialog-resolve <dialog> [--accept]
    browserctl --socket <path> context-cookies <context>
    browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
    browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
    browserctl --socket <path> context-clear-cookies <context>
    browserctl --socket <path> context-storage-origins <context>
    browserctl --socket <path> context-storage-values <context> <origin>
    browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
    browserctl --socket <path> context-storage-clear <context> <origin>
    browserctl --socket <path> context-permission <context> <permission> <origin>
    browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow|deny|prompt>
    browserctl --socket <path> context-permissions <context>
    browserctl --socket <path> context-download <context> <url> [path]
    browserctl --socket <path> context-downloads <context>
    browserctl --socket <path> context-clear-downloads <context>
    browserctl --socket <path> context-open-profile <context> <directory>
    browserctl --socket <path> context-checkpoint <context>
    browserctl --socket <path> context-blocking <context> <on|off> [rules...]
    browserctl --socket <path> context-profile-usage <context>
    browserctl --socket <path> context-bookmark-add <context> <url> [title]
    browserctl --socket <path> context-bookmarks <context>
    browserctl --socket <path> context-bookmark-remove <context> <url>
    browserctl --socket <path> credentials-list <context> [origin]
    browserctl --socket <path> credentials-get <context> <credential-id>
    browserctl --socket <path> credentials-save <context> <origin> <username> <password> [label]
    browserctl --socket <path> credentials-delete <context> <credential-id>
    browserctl --socket <path> credentials-fill <page> <credential-id>
    browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
    browserctl --socket <path> context-search-provider <context>
    browserctl --socket <path> context-set-search-provider <context> <endpoint>
    browserctl --socket <path> session-create <name>
    browserctl --socket <path> session-list
    browserctl --socket <path> session-destroy <session>
    browserctl --socket <path> session-pages <session>
    browserctl --socket <path> fleet-stats
    browserctl --socket <path> fleet-pages
    browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
    browserctl --socket <path> workspace-lease-acquire <context> <agent> [seconds] [branch] [repo-root] [worktree]
    browserctl --socket <path> workspace-lease-renew <context> <lease-id> <agent> [seconds]
    browserctl --socket <path> workspace-lease-release <context> <lease-id> <agent>
    browserctl --socket <path> workspace-lease-cancel <context> <lease-id>
    browserctl --socket <path> workspace-lease-list [context]
    browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
    browserctl --socket <path> exec <program.json> [--timeout-ms N]
    browserctl --socket <path> handoff-request <page> <category> <reason...>
    browserctl --socket <path> handoff-list [--context N] [--page N] [--state S] [--kind K] [--id ID]
    browserctl --socket <path> handoff-claim <id> [human]
    browserctl --socket <path> handoff-complete <id> [outcome]
    browserctl --socket <path> handoff-cancel <id> [actor]
    browserctl --socket <path> handoff-resume <id> [page]
    browserctl --socket <path> handoff-wait <id> [timeout-ms]
    browserctl --socket <path> approval-request <category> <reason> [--context N] [--page N] [--agent A] [--ttl-seconds N]
    browserctl --socket <path> approval-list [--context N] [--page N] [--state S] [--id ID]
    browserctl --socket <path> approval-resolve <id> <approve|deny> [note]
    browserctl --socket <path> approval-cancel <id> [actor]
    browserctl --socket <path> approval-wait <id> [timeout-ms]
    browserctl --socket <path> task-verify <verification-plan.json>
    browserctl --socket <path> events-recent (--context ID|--page ID) [--family NAME] [--since N] [--limit N]
    capture-flags: [--format webp|jpeg|png] [--quality 0..1] [--width N] [--height N]
      [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact]
    """
}
