import CoreMedia
import CoreVideo
import DOM
import EngineCore
import Foundation

public actor MediaRegistry {
  public struct Element: Sendable {
    public var page: PageID
    public var node: NodeID
    public var tag: String
    public var source: MediaSource?
    public var backend: PlayerBackend
    public var autoplay: Bool
    public var events: [MediaEvent]

    public init(page: PageID, node: NodeID, tag: String) {
      self.page = page
      self.node = node
      self.tag = tag
      self.source = nil
      self.backend = PlayerBackend()
      self.autoplay = false
      self.events = []
    }
  }

  private var elements: [NodeID: Element] = [:]
  private var autoplayAllowed = true

  public init() {}

  public func setAutoplayAllowed(_ allowed: Bool) {
    autoplayAllowed = allowed
  }

  @discardableResult
  public func sync(
    pageID: PageID, document: DOMDocument, baseURL: URL,
    onEvent: (@Sendable (NodeID, MediaEvent) -> Void)? = nil
  ) -> [NodeID] {
    var live: [NodeID] = []
    for id in document.allNodeIDs() {
      guard let node = document.node(id),
        let tag = node.tagName?.lowercased(), tag == "video" || tag == "audio"
      else { continue }
      live.append(id)
      if elements[id] == nil {
        var element = Element(page: pageID, node: id, tag: tag)
        element.autoplay = node.attribute("autoplay") != nil
        if let handler = onEvent {
          let nodeID = id
          element.backend.setEventHandler { event, _ in handler(nodeID, event) }
        }
        elements[id] = element
      }
      if elements[id]?.source == nil,
        let source = resolveSource(node: node, document: document, baseURL: baseURL)
      {
        elements[id]?.source = source
        elements[id]?.backend.load(url: source.url)
        if elements[id]?.autoplay == true && autoplayAllowed {
          elements[id]?.backend.play()
        }
      }
    }
    let stale = elements.keys.filter { key in
      elements[key]?.page == pageID && !live.contains(key)
    }
    for key in stale {
      elements[key]?.backend.shutdown()
      elements.removeValue(forKey: key)
    }
    return live
  }

  public func element(_ node: NodeID) -> Element? {
    elements[node]
  }

  public func page(containing node: NodeID) -> PageID? {
    elements[node]?.page
  }

  public func reload(_ node: NodeID) {
    guard let element = elements[node], let source = element.source else { return }
    element.backend.load(url: source.url)
  }

  public func elements(pageID: PageID) -> [Element] {
    elements.values.filter { $0.page == pageID }
  }

  public func snapshot(_ node: NodeID, tag: String) -> MediaElementState {
    guard let element = elements[node] else {
      return MediaElementState(nodeIndex: node.index, nodeGeneration: node.version, tag: tag)
    }
    let (snap, frames, lastFrame) = element.backend.state()
    return MediaElementState(
      nodeIndex: node.index, nodeGeneration: node.version, tag: element.tag,
      currentSrc: element.source?.url.absoluteString,
      networkState: element.source == nil ? .noSource : (snap.statusReady ? .idle : .loading),
      readyState: snap.statusReady ? .enoughData : .nothing,
      seeking: false, paused: snap.rate == 0, ended: false, currentTime: snap.currentTime,
      duration: snap.duration, volume: snap.volume, muted: snap.muted,
      playbackRate: snap.rate == 0 ? 1 : snap.rate, videoWidth: snap.videoWidth,
      videoHeight: snap.videoHeight, error: snap.error, audioTracks: snap.audioTracks,
      textTracks: snap.textTracks, deliveredFrames: frames, lastFrameTime: lastFrame)
  }

  public func play(_ node: NodeID) {
    elements[node]?.backend.play()
  }

  public func pause(_ node: NodeID) {
    elements[node]?.backend.pause()
  }

  public func seek(_ node: NodeID, to seconds: Double) async -> Bool {
    guard let backend = elements[node]?.backend else { return false }
    return await withCheckedContinuation { continuation in
      backend.seek(to: seconds) { finished in
        continuation.resume(returning: finished)
      }
    }
  }

  public func setVolume(_ node: NodeID, volume: Double) {
    elements[node]?.backend.setVolume(volume)
  }

  public func setMuted(_ node: NodeID, muted: Bool) {
    elements[node]?.backend.setMuted(muted)
  }

  public func setRate(_ node: NodeID, rate: Double) {
    elements[node]?.backend.setRate(rate)
  }

  public func pollFrames(_ node: NodeID) {
    elements[node]?.backend.pollFrame()
  }

  public func setFrameHandler(
    _ node: NodeID, handler: (@Sendable (CVPixelBuffer, CMTime) -> Void)?
  ) {
    elements[node]?.backend.setFrameHandler(handler)
  }

  public func removePage(_ pageID: PageID) {
    for key in elements.keys where elements[key]?.page == pageID {
      elements[key]?.backend.shutdown()
      elements.removeValue(forKey: key)
    }
  }

  private func resolveSource(
    node: DOMNode, document: DOMDocument, baseURL: URL
  ) -> MediaSource? {
    if let src = node.attribute("src"),
      let url = URL(string: src, relativeTo: baseURL)?.absoluteURL,
      MediaFormat.supportedSchemes(url)
    {
      let mime = node.attribute("type")
      return MediaSource(url: url, mimeType: mime)
    }
    for childID in node.children {
      guard let child = document.node(childID),
        child.tagName?.lowercased() == "source",
        let src = child.attribute("src"),
        let url = URL(string: src, relativeTo: baseURL)?.absoluteURL,
        MediaFormat.supportedSchemes(url)
      else { continue }
      return MediaSource(url: url, mimeType: child.attribute("type"))
    }
    return nil
  }
}
