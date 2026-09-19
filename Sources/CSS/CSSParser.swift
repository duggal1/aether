import Foundation

public enum CSSParser {
  public static func parse(_ source: String, startingSourceOrder: Int = 0) -> Stylesheet {
    var state = TopLevelState(sourceOrder: startingSourceOrder)
    parseTopLevel(source, layer: nil, media: nil, state: &state)
    return Stylesheet(rules: state.rules, layerOrder: state.layers.order)
  }

  struct TopLevelState {
    var rules: [CSSRule] = []
    var layers = LayerOrder()
    var sourceOrder: Int
  }

  static func parseTopLevel(
    _ source: String, layer: String?, media: String?, state: inout TopLevelState
  ) {
    var index = source.startIndex
    while index < source.endIndex {
      skipWhitespaceAndComments(source, index: &index)
      guard index < source.endIndex else { break }
      if source[index] == "@" {
        guard let nameEnd = source[index...].firstIndex(where: { $0.isWhitespace || $0 == "{" || $0 == ";" || $0 == "(" }) else {
          break
        }
        let atName = String(source[source.index(after: index)..<nameEnd]).lowercased()
        if atName == "media" {
          var scan = nameEnd
          skipWhitespaceAndComments(source, index: &scan)
          guard let open = source[scan...].firstIndex(of: "{"),
            let close = matchingBrace(in: source, from: open)
          else { break }
          let prelude = String(source[scan..<open]).trimmingCharacters(
            in: .whitespacesAndNewlines)
          let combined: String? =
            media == nil ? prelude : [media!, prelude].joined(separator: " and ")
          parseTopLevel(
            String(source[source.index(after: open)..<close]), layer: layer, media: combined,
            state: &state)
          index = source.index(after: close)
          continue
        }
        if atName == "layer" {
          var scan = nameEnd
          skipWhitespaceAndComments(source, index: &scan)
          if scan < source.endIndex, source[scan] == "{" {
            guard let close = matchingBrace(in: source, from: scan) else { break }
            parseTopLevel(
              String(source[source.index(after: scan)..<close]), layer: layer, media: media,
              state: &state)
            index = source.index(after: close)
            continue
          }
          let stmtEnd =
            source[scan...].firstIndex(of: ";") ?? source[scan...].firstIndex(of: "{")
          let headerEnd = stmtEnd ?? source.endIndex
          let header = String(source[scan..<headerEnd]).trimmingCharacters(
            in: .whitespacesAndNewlines)
          let names = header.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
          }.filter { !$0.isEmpty }
          if headerEnd < source.endIndex, source[headerEnd] == "{" {
            let target = names.first
            if let target { state.layers.declare(target) }
            guard let close = matchingBrace(in: source, from: headerEnd) else { break }
            parseTopLevel(
              String(source[source.index(after: headerEnd)..<close]),
              layer: target ?? layer, media: media, state: &state)
            index = source.index(after: close)
          } else {
            for name in names { state.layers.declare(name) }
            index = headerEnd < source.endIndex ? source.index(after: headerEnd) : source.endIndex
          }
          continue
        }
        if atName == "supports" {
          guard let open = source[index...].firstIndex(of: "{"),
            let close = matchingBrace(in: source, from: open)
          else { break }
          parseTopLevel(
            String(source[source.index(after: open)..<close]), layer: layer, media: media,
            state: &state)
          index = source.index(after: close)
          continue
        }
        if let open = source[index...].firstIndex(of: "{") {
          let semi = source[index...].firstIndex(of: ";")
          if let semi, semi < open {
            index = source.index(after: semi)
          } else if let close = matchingBrace(in: source, from: open) {
            index = source.index(after: close)
          } else {
            break
          }
        } else if let semi = source[index...].firstIndex(of: ";") {
          index = source.index(after: semi)
        } else {
          break
        }
        continue
      }
      guard let open = source[index...].firstIndex(of: "{") else { break }
      let selectorSource = String(source[index..<open]).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard let close = matchingBrace(in: source, from: open) else { break }
      let declarationSource = String(source[source.index(after: open)..<close])
      let selectors = selectorSource.split(separator: ",").compactMap { parseSelector(String($0)) }
      let declarations = parseDeclarations(declarationSource)
      if !selectors.isEmpty, !declarations.isEmpty {
        state.rules.append(
          CSSRule(
            selectors: selectors, declarations: declarations, sourceOrder: state.sourceOrder,
            layer: layer, media: media))
        state.sourceOrder += 1
      }
      index = source.index(after: close)
    }
  }

  public static func parseDeclarations(_ source: String) -> [CSSDeclaration] {
    splitDeclarations(source).compactMap { item in
      guard let colon = item.firstIndex(of: ":") else { return nil }
      let property = item[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      var value = item[item.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !property.isEmpty, !value.isEmpty else { return nil }
      var important = false
      if value.lowercased().hasSuffix("!important") {
        important = true
        value = String(value.dropLast("!important".count)).trimmingCharacters(
          in: .whitespacesAndNewlines)
      }
      return CSSDeclaration(property: property, value: value, important: important)
    }
  }

  public static func parseSelector(_ source: String) -> CSSSelector? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var parts: [CSSSelectorPart] = []
    var current = ""
    var pendingCombinator: CSSCombinator? = nil
    var bracketDepth = 0
    var parenDepth = 0
    var index = trimmed.startIndex

    func flush() {
      let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty, let simple = parseSimpleSelector(token) else {
        current = ""
        return
      }
      parts.append(
        CSSSelectorPart(
          simple: simple,
          combinatorToPrevious: parts.isEmpty ? nil : (pendingCombinator ?? .descendant)))
      current = ""
      pendingCombinator = nil
    }

    while index < trimmed.endIndex {
      let c = trimmed[index]
      if c == "[" {
        bracketDepth += 1
        current.append(c)
        index = trimmed.index(after: index)
        continue
      }
      if c == "]" {
        bracketDepth = max(0, bracketDepth - 1)
        current.append(c)
        index = trimmed.index(after: index)
        continue
      }
      if c == "(" {
        parenDepth += 1
        current.append(c)
        index = trimmed.index(after: index)
        continue
      }
      if c == ")" {
        parenDepth = max(0, parenDepth - 1)
        current.append(c)
        index = trimmed.index(after: index)
        continue
      }
      if bracketDepth == 0, parenDepth == 0, c == ">" || c == "+" || c == "~" {
        flush()
        pendingCombinator =
          c == ">" ? .child : c == "+" ? .adjacentSibling : .generalSibling
        index = trimmed.index(after: index)
        while index < trimmed.endIndex, trimmed[index].isWhitespace {
          index = trimmed.index(after: index)
        }
        continue
      }
      if bracketDepth == 0, parenDepth == 0, c.isWhitespace {
        flush()
        if pendingCombinator == nil { pendingCombinator = .descendant }
        while index < trimmed.endIndex, trimmed[index].isWhitespace {
          index = trimmed.index(after: index)
        }
        continue
      }
      current.append(c)
      index = trimmed.index(after: index)
    }
    flush()
    return parts.isEmpty ? nil : CSSSelector(parts: parts)
  }

  private static func parseSimpleSelector(_ source: String) -> CSSSimpleSelector? {
    var selector = CSSSimpleSelector()
    var index = source.startIndex
    if index < source.endIndex, source[index] == "*" {
      selector.universal = true
      index = source.index(after: index)
    } else if index < source.endIndex, source[index].isLetter {
      let start = index
      while index < source.endIndex, isName(source[index]) { index = source.index(after: index) }
      selector.tag = String(source[start..<index]).lowercased()
    }

    while index < source.endIndex {
      switch source[index] {
      case "#":
        index = source.index(after: index)
        let start = index
        while index < source.endIndex, isName(source[index]) { index = source.index(after: index) }
        selector.id = String(source[start..<index])
      case ".":
        index = source.index(after: index)
        let start = index
        while index < source.endIndex, isName(source[index]) { index = source.index(after: index) }
        selector.classes.append(String(source[start..<index]))
      case "[":
        guard let close = source[index...].firstIndex(of: "]") else { return nil }
        let innerStart = source.index(after: index)
        let inner = String(source[innerStart..<close])
        if let attribute = parseAttributeSelector(inner) {
          selector.attributes.append(attribute)
        } else {
          return nil
        }
        index = source.index(after: close)
      case ":":
        if source[index...].hasPrefix("::") {
          index = source.index(index, offsetBy: 2)
          let start = index
          while index < source.endIndex, isName(source[index]) { index = source.index(after: index) }
          let elementName = String(source[start..<index]).lowercased()
          if !elementName.isEmpty { selector.pseudoElement = elementName }
          if index < source.endIndex, source[index] == "(" {
            index = skipParenthesized(source, from: index)
          }
        } else {
          index = source.index(after: index)
          let start = index
          while index < source.endIndex, isName(source[index]) { index = source.index(after: index) }
          let pseudoName = String(source[start..<index]).lowercased()
          var argument: String?
          if index < source.endIndex, source[index] == "(" {
            let argStart = source.index(after: index)
            let after = skipParenthesized(source, from: index)
            argument = String(source[argStart..<source.index(before: after)])
              .trimmingCharacters(in: .whitespacesAndNewlines)
            index = after
          }
          if !pseudoName.isEmpty {
            selector.pseudos.append(CSSPseudoClass(name: pseudoName, argument: argument))
          }
        }
      default:
        index = source.index(after: index)
      }
    }
    return selector
  }

  private static func splitDeclarations(_ source: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    var parentheses = 0
    for c in source {
      if let q = quote {
        current.append(c)
        if c == q { quote = nil }
        continue
      }
      if c == "\"" || c == "'" {
        quote = c
        current.append(c)
        continue
      }
      if c == "(" {
        parentheses += 1
        current.append(c)
        continue
      }
      if c == ")" {
        parentheses = max(0, parentheses - 1)
        current.append(c)
        continue
      }
      if c == ";", parentheses == 0 {
        result.append(current)
        current = ""
      } else {
        current.append(c)
      }
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(current) }
    return result
  }

  private static func matchingBrace(in source: String, from open: String.Index) -> String.Index? {
    var depth = 0
    var quote: Character?
    var index = open
    while index < source.endIndex {
      let c = source[index]
      if let q = quote {
        if c == q { quote = nil }
      } else if c == "\"" || c == "'" {
        quote = c
      } else if c == "{" {
        depth += 1
      } else if c == "}" {
        depth -= 1
        if depth == 0 { return index }
      }
      index = source.index(after: index)
    }
    return nil
  }

  private static func skipWhitespaceAndComments(_ source: String, index: inout String.Index) {
    while index < source.endIndex {
      if source[index].isWhitespace {
        index = source.index(after: index)
        continue
      }
      if source[index] == "/" {
        let next = source.index(after: index)
        if next < source.endIndex, source[next] == "*",
          let end = source.range(of: "*/", range: source.index(after: next)..<source.endIndex)
        {
          index = end.upperBound
          continue
        }
      }
      break
    }
  }

  private static func parseAttributeSelector(_ inner: String) -> CSSAttributeSelector? {
    let operators: [(String, CSSAttributeOperator)] = [
      ("~=", .includes), ("|=", .dashMatch), ("^=", .prefix), ("$=", .suffix), ("*=", .substring),
    ]
    for (symbol, op) in operators {
      if let range = inner.range(of: symbol) {
        let name = String(inner[..<range.lowerBound]).trimmingCharacters(
          in: .whitespacesAndNewlines
        ).lowercased()
        var value = String(inner[range.upperBound...]).trimmingCharacters(
          in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !name.isEmpty else { return nil }
        return CSSAttributeSelector(name: name, value: value, op: op)
      }
    }
    if let equals = inner.firstIndex(of: "=") {
      let name = String(inner[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      var value = String(inner[inner.index(after: equals)...]).trimmingCharacters(
        in: .whitespacesAndNewlines)
      value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      guard !name.isEmpty else { return nil }
      return CSSAttributeSelector(name: name, value: value, op: .equals)
    }
    let name = inner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !name.isEmpty else { return nil }
    return CSSAttributeSelector(name: name)
  }

  private static func skipParenthesized(_ source: String, from open: String.Index) -> String.Index {
    var index = open
    var depth = 0
    while index < source.endIndex {
      if source[index] == "(" { depth += 1 }
      if source[index] == ")" {
        depth -= 1
        if depth == 0 { return source.index(after: index) }
      }
      index = source.index(after: index)
    }
    return source.endIndex
  }

  private static func isName(_ c: Character) -> Bool {
    c.isLetter || c.isNumber || c == "-" || c == "_"
  }
}
