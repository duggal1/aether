import AetherHumanUI
import AgentProtocol
import AppKit
import Foundation

@MainActor
final class AppAutomationCommands {
  private weak var workspace: BrowserWorkspace?

  init(workspace: BrowserWorkspace) { self.workspace = workspace }

  func handle(_ request: AgentRequest) -> AgentResponse {
    do {
      guard let workspace else { throw CommandError("Browser is shutting down") }
      if request.method == "app.status" {
        return AgentResponse(id: request.id, result: .object([
          "ready": .bool(!workspace.windows.isEmpty),
          "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)),
          "windows": .array(workspace.windows.map { window in
            .object(["id": .string(window.id.uuidString),
              "selected": window.selectedID.map { .string($0.uuidString) } ?? .null,
              "tabs": .array(window.tabs.map(project))])
          }),
          "nativeWindows": .array(NSApp?.windows.filter { $0.canBecomeMain }.map { window in
            .object(["number": .number(Double(window.windowNumber)), "visible": .bool(window.isVisible),
              "title": .string(window.title)])
          } ?? []),
        ]))
      }
      let window: BrowserWindowModel
      if let id = request.params["window"]?.string {
        guard let match = workspace.windows.first(where: { $0.id.uuidString == id }) else {
          throw CommandError("Unknown window")
        }
        window = match
      } else {
        guard let first = workspace.windows.first else { throw CommandError("Browser window is not ready") }
        window = first
      }
      if request.method == "app.open" {
        let tab = window.newTab(url: try url(request))
        return AgentResponse(id: request.id, result: project(tab))
      }
      if request.method == "app.tabs" {
        return AgentResponse(id: request.id, result: .array(window.tabs.map(project)))
      }
      guard let id = request.params["tab"]?.string,
        let tab = window.tabs.first(where: { $0.id.uuidString == id }) else {
        throw CommandError("A valid tab ID is required")
      }
      switch request.method {
      case "app.navigate": window.navigate(tab, text: try url(request))
      case "app.select": window.select(tab.id)
      case "app.close": window.close(tab.id)
      case "app.back": window.select(tab.id); window.perform(.back)
      case "app.forward": window.select(tab.id); window.perform(.forward)
      case "app.reload": window.select(tab.id); window.perform(.reload)
      default: throw CommandError("Unknown app method: \(request.method)")
      }
      return AgentResponse(id: request.id, result: project(tab))
    } catch {
      return AgentResponse(id: request.id,
        error: AgentError(code: "app", message: String(describing: error)))
    }
  }

  private func url(_ request: AgentRequest) throws -> String {
    guard let value = request.params["url"]?.string, let url = URL(string: value),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
      throw CommandError("An absolute HTTP or HTTPS URL is required")
    }
    return value
  }

  private func project(_ tab: BrowserTab) -> JSONValue {
    let state: String
    var error: JSONValue = .null
    switch tab.loadState {
    case .newTab: state = "newTab"
    case .loading: state = "loading"
    case .ready: state = "ready"
    case .search: state = "search"
    case .failed(let message): state = "failed"; error = .string(message)
    }
    return .object([
      "id": .string(tab.id.uuidString),
      "page": tab.enginePageID.flatMap(UInt64.init).map { .number(Double($0)) } ?? .null,
      "url": tab.url.map(JSONValue.string) ?? .null,
      "pendingURL": tab.pendingURL.map(JSONValue.string) ?? .null,
      "title": .string(tab.title), "state": .string(state), "error": error,
      "loading": .bool(tab.isLoading), "contentReady": .bool(tab.contentReady),
      "progress": .number(tab.loadProgress),
      "canGoBack": .bool(tab.canGoBack), "canGoForward": .bool(tab.canGoForward),
    ])
  }

  private struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }
}
