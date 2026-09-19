import Foundation

public final class HTMLTokenizer {
  private var buffer = ""
  private var cursor: String.Index
  private var rawTextTag: String?
  private static let rawTextTags: Set<String> = [
    "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "noscript",
  ]
  private static let escapableRawTags: Set<String> = ["textarea", "title"]

  public init() {
    cursor = buffer.startIndex
  }

  public func feed(_ chunk: String, isFinal: Bool = false) -> [HTMLToken] {
    let normalized = chunk.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\0", with: "\u{FFFD}")
    if cursor > buffer.startIndex {
      buffer = String(buffer[cursor...])
    }
    buffer.append(normalized)
    cursor = buffer.startIndex

    var tokens: [HTMLToken] = []
    while cursor < buffer.endIndex {
      if let rawTextTag {
        let closing = "</\(rawTextTag)"
        if let range = buffer.range(
          of: closing, options: [.caseInsensitive], range: cursor..<buffer.endIndex)
        {
          if cursor < range.lowerBound {
            let raw = String(buffer[cursor..<range.lowerBound])
            let text =
              Self.escapableRawTags.contains(rawTextTag) ? decodeEntities(raw) : raw
            if !text.isEmpty { tokens.append(.character(text)) }
          }
          cursor = range.lowerBound
          self.rawTextTag = nil
          continue
        }
        if isFinal {
          let raw = String(buffer[cursor...])
          let text =
            Self.escapableRawTags.contains(rawTextTag) ? decodeEntities(raw) : raw
          if !text.isEmpty { tokens.append(.character(text)) }
          cursor = buffer.endIndex
        }
        break
      }
      if buffer[cursor] != "<" {
        let start = cursor
        while cursor < buffer.endIndex, buffer[cursor] != "<" {
          cursor = buffer.index(after: cursor)
        }
        let text = decodeEntities(String(buffer[start..<cursor]))
        if !text.isEmpty { tokens.append(.character(text)) }
        continue
      }

      let tokenStart = cursor
      guard let next = peek(1) else {
        cursor = tokenStart
        break
      }

      if next == "!" {
        if hasPrefix("<![CDATA[") {
          let contentStart = buffer.index(cursor, offsetBy: 9)
          if let end = buffer.range(of: "]]>", range: contentStart..<buffer.endIndex) {
            tokens.append(.character(String(buffer[contentStart..<end.lowerBound])))
            cursor = end.upperBound
            continue
          } else if isFinal {
            tokens.append(.character(String(buffer[contentStart...])))
            cursor = buffer.endIndex
          } else {
            cursor = tokenStart
          }
          break
        }
        if hasPrefix("<!--") {
          guard
            let end = buffer.range(
              of: "-->", range: buffer.index(cursor, offsetBy: 4)..<buffer.endIndex)
          else {
            if isFinal {
              let start = buffer.index(cursor, offsetBy: 4)
              tokens.append(.comment(String(buffer[start...])))
              cursor = buffer.endIndex
            } else {
              cursor = tokenStart
            }
            break
          }
          let start = buffer.index(cursor, offsetBy: 4)
          tokens.append(.comment(String(buffer[start..<end.lowerBound])))
          cursor = end.upperBound
          continue
        }

        if hasPrefixCaseInsensitive("<!doctype") {
          guard let close = buffer[cursor...].firstIndex(of: ">") else {
            cursor = tokenStart
            break
          }
          let start = buffer.index(cursor, offsetBy: 9)
          let name = buffer[start..<close].trimmingCharacters(in: .whitespacesAndNewlines)
          tokens.append(.doctype(name))
          cursor = buffer.index(after: close)
          continue
        }

        guard let close = buffer[cursor...].firstIndex(of: ">") else {
          cursor = tokenStart
          break
        }
        let start = buffer.index(cursor, offsetBy: 2)
        tokens.append(.comment(String(buffer[start..<close])))
        cursor = buffer.index(after: close)
        continue
      }

      if next == "/" {
        guard let parsed = parseEndTag(from: cursor) else {
          cursor = tokenStart
          break
        }
        tokens.append(.endTag(parsed.name))
        cursor = parsed.end
        continue
      }

      if next.isLetter {
        guard let parsed = parseStartTag(from: cursor) else {
          cursor = tokenStart
          break
        }
        tokens.append(
          .startTag(
            name: parsed.name, attributes: parsed.attributes, selfClosing: parsed.selfClosing))
        cursor = parsed.end
        if !parsed.selfClosing, Self.rawTextTags.contains(parsed.name) {
          rawTextTag = parsed.name
        }
        if parsed.name == "plaintext" {
          let rest = String(buffer[cursor...])
          if !rest.isEmpty { tokens.append(.character(rest)) }
          cursor = buffer.endIndex
          break
        }
        continue
      }

      tokens.append(.character("<"))
      cursor = buffer.index(after: cursor)
    }

    if isFinal, cursor < buffer.endIndex {
      let tail = decodeEntities(String(buffer[cursor...]))
      if !tail.isEmpty { tokens.append(.character(tail)) }
      cursor = buffer.endIndex
    }

    return tokens
  }

