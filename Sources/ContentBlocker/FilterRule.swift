import Foundation

enum PatternToken: Equatable, Sendable {
  case literal(String)
  case separator
  case wildcard
}

struct NetworkFilterRule: Sendable {
  let tokens: [PatternToken]
  let hostAnchor: Bool
  let prefixAnchor: Bool
  let suffixAnchor: Bool
  let patternHost: String?
  let resourceKinds: Set<BlockResourceKind>?
  let thirdPartyOnly: Bool
  let firstPartyOnly: Bool
  let includedDomains: [String]
  let excludedDomains: [String]
  let isException: Bool
  let important: Bool
  let matchCase: Bool

  static let separatorScalars: Set<Unicode.Scalar> = [":", "/", "?", "=", "&", "."]

  func matches(url: URL, kind: BlockResourceKind, documentHost: String?) -> Bool {
    if let kinds = resourceKinds, !kinds.contains(kind) { return false }
    if thirdPartyOnly, Self.isFirstParty(urlHost: url.host, documentHost: documentHost) {
      return false
    }
    if firstPartyOnly, !Self.isFirstParty(urlHost: url.host, documentHost: documentHost) {
      return false
    }
    if let documentHost, !includedDomains.isEmpty {
      let applies = includedDomains.contains { Self.domainMatches(host: documentHost, domain: $0) }
      guard applies else { return false }
    }
    if let documentHost, !excludedDomains.isEmpty {
      let excluded = excludedDomains.contains { Self.domainMatches(host: documentHost, domain: $0) }
      if excluded { return false }
    }
    return matchesPattern(url: url)
  }

  static func isFirstParty(urlHost: String?, documentHost: String?) -> Bool {
    guard let urlHost, let documentHost else { return true }
    let url = urlHost.lowercased()
    let document = documentHost.lowercased()
    return url == document || url.hasSuffix("." + document) || document.hasSuffix("." + url)
  }

  static func domainMatches(host: String, domain: String) -> Bool {
    let normalized = domain.lowercased()
    return host == normalized || host.hasSuffix("." + normalized)
  }

  private func matchesPattern(url: URL) -> Bool {
    let target = matchCase ? url.absoluteString : url.absoluteString.lowercased()
    if hostAnchor {
      guard let patternHost else { return false }
      guard let urlHost = url.host?.lowercased() else { return false }
      guard urlHost == patternHost || urlHost.hasSuffix("." + patternHost) else { return false }
      guard let schemeRange = target.range(of: "://") else { return false }
      let hostStart = schemeRange.upperBound
      let offset = urlHost.count - patternHost.count
      guard offset >= 0 else { return false }
      let index = target.index(hostStart, offsetBy: offset)
      return Self.match(tokens, from: 0, at: index, in: target, suffixAnchor: suffixAnchor)
    }
    return Self.match(tokens, from: 0, at: target.startIndex, in: target, suffixAnchor: suffixAnchor)
  }

  static func match(
    _ tokens: [PatternToken], from index: Int, at position: String.Index, in target: String,
    suffixAnchor: Bool
  ) -> Bool {
    var tokenIndex = index
    var cursor = position
    while tokenIndex < tokens.count {
      switch tokens[tokenIndex] {
      case .literal(let text):
        guard cursor <= target.endIndex,
          target.range(of: text, range: cursor..<target.endIndex)?.lowerBound == cursor
        else { return false }
        cursor = target.index(cursor, offsetBy: text.count)
      case .separator:
        if cursor == target.endIndex { break }
        guard let scalar = target[cursor].unicodeScalars.first,
          separatorScalars.contains(scalar)
        else { return false }
        cursor = target.index(after: cursor)
      case .wildcard:
        if tokenIndex == tokens.count - 1 { return true }
        var candidate = cursor
        while true {
          if match(tokens, from: tokenIndex + 1, at: candidate, in: target, suffixAnchor: suffixAnchor) {
            return true
          }
          if candidate == target.endIndex { return false }
          candidate = target.index(after: candidate)
        }
      }
      tokenIndex += 1
    }
    if suffixAnchor { return cursor == target.endIndex }
    return true
  }
}

