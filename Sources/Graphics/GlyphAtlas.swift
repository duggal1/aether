import EngineCore
import Foundation

public struct GlyphKey: Hashable, Sendable, Codable {
  public var scalar: UInt32
  public var fontSizeMillipoints: Int
  public var fontWeight: Int

  public init(scalar: UInt32, fontSizeMillipoints: Int, fontWeight: Int) {
    self.scalar = scalar
    self.fontSizeMillipoints = fontSizeMillipoints
    self.fontWeight = fontWeight
  }
}

public struct GlyphCell: Hashable, Sendable, Codable {
  public var key: GlyphKey
  public var bounds: Rect
  public var lastUsed: UInt64

  public init(key: GlyphKey, bounds: Rect, lastUsed: UInt64) {
    self.key = key
    self.bounds = bounds
    self.lastUsed = lastUsed
  }
}

struct GlyphShelf: Sendable {
  var originY: Double
  var height: Double
  var cursorX: Double
}

public struct GlyphAtlas: Sendable {
  public var width: Double
  public var height: Double
  public private(set) var cells: [GlyphKey: GlyphCell]
  public private(set) var usedArea: Double
  private var shelves: [GlyphShelf]
  private var clock: UInt64

  public init(width: Double = 1024, height: Double = 1024) {
    self.width = max(1, width)
    self.height = max(1, height)
    self.cells = [:]
    self.usedArea = 0
    self.shelves = []
    self.clock = 0
  }

  public var count: Int { cells.count }

  public var occupancy: Double {
    guard width > 0, height > 0 else { return 0 }
    return usedArea / (width * height)
  }

  public mutating func cell(for key: GlyphKey, size: Size) -> Rect? {
    clock &+= 1
    if var existing = cells[key] {
      existing.lastUsed = clock
      cells[key] = existing
      return existing.bounds
    }
    let placedWidth = max(1, ceil(size.width) + 1)
    let placedHeight = max(1, ceil(size.height) + 1)
    guard placedWidth <= width, placedHeight <= height else { return nil }
    for index in shelves.indices {
      if shelves[index].height >= placedHeight,
        shelves[index].cursorX + placedWidth <= width
      {
        let placed = Rect(
          x: shelves[index].cursorX, y: shelves[index].originY,
          width: placedWidth, height: placedHeight)
        shelves[index].cursorX += placedWidth
        cells[key] = GlyphCell(key: key, bounds: placed, lastUsed: clock)
        usedArea += placedWidth * placedHeight
        return placed
      }
    }
    let bottom = shelves.reduce(0) { max($0, $1.originY + $1.height) }
    guard bottom + placedHeight <= height else { return nil }
    let placed = Rect(x: 0, y: bottom, width: placedWidth, height: placedHeight)
    shelves.append(GlyphShelf(originY: bottom, height: placedHeight, cursorX: placedWidth))
    cells[key] = GlyphCell(key: key, bounds: placed, lastUsed: clock)
    usedArea += placedWidth * placedHeight
    return placed
  }

  public mutating func remove(_ key: GlyphKey) {
    guard let cell = cells.removeValue(forKey: key) else { return }
    usedArea = max(0, usedArea - cell.bounds.width * cell.bounds.height)
  }

  public mutating func clear() {
    cells.removeAll(keepingCapacity: true)
    shelves.removeAll(keepingCapacity: true)
    usedArea = 0
  }
}
