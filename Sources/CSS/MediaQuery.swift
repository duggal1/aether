import EngineCore
import Foundation

public struct MediaQuery: Hashable, Sendable {
  public enum Condition: Hashable, Sendable {
    case minWidth(Double)
    case maxWidth(Double)
    case minHeight(Double)
    case maxHeight(Double)
    case orientationPortrait
    case orientationLandscape
  }

  public var conditions: [Condition]
  public var isPrint: Bool

  public init(conditions: [Condition] = [], isPrint: Bool = false) {
    self.conditions = conditions
    self.isPrint = isPrint
  }

  public func matches(viewport: Size) -> Bool {
    if isPrint { return false }
    for condition in conditions {
      switch condition {
      case .minWidth(let v): if viewport.width < v { return false }
      case .maxWidth(let v): if viewport.width > v { return false }
      case .minHeight(let v): if viewport.height < v { return false }
      case .maxHeight(let v): if viewport.height > v { return false }
      case .orientationPortrait: if viewport.width > viewport.height { return false }
      case .orientationLandscape: if viewport.height > viewport.width { return false }
      }
    }
    return true
  }

  public static func matchesAny(_ prelude: String, viewport: Size) -> Bool {
    parseList(prelude).contains { $0.matches(viewport: viewport) }
  }

  public static func parseList(_ prelude: String) -> [MediaQuery] {
    splitQueries(prelude).map { parseSingle($0) }
  }

  static func splitQueries(_ prelude: String) -> [String] {
    var result: [String] = []
    var current = ""
    var depth = 0
    for character in prelude {
      if character == "(" { depth += 1 }
      if character == ")" { depth -= 1 }
      if character == ",", depth == 0 {
        result.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    result.append(current)
    return result.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
  }

  static func parseSingle(_ query: String) -> MediaQuery {
    let lower = query.lowercased()
    if lower.contains("print") { return MediaQuery(isPrint: true) }
    var conditions: [Condition] = []
    var search = lower.startIndex
    while let open = lower.range(of: "(", range: search..<lower.endIndex) {
      guard let close = lower.range(of: ")", range: open.upperBound..<lower.endIndex) else {
        break
      }
      let feature = lower[open.upperBound..<close.lowerBound]
      let parts = feature.split(separator: ":").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      if parts.count == 2 {
        let pixels = parsePixels(parts[1])
        switch parts[0] {
        case "min-width": if let v = pixels { conditions.append(.minWidth(v)) }
        case "max-width": if let v = pixels { conditions.append(.maxWidth(v)) }
        case "min-height": if let v = pixels { conditions.append(.minHeight(v)) }
        case "max-height": if let v = pixels { conditions.append(.maxHeight(v)) }
        case "orientation":
          if parts[1] == "portrait" { conditions.append(.orientationPortrait) }
          if parts[1] == "landscape" { conditions.append(.orientationLandscape) }
        default: break
        }
      } else if feature.trimmingCharacters(in: .whitespacesAndNewlines) == "orientation: portrait" {
        conditions.append(.orientationPortrait)
      }
      search = close.upperBound
    }
    return MediaQuery(conditions: conditions)
  }

  static func parsePixels(_ value: String) -> Double? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasSuffix("px") { return Double(trimmed.dropLast(2)) }
    if trimmed.hasSuffix("em") {
      guard let n = Double(trimmed.dropLast(2)) else { return nil }
      return n * 16
    }
    return Double(trimmed)
  }
}

public struct LayerOrder: Sendable {
  public var order: [String] = []

  public init() {}

  public mutating func declare(_ name: String) {
    if !order.contains(name) { order.append(name) }
  }

  public func rank(of layer: String?) -> Int {
    guard let layer else { return Int.max }
    return order.firstIndex(of: layer) ?? order.count
  }
}
