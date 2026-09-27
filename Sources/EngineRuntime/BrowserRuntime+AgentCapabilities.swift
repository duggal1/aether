import AppKit
import EngineCore
import Foundation

/// One loaded browser extension as an agent can see it (directive §6.5).
public struct BrowserExtensionInfo: Hashable, Sendable, Codable {
  public var identifier: String
  public var name: String
  public var loaded: Bool
  public var inspectable: Bool

  public init(identifier: String, name: String, loaded: Bool, inspectable: Bool) {
    self.identifier = identifier
    self.name = name
    self.loaded = loaded
    self.inspectable = inspectable
  }
}

/// Tier 2 raw capability that had no code-callable equivalent (directive §6.2, §6.4, §6.5).
/// Every method here is a thin read or a real platform call — no adapter logic, no second
/// implementation of browser behaviour (directive §13.1).
extension BrowserRuntime {
  /// Aborts the in-flight navigation, like the human stop control.
  public func stopLoading(pageID: PageID) async throws {
    _ = try await webPage(pageID)
    await stopNavigation(pageID: pageID)
  }

  public func zoom(pageID: PageID) async throws -> Double {
    try await requireAgentControl(pageID: pageID)
    return try await webPage(pageID).zoomFactor()
  }

  public func setZoom(pageID: PageID, factor: Double) async throws -> Double {
    try await requireAgentControl(pageID: pageID)
    guard factor.isFinite else { throw BrowserRuntimeError.invalidState("zoom factor") }
    return try await webPage(pageID).setZoomFactor(factor)
  }

  /// Prints the page to a real PDF artifact and returns its size in bytes.
  public func printPage(pageID: PageID, into url: URL) async throws -> Int {
    try await requireAgentControl(pageID: pageID)
    return try await webPage(pageID).printPDF(to: url)
  }

  /// Reads the system clipboard. Agents reach the clipboard the same way a human does; the
  /// call is explicit and audited at the operation boundary, never automatic.
  public func clipboardRead() -> String {
    NSPasteboard.general.string(forType: .string) ?? ""
  }

  public func clipboardWrite(_ text: String) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(text, forType: .string)
  }

  /// File upload is a real gap: WebKit exposes no public API to populate a file input except
  /// through the user-picked `NSOpenPanel` flow, so it is reported as a typed limitation
  /// rather than silently doing nothing (directive §6.7, §12.1.14).
  public func uploadFile(pageID: PageID, path: String) async throws -> Int {
    _ = try await webPage(pageID)
    throw BrowserRuntimeError.unsupported(
      "WebKit does not expose a public API to attach a file to a file input without the user selecting it")
  }

  /// Enumerates the extensions loaded on the page's profile controller. An empty list is a
  /// truthful "none are installed", not a missing capability.
  public func listExtensions(pageID: PageID) async throws -> [BrowserExtensionInfo] {
    try await requireAgentControl(pageID: pageID)
    return try await webPage(pageID).loadedExtensions()
  }
}
