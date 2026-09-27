import EngineCore
import Foundation
import WebKit

// The Web Inspector: WebKit's own, on the page in front — from the View menu
// and its keys, as from Inspect Element in a page's right-click menu.
//
// WebKit answers for its inspector only through names outside the public
// framework, so each is asked for before it is used; a WebKit without them
// leaves the caller doing nothing rather than the app falling over.

extension BrowserRuntime {
  /// The inspector, or put away if it is up.
  public func toggleInspector(pageID: PageID) async throws {
    let page = try await webPage(pageID)
    await MainActor.run {
      guard let inspector = Self.inspector(of: page.view) else { return }
      if Self.inspectorAsks(inspector, "isVisible") {
        Self.inspectorSend(inspector, "close")
      } else {
        Self.inspectorSend(inspector, "show")
      }
    }
  }

  /// The inspector, at its console.
  public func showConsole(pageID: PageID) async throws {
    let page = try await webPage(pageID)
    await MainActor.run {
      guard let inspector = Self.inspector(of: page.view) else { return }
      Self.inspectorSend(inspector, "showConsole")
    }
  }

  /// The inspector, with the next click on the page picking what it shows.
  /// Again, and the picking stops.
  public func inspectElement(pageID: PageID) async throws {
    let page = try await webPage(pageID)
    await MainActor.run {
      guard let inspector = Self.inspector(of: page.view) else { return }
      if !Self.inspectorAsks(inspector, "isVisible") { Self.inspectorSend(inspector, "show") }
      Self.inspectorSend(inspector, "toggleElementSelection")
    }
  }

  /// Whether the page's inspector is currently visible.
  public func isInspectorVisible(pageID: PageID) async throws -> Bool {
    let page = try await webPage(pageID)
    return await MainActor.run {
      guard let inspector = Self.inspector(of: page.view) else { return false }
      return Self.inspectorAsks(inspector, "isVisible")
    }
  }

  @MainActor
  private static func inspector(of web: WKWebView) -> NSObject? {
    let get = NSSelectorFromString("_inspector")
    guard web.responds(to: get) else { return nil }
    return web.perform(get)?.takeUnretainedValue() as? NSObject
  }

  @MainActor
  private static func inspectorSend(_ inspector: NSObject, _ name: String) {
    let selector = NSSelectorFromString(name)
    guard inspector.responds(to: selector) else { return }
    inspector.perform(selector)
  }

  @MainActor
  private static func inspectorAsks(_ inspector: NSObject, _ name: String) -> Bool {
    let selector = NSSelectorFromString(name)
    guard inspector.responds(to: selector) else { return false }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(inspector.method(for: selector), to: Getter.self)(inspector, selector)
  }
}
