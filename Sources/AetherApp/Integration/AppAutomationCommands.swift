import AetherHumanUI
import AgentProtocol
import AppKit
import Foundation
import WebKit

@MainActor
final class AppAutomationCommands {
  private weak var workspace: BrowserWorkspace?

  init(workspace: BrowserWorkspace) { self.workspace = workspace }

  func handle(_ request: AgentRequest) async -> AgentResponse {
    AetherLatencyProbe.mark("cmd.received \(request.method)")
    do {
      guard let workspace else { throw CommandError("Browser is shutting down") }
      if request.method == "app.status" {
        return AgentResponse(id: request.id, result: .object([
          "ready": .bool(!workspace.windows.isEmpty),
          "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)),
          "windows": .array(workspace.windows.map { window in
            .object(["id": .string(window.id.uuidString),
              "selected": window.selectedID.map { .string($0.uuidString) } ?? .null,
              "hoveredLink": window.hoveredLink.map(JSONValue.string) ?? .null,
              "floatingPage": window.floatingPageID.map(JSONValue.string) ?? .null,
              "sidebarCollapsed": .bool(window.sidebarCollapsed),
              "tabs": .array(window.tabs.map(project))])
          }),
          "nativeWindows": .array(NSApp?.windows.filter { $0.canBecomeMain }.map { window in
            .object(["number": .number(Double(window.windowNumber)), "visible": .bool(window.isVisible),
              "title": .string(window.title)])
          } ?? []),
        ]))
      }
      if request.method == "app.captureWindow" {
        guard let nativeWindow = NSApp?.windows.first(where: { $0.canBecomeMain && $0.isVisible }),
          let content = nativeWindow.contentView,
          let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
          throw CommandError("No visible browser window is available")
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
          throw CommandError("The browser window could not be captured")
        }
        let file = FileManager.default.temporaryDirectory
          .appendingPathComponent("aether-window-\(ProcessInfo.processInfo.processIdentifier).png")
        try data.write(to: file, options: .atomic)
        return AgentResponse(id: request.id, result: .object([
          "path": .string(file.path),
          "width": .number(Double(bitmap.pixelsWide)),
          "height": .number(Double(bitmap.pixelsHigh)),
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
      if request.method == "app.metrics" {
        guard let pageID = tab.enginePageID,
          let webView = workspace.engine.surface(pageID: pageID) as? WKWebView else {
          throw CommandError("Tab has no web page")
        }
        let source = """
          JSON.stringify((() => {
            const navigation = performance.getEntriesByType('navigation')[0];
            const paints = performance.getEntriesByType('paint');
            const largest = performance.getEntriesByType('largest-contentful-paint');
            const fcp = paints.find(entry => entry.name === 'first-contentful-paint');
            return {
              href: location.href,
              title: document.title,
              readyState: document.readyState,
              timeOrigin: performance.timeOrigin,
              fcpMs: fcp ? fcp.startTime : null,
              lcpMs: largest.length ? largest[largest.length - 1].startTime : null,
              requestStartMs: navigation ? navigation.requestStart : null,
              responseStartMs: navigation ? navigation.responseStart : null,
              responseEndMs: navigation ? navigation.responseEnd : null,
              redirectCount: navigation ? navigation.redirectCount : null,
              transferSize: navigation ? navigation.transferSize : null,
              domContentLoadedMs: navigation ? navigation.domContentLoadedEventEnd : null,
              loadEventEndMs: navigation && navigation.loadEventEnd ? navigation.loadEventEnd : null
            };
          })())
          """
        guard let json = try await webView.evaluateJavaScript(source) as? String,
          let data = json.data(using: .utf8) else {
          throw CommandError("Page performance metrics are unavailable")
        }
        return AgentResponse(id: request.id, result: try JSONDecoder().decode(JSONValue.self, from: data))
      }
      switch request.method {
      case "app.navigate": window.navigate(tab, text: try url(request))
      case "app.select": window.select(tab.id)
      case "app.close": window.close(tab.id)
      case "app.back": window.select(tab.id); window.perform(.back)
      case "app.forward": window.select(tab.id); window.perform(.forward)
      case "app.reload": window.select(tab.id); window.perform(.reload)
      case "app.float": window.select(tab.id); window.toggleFloatingVideo()
      case "app.copyMarkdown": window.copyMarkdownLink(for: tab)
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
      "paintReady": .bool(tab.paintReady),
      "progress": .number(tab.loadProgress),
      "canGoBack": .bool(tab.canGoBack), "canGoForward": .bool(tab.canGoForward),
    ])
  }

  private struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }
}
