import Foundation

public enum SearchIntent: String, Sendable, Codable, CaseIterable {
  case navigational
  case informational
  case local
}

public enum SearchCandidateKind: String, Sendable, Codable, Hashable {
  case navigate
  case completion
  case history
  case bookmark
  case openTab
  case web
  case google
}

public struct SearchCandidate: Sendable, Hashable, Identifiable {
  public let id: String
  public let kind: SearchCandidateKind
  public let title: String
  public let subtitle: String
  public let url: URL?
  public let completion: String?
  public let relevance: Double
  public let confidence: Double
  public let score: Double

  public init(
    id: String, kind: SearchCandidateKind, title: String, subtitle: String = "",
    url: URL? = nil, completion: String? = nil, relevance: Double = 0,
    confidence: Double = 0, score: Double = 0
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.url = url
    self.completion = completion
    self.relevance = relevance
    self.confidence = confidence
    self.score = score
  }
}

public struct LocalSignal: Sendable, Hashable {
  public enum Kind: String, Sendable, Hashable, Codable {
    case history
    case bookmark
    case openTab
    case shortcut
  }

  public let kind: Kind
  public let title: String
  public let url: URL
  public let visits: Int
  public let lastVisit: Double

  public init(kind: Kind, title: String, url: URL, visits: Int = 1, lastVisit: Double = 0) {
    self.kind = kind
    self.title = title
    self.url = url
    self.visits = visits
    self.lastVisit = lastVisit
  }

  public var host: String { url.host ?? "" }
}

public enum SearchTuning {
  public static let confidenceFloor = 0.6
  public static let minimumRelevance = 0.25
  public static let maximumLocalSignals = 8
  public static let maximumRankedResults = 12
  public static let maximumDomainGuesses = 4
  public static let completionLimit = 8
  public static let recencyHalfLifeDays = 30.0
  public static let relevanceWeight = 2.5
  public static let localTierBonus = 0.8
  public static let webTierBonus = 0.3
  public static let recencyWeight = 0.3
  public static let visitWeight = 0.01
  public static let visitCeiling = 20.0
  public static let cacheLifetime = 300.0
  public static let cacheCapacity = 256
}

public struct SearchOutcome: Sendable {
  public let query: String
  public let intent: SearchIntent
  public let intentConfidence: Double
  public let candidates: [SearchCandidate]
  public let model: String?
  public let degraded: Bool
  public let retrievalCount: Int
  public let answers: Int

  public init(
    query: String, intent: SearchIntent, intentConfidence: Double,
    candidates: [SearchCandidate], model: String?, degraded: Bool,
    retrievalCount: Int, answers: Int
  ) {
    self.query = query
    self.intent = intent
    self.intentConfidence = intentConfidence
    self.candidates = candidates
    self.model = model
    self.degraded = degraded
    self.retrievalCount = retrievalCount
    self.answers = answers
  }

  public var isLowConfidence: Bool { intentConfidence < SearchTuning.confidenceFloor }
  public var primary: SearchCandidate? { candidates.first }

  public static func empty(_ query: String) -> SearchOutcome {
    SearchOutcome(
      query: query, intent: .informational, intentConfidence: 0, candidates: [],
      model: nil, degraded: true, retrievalCount: 0, answers: 0)
  }
}

public enum JevQuestionType: String, Sendable, Codable, CaseIterable {
  case choice
  case score
  case noul
}

public enum JevCriteria: Sendable, Encodable {
  case options([String: String])
  case levels([String])

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .options(let values): try container.encode(values)
    case .levels(let values): try container.encode(values)
    }
  }
}

public struct JevQuestion: Sendable, Encodable {
  public let type: JevQuestionType
  public let instructions: String
  public let criteria: JevCriteria?

  public init(type: JevQuestionType, instructions: String, criteria: JevCriteria? = nil) {
    self.type = type
    self.instructions = instructions
    self.criteria = criteria
  }

  public static func choice(_ instructions: String, _ options: [String: String]) -> JevQuestion {
    JevQuestion(type: .choice, instructions: instructions, criteria: .options(options))
  }

  public static func score(_ instructions: String, _ levels: [String]) -> JevQuestion {
    JevQuestion(type: .score, instructions: instructions, criteria: .levels(levels))
  }

  public static func noul(_ instructions: String, yes: String, no: String) -> JevQuestion {
    JevQuestion(
      type: .noul, instructions: instructions, criteria: .options(["true": yes, "false": no]))
  }
}

public struct JevAnswer: Sendable, Decodable {
  public let type: String?
  public let choice: String?
  public let confidence: Double?
  public let probabilities: [String: Double]?
  public let score: Double?
  public let noul: Double?
}

public struct JevUsage: Sendable, Decodable {
  public let inputTokens: Int?
  public let outputTokens: Int?

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }
}

public struct JevResponse: Sendable, Decodable {
  public let model: String?
  public let answers: [String: JevAnswer]
  public let usage: JevUsage?
}

public enum JevError: Error, Sendable, CustomStringConvertible {
  case notConfigured
  case timeout
  case overloaded
  case transport(String)
  case status(Int, String)
  case decoding(String)

  public var description: String {
    switch self {
    case .notConfigured: return "Jev search is not configured"
    case .timeout: return "Jev request timed out"
    case .overloaded: return "Jev request capacity is full"
    case .transport(let value): return value
    case .status(let code, let body): return "HTTP \(code): \(body)"
    case .decoding(let value): return value
    }
  }
}
