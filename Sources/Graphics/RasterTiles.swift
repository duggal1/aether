import EngineCore
import Foundation

public struct TileKey: Hashable, Sendable, Codable {
  public var column: Int
  public var row: Int

  public init(column: Int, row: Int) {
    self.column = column
    self.row = row
  }
}

public struct TileRequest: Hashable, Sendable, Codable {
  public var key: TileKey
  public var bounds: Rect

  public init(key: TileKey, bounds: Rect) {
    self.key = key
    self.bounds = bounds
  }
}

public struct RasterTile: Hashable, Sendable, Codable {
  public var key: TileKey
  public var bounds: Rect
  public var lastUsed: UInt64
  public var byteCount: Int

  public init(key: TileKey, bounds: Rect, lastUsed: UInt64, byteCount: Int) {
    self.key = key
    self.bounds = bounds
    self.lastUsed = lastUsed
    self.byteCount = byteCount
  }
}

public struct TileCoverage: Hashable, Sendable, Codable {
  public var missing: [TileRequest]
  public var resident: [TileKey]

  public init(missing: [TileRequest], resident: [TileKey]) {
    self.missing = missing
    self.resident = resident
  }
}

public struct TileCache: Sendable {
  public var tileSize: Double
  public var budgetBytes: Int
  public private(set) var tiles: [TileKey: RasterTile]
  public private(set) var usedBytes: Int
  private var clock: UInt64

  public init(tileSize: Double = 256, budgetBytes: Int = 128_000_000) {
    self.tileSize = max(1, tileSize)
    self.budgetBytes = max(1, budgetBytes)
    self.tiles = [:]
    self.usedBytes = 0
    self.clock = 0
  }

  public static func byteCount(width: Double, height: Double) -> Int {
    max(1, Int(ceil(width))) * max(1, Int(ceil(height))) * 4
  }

  public mutating func coverage(for viewport: Rect) -> TileCoverage {
    let span = tileSize
    let firstColumn = Int(floor(viewport.minX / span))
    let lastColumn = Int(floor((viewport.maxX - 0.001) / span))
    let firstRow = Int(floor(viewport.minY / span))
    let lastRow = Int(floor((viewport.maxY - 0.001) / span))
    guard lastColumn >= firstColumn, lastRow >= firstRow else {
      return TileCoverage(missing: [], resident: [])
    }
    clock &+= 1
    var missing: [TileRequest] = []
    var resident: [TileKey] = []
    for column in firstColumn...lastColumn {
      for row in firstRow...lastRow {
        let key = TileKey(column: column, row: row)
        let bounds = Rect(
          x: Double(column) * span, y: Double(row) * span, width: span, height: span)
        if var tile = tiles[key] {
          tile.lastUsed = clock
          tiles[key] = tile
          resident.append(key)
        } else {
          missing.append(TileRequest(key: key, bounds: bounds))
        }
      }
    }
    return TileCoverage(missing: missing, resident: resident)
  }

  public mutating func store(_ request: TileRequest) -> Bool {
    let bytes = Self.byteCount(width: request.bounds.width, height: request.bounds.height)
    guard bytes <= budgetBytes else { return false }
    if tiles[request.key] != nil { return true }
    while usedBytes + bytes > budgetBytes,
      let oldest = tiles.min(by: { $0.value.lastUsed < $1.value.lastUsed })
    {
      tiles.removeValue(forKey: oldest.key)
      usedBytes = max(0, usedBytes - oldest.value.byteCount)
    }
    clock &+= 1
    tiles[request.key] = RasterTile(
      key: request.key, bounds: request.bounds, lastUsed: clock, byteCount: bytes)
    usedBytes += bytes
    return true
  }

  public mutating func invalidate(_ region: DirtyRegion) -> [TileKey] {
    guard let bounds = region.bounds else { return [] }
    var removed: [TileKey] = []
    for (key, tile) in tiles where tile.bounds.intersects(bounds) {
      removed.append(key)
      usedBytes = max(0, usedBytes - tile.byteCount)
    }
    for key in removed { tiles.removeValue(forKey: key) }
    return removed.sorted {
      if $0.row != $1.row { return $0.row < $1.row }
      return $0.column < $1.column
    }
  }
}
