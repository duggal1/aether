import CoreVideo
import Foundation
import Metal

public struct MediaVideoFrame: @unchecked Sendable {
  public let texture: MTLTexture
  private let surface: CVMetalTexture
  private let buffer: CVPixelBuffer
  init(texture: MTLTexture, surface: CVMetalTexture, buffer: CVPixelBuffer) {
    self.texture = texture; self.surface = surface; self.buffer = buffer
  }
}

final class VideoTextureCache: @unchecked Sendable {
  private let lock = NSLock()
  private var cache: CVMetalTextureCache?

  init() {}

  func frame(
    for pixelBuffer: CVPixelBuffer, device: MTLDevice
  ) -> MediaVideoFrame? {
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
      return MediaVideoFrame(texture: texture, surface: surface, buffer: pixelBuffer)
    }
  }

  func flush() {
    lock.withLock {
      guard let cache else { return }
      CVMetalTextureCacheFlush(cache, 0)
    }
  }
}
