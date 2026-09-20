import CoreVideo
import Foundation
import Metal

final class VideoTextureCache: @unchecked Sendable {
  private let lock = NSLock()
  private var cache: CVMetalTextureCache?

  init() {}

  func texture(
    for pixelBuffer: CVPixelBuffer, device: MTLDevice
  ) -> MTLTexture? {
    lock.withLock {
      if cache == nil {
        var created: CVMetalTextureCache?
        guard
          CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &created) == kCVReturnSuccess,
          let created
        else { return nil }
        cache = created
      }
      guard let cache else { return nil }
      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      var surface: CVMetalTexture?
      guard
        CVMetalTextureCacheCreateTextureFromImage(
          kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0,
          &surface) == kCVReturnSuccess,
        let surface, let texture = CVMetalTextureGetTexture(surface)
      else { return nil }
      return texture
    }
  }

  func flush() {
    lock.withLock {
      guard let cache else { return }
      CVMetalTextureCacheFlush(cache, 0)
    }
  }
}
