import AppKit
import EngineCore
import Foundation
import WebKit

/// Agent-facing page capabilities that the human browser gets from `WKWebView` but that had
/// no code-callable equivalent (directive §6.2, §6.5). Every one is a real WebKit call, not
/// a simulated one.
extension WebKitPage {
  /// Current page zoom factor (1.0 = 100%), the same value the human zoom control reads.
  func zoomFactor() -> Double { Double(view.pageZoom) }

  /// Sets page zoom, clamped to the range the human control permits (0.25–5.0) so an agent
  /// cannot drive a page into an unreadable state.
  func setZoomFactor(_ factor: Double) -> Double {
    let clamped = min(5, max(0.25, factor))
    view.pageZoom = CGFloat(clamped)
    return Double(view.pageZoom)
  }

  /// Aborts the in-flight load, exactly as the human stop control does.
  func stopLoading() { view.stopLoading() }

  /// Writes the page as a PDF artifact and returns its byte size. Tier 3 evidence with a
  /// real file on disk, so success is the file, never the gesture.
  func printPDF(to url: URL) async throws -> Int {
    let data = try await view.pdf(configuration: WKPDFConfiguration())
    try data.write(to: url, options: .atomic)
    return data.count
  }

  /// The extensions loaded on this page's profile controller, as an agent can see them.
  /// The mapping happens here so the MainActor-isolated controller is read on the main
  /// actor and only a Sendable value crosses back (directive §6.5).
  func loadedExtensions() -> [BrowserExtensionInfo] {
    let contexts = context.extensionController?.extensionContexts ?? []
    return contexts.map { context in
      BrowserExtensionInfo(
        identifier: context.uniqueIdentifier,
        name: context.webExtension.displayName ?? context.uniqueIdentifier,
        loaded: context.isLoaded,
        inspectable: context.isInspectable)
    }.sorted { $0.identifier < $1.identifier }
  }
}
