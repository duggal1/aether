import Foundation

public enum JSLexer {
  private static let keywords: Set<String> = [
    "let", "const", "var", "function", "return", "if", "else", "true", "false", "null",
    "undefined", "while", "do", "for", "break", "continue", "switch", "case", "default",
    "throw", "try", "catch", "finally", "new", "typeof", "void", "delete", "in", "of",
    "instanceof", "this", "super", "class", "extends", "static", "import", "export", "from",
    "async", "await", "yield", "debugger", "with", "get", "set", "target", "as",
  ]
  private static let threeCharacterSymbols: Set<String> = [
    "===", "!==", ">>>", "<<=", ">>=", "**=", "...", "&&=", "||=", "??=", ">>>=",
  ]
  private static let twoCharacterSymbols: Set<String> = [
    "==", "!=", "<=", ">=", "&&", "||", "=>", "+=", "-=", "*=", "/=", "%=", "**", "++",
    "--", "<<", ">>", "??", "&=", "|=", "^=",
  ]
  private static let regexAllowedSymbols: Set<String> = [
    "(", ",", "=", ":", "[", "!", "?", "{", "}", ";", "+", "-", "*", "%", "&", "|", "^",
    "~", "<", ">", "&&", "||", "??", "**", "=>", "...",
  ]
  private static let regexAllowedKeywords: Set<String> = [
    "return", "typeof", "new", "delete", "void", "in", "of", "instanceof", "throw", "case",
    "do", "else", "yield", "await",
  ]