  private func parseEndTag(from start: String.Index) -> (name: String, end: String.Index)? {
    var index = buffer.index(start, offsetBy: 2)
    skipWhitespace(&index)
    let nameStart = index
    while index < buffer.endIndex, isTagNameCharacter(buffer[index]) {
      index = buffer.index(after: index)
    }
    guard index > nameStart else { return nil }
    let name = String(buffer[nameStart..<index]).lowercased()
    while index < buffer.endIndex, buffer[index] != ">" {
      index = buffer.index(after: index)
    }
    guard index < buffer.endIndex else { return nil }
    return (name, buffer.index(after: index))
  }

  private func parseStartTag(from start: String.Index) -> (
    name: String, attributes: [HTMLAttributeToken], selfClosing: Bool, end: String.Index
  )? {
    var index = buffer.index(after: start)
    let nameStart = index
    while index < buffer.endIndex, isTagNameCharacter(buffer[index]) {
      index = buffer.index(after: index)
    }
    guard index > nameStart else { return nil }
    let name = String(buffer[nameStart..<index]).lowercased()
    var attributes: [HTMLAttributeToken] = []
    var selfClosing = false

    while index < buffer.endIndex {
      skipWhitespace(&index)
      guard index < buffer.endIndex else { return nil }

      if buffer[index] == ">" {
        return (name, attributes, selfClosing, buffer.index(after: index))
      }

      if buffer[index] == "/" {
        let next = buffer.index(after: index)
        guard next < buffer.endIndex else { return nil }
        if buffer[next] == ">" {
          selfClosing = true
          return (name, attributes, true, buffer.index(after: next))
        }
      }

      let attrNameStart = index
      while index < buffer.endIndex,
        !buffer[index].isWhitespace,
        buffer[index] != "=",
        buffer[index] != ">",
        buffer[index] != "/"
      {
        index = buffer.index(after: index)
      }
      guard index > attrNameStart else { return nil }
      let attrName = String(buffer[attrNameStart..<index]).lowercased()
      skipWhitespace(&index)
      var value = ""
      if index < buffer.endIndex, buffer[index] == "=" {
        index = buffer.index(after: index)
        skipWhitespace(&index)
        guard index < buffer.endIndex else { return nil }
        if buffer[index] == "\"" || buffer[index] == "'" {
          let quote = buffer[index]
          index = buffer.index(after: index)
          let valueStart = index
          while index < buffer.endIndex, buffer[index] != quote {
            index = buffer.index(after: index)
          }
          guard index < buffer.endIndex else { return nil }
          value = decodeEntities(String(buffer[valueStart..<index]))
          index = buffer.index(after: index)
        } else {
          let valueStart = index
          while index < buffer.endIndex,
            !buffer[index].isWhitespace,
            buffer[index] != ">"
          {
            index = buffer.index(after: index)
          }
          value = decodeEntities(String(buffer[valueStart..<index]))
        }
      }
      if !attributes.contains(where: { $0.name == attrName }) {
        attributes.append(HTMLAttributeToken(name: attrName, value: value))
      }
    }

    return nil
  }

  private func skipWhitespace(_ index: inout String.Index) {
    while index < buffer.endIndex, buffer[index].isWhitespace {
      index = buffer.index(after: index)
    }
  }

  private func peek(_ distance: Int) -> Character? {
    guard let index = buffer.index(cursor, offsetBy: distance, limitedBy: buffer.endIndex),
      index < buffer.endIndex
    else { return nil }
    return buffer[index]
  }

  private func hasPrefix(_ prefix: String) -> Bool {
    buffer[cursor...].hasPrefix(prefix)
  }

  private func hasPrefixCaseInsensitive(_ prefix: String) -> Bool {
    buffer[cursor...].prefix(prefix.count).lowercased() == prefix.lowercased()
  }

