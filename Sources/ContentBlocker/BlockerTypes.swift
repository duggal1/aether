import Foundation

public enum BlockResourceKind: String, Sendable, CaseIterable, Codable {
  case document
  case script
  case image
  case stylesheet
  case subdocument
  case xmlhttprequest
  case media
  case websocket
  case font
  case other

  init?(filterOption: String) {
    switch filterOption.lowercased() {
    case "document": self = .document
    case "script": self = .script
    case "image": self = .image
    case "stylesheet": self = .stylesheet
    case "subdocument", "iframe": self = .subdocument
    case "xmlhttprequest", "xhr", "fetch": self = .xmlhttprequest
    case "media": self = .media
    case "websocket": self = .websocket
    case "font": self = .font
    case "other", "object": self = .other
    default: return nil
    }
  }
}

public struct BlockDecision: Sendable, Equatable {
  public var blocked: Bool
  public var reason: String?

  public static let allow = BlockDecision(blocked: false, reason: nil)
  public static func block(_ reason: String) -> BlockDecision {
    BlockDecision(blocked: true, reason: reason)
  }
}

public struct FilterStats: Sendable, Equatable, Codable {
  public var requestsEvaluated: Int
  public var requestsBlocked: Int
  public var exceptionsMatched: Int
  public var allowlistedRequests: Int
  public var cosmeticSitesStyled: Int
  public var networkRules: Int
  public var cosmeticRules: Int

  public init(
    requestsEvaluated: Int = 0, requestsBlocked: Int = 0, exceptionsMatched: Int = 0,
    allowlistedRequests: Int = 0, cosmeticSitesStyled: Int = 0, networkRules: Int = 0,
    cosmeticRules: Int = 0
  ) {
    self.requestsEvaluated = requestsEvaluated
    self.requestsBlocked = requestsBlocked
    self.exceptionsMatched = exceptionsMatched
    self.allowlistedRequests = allowlistedRequests
    self.cosmeticSitesStyled = cosmeticSitesStyled
    self.networkRules = networkRules
    self.cosmeticRules = cosmeticRules
  }
}

public struct BlockerConfiguration: Sendable, Codable, Equatable {
  public var enabled: Bool
  public var temporaryAllowedDomains: Set<String>
  public var maximumRules: Int

  public init(enabled: Bool = true, temporaryAllowedDomains: Set<String> = [], maximumRules: Int = 50_000)
  {
    self.enabled = enabled
    self.temporaryAllowedDomains = temporaryAllowedDomains
    self.maximumRules = maximumRules
  }
}

public enum BlockerError: Error, Sendable, CustomStringConvertible {
  case emptyRuleSetRejected(previousRuleCount: Int)
  case ruleLimitExceeded(limit: Int)
  case invalidDomain(String)

  public var description: String {
    switch self {
    case .emptyRuleSetRejected(let previous):
      return "filter update rejected: zero valid rules would replace \(previous) active rules"
    case .ruleLimitExceeded(let limit):
      return "filter update rejected: rule limit \(limit) exceeded"
    case .invalidDomain(let domain):
      return "filter update rejected: invalid domain '\(domain)'"
    }
  }
}