  public static func tokenize(_ source: String) throws -> [JSToken] {
    let chars = Array(source)
    var tokens: [JSToken] = []
    var i = 0
    var lineBreakBefore = false
    var previous: JSTokenKind?
    var templateDepths: [Int] = []
    var braceDepth = 0

    func emit(_ kind: JSTokenKind, offset: Int) {
      tokens.append(JSToken(kind: kind, offset: offset, lineTerminatorBefore: lineBreakBefore))
      lineBreakBefore = false
      previous = kind
    }

    func skipWhitespaceAndComments() throws {
      while i < chars.count {
        let c = chars[i]
        if c == "\n" || c == "\r" || c == "\u{2028}" || c == "\u{2029}" {
          lineBreakBefore = true
          if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
          i += 1
        } else if c.isWhitespace {
          i += 1
        } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
          i += 2
          while i < chars.count, chars[i] != "\n" { i += 1 }
        } else if c == "<", i + 3 < chars.count, chars[i + 1] == "!", chars[i + 2] == "-",
          chars[i + 3] == "-"
        {
          i += 4
          while i < chars.count, chars[i] != "\n" { i += 1 }
        } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
          i += 2
          var closed = false
          while i + 1 < chars.count {
            if chars[i] == "*" && chars[i + 1] == "/" {
              i += 2
              closed = true
              break
            }
            if chars[i] == "\n" || chars[i] == "\r" { lineBreakBefore = true }
            i += 1
          }
          if !closed { throw JSError.syntax("Unterminated block comment") }
        } else {
          break
        }
      }
    }

    func scanTemplateChunk() throws {
      let start = i
      var value = ""
      while i < chars.count {
        let c = chars[i]
        if c == "`" {
          emit(.templateChunk(value), offset: start)
          emit(.symbol("`"), offset: i)
          i += 1
          return
        }
        if c == "$", i + 1 < chars.count, chars[i + 1] == "{" {
          emit(.templateChunk(value), offset: start)
          emit(.symbol("${"), offset: i)
          templateDepths.append(braceDepth)
          i += 2
          return
        }
        if c == "\\", i + 1 < chars.count {
          i += 1
          let e = chars[i]
          switch e {
          case "n": value.append("\n")
          case "r": value.append("\r")
          case "t": value.append("\t")
          case "b": value.append("\u{8}")
          case "f": value.append("\u{C}")
          case "v": value.append("\u{B}")
          case "0": value.append("\0")
          case "`": value.append("`")
          case "$": value.append("$")
          case "\\": value.append("\\")
          case "u": value.append(try scanUnicodeEscape(chars: chars, index: &i))
          default: value.append(e)
          }
          i += 1
          continue
        }
        if c == "\n" || c == "\r" { lineBreakBefore = true }
        value.append(c)
        i += 1
      }
      throw JSError.syntax("Unterminated template literal at \(start)")
    }

    while true {
      try skipWhitespaceAndComments()
      guard i < chars.count else { break }
      let c = chars[i]
      let start = i

      if c == "`" {
        emit(.symbol("`"), offset: start)
        i += 1
        try scanTemplateChunk()
        continue
      }
      if c == "{" {
        braceDepth += 1
        emit(.symbol("{"), offset: start)
        i += 1
        continue
      }
      if c == "}" {
        if let expected = templateDepths.last, braceDepth == expected {
          templateDepths.removeLast()
          emit(.symbol("}"), offset: start)
          i += 1
          try scanTemplateChunk()
        } else {
          braceDepth = max(0, braceDepth - 1)
          emit(.symbol("}"), offset: start)
          i += 1
        }
        continue
      }
      if c == "\"" || c == "'" {
        let quote = c
        i += 1
        var value = ""
        var closed = false
        while i < chars.count {
          let ch = chars[i]
          if ch == quote {
            closed = true
            i += 1
            break
          }
          if ch == "\n" || ch == "\r" {
            throw JSError.syntax("Unterminated string at \(start)")
          }
          if ch == "\\", i + 1 < chars.count {
            i += 1
            switch chars[i] {
            case "n": value.append("\n")
            case "r": value.append("\r")
            case "t": value.append("\t")
            case "b": value.append("\u{8}")
            case "f": value.append("\u{C}")
            case "v": value.append("\u{B}")
            case "0": value.append("\0")
            case "u": value.append(try scanUnicodeEscape(chars: chars, index: &i))
            case "x":
              guard i + 2 < chars.count,
                let scalar = hexValue(chars[i + 1], chars[i + 2])
              else { throw JSError.syntax("Invalid hex escape at \(i)") }
              value.append(Character(UnicodeScalar(scalar)!))
              i += 2
            case "\n": break
            default: value.append(chars[i])
            }
          } else {
            value.append(ch)
          }
          i += 1
        }
        guard closed else { throw JSError.syntax("Unterminated string at \(start)") }
        emit(.string(value), offset: start)
        continue
      }
      if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
        let token = try scanNumber(chars: chars, index: &i)
        emit(token, offset: start)
        continue
      }
      if c == "#" , i + 1 < chars.count, isIdentifierStart(chars[i + 1]) {
        i += 1
        let name = "#" + scanIdentifier(chars: chars, index: &i)
        emit(.identifier(name), offset: start)
        continue
      }
      if isIdentifierStart(c) {
        let value = scanIdentifier(chars: chars, index: &i)
        emit(
          keywords.contains(value) ? .keyword(value) : .identifier(value), offset: start)
        continue
      }
      if c == "/" {
        if i + 1 < chars.count, chars[i + 1] == "/" || chars[i + 1] == "*" {
          try skipWhitespaceAndComments()
          continue
        }
        if allowsRegex(previous) {
          let (pattern, flags) = try scanRegex(chars: chars, index: &i)
          emit(.regex(pattern: pattern, flags: flags), offset: start)
        } else {
          if i + 1 < chars.count, chars[i + 1] == "=" {
            emit(.symbol("/="), offset: start)
            i += 2
          } else {
            emit(.symbol("/"), offset: start)
            i += 1
          }
        }
        continue
      }
      if i + 2 < chars.count {
        let symbol = String(chars[i...i + 2])
        if threeCharacterSymbols.contains(symbol) {
          emit(.symbol(symbol), offset: start)
          i += 3
          continue
        }
      }
      if i + 1 < chars.count {
        var symbol = String(chars[i...i + 1])
        if symbol == "?." {
          if i + 2 < chars.count, chars[i + 2].isNumber {
            emit(.symbol("?"), offset: start)
            i += 1
            continue
          }
        }
        if twoCharacterSymbols.contains(symbol) {
          if symbol == "?" { symbol = "??" }
          emit(.symbol(symbol), offset: start)
          i += 2
          continue
        }
      }
      if "()[];,.:+-*%<>=!&|^~?".contains(c) {
        emit(.symbol(String(c)), offset: start)
        i += 1
        continue
      }
      throw JSError.syntax("Unexpected character \(c) at \(start)")
    }
    tokens.append(
      JSToken(kind: .eof, offset: chars.count, lineTerminatorBefore: lineBreakBefore))
    return tokens
  }

  private static func allowsRegex(_ previous: JSTokenKind?) -> Bool {
    guard let previous else { return true }
    switch previous {
    case .number, .bigint, .string, .regex, .templateChunk:
      return false
    case .identifier:
      return false
    case .keyword(let word):
      return regexAllowedKeywords.contains(word)
    case .symbol(let symbol):
      if symbol == ")" || symbol == "]" || symbol == "}" || symbol == "`" { return false }
      if symbol == "${" || symbol == "++" || symbol == "--" { return true }
      return regexAllowedSymbols.contains(symbol)
    case .eof:
      return false
    }
  }

  private static func scanRegex(chars: [Character], index: inout Int) throws -> (String, String) {
    var pattern = ""
    var i = index + 1
    var inClass = false
    var closed = false
    while i < chars.count {
      let c = chars[i]
      if c == "\n" || c == "\r" { throw JSError.syntax("Unterminated regex at \(index)") }
      if c == "\\" {
        pattern.append(c)
        i += 1
        guard i < chars.count else { break }
        pattern.append(chars[i])
        i += 1
        continue
      }
      if c == "[" { inClass = true }
      if c == "]" { inClass = false }
      if c == "/", !inClass {
        closed = true
        i += 1
        break
      }
      pattern.append(c)
      i += 1
    }
    guard closed else { throw JSError.syntax("Unterminated regex at \(index)") }
    var flags = ""
    while i < chars.count, chars[i].isLetter {
      flags.append(chars[i])
      i += 1
    }
    index = i
    return (pattern, flags)
  }

  private static func scanNumber(chars: [Character], index: inout Int) throws -> JSTokenKind {
    var i = index
    if chars[i] == "0", i + 1 < chars.count {
      let marker = chars[i + 1]
      if marker == "x" || marker == "X" || marker == "b" || marker == "B" || marker == "o"
        || marker == "O"
      {
        let radix: Int
        switch marker {
        case "x", "X": radix = 16
        case "b", "B": radix = 2
        default: radix = 8
        }
        i += 2
        let start = i
        while i < chars.count, chars[i] != "_" && isDigit(chars[i], radix: radix) { i += 1 }
        let digits = String(chars[start..<i]).replacingOccurrences(of: "_", with: "")
        guard !digits.isEmpty, let raw = UInt64(digits, radix: radix) else {
          throw JSError.syntax("Invalid number at \(index)")
        }
        if i < chars.count, chars[i] == "n" {
          index = i + 1
          return .bigint(String(raw))
        }
        index = i
        return .number(Double(raw))
      }
    }
    var text = ""
    var hasDigits = false
    while i < chars.count, chars[i].isNumber || chars[i] == "_" {
      if chars[i].isNumber { hasDigits = true }
      if chars[i] != "_" { text.append(chars[i]) }
      i += 1
    }
    if i < chars.count, chars[i] == "." {
      text.append(".")
      i += 1
      while i < chars.count, chars[i].isNumber || chars[i] == "_" {
        if chars[i].isNumber { hasDigits = true }
        if chars[i] != "_" { text.append(chars[i]) }
        i += 1
      }
    }
    if i < chars.count, chars[i] == "e" || chars[i] == "E" {
      var j = i + 1
      if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
      if j < chars.count, chars[j].isNumber {
        text.append(contentsOf: chars[i...j])
        i = j + 1
        while i < chars.count, chars[i].isNumber {
          text.append(chars[i])
          i += 1
        }
        hasDigits = true
      }
    }
    guard hasDigits, let value = Double(text) else {
      throw JSError.syntax("Invalid number at \(index)")
    }
    if i < chars.count, chars[i] == "n" {
      index = i + 1
      if text.contains(".") || text.contains("e") || text.contains("E") {
        throw JSError.syntax("Invalid BigInt literal at \(index)")
      }
      return .bigint(text)
    }
    index = i
    return .number(value)
  }

  private static func scanUnicodeEscape(chars: [Character], index: inout Int) throws -> String {
    guard index < chars.count, chars[index] == "u" else { return "u" }
    if index + 1 < chars.count, chars[index + 1] == "{" {
      var j = index + 2
      var hex = ""
      while j < chars.count, chars[j] != "}" {
        hex.append(chars[j])
        j += 1
      }
      guard j < chars.count, let code = UInt32(hex, radix: 16),
        let scalar = UnicodeScalar(code)
      else { throw JSError.syntax("Invalid unicode escape at \(index)") }
      index = j
      return String(scalar)
    }
    guard index + 4 < chars.count else {
      throw JSError.syntax("Invalid unicode escape at \(index)")
    }
    let hex = String(chars[(index + 1)...(index + 4)])
    guard let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) else {
      throw JSError.syntax("Invalid unicode escape at \(index)")
    }
    index += 4
    return String(scalar)
  }

  private static func hexValue(_ a: Character, _ b: Character) -> UInt32? {
    let digits = "0123456789abcdefABCDEF"
    guard digits.contains(a), digits.contains(b) else { return nil }
    return UInt32(String([a, b]), radix: 16)
  }

  private static func isDigit(_ c: Character, radix: Int) -> Bool {
    switch radix {
    case 2: return c == "0" || c == "1"
    case 8: return c >= "0" && c <= "7"
    case 16: return c.isHexDigit
    default: return c.isNumber
    }
  }

  private static func isIdentifierStart(_ c: Character) -> Bool {
    c.isLetter || c == "_" || c == "$"
  }

  private static func scanIdentifier(chars: [Character], index: inout Int) -> String {
    let start = index
    index += 1
    while index < chars.count {
      let c = chars[index]
      if c.isLetter || c.isNumber || c == "_" || c == "$" { index += 1 } else { break }
    }
    return String(chars[start..<index])
  }
}
