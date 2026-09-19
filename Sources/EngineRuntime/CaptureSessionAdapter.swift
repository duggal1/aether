import AetherCapture
import EngineCore
import Foundation

public struct BrowserCaptureEngine: AetherCaptureEngine {
  public let runtime: BrowserRuntime

  public init(runtime: BrowserRuntime) {
    self.runtime = runtime
  }

  public func makeCaptureSession(viewport: CaptureViewport) async throws -> any AetherCaptureSession
  {
    guard viewport.width > 0, viewport.height > 0, viewport.width <= 8192, viewport.height <= 8192
    else { throw CaptureFailure.invalidOptions }
    guard viewport.scale == 1 else { throw CaptureFailure.invalidOptions }
    let session = NativeCaptureSession(
      runtime: runtime, viewport: Size(width: Double(viewport.width), height: Double(viewport.height)))
    try await session.open()
    return session
  }
}

public actor NativeCaptureSession: AetherCaptureSession {
  private let runtime: BrowserRuntime
  private let viewport: Size
  private var contextID: ContextID?
  private var pageID: PageID?

  init(runtime: BrowserRuntime, viewport: Size) {
    self.runtime = runtime
    self.viewport = viewport
  }

  func open() async throws {
    let context = await runtime.createContext(name: "capture")
    do {
      let page = try await runtime.createPage(contextID: context.id, viewport: viewport)
      contextID = context.id
      pageID = page.id
    } catch {
      try? await runtime.destroyContext(context.id)
      throw error
    }
  }

  public func navigate(to url: URL) async throws {
    let (_, page) = try requireIDs()
    do {
      _ = try await runtime.navigate(pageID: page, to: url)
    } catch {
      throw CaptureFailure.navigationFailed(String(describing: error))
    }
  }

  public func state() async throws -> AetherPageState {
    let (_, page) = try requireIDs()
    let data = try await runtime.captureState(pageID: page)
    guard let url = data.url else {
      throw CaptureFailure.navigationFailed("Page has no URL")
    }
    var blocked: String?
    if [403, 429, 451].contains(data.statusCode) {
      blocked = "Server refused capture with HTTP \(data.statusCode)"
    }
    return AetherPageState(
      finalURL: url, title: data.title, viewportCSSWidth: data.viewport.width,
      viewportCSSHeight: data.viewport.height,
      documentCSSHeight: max(0, data.documentSize.height), scrollY: data.scroll.y,
      blockedReason: blocked)
  }

  public func scrollTo(documentY: Double) async throws {
    let (_, page) = try requireIDs()
    let data = try await runtime.captureState(pageID: page)
    let limit = max(0, data.documentSize.height - data.viewport.height)
    _ = try await runtime.scrollTo(pageID: page, x: 0, y: min(max(0, documentY), limit))
  }

  public func waitForVisualStability(maxMilliseconds: Int) async throws {
    let (_, page) = try requireIDs()
    try Task.checkCancellation()
    let budget = max(0, maxMilliseconds)
    let clock = ContinuousClock()
    let started = clock.now
    var since: UInt64 = 0
    var quietPasses = 0
    while true {
      let deltas = (try? await runtime.mutations(pageID: page, since: since)) ?? []
      if let latest = deltas.map(\.version).max() { since = max(since, latest) }
      if deltas.isEmpty {
        quietPasses += 1
      } else {
        quietPasses = 0
      }
      if quietPasses >= 2 { return }
      let elapsed = started.duration(to: clock.now)
      let elapsedMilliseconds = Int(
        elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
      )
      if elapsedMilliseconds >= budget { return }
      try await Task.sleep(for: .milliseconds(30))
      try Task.checkCancellation()
    }
  }

  public func renderViewport() async throws -> AetherRaster {
    let (_, page) = try requireIDs()
    let data = try await runtime.captureState(pageID: page)
    let buffer = try await runtime.render(
      pageID: page, origin: Point(x: 0, y: data.scroll.y))
    guard buffer.width > 0, buffer.height > 0 else { throw CaptureFailure.invalidRaster }
    return try AetherRaster(
      rgba: Data(buffer.bytes), width: buffer.width, height: buffer.height,
      bytesPerRow: buffer.width * 4)
  }

  public func snapshot(includeComputedStyles: Bool, redactSensitive: Bool) async throws
    -> AetherDocumentSnapshot
  {
    let (_, page) = try requireIDs()
    let data = try await runtime.captureDocument(
      pageID: page, includeComputedStyles: includeComputedStyles, redactSensitive: redactSensitive)
    return AetherDocumentSnapshot(
      html: data.html,
      stylesheets: data.stylesheets.map {
        AetherStylesheet(sourceURL: $0.sourceURL, media: $0.media, css: $0.css)
      },
      nodes: data.nodes.map {
        AetherDocumentNode(
          selector: $0.selector, tag: $0.tag, role: $0.role, text: $0.text,
          bounds: CaptureRect(
            x: $0.bounds.minX, y: $0.bounds.minY, width: $0.bounds.width,
            height: $0.bounds.height),
          computedStyles: $0.computedStyles)
      },
      resources: data.resources.map { AetherResourceReference(url: $0.url, kind: $0.kind) },
      warnings: data.issues.map { CaptureWarning($0.code, $0.detail) })
  }

  public func resourceBytes(for url: URL, maximumBytes: Int) async throws -> Data? {
    let (context, _) = try requireIDs()
    return try await runtime.cachedResourceBytes(
      contextID: context, url: url, maximumBytes: maximumBytes)
  }

  public func close() async {
    if let context = contextID { try? await runtime.destroyContext(context) }
    contextID = nil
    pageID = nil
  }

  private func requireIDs() throws -> (ContextID, PageID) {
    guard let context = contextID, let page = pageID else {
      throw CaptureFailure.navigationFailed("Capture session is closed")
    }
    return (context, page)
  }
}
