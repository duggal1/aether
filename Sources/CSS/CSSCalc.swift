import EngineCore
import Foundation

public enum CSSCalc {
  public static func resolveValue(
    _ raw: String, customProps: [String: String], reference: Double, fontSize: Double,
    rootFontSize: Double, viewport: Size
  ) -> Double? {
    let substituted = substituteVars(raw, customProps: customProps, depth: 0)
    let value = substituted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.hasPrefix("calc(") && value.hasSuffix(")") {
      return evaluateExpression(
        String(value.dropFirst(5).dropLast()),
        reference: reference, fontSize: fontSize, rootFontSize: rootFontSize, viewport: viewport)
    }
    if value.hasPrefix("min(") && value.hasSuffix(")") {
      let args = splitTopLevel(String(value.dropFirst(4).dropLast()))
      let resolved = args.compactMap {
        resolveValue(
          $0, customProps: customProps, reference: reference, fontSize: fontSize,
          rootFontSize: rootFontSize, viewport: viewport)
      }
      guard resolved.count == args.count, !resolved.isEmpty else { return nil }
      return resolved.min()
    }
    if value.hasPrefix("max(") && value.hasSuffix(")") {
      let args = splitTopLevel(String(value.dropFirst(4).dropLast()))
      let resolved = args.compactMap {
        resolveValue(
          $0, customProps: customProps, reference: reference, fontSize: fontSize,
          rootFontSize: rootFontSize, viewport: viewport)
      }
      guard resolved.count == args.count, !resolved.isEmpty else { return nil }
      return resolved.min() == nil ? nil : resolved.max()
    }
    if value.hasPrefix("clamp(") && value.hasSuffix(")") {
      let args = splitTopLevel(String(value.dropFirst(6).dropLast()))
      guard args.count == 3 else { return nil }
      guard
        let low = resolveValue(
          args[0], customProps: customProps, reference: reference, fontSize: fontSize,
          rootFontSize: rootFontSize, viewport: viewport),
        let center = resolveValue(
          args[1], customProps: customProps, reference: reference, fontSize: fontSize,
          rootFontSize: rootFontSize, viewport: viewport),
        let high = resolveValue(
          args[2], customProps: customProps, reference: reference, fontSize: fontSize,
          rootFontSize: rootFontSize, viewport: viewport)
      else { return nil }
      return min(max(center, low), high)
    }
    if let length = CSSLength.parse(value) {
      return length.resolve(
        reference: reference, fontSize: fontSize, rootFontSize: rootFontSize, viewport: viewport)
    }
    return Double(value)
  }

  public static func substituteVars(
    _ raw: String, customProps: [String: String], depth: Int
  ) -> String {
    guard depth < 16, raw.contains("var(") else { return raw }
    var output = ""
    var index = raw.startIndex
    while index < raw.endIndex {
      guard let varRange = raw.range(of: "var(", range: index..<raw.endIndex) else {
        output += raw[index...]
        break
      }
      output += raw[index..<varRange.lowerBound]
      let innerStart = varRange.upperBound
      guard let innerEnd = matchParen(in: raw, from: innerStart) else {
        output += raw[varRange.lowerBound...]
        break
      }
      let inner = String(raw[innerStart..<innerEnd])
      let parts = splitTopLevel(inner, separator: ",")
      let name = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      var replacement: String?
      if name.hasPrefix("--") { replacement = customProps[name] }
      if replacement == nil, parts.count > 1 {
        replacement = parts.dropFirst().joined(separator: ",")
      }
      output += substituteVars(replacement ?? "", customProps: customProps, depth: depth + 1)
      index = raw.index(after: innerEnd)
    }
    return output
  }