struct CosmeticFilterRule: Sendable {
  let includedDomains: [String]
  let excludedDomains: [String]
  let selector: String
  let isException: Bool

  func applies(toHost host: String?) -> Bool {
    if let host {
      if excludedDomains.contains(where: { NetworkFilterRule.domainMatches(host: host, domain: $0) }) {
        return false
      }
      if includedDomains.isEmpty { return true }
      return includedDomains.contains { NetworkFilterRule.domainMatches(host: host, domain: $0) }
    }
    return includedDomains.isEmpty
  }
}

enum FilterListParser {
  struct Result: Sendable {
    var network: [NetworkFilterRule] = []
    var cosmetic: [CosmeticFilterRule] = []
    var skipped = 0
    var accepted = 0

    var isEmpty: Bool { network.isEmpty && cosmetic.isEmpty }
  }

  static let maximumSelectorLength = 512
  static let maximumPatternLength = 1024

  static let knownResourceOptions: Set<String> = [
    "script", "image", "stylesheet", "subdocument", "iframe", "xmlhttprequest", "xhr", "fetch",
    "media", "websocket", "font", "document", "other", "object",
  ]
  static let unsupportedOptions: Set<String> = [
    "popup", "genericblock", "generichide", "webrtc", "ping", "worker", "csp",
    "replace", "redirect", "rewrite", "elemhide", "bg", "third-party-cache",
  ]

