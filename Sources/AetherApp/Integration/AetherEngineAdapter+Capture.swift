import AetherHumanUI
import EngineRuntime
import Foundation

extension AetherEngineAdapter: BrowserPageCapturing {
  func captureLivePage(pageID: String, into directory: String, includeSource: Bool) async throws
    -> BrowserLiveCapture
  {
    let id = try page(pageID)
    let captured = try await engine.runtime.captureLivePage(
      pageID: id, into: URL(fileURLWithPath: directory), includeSource: includeSource)
    return BrowserLiveCapture(
      directory: captured.directory.path,
      imageFile: captured.imageFile,
      imageFormat: captured.imageFormat,
      pixelWidth: captured.pixelWidth,
      pixelHeight: captured.pixelHeight,
      htmlFile: captured.htmlFile,
      computedStylesFile: captured.computedStylesFile,
      manifestFile: captured.manifestFile,
      truncated: captured.truncated,
      warnings: captured.warnings)
  }

  func pageSource(pageID: String) async throws -> BrowserPageSource {
    let id = try page(pageID)
    let state = try await engine.runtime.captureState(pageID: id)
    let document = try await engine.runtime.captureDocument(
      pageID: id, includeComputedStyles: true, redactSensitive: false)
    return BrowserPageSource(
      url: state.url?.absoluteString ?? "",
      title: state.title,
      html: document.html,
      stylesheets: document.stylesheets.map(\.css),
      computedStyles: document.nodes.map(\.computedStyles))
  }
}
