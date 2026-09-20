import EngineCore
import Foundation
import Media
import Metal

public struct RuntimeVideoLayer: Sendable {
  public let frame: MediaVideoFrame
  public let rect: Rect
}

extension BrowserRuntime {
  public func videoLayers(pageID: PageID, device: MTLDevice) async throws -> [RuntimeVideoLayer] {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded, let context = contexts[page.contextID] else { return [] }
    let elements = await context.media.elements(pageID: pageID)
    return elements.compactMap { element in
      guard element.tag == "video", let box = loaded.layout.boxes[element.node],
        let frame = element.backend.currentVideoFrame(device: device) else { return nil }
      return RuntimeVideoLayer(frame: frame, rect: box.frame)
    }
  }
}
