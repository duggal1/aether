import Foundation

public enum CSSTokenizer {
  public static func tokenize(_ source: String) -> [CSSToken] {
    var tokens: [CSSToken] = []
    var index = source.startIndex

    while index < source.endIndex {
      let c = source[index]
      if c.isWhitespace {
        while index < source.endIndex, source[index].isWhitespace {
          index = source.index(after: index)
        }
        if tokens.last != .whitespace { tokens.append(.whitespace) }
        continue
      }

      if c == "/", let next = nextIndex(after: index, in: source), source[next] == "*" {
        if let end = source.range(of: "*/", range: source.index(after: next)..<source.endIndex) {
          index = end.upperBound
        } else {
          index = source.endIndex
        }
        continue
      }

      switch c {
      case ":":
        tokens.append(.colon)
        index = source.index(after: index)
      case ";":
        tokens.append(.semicolon)
        index = source.index(after: index)
      case ",":
        tokens.append(.comma)
        index = source.index(after: index)
      case "{":
        tokens.append(.leftBrace)
        index = source.index(after: index)
      case "}":
        tokens.append(.rightBrace)
        index = source.index(after: index)
      case "(":
        tokens.append(.leftParen)
        index = source.index(after: index)
      case ")":
        tokens.append(.rightParen)
        index = source.index(after: index)
      case "[":
        tokens.append(.leftBracket)
        index = source.index(after: index)
      case "]":
        tokens.append(.rightBracket)
        index = source.index(after: index)
      case "\"", "'":
        let quote = c
        index = source.index(after: index)
        var value = ""
        while index < source.endIndex, source[index] != quote {
          if source[index] == "\\", let next = nextIndex(after: index, in: source) {
            value.append(source[next])
            index = source.index(after: next)
          } else {
            value.append(source[index])
            index = source.index(after: index)
          }
        }
        if index < source.endIndex { index = source.index(after: index) }
        tokens.append(.string(value))
      case "#":
        let start = source.index(after: index)
        var end = start
        while end < source.endIndex, isName(source[end]) { end = source.index(after: end) }
        tokens.append(.hash(String(source[start..<end])))
        index = end
      default:
        if c.isNumber || ((c == "+" || c == "-" || c == ".") && looksNumeric(at: index, in: source))
        {
          let parsed = parseNumber(at: index, in: source)
          index = parsed.end
          if index < source.endIndex, source[index] == "%" {
            tokens.append(.percentage(parsed.value))
            index = source.index(after: index)
          } else {
            let unitStart = index
            while index < source.endIndex, source[index].isLetter {
              index = source.index(after: index)
            }
            if unitStart < index {
              tokens.append(
                .dimension(parsed.value, String(source[unitStart..<index]).lowercased()))
            } else {
              tokens.append(.number(parsed.value))
            }
          }
        } else if isNameStart(c) {
          let start = index
          index = source.index(after: index)
          while index < source.endIndex, isName(source[index]) {
            index = source.index(after: index)
          }
          tokens.append(.ident(String(source[start..<index]).lowercased()))
        } else {
          tokens.append(.delimiter(c))
          index = source.index(after: index)
        }
      }
    }

    return tokens
  }

  private static func looksNumeric(at index: String.Index, in source: String) -> Bool {
    guard let next = nextIndex(after: index, in: source) else { return false }
    return source[next].isNumber || source[next] == "."
  }

  private static func parseNumber(at start: String.Index, in source: String) -> (
    value: Double, end: String.Index
  ) {
    var index = start
    if source[index] == "+" || source[index] == "-" { index = source.index(after: index) }
    var seenDot = false
    while index < source.endIndex {
      let c = source[index]
      if c == ".", !seenDot {
        seenDot = true
        index = source.index(after: index)
      } else if c.isNumber {
        index = source.index(after: index)
      } else {
        break
      }
    }
    return (Double(source[start..<index]) ?? 0, index)
  }

  private static func isNameStart(_ c: Character) -> Bool {
    c.isLetter || c == "_" || c == "-"
  }

  private static func isName(_ c: Character) -> Bool {
    isNameStart(c) || c.isNumber
  }

  private static func nextIndex(after index: String.Index, in source: String) -> String.Index? {
    let next = source.index(after: index)
    return next < source.endIndex ? next : nil
  }
}
