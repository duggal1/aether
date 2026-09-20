import AppKit
import BrowserEngine
import EngineCore
import EngineRuntime
import Graphics
import Metal
import Media
import QuartzCore

@MainActor
final class EnginePageView: NSView {
  let engine: NativeBrowserEngine
  let pageID: PageID
  let renderer: MetalRenderer
  let metalLayer = CAMetalLayer()
  let queue: MTLCommandQueue
  var presentation: Task<Void, Never>?
  var input: Task<Void, Never>?
  var needsFrame = true
  var previousFrame: RuntimePageFrame?
  var editingText = ""
  var editingSelection = NSRange(location: 0, length: 0)
  var markedTextValue = ""
  var lastError: String?
  var framesPresented = 0

  init(engine: NativeBrowserEngine, pageID: PageID) throws {
    guard let renderer = MetalRenderer(), let queue = renderer.device.makeCommandQueue() else {
      throw RendererError.renderingFailed
    }
    self.engine = engine
    self.pageID = pageID
    self.renderer = renderer
    self.queue = queue
    super.init(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
    metalLayer.device = renderer.device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = false
    metalLayer.isOpaque = true
    metalLayer.backgroundColor = NSColor.white.cgColor
    wantsLayer = true
    layer = metalLayer
    setAccessibilityRole(.webArea)
    setAccessibilityLabel("Aether web page")
  }

  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func layout() {
    super.layout()
    invalidatePage()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { stopPresenting() }
    else { startPresenting() }
  }

  func invalidatePage() { needsFrame = true }

  func startPresenting() {
    guard presentation == nil else { return }
    presentation = Task { [weak self] in
      while !Task.isCancelled {
        guard let self, self.window != nil else { return }
        do { try await self.presentFrame() }
        catch {
          if !(error is CancellationError) { self.lastError = String(describing: error) }
        }
        try? await Task.sleep(for: .milliseconds(33))
      }
    }
  }

  func stopPresenting() {
    presentation?.cancel()
    presentation = nil
  }

  func presentFrame() async throws {
    guard bounds.width > 0, bounds.height > 0 else { return }
    let size = Size(width: bounds.width, height: bounds.height)
    let info = try await engine.runtime.pageInfo(pageID)
    if info.viewport != size { _ = try await engine.runtime.resize(pageID: pageID, viewport: size) }
    guard info.loaded else { return }
    let frame = try await engine.runtime.presentationFrame(pageID: pageID)
    let changed = previousFrame?.revision != frame.revision
      || previousFrame?.navigation != frame.navigation || previousFrame?.scroll != frame.scroll
      || previousFrame?.viewport != frame.viewport
    let videos = try await engine.runtime.videoLayers(pageID: pageID, device: renderer.device)
    guard needsFrame || changed || !videos.isEmpty else { return }
    needsFrame = false
    previousFrame = frame
    metalLayer.drawableSize = CGSize(width: ceil(size.width), height: ceil(size.height))
    guard let drawable = metalLayer.nextDrawable() else { needsFrame = true; return }
    let texture = try renderer.renderFrame(frame.displayList, viewport: size,
      origin: Point(x: -frame.scroll.x, y: -frame.scroll.y),
      videoLayers: videos.map { MetalVideoLayer(texture: $0.frame.texture, rect: $0.rect) }).texture
    guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
      throw RendererError.renderingFailed
    }
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: min(texture.width, drawable.texture.width),
        height: min(texture.height, drawable.texture.height), depth: 1),
      to: drawable.texture, destinationSlice: 0, destinationLevel: 0,
      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
    blit.endEncoding()
    command.present(drawable)
    command.commit()
    framesPresented += 1
    lastError = nil
  }

  func enqueue(_ operation: @escaping @MainActor () async throws -> Void) {
    let previous = input
    input = Task { [weak self] in
      await previous?.value
      guard !Task.isCancelled, let self else { return }
      do {
        try await operation()
        await self.refreshEditingState()
        self.invalidatePage()
      } catch { self.lastError = String(describing: error) }
    }
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    enqueue { [engine, pageID] in
      if let node = try await engine.runtime.nodeAtPoint(pageID: pageID, x: point.x, y: point.y) {
        _ = try await engine.click(pageID: pageID, nodeID: node.id)
      }
    }
  }

  override func scrollWheel(with event: NSEvent) {
    let scale = event.hasPreciseScrollingDeltas ? 1.0 : 30.0
    let x = -event.scrollingDeltaX * scale
    let y = -event.scrollingDeltaY * scale
    enqueue { [engine, pageID] in try await engine.runtime.scrollBy(pageID: pageID, x: x, y: y) }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 48 {
      let backwards = event.modifierFlags.contains(.shift)
      enqueue { [engine, pageID] in try await engine.runtime.focusNext(pageID: pageID, backwards: backwards) }
    } else { interpretKeyEvents([event]) }
  }

  override func resignFirstResponder() -> Bool {
    unmarkText()
    return super.resignFirstResponder()
  }

  func refreshEditingState() async {
    guard let state = try? await engine.runtime.editingState(pageID: pageID) else {
      editingText = ""; editingSelection = NSRange(location: 0, length: 0); return
    }
    editingText = state.text
    editingSelection = state.selection
  }
}
