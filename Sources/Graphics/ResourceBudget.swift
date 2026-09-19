import EngineCore

public enum ResourceCategory: String, Hashable, Sendable, Codable, CaseIterable {
  case images
  case textures
  case raster
  case glyphs
}

public enum ResourcePressure: String, Hashable, Sendable, Codable {
  case nominal
  case elevated
  case critical
}

public struct ResourceBudget: Hashable, Sendable, Codable {
  public var maxImageBytes: Int
  public var maxTextureBytes: Int
  public var maxRasterBytes: Int
  public var maxGlyphBytes: Int

  public init(
    maxImageBytes: Int = 192_000_000, maxTextureBytes: Int = 256_000_000,
    maxRasterBytes: Int = 128_000_000, maxGlyphBytes: Int = 32_000_000
  ) {
    self.maxImageBytes = max(1, maxImageBytes)
    self.maxTextureBytes = max(1, maxTextureBytes)
    self.maxRasterBytes = max(1, maxRasterBytes)
    self.maxGlyphBytes = max(1, maxGlyphBytes)
  }

  public static var standard: ResourceBudget { ResourceBudget() }

  public func limit(for category: ResourceCategory) -> Int {
    switch category {
    case .images: return maxImageBytes
    case .textures: return maxTextureBytes
    case .raster: return maxRasterBytes
    case .glyphs: return maxGlyphBytes
    }
  }
}

public struct ResourceLedger: Hashable, Sendable, Codable {
  public var budget: ResourceBudget
  public private(set) var usage: [ResourceCategory: Int]

  public init(budget: ResourceBudget = .standard) {
    self.budget = budget
    self.usage = [:]
  }

  public func used(_ category: ResourceCategory) -> Int {
    usage[category, default: 0]
  }

  public mutating func allocate(_ bytes: Int, category: ResourceCategory) -> Bool {
    guard bytes >= 0 else { return false }
    let limit = budget.limit(for: category)
    guard used(category) + bytes <= limit else { return false }
    usage[category, default: 0] += bytes
    return true
  }

  public mutating func release(_ bytes: Int, category: ResourceCategory) {
    usage[category, default: 0] = max(0, used(category) - max(0, bytes))
  }

  public mutating func reset(_ category: ResourceCategory) {
    usage[category] = 0
  }

  public func pressure(for category: ResourceCategory) -> ResourcePressure {
    let ratio = Double(used(category)) / Double(max(1, budget.limit(for: category)))
    if ratio >= 0.95 { return .critical }
    if ratio >= 0.75 { return .elevated }
    return .nominal
  }

  public var overallPressure: ResourcePressure {
    var worst = ResourcePressure.nominal
    for category in ResourceCategory.allCases {
      let current = pressure(for: category)
      if current == .critical { return .critical }
      if current == .elevated { worst = .elevated }
    }
    return worst
  }
}
