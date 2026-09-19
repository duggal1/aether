import EngineCore
import Foundation

struct ChunkGridKey: Hashable, Sendable {
  var column: Int
  var row: Int
}

public struct PaintChunk: Hashable, Sendable, Codable {
  public var column: Int
  public var row: Int
  public var bounds: Rect
  public var commandIndices: [Int]

  public init(column: Int, row: Int, bounds: Rect, commandIndices: [Int]) {
    self.column = column
    self.row = row
    self.bounds = bounds
    self.commandIndices = commandIndices
  }
}

public struct PaintChunkIndex: Hashable, Sendable {
  public var chunks: [PaintChunk]
  public var chunkSize: Double

  public init(chunks: [PaintChunk], chunkSize: Double) {
    self.chunks = chunks
    self.chunkSize = chunkSize
  }

  public static func build(_ list: DisplayList, chunkSize: Double = 512) -> PaintChunkIndex {
    let stride = max(1, chunkSize)
    let columns = max(1, Int(ceil(list.size.width / stride)))
    let rows = max(1, Int(ceil(list.size.height / stride)))
    func column(_ x: Double) -> Int { max(0, min(columns - 1, Int(floor(x / stride)))) }
    func row(_ y: Double) -> Int { max(0, min(rows - 1, Int(floor(y / stride)))) }
    let fallback = Rect(x: 0, y: 0, width: list.size.width, height: list.size.height)
    var slots: [ChunkGridKey: [Int]] = [:]
    var order: [ChunkGridKey] = []
    for (index, command) in list.commands.enumerated() {
      let bounds = commandBounds(command) ?? fallback
      let target: Rect = bounds.isEmpty ? Rect(x: bounds.minX, y: bounds.minY, width: 1, height: 1) : bounds
      for c in column(target.minX)...column(target.maxX) {
        for r in row(target.minY)...row(target.maxY) {
          let key = ChunkGridKey(column: c, row: r)
          if slots[key] == nil { order.append(key) }
          slots[key, default: []].append(index)
        }
      }
    }
    let built = order.map { key in
      PaintChunk(
        column: key.column, row: key.row,
        bounds: Rect(
          x: Double(key.column) * stride, y: Double(key.row) * stride,
          width: stride, height: stride),
        commandIndices: slots[key] ?? [])
    }
    return PaintChunkIndex(chunks: built, chunkSize: stride)
  }

  public func chunks(intersecting rect: Rect) -> [PaintChunk] {
    chunks.filter { $0.bounds.intersects(rect) }
  }

  public func commandIndices(dirty region: DirtyRegion) -> [Int] {
    guard !region.isEmpty else { return [] }
    var found = Set<Int>()
    for rect in region.regions {
      for chunk in chunks where chunk.bounds.intersects(rect) {
        for index in chunk.commandIndices { found.insert(index) }
      }
    }
    return found.sorted()
  }

  static func commandBounds(_ command: DisplayCommand) -> Rect? {
    switch command {
    case .rect(let value): return value.rect
    case .text(let value): return value.rect
    case .image(let value): return value.rect
    case .pushClip(let value): return value.rect
    case .popClip: return nil
    }
  }
}
