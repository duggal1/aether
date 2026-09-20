import CSS
import DOM
import Foundation

public enum SelectorMatcher {
  public static func matches(_ selector: CSSSelector, node: NodeID, document: DOMDocument) -> Bool {
    guard !selector.parts.isEmpty else { return false }
    return matchPart(selector.parts.count - 1, node: node, selector: selector, document: document)
  }

  private struct InnerSelectorPart {
    var combinator: CSSCombinator
    var selector: CSSSelector
  }

  private final class InnerSelectorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var anyList: [String: [CSSSelector]] = [:]
    private var hasList: [String: [InnerSelectorPart]] = [:]
    private let limit = 4096

    func any(_ key: String, build: () -> [CSSSelector]) -> [CSSSelector] {
      lock.lock()
      defer { lock.unlock() }
      if let cached = anyList[key] { return cached }
      let value = build()
      if anyList.count >= limit { anyList.removeAll(keepingCapacity: true) }
      anyList[key] = value
      return value
    }

    func has(_ key: String, build: () -> [InnerSelectorPart]) -> [InnerSelectorPart] {
      lock.lock()
      defer { lock.unlock() }
      if let cached = hasList[key] { return cached }
      let value = build()
      if hasList.count >= limit { hasList.removeAll(keepingCapacity: true) }
      hasList[key] = value
      return value
    }
  }

  private static let innerCache = InnerSelectorCache()

  private static func attributeValue(_ name: String, of node: DOMNode) -> String? {
    for attribute in node.attributes where attribute.name.string == name { return attribute.value }
    return nil
  }

  private static func isWhitespaceByte(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
  }

  private static func containsToken(_ text: String, _ token: String) -> Bool {
    let bytes = text.utf8
    let needle = token.utf8
    var index = bytes.startIndex
    while index < bytes.endIndex {
      while index < bytes.endIndex, isWhitespaceByte(bytes[index]) {
        bytes.formIndex(after: &index)
      }
      var end = index
      while end < bytes.endIndex, !isWhitespaceByte(bytes[end]) {
        bytes.formIndex(after: &end)
      }
      if index < end, bytes[index..<end].elementsEqual(needle) { return true }
      index = end
    }
    return false
  }

  private static func matchPart(
    _ index: Int, node: NodeID, selector: CSSSelector, document: DOMDocument
  ) -> Bool {
    guard index >= 0, matchesSimple(selector.parts[index].simple, node: node, document: document)
    else { return false }
    if index == 0 { return true }

    switch selector.parts[index].combinatorToPrevious ?? .descendant {
    case .child:
      guard let parent = document.parent(of: node) else { return false }
      return matchPart(index - 1, node: parent, selector: selector, document: document)
    case .descendant:
      var ancestor = document.parent(of: node)
      while let current = ancestor {
        if matchPart(index - 1, node: current, selector: selector, document: document) {
          return true
        }
        ancestor = document.parent(of: current)
      }
      return false
    case .adjacentSibling:
      guard let previous = previousSibling(of: node, in: document) else { return false }
      return matchPart(index - 1, node: previous, selector: selector, document: document)
    case .generalSibling:
      var sibling = previousSibling(of: node, in: document)
      while let current = sibling {
        if matchPart(index - 1, node: current, selector: selector, document: document) {
          return true
        }
        sibling = previousSibling(of: current, in: document)
      }
      return false
    }
  }

  private static func previousSibling(of id: NodeID, in document: DOMDocument) -> NodeID? {
    guard let parent = document.parent(of: id) else { return nil }
    let siblings = document.children(of: parent).filter {
      guard let node = document.node($0) else { return false }
      if case .element = node.kind { return true }
      return false
    }
    guard let position = siblings.firstIndex(of: id), position > 0 else { return nil }
    return siblings[siblings.index(before: position)]
  }

  private static func matchesSimple(
    _ selector: CSSSimpleSelector, node id: NodeID, document: DOMDocument
  ) -> Bool {
    guard let node = document.node(id), case .element = node.kind else { return false }
    if selector.pseudoElement != nil { return false }
    if let tag = selector.tag, node.tagName != tag { return false }
    if selector.universal, selector.tag != nil { return false }
    if let idValue = selector.id, attributeValue("id", of: node) != idValue { return false }
    if !selector.classes.isEmpty {
      let classAttribute = attributeValue("class", of: node) ?? ""
      for required in selector.classes where !containsToken(classAttribute, required) { return false }
    }
    for attribute in selector.attributes {
      guard matchesAttribute(attribute, node: node) else { return false }
    }
    for pseudo in selector.pseudos {
      guard matchesPseudo(pseudo, node: id, document: document) else { return false }
    }
    return true
  }

  private static func matchesAttribute(_ selector: CSSAttributeSelector, node: DOMNode) -> Bool {
    guard let actual = node.attribute(selector.name) else { return false }
    switch selector.op {
    case .exists:
      return true
    case .equals:
      return actual == (selector.value ?? "")
    case .includes:
      guard let expected = selector.value else { return false }
      return containsToken(actual, expected)
    case .dashMatch:
      guard let expected = selector.value else { return false }
      return actual == expected || actual.hasPrefix(expected + "-")
    case .prefix:
      guard let expected = selector.value else { return false }
      return actual.hasPrefix(expected)
    case .suffix:
      guard let expected = selector.value else { return false }
      return actual.hasSuffix(expected)
    case .substring:
      guard let expected = selector.value, !expected.isEmpty else { return false }
      return actual.contains(expected)
    }
  }

  private static func matchesPseudo(
    _ pseudo: CSSPseudoClass, node id: NodeID, document: DOMDocument
  ) -> Bool {
    switch pseudo.name {
    case "first-child":
      return elementIndex(of: id, in: document)?.isFirst ?? false
    case "last-child":
      return elementIndex(of: id, in: document)?.isLast ?? false
    case "only-child":
      guard let position = elementIndex(of: id, in: document) else { return false }
      return position.isFirst && position.isLast
    case "first-of-type":
      return typeIndex(of: id, in: document)?.isFirst ?? false
    case "last-of-type":
      return typeIndex(of: id, in: document)?.isLast ?? false
    case "only-of-type":
      guard let position = typeIndex(of: id, in: document) else { return false }
      return position.isFirst && position.isLast
    case "empty":
      guard let node = document.node(id) else { return false }
      return node.children.isEmpty
    case "root":
      guard let node = document.node(id) else { return false }
      return node.tagName == "html" && document.parent(of: id) == nil
        || document.parent(of: id) == document.root && node.tagName == "html"
    case "nth-child":
      guard let position = elementIndex(of: id, in: document),
        let (a, b) = parseNth(pseudo.argument ?? "")
      else { return false }
      return matchesNth(position.index, a: a, b: b)
    case "nth-of-type":
      guard let position = typeIndex(of: id, in: document),
        let (a, b) = parseNth(pseudo.argument ?? "")
      else { return false }
      return matchesNth(position.index, a: a, b: b)
    case "nth-last-child":
      guard let position = elementIndex(of: id, in: document),
        let (a, b) = parseNth(pseudo.argument ?? "")
      else { return false }
      return matchesNth(position.fromEnd, a: a, b: b)
    case "not":
      guard let argument = pseudo.argument else { return false }
      return !matchesAnyInner(argument, node: id, document: document)
    case "is", "where":
      guard let argument = pseudo.argument else { return false }
      return matchesAnyInner(argument, node: id, document: document)
    case "has":
      guard let argument = pseudo.argument else { return false }
      return matchesHas(argument, node: id, document: document)
    case "checked":
      guard let node = document.node(id) else { return false }
      return node.attribute("checked") != nil || node.attribute("selected") != nil
    case "disabled":
      guard let node = document.node(id) else { return false }
      return node.attribute("disabled") != nil
    case "enabled":
      guard let node = document.node(id) else { return false }
      return node.attribute("disabled") == nil
    case "hover", "active", "focus", "focus-within", "focus-visible", "visited", "link", "target":
      return false
    default:
      return false
    }
  }

  private static func elementIndex(of id: NodeID, in document: DOMDocument) -> (
    index: Int, fromEnd: Int, isFirst: Bool, isLast: Bool
  )? {
    guard let parent = document.parent(of: id) else { return nil }
    let siblings = document.children(of: parent).filter {
      guard let node = document.node($0) else { return false }
      if case .element = node.kind { return true }
      return false
    }
    guard let position = siblings.firstIndex(of: id) else { return nil }
    return (
      index: position + 1, fromEnd: siblings.count - position, isFirst: position == 0,
      isLast: position == siblings.count - 1
    )
  }

  private static func typeIndex(of id: NodeID, in document: DOMDocument) -> (
    index: Int, isFirst: Bool, isLast: Bool
  )? {
    guard let node = document.node(id), let tag = node.tagName,
      let parent = document.parent(of: id)
    else { return nil }
    let siblings = document.children(of: parent).filter {
      document.node($0)?.tagName == tag
    }
    guard let position = siblings.firstIndex(of: id) else { return nil }
    return (
      index: position + 1, isFirst: position == 0, isLast: position == siblings.count - 1
    )
  }

  private static func matchesAnyInner(
    _ argument: String, node id: NodeID, document: DOMDocument
  ) -> Bool {
    for selector in innerCache.any(argument, build: { parsedInnerSelectors(argument) }) {
      if matches(selector, node: id, document: document) { return true }
    }
    return false
  }

  private static func parsedInnerSelectors(_ argument: String) -> [CSSSelector] {
    splitInnerSelectors(argument).compactMap { CSSParser.parseSelector($0) }
  }

  private static func matchesHas(
    _ argument: String, node id: NodeID, document: DOMDocument
  ) -> Bool {
    for part in innerCache.has(argument, build: { parsedHasSelectors(argument) }) {
      switch part.combinator {
      case .child:
        for child in document.children(of: id) where document.node(child)?.tagName != nil {
          if matches(part.selector, node: child, document: document) { return true }
        }
      case .adjacentSibling, .generalSibling:
        guard let parent = document.parent(of: id) else { continue }
        let siblings = document.children(of: parent).filter { document.node($0)?.tagName != nil }
        guard let position = siblings.firstIndex(of: id) else { continue }
        let following = siblings[siblings.index(after: position)...]
        if part.combinator == .adjacentSibling {
          if let next = following.first, matches(part.selector, node: next, document: document) {
            return true
          }
        } else {
          for sibling in following where matches(part.selector, node: sibling, document: document) {
            return true
          }
        }
      case .descendant:
        var stack = document.children(of: id)
        while let current = stack.popLast() {
          if document.node(current)?.tagName != nil,
            matches(part.selector, node: current, document: document)
          {
            return true
          }
          stack.append(contentsOf: document.children(of: current))
        }
      }
    }
    return false
  }

  private static func parsedHasSelectors(_ argument: String) -> [InnerSelectorPart] {
    var parts: [InnerSelectorPart] = []
    for part in splitInnerSelectors(argument) {
      let combinator: CSSCombinator
      let source: String
      if part.hasPrefix(">") {
        combinator = .child
        source = String(part.dropFirst())
      } else if part.hasPrefix("+") {
        combinator = .adjacentSibling
        source = String(part.dropFirst())
      } else if part.hasPrefix("~") {
        combinator = .generalSibling
        source = String(part.dropFirst())
      } else {
        combinator = .descendant
        source = part
      }
      let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let selector = CSSParser.parseSelector(trimmed) else { continue }
      parts.append(InnerSelectorPart(combinator: combinator, selector: selector))
    }
    return parts
  }

  private static func splitInnerSelectors(_ argument: String) -> [String] {
    var result: [String] = []
    var current = ""
    var depth = 0
    for character in argument {
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
    return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
      !$0.isEmpty
    }
  }

  static func parseNth(_ argument: String) -> (Int, Int)? {
    let value = argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "odd" { return (2, 1) }
    if value == "even" { return (2, 0) }
    if let index = Int(value) { return (0, index) }
    let stripped = value.replacingOccurrences(of: " ", with: "")
    guard let nRange = stripped.range(of: "n") else { return nil }
    let aText = String(stripped[..<nRange.lowerBound])
    let bText = String(stripped[nRange.upperBound...])
    let a: Int
    if aText.isEmpty { a = 1 } else if aText == "-" { a = -1 } else if aText == "+" { a = 1 } else {
      guard let parsed = Int(aText) else { return nil }
      a = parsed
    }
    let b: Int
    if bText.isEmpty { b = 0 } else {
      guard let parsed = Int(bText) else { return nil }
      b = parsed
    }
    return (a, b)
  }

  private static func matchesNth(_ index: Int, a: Int, b: Int) -> Bool {
    if a == 0 { return index == b }
    let delta = index - b
    if a > 0 { return delta >= 0 && delta % a == 0 }
    return delta <= 0 && delta % a == 0
  }
}
