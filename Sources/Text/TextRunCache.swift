import EngineCore

public struct TextCacheKey: Hashable, Sendable, Codable {
  public var text: String
  public var fontSizeMillipoints: Int
  public var fontWeight: Int
  public var maxWidthPoints: Int

  public init(text: String, fontSize: Double, fontWeight: Int, maxWidth: Double?) {
    self.text = text
    self.fontSizeMillipoints = max(1, Int((fontSize * 1000).rounded()))
    self.fontWeight = fontWeight
    self.maxWidthPoints = maxWidth.map { max(0, Int($0.rounded())) } ?? -1
  }
}

public struct TextRunCache: Sendable {
  public var capacity: Int
  public private(set) var hits: Int
  public private(set) var misses: Int
  private var entries: [TextCacheKey: TextRunMetrics]
  private var order: [TextCacheKey]

  public init(capacity: Int = 2048) {
    self.capacity = max(1, capacity)
    self.hits = 0
    self.misses = 0
    self.entries = [:]
    self.order = []
  }

  public var count: Int { entries.count }

  public var hitRate: Double {
    let total = hits + misses
    guard total > 0 else { return 0 }
    return Double(hits) / Double(total)
  }

  public mutating func metrics(
    for key: TextCacheKey, measuring: (TextCacheKey) -> TextRunMetrics
  ) -> TextRunMetrics {
    if let hit = entries[key] {
      hits += 1
      if let index = order.firstIndex(of: key) {
        order.remove(at: index)
        order.append(key)
      }
      return hit
    }
    misses += 1
    let value = measuring(key)
    entries[key] = value
    order.append(key)
    if order.count > capacity {
      let evicted = order.removeFirst()
      entries.removeValue(forKey: evicted)
    }
    return value
  }

  public mutating func clear() {
    entries.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
    hits = 0
    misses = 0
  }
}