  static func splitTopLevel(_ source: String, separator: Character = ",") -> [String] {
    var result: [String] = []
    var current = ""
    var depth = 0
    var quote: Character?
    for character in source {
      if let q = quote {
        current.append(character)
        if character == q { quote = nil }
        continue
      }
      if character == "\"" || character == "'" {
        quote = character
        current.append(character)
        continue
      }
      if character == "(" { depth += 1 }
      if character == ")" { depth -= 1 }
      if character == separator, depth == 0 {
        result.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    result.append(current)
    return result
  }

  static func matchParen(in source: String, from start: String.Index) -> String.Index? {
    var depth = 1
    var index = start
    while index < source.endIndex {
      if source[index] == "(" { depth += 1 }
      if source[index] == ")" {
        depth -= 1
        if depth == 0 { return index }
      }
      index = source.index(after: index)
    }
    return nil
  }

  static func evaluateExpression(
    _ source: String, reference: Double, fontSize: Double, rootFontSize: Double, viewport: Size
  ) -> Double? {
    var parser = MathParser(
      source: source, reference: reference, fontSize: fontSize, rootFontSize: rootFontSize,
      viewport: viewport)
    guard let value = parser.parseSum(), parser.isAtEnd else { return nil }
    return value
  }

  struct MathParser {
    var tokens: [MathToken]
    var position = 0
    var reference: Double
    var fontSize: Double
    var rootFontSize: Double
    var viewport: Size

    init(
      source: String, reference: Double, fontSize: Double, rootFontSize: Double, viewport: Size
    ) {
      self.tokens = MathParser.tokenize(source)
      self.reference = reference
      self.fontSize = fontSize
      self.rootFontSize = rootFontSize
      self.viewport = viewport
    }

    var isAtEnd: Bool { position >= tokens.count }

    mutating func parseSum() -> Double? {
      guard var value = parseProduct() else { return nil }
      while position < tokens.count {
        guard case .op(let c) = tokens[position], c == "+" || c == "-" else { break }
        position += 1
        guard let rhs = parseProduct() else { return nil }
        value = c == "+" ? value + rhs : value - rhs
      }
      return value
    }

    mutating func parseProduct() -> Double? {
      guard var value = parseFactor() else { return nil }
      while position < tokens.count {
        guard case .op(let c) = tokens[position], c == "*" || c == "/" else { break }
        position += 1
        guard let rhs = parseFactor() else { return nil }
        if c == "*" { value *= rhs } else { guard rhs != 0 else { return nil }; value /= rhs }
      }
      return value
    }

    mutating func parseFactor() -> Double? {
      guard position < tokens.count else { return nil }
      switch tokens[position] {
      case .length(let text):
        position += 1
        if let length = CSSLength.parse(text) {
          return length.resolve(
            reference: reference, fontSize: fontSize, rootFontSize: rootFontSize,
            viewport: viewport)
        }
        return Double(text)
      case .lparen:
        position += 1
        guard let value = parseSum(), position < tokens.count, tokens[position] == .rparen else {
          return nil
        }
        position += 1
        return value
      case .op(let c) where c == "+" || c == "-":
        position += 1
        guard let value = parseFactor() else { return nil }
        return c == "-" ? -value : value
      default:
        return nil
      }
    }

    static func tokenize(_ source: String) -> [MathToken] {
      var tokens: [MathToken] = []
      var index = source.startIndex
      while index < source.endIndex {
        let c = source[index]
        if c.isWhitespace {
          index = source.index(after: index)
          continue
        }
        if c == "(" {
          tokens.append(.lparen)
          index = source.index(after: index)
          continue
        }
        if c == ")" {
          tokens.append(.rparen)
          index = source.index(after: index)
          continue
        }
        if "+-*/".contains(c) {
          tokens.append(.op(c))
          index = source.index(after: index)
          continue
        }
        let start = index
        while index < source.endIndex,
          source[index].isNumber || source[index] == "."
            || source[index].isLetter || source[index] == "%"
        {
          index = source.index(after: index)
        }
        guard index > start else {
          index = source.index(after: index)
          continue
        }
        tokens.append(.length(String(source[start..<index])))
      }
      return tokens
    }
  }

  enum MathToken: Equatable {
    case length(String)
    case op(Character)
    case lparen
    case rparen
  }
}