  static func parse(_ text: String) -> Result {
    var result = Result()
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
      if parseCosmetic(line, into: &result) { result.accepted += 1; continue }
      if let rule = parseNetwork(line) {
        result.network.append(rule)
        result.accepted += 1
      } else {
        result.skipped += 1
      }
    }
    return result
  }

  static func parseCosmetic(_ line: String, into result: inout Result) -> Bool {
    if line.contains("#$#") || line.contains("#@$#") || line.contains("%") { return false }
    let exceptionMarker = "#@#"
    let css4Marker = "#?#"
    let standardMarker = "##"
    var isException = false
    var separatorRange = line.range(of: standardMarker)
    if let css4 = line.range(of: css4Marker), css4.lowerBound < (separatorRange?.lowerBound ?? line.endIndex) {
      separatorRange = css4
    }
    if let exception = line.range(of: exceptionMarker) {
      separatorRange = exception
      isException = true
    }
    guard let marker = separatorRange else { return false }
    let domainPart = String(line[line.startIndex..<marker.lowerBound])
    let selector = String(line[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard !selector.isEmpty, selector.count <= maximumSelectorLength else { return false }
    var included: [String] = []
    var excluded: [String] = []
    for piece in domainPart.split(separator: ",") {
      let domain = piece.trimmingCharacters(in: .whitespaces).lowercased()
      if domain.isEmpty { continue }
      if domain.hasPrefix("~") {
        let normalized = String(domain.dropFirst())
        guard isValidDomain(normalized) else { return false }
        excluded.append(normalized)
      } else {
        let normalized = domain.hasPrefix("*.") ? String(domain.dropFirst(2)) : domain
        guard isValidDomain(normalized) else { return false }
        included.append(normalized)
      }
    }
    result.cosmetic.append(
      CosmeticFilterRule(
        includedDomains: included, excludedDomains: excluded, selector: selector,
        isException: isException))
    return true
  }

  static func parseNetwork(_ line: String) -> NetworkFilterRule? {
    var body = line
    var isException = false
    if body.hasPrefix("@@") {
      isException = true
      body = String(body.dropFirst(2))
    }
    guard !body.isEmpty, body.count <= maximumPatternLength else { return nil }
    var options: [String] = []
    if let dollar = body.lastIndex(of: "$") {
      let candidate = String(body[body.index(after: dollar)...])
      let parsed = candidate.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces).lowercased()
      }
      if !parsed.isEmpty, parsed.allSatisfy({ isKnownOption($0) || $0.hasPrefix("domain=") }) {
        options = parsed
        body = String(body[body.startIndex..<dollar])
      }
    }
    guard !body.isEmpty else { return nil }
    if body.count >= 2, body.hasPrefix("/"), body.hasSuffix("/") { return nil }
    var hostAnchor = false
    var prefixAnchor = false
    var suffixAnchor = false
    if body.hasPrefix("||") {
      hostAnchor = true
      body = String(body.dropFirst(2))
    } else if body.hasPrefix("|") {
      prefixAnchor = true
      body = String(body.dropFirst(1))
    }
    if body.hasSuffix("|") {
      suffixAnchor = true
      body = String(body.dropLast(1))
    }
    guard !body.isEmpty else { return nil }
    var patternHost: String?
    if hostAnchor {
      let hostEnd = body.firstIndex(where: { "/^*|".contains($0) }) ?? body.endIndex
      let candidate = String(body[body.startIndex..<hostEnd]).lowercased()
      guard isValidDomain(candidate) else { return nil }
      patternHost = candidate
    }
    guard let tokens = compile(body) else { return nil }
    var resourceKinds: Set<BlockResourceKind>?
    var thirdPartyOnly = false
    var firstPartyOnly = false
    var important = false
    var matchCase = false
    var included: [String] = []
    var excluded: [String] = []
    for option in options {
      if option == "third-party" { thirdPartyOnly = true; continue }
      if option == "~third-party" { firstPartyOnly = true; continue }
      if option == "important" { important = true; continue }
      if option == "match-case" { matchCase = true; continue }
      if option.hasPrefix("domain=") {
        let value = String(option.dropFirst("domain=".count))
        for piece in value.split(separator: "|") {
          let domain = piece.trimmingCharacters(in: .whitespaces).lowercased()
          if domain.hasPrefix("~") {
            let normalized = String(domain.dropFirst())
            guard isValidDomain(normalized) else { return nil }
            excluded.append(normalized)
          } else {
            guard isValidDomain(domain) else { return nil }
            included.append(domain)
          }
        }
        continue
      }
      if option.hasPrefix("~"), let kind = BlockResourceKind(filterOption: String(option.dropFirst())) {
        if resourceKinds == nil { resourceKinds = Set(BlockResourceKind.allCases) }
        resourceKinds?.remove(kind)
        continue
      }
      if let kind = BlockResourceKind(filterOption: option) {
        resourceKinds?.insert(kind)
        if resourceKinds == nil { resourceKinds = [kind] }
        continue
      }
      return nil
    }
    return NetworkFilterRule(
      tokens: tokens, hostAnchor: hostAnchor, prefixAnchor: prefixAnchor, suffixAnchor: suffixAnchor,
      patternHost: patternHost, resourceKinds: resourceKinds, thirdPartyOnly: thirdPartyOnly,
      firstPartyOnly: firstPartyOnly, includedDomains: included, excludedDomains: excluded,
      isException: isException, important: important, matchCase: matchCase)
  }

  static func isKnownOption(_ option: String) -> Bool {
    if option.isEmpty { return false }
    if option == "third-party" || option == "~third-party" || option == "important"
      || option == "match-case" { return true }
    if option.hasPrefix("domain=") { return true }
    if option.hasPrefix("~") {
      return BlockResourceKind(filterOption: String(option.dropFirst())) != nil
    }
    return BlockResourceKind(filterOption: option) != nil
  }

  static func isValidDomain(_ domain: String) -> Bool {
    guard !domain.isEmpty, domain.count <= 253 else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
    return domain.unicodeScalars.allSatisfy { allowed.contains($0) }
      && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !domain.contains("..")
      && !domain.hasPrefix("-") && !domain.hasSuffix("-")
  }

  static func compile(_ pattern: String) -> [PatternToken]? {
    guard !pattern.isEmpty, pattern.count <= maximumPatternLength else { return nil }
    var tokens: [PatternToken] = []
    var literal: [Character] = []
    func flushLiteral() {
      guard !literal.isEmpty else { return }
      tokens.append(.literal(String(literal).lowercased()))
      literal.removeAll(keepingCapacity: true)
    }
    for character in pattern {
      switch character {
      case "*": flushLiteral(); tokens.append(.wildcard)
      case "^": flushLiteral(); tokens.append(.separator)
      case "\\", "|": return nil
      default: literal.append(character)
      }
    }
    flushLiteral()
    return tokens
  }
}
