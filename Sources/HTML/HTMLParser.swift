import DOM
import EngineCore
import Foundation

public struct HTMLParseResult: Sendable {
  public let document: DOMDocument
  public let tokenCount: Int

  public init(document: DOMDocument, tokenCount: Int) {
    self.document = document
    self.tokenCount = tokenCount
  }
}

public enum HTMLParser {
  public static func parse(_ html: String, documentID: DocumentID = DocumentID(rawValue: 1))
    -> HTMLParseResult
  {
    let tokenizer = HTMLTokenizer()
    let document = DOMDocument(id: documentID)
    let builder = HTMLTreeBuilder(document: document)
    let tokens = tokenizer.feed(html, isFinal: true)
    builder.consume(tokens)
    return HTMLParseResult(document: document, tokenCount: tokens.count)
  }

  public static func parseFragment(
    _ html: String, contextTag: String = "div",
    documentID: DocumentID = DocumentID(rawValue: 1)
  ) -> HTMLParseResult {
    let tokenizer = HTMLTokenizer()
    let document = DOMDocument(id: documentID)
    let builder = HTMLTreeBuilder(document: document, fragmentContext: contextTag)
    let tokens = tokenizer.feed(html, isFinal: true)
    builder.consume(tokens)
    return HTMLParseResult(document: document, tokenCount: tokens.count)
  }

  public static func parse(
    bytes: Data, documentID: DocumentID = DocumentID(rawValue: 1)
  ) -> HTMLParseResult {
    parse(decodeBytes(bytes), documentID: documentID)
  }

  public static func decodeBytes(_ bytes: Data) -> String {
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
      return String(data: bytes.dropFirst(3), encoding: .utf8) ?? ""
    }
    if bytes.starts(with: [0xFF, 0xFE]) {
      return String(data: bytes, encoding: .utf16LittleEndian) ?? ""
    }
    if bytes.starts(with: [0xFE, 0xFF]) {
      return String(data: bytes, encoding: .utf16BigEndian) ?? ""
    }
    if let text = String(data: bytes, encoding: .utf8) {
      return text
    }
    let prefix = String(data: bytes.prefix(4096), encoding: .isoLatin1) ?? ""
    if let charset = sniffCharset(in: prefix), charset != "utf-8", charset != "utf8" {
      if let encoding = encodingForLabel(charset),
        let text = String(data: bytes, encoding: encoding)
      {
        return text
      }
    }
    return String(data: bytes, encoding: .isoLatin1) ?? ""
  }

  public static func parse(
    chunks: some Sequence<String>, documentID: DocumentID = DocumentID(rawValue: 1)
  ) -> HTMLParseResult {
    let tokenizer = HTMLTokenizer()
    let document = DOMDocument(id: documentID)
    let builder = HTMLTreeBuilder(document: document)
    var count = 0
    for chunk in chunks {
      let tokens = tokenizer.feed(chunk)
      count += tokens.count
      builder.consume(tokens)
    }
    let finalTokens = tokenizer.feed("", isFinal: true)
    count += finalTokens.count
    builder.consume(finalTokens)
    return HTMLParseResult(document: document, tokenCount: count)
  }

  public static func sniffCharset(in head: String) -> String? {
    let lower = head.lowercased()
    var searchFrom = lower.startIndex
    while let metaRange = lower.range(of: "<meta", range: searchFrom..<lower.endIndex) {
      let scope = lower[metaRange.lowerBound...].prefix(1024)
      if let charsetRange = scope.range(of: "charset=") {
        var value = scope[charsetRange.upperBound...]
        value = value.drop(while: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
        let end =
          value.firstIndex(where: {
            $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == ">" || $0 == ";" || $0 == ","
          }) ?? value.endIndex
        let label = String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
      }
      searchFrom = metaRange.upperBound
    }
    return nil
  }

  static func encodingForLabel(_ label: String) -> String.Encoding? {
    switch label.lowercased().replacingOccurrences(of: "_", with: "-") {
    case "utf-8", "utf8": return .utf8
    case "iso-8859-1", "latin1", "windows-1252", "ascii": return .isoLatin1
    case "utf-16", "utf-16le": return .utf16LittleEndian
    case "utf-16be": return .utf16BigEndian
    case "shift-jis", "shift-jisx0213", "windows-31j": return .shiftJIS
    case "euc-jp": return .japaneseEUC
    case "iso-2022-jp": return .iso2022JP
    default: return nil
    }
  }
}
