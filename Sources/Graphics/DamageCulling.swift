import Display
import EngineCore

extension DirtyRegion {
  public func intersects(_ rect: Rect) -> Bool {
    guard !rect.isEmpty else { return false }
    return regions.contains { $0.intersects(rect) }
  }
}

extension DisplayList {
  public func commands(intersecting region: DirtyRegion) -> [DisplayCommand] {
    guard !region.isEmpty else { return [] }
    return commands.filter { command in
      switch command {
      case .pushClip, .popClip:
        return true
      case .rect(let value):
        return region.intersects(value.rect)
      case .text(let value):
        return region.intersects(value.rect)
      case .image(let value):
        return region.intersects(value.rect)
      }
    }
  }
}