  private func isTagNameCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "-" || character == ":"
      || character == "_"
  }

  private func decodeEntities(_ value: String) -> String {
    var output = ""
    output.reserveCapacity(value.count)
    var index = value.startIndex
    while index < value.endIndex {
      guard value[index] == "&" else {
        output.append(value[index])
        index = value.index(after: index)
        continue
      }
      let afterAmp = value.index(after: index)
      guard afterAmp < value.endIndex else {
        output.append("&")
        index = afterAmp
        continue
      }
      if value[afterAmp] == "#" {
        if let (scalar, next) = decodeNumericReference(from: value, at: afterAmp) {
          output.append(Character(scalar))
          index = next
        } else {
          output.append("&")
          index = afterAmp
        }
        continue
      }
      var end = afterAmp
      while end < value.endIndex, value[end].isLetter || value[end].isNumber {
        end = value.index(after: end)
      }
      let hasSemicolon = end < value.endIndex && value[end] == ";"
      let nameEnd = end
      let name = String(value[afterAmp..<nameEnd]).lowercased()
      if hasSemicolon {
        if let replacement = Self.namedEntities[name] {
          output.append(replacement)
          index = value.index(after: end)
        } else {
          output.append(value[index])
          index = afterAmp
        }
        continue
      }
      if let replacement = Self.legacyEntities[name],
        end >= value.endIndex || !(value[end].isLetter || value[end].isNumber || value[end] == "=")
      {
        output.append(replacement)
        index = end
        continue
      }
      output.append("&")
      index = afterAmp
    }
    return output
  }

  private func decodeNumericReference(
    from value: String, at hashIndex: String.Index
  ) -> (UnicodeScalar, String.Index)? {
    var index = value.index(after: hashIndex)
    guard index < value.endIndex else { return nil }
    let isHex: Bool
    if value[index] == "x" || value[index] == "X" {
      isHex = true
      index = value.index(after: index)
    } else {
      isHex = false
    }
    let digitsStart = index
    while index < value.endIndex,
      isHex
        ? value[index].isHexDigit
        : value[index].isNumber
    {
      index = value.index(after: index)
    }
    guard index > digitsStart, index < value.endIndex, value[index] == ";" else { return nil }
    let digits = String(value[digitsStart..<index])
    let codePoint = isHex ? UInt32(digits, radix: 16) : UInt32(digits)
    guard let raw = codePoint, raw != 0,
      let scalar = UnicodeScalar(Self.replaceNumericCodePoint(raw))
    else { return nil }
    return (scalar, value.index(after: index))
  }

  private static func replaceNumericCodePoint(_ value: UInt32) -> UInt32 {
    if value == 0x0D { return 0x0D }
    if value >= 0xD800 && value <= 0xDFFF { return 0xFFFD }
    if value > 0x10FFFF { return 0xFFFD }
    if value == 0 || (value >= 0x01 && value <= 0x08) || value == 0x0B
      || (value >= 0x0E && value <= 0x1F) || value == 0x7F
    {
      return 0xFFFD
    }
    return value
  }

  private static let namedEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    "iexcl": "¡", "cent": "¢", "pound": "£", "curren": "¤", "yen": "¥",
    "brvbar": "¦", "sect": "§", "uml": "¨", "copy": "©", "ordf": "ª",
    "laquo": "«", "not": "¬", "shy": "\u{00AD}", "reg": "®", "macr": "¯",
    "deg": "°", "plusmn": "±", "sup2": "²", "sup3": "³", "acute": "´",
    "micro": "µ", "para": "¶", "middot": "·", "cedil": "¸", "sup1": "¹",
    "ordm": "º", "raquo": "»", "frac14": "¼", "frac12": "½", "frac34": "¾",
    "iquest": "¿", "times": "×", "divide": "÷", "forall": "∀", "part": "∂",
    "exist": "∃", "empty": "∅", "nabla": "∇", "isin": "∈", "notin": "∉",
    "ni": "∋", "prod": "∏", "sum": "∑", "minus": "−", "lowast": "∗",
    "radic": "√", "prop": "∝", "infin": "∞", "ang": "∠", "and": "∧",
    "or": "∨", "cap": "∩", "cup": "∪", "int": "∫", "there4": "∴",
    "sim": "∼", "cong": "≅", "asymp": "≈", "ne": "≠", "equiv": "≡",
    "le": "≤", "ge": "≥", "sub": "⊂", "sup": "⊃", "nsub": "⊄",
    "sube": "⊆", "supe": "⊇", "oplus": "⊕", "otimes": "⊗", "perp": "⊥",
    "sdot": "⋅", "hellip": "…", "prime": "′", "oline": "‾", "frasl": "⁄",
    "weierp": "℘", "image": "ℑ", "real": "ℜ", "alefsym": "ℵ", "larr": "←",
    "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔", "crarr": "↵",
    "lArr": "⇐", "uArr": "⇑", "rArr": "⇒", "dArr": "⇓", "hArr": "⇔",
    "trade": "™", "euro": "€", "ldquo": "“", "rdquo": "”", "lsquo": "‘",
    "rsquo": "’", "sbquo": "‚", "bdquo": "„", "dagger": "†", "dagger2": "‡",
    "bull": "•", "ndash": "–", "mdash": "—", "permil": "‰", "lsaquo": "‹",
    "rsaquo": "›", "oline2": "‾", "frasl2": "⁄", "alpha": "α", "beta": "β",
    "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ", "eta": "η",
    "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ",
    "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "rho": "ρ",
    "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ",
    "psi": "ψ", "omega": "ω", "thetasym": "ϑ", "upsih": "ϒ", "piv": "ϖ",
    "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
    "zwnj": "\u{200C}", "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}",
    "oelig": "œ", "scaron": "š", "yuml": "ÿ", "fnof": "ƒ", "circ": "ˆ",
    "tilde": "˜", "ensp2": "\u{2002}", "diams": "♦", "clubs": "♣",
    "hearts": "♥", "spades": "♠", "loz": "◊",
  ]

  private static let legacyEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "nbsp": "\u{00A0}",
    "copy": "©", "reg": "®", "trade": "™",
  ]
}
