import EngineCore
import Foundation

public enum CSSCombinator: String, Hashable, Sendable, Codable {
  case descendant
  case child
  case adjacentSibling
  case generalSibling
}

public enum CSSAttributeOperator: String, Hashable, Sendable, Codable {
  case exists
  case equals
  case includes
  case dashMatch
  case prefix
  case suffix
  case substring
}

public struct CSSPseudoClass: Hashable, Sendable, Codable {
  public var name: String
  public var argument: String?

  public init(name: String, argument: String? = nil) {
    self.name = name.lowercased()
    self.argument = argument
  }
}

public struct CSSSimpleSelector: Hashable, Sendable, Codable {
  public var tag: String?
  public var id: String?
  public var classes: [String]
  public var attributes: [CSSAttributeSelector]
  public var pseudos: [CSSPseudoClass]
  public var pseudoElement: String?
  public var universal: Bool

  public init(
    tag: String? = nil, id: String? = nil, classes: [String] = [],
    attributes: [CSSAttributeSelector] = [], pseudos: [CSSPseudoClass] = [],
    pseudoElement: String? = nil, universal: Bool = false
  ) {
    self.tag = tag
    self.id = id
    self.classes = classes
    self.attributes = attributes
    self.pseudos = pseudos
    self.pseudoElement = pseudoElement
    self.universal = universal
  }

  public var specificity: CSSSpecificity {
    var classes = classes.count + attributes.count
    var ids = id == nil ? 0 : 1
    var types = tag == nil ? 0 : 1
    for pseudo in pseudos {
      switch pseudo.name {
      case "where":
        continue
      case "is", "not", "has":
        if let argument = pseudo.argument {
          var best = CSSSpecificity()
          for selector in argument.split(separator: ",") {
            if let parsed = CSSSpecificity.innerSpecificity(String(selector)) {
              if best < parsed { best = parsed }
            }
          }
          ids += best.ids
          classes += best.classes
          types += best.types
        } else {
          classes += 1
        }
      default:
        classes += 1
      }
    }
    return CSSSpecificity(ids: ids, classes: classes, types: types)
  }
}

public struct CSSAttributeSelector: Hashable, Sendable, Codable {
  public var name: String
  public var op: CSSAttributeOperator
  public var value: String?

  public init(name: String, value: String? = nil, op: CSSAttributeOperator? = nil) {
    self.name = name
    if let value {
      self.value = value
      self.op = op ?? .equals
    } else {
      self.value = nil
      self.op = .exists
    }
  }
}

public struct CSSSelectorPart: Hashable, Sendable, Codable {
  public var simple: CSSSimpleSelector
  public var combinatorToPrevious: CSSCombinator?

  public init(simple: CSSSimpleSelector, combinatorToPrevious: CSSCombinator? = nil) {
    self.simple = simple
    self.combinatorToPrevious = combinatorToPrevious
  }
}

public struct CSSSelector: Hashable, Sendable, Codable {
  public var parts: [CSSSelectorPart]

  public init(parts: [CSSSelectorPart]) {
    self.parts = parts
  }

  public var specificity: CSSSpecificity {
    parts.reduce(CSSSpecificity()) { $0 + $1.simple.specificity }
  }
}

public struct CSSSpecificity: Comparable, Hashable, Sendable, Codable {
  public var ids: Int
  public var classes: Int
  public var types: Int

  public init(ids: Int = 0, classes: Int = 0, types: Int = 0) {
    self.ids = ids
    self.classes = classes
    self.types = types
  }

  public static func + (lhs: CSSSpecificity, rhs: CSSSpecificity) -> CSSSpecificity {
    CSSSpecificity(
      ids: lhs.ids + rhs.ids, classes: lhs.classes + rhs.classes, types: lhs.types + rhs.types)
  }

  public static func < (lhs: CSSSpecificity, rhs: CSSSpecificity) -> Bool {
    if lhs.ids != rhs.ids { return lhs.ids < rhs.ids }
    if lhs.classes != rhs.classes { return lhs.classes < rhs.classes }
    return lhs.types < rhs.types
  }

  static func innerSpecificity(_ source: String) -> CSSSpecificity? {
    CSSParser.parseSelector(source)?.specificity
  }
}

public struct CSSDeclaration: Hashable, Sendable, Codable {
  public var property: String
  public var value: String
  public var important: Bool

  public init(property: String, value: String, important: Bool = false) {
    let trimmed = property.trimmingCharacters(in: .whitespacesAndNewlines)
    self.property = trimmed.hasPrefix("--") ? trimmed : trimmed.lowercased()
    self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    self.important = important
  }

  public var isCustomProperty: Bool { property.hasPrefix("--") }
}

public struct CSSRule: Hashable, Sendable, Codable {
  public var selectors: [CSSSelector]
  public var declarations: [CSSDeclaration]
  public var sourceOrder: Int
  public var layer: String?
  public var media: String?

  public init(
    selectors: [CSSSelector], declarations: [CSSDeclaration], sourceOrder: Int,
    layer: String? = nil, media: String? = nil
  ) {
    self.selectors = selectors
    self.declarations = declarations
    self.sourceOrder = sourceOrder
    self.layer = layer
    self.media = media
  }
}

public struct Stylesheet: Hashable, Sendable, Codable {
  public var rules: [CSSRule]
  public var layerOrder: [String]

  public init(rules: [CSSRule] = [], layerOrder: [String] = []) {
    self.rules = rules
    self.layerOrder = layerOrder
  }
}

public enum CSSLength: Hashable, Sendable, Codable {
  case auto
  case px(Double)
  case percent(Double)
  case em(Double)
  case rem(Double)
  case viewportWidth(Double)
  case viewportHeight(Double)
  case viewportMin(Double)
  case viewportMax(Double)
  case ch(Double)

  public static func parse(_ raw: String) -> CSSLength? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "auto" { return .auto }
    let units: [(String, (Double) -> CSSLength)] = [
      ("vmin", CSSLength.viewportMin),
      ("vmax", CSSLength.viewportMax),
      ("px", CSSLength.px),
      ("rem", CSSLength.rem),
      ("em", CSSLength.em),
      ("vw", CSSLength.viewportWidth),
      ("vh", CSSLength.viewportHeight),
      ("ch", CSSLength.ch),
      ("%", CSSLength.percent),
    ]
    for (suffix, make) in units where value.hasSuffix(suffix) {
      if let number = Double(value.dropLast(suffix.count)) { return make(number) }
    }
    if let number = Double(value) { return .px(number) }
    return nil
  }

  public func resolve(reference: Double, fontSize: Double, rootFontSize: Double, viewport: Size)
    -> Double?
  {
    switch self {
    case .auto: return nil
    case .px(let value): return value
    case .percent(let value): return reference * value / 100
    case .em(let value): return fontSize * value
    case .rem(let value): return rootFontSize * value
    case .viewportWidth(let value): return viewport.width * value / 100
    case .viewportHeight(let value): return viewport.height * value / 100
    case .viewportMin(let value): return min(viewport.width, viewport.height) * value / 100
    case .viewportMax(let value): return max(viewport.width, viewport.height) * value / 100
    case .ch(let value): return fontSize * 0.5 * value
    }
  }
}
