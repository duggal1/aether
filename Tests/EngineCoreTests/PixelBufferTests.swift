import EngineCore
import Foundation
import Testing

struct PixelBufferTests {
  @Test func pngWriteProducesDecodableFile() throws {
    var buffer = PixelBuffer(width: 16, height: 16)
    buffer.blend(
      rect: Rect(x: 2, y: 2, width: 12, height: 12),
      color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("aether-pixel-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try buffer.write(to: url)
    let data = try Data(contentsOf: url)
    #expect(data.count > 8)
    #expect(data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
  }

  @Test func pngWriteSurfacesRealIOError() throws {
    let buffer = PixelBuffer(width: 8, height: 8)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("aether-missing-dir-\(UUID().uuidString)")
      .appendingPathComponent("tile.png")
    do {
      try buffer.write(to: url)
      Issue.record("Writing PNG into a missing directory unexpectedly succeeded")
    } catch is PixelBufferError {
      Issue.record("IO failure must not masquerade as an encoding failure")
    } catch {
      let nsError = error as NSError
      #expect(nsError.domain == NSCocoaErrorDomain)
    }
  }

  @Test func ppmWriteSurfacesRealIOError() throws {
    let buffer = PixelBuffer(width: 8, height: 8)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("aether-missing-dir-\(UUID().uuidString)")
      .appendingPathComponent("tile.ppm")
    #expect(throws: (any Error).self) { try buffer.write(to: url) }
  }
}
