import Display
import EngineCore

public struct RetainedRaster: Sendable {
  private var displayList: DisplayList?
  private var viewport: Size?
  private var origin: Point?
  private var pixels: PixelBuffer?
  public private(set) var revision: UInt64 = 0

  public init() {}

  public var byteCount: Int { pixels?.bytes.count ?? 0 }

  public mutating func clear() {
    displayList = nil
    viewport = nil
    origin = nil
    pixels = nil
  }

  public mutating func render(
    _ list: DisplayList, viewport: Size, origin: Point, maximumBytes: Int
  ) throws -> (pixels: PixelBuffer, reused: Bool) {
    guard viewport.width.isFinite, viewport.height.isFinite,
      viewport.width > 0, viewport.height > 0,
      viewport.width <= 16384, viewport.height <= 16384,
      origin.x.isFinite, origin.y.isFinite,
      abs(origin.x) <= 1_000_000_000, abs(origin.y) <= 1_000_000_000
    else { throw RendererError.renderingFailed }
    let bytes = Int(viewport.width.rounded(.up)) * Int(viewport.height.rounded(.up)) * 4
    guard bytes <= maximumBytes else { throw RendererError.renderingFailed }
    if self.viewport == viewport, self.origin == origin, displayList == list, let pixels {
      return (pixels, true)
    }
    clear()
    let rendered = try SoftwareRenderer().render(list, viewport: viewport, origin: origin)
    displayList = list
    self.viewport = viewport
    self.origin = origin
    pixels = rendered
    revision &+= 1
    return (rendered, false)
  }
}
