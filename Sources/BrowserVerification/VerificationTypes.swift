import EngineCore
import Foundation

public enum BrowserVerificationStatus: String, Codable, Hashable, Sendable {
  case verified
  case failed
  case inconclusive
}

public enum BrowserTextMatchMode: String, Codable, Hashable, Sendable {
  case exact
  case contains
  case prefix

  public func matches(_ actual: String, expected: String) -> Bool {
    switch self {
    case .exact: actual == expected
    case .contains: actual.range(of: expected, options: .caseInsensitive) != nil
    case .prefix: actual.range(of: expected, options: [.caseInsensitive, .anchored]) != nil
    }
  }
}

public struct BrowserTextExpectation: Codable, Hashable, Sendable {
  public let value: String
  public let mode: BrowserTextMatchMode

  public init(_ value: String, mode: BrowserTextMatchMode = .exact) {
    self.value = value
    self.mode = mode
  }
}

public enum BrowserElementCondition: Codable, Hashable, Sendable {
  case exists
  case absent
  case visible
  case enabled
  case accessibleName(BrowserTextExpectation)

  private enum CodingKeys: String, CodingKey {
    case kind
    case expectation
  }

  private enum Kind: String, Codable {
    case exists
    case absent
    case visible
    case enabled
    case accessibleName
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .exists: self = .exists
    case .absent: self = .absent
    case .visible: self = .visible
    case .enabled: self = .enabled
    case .accessibleName:
      self = .accessibleName(try container.decode(BrowserTextExpectation.self, forKey: .expectation))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .exists:
      try container.encode(Kind.exists, forKey: .kind)
    case .absent:
      try container.encode(Kind.absent, forKey: .kind)
    case .visible:
      try container.encode(Kind.visible, forKey: .kind)
    case .enabled:
      try container.encode(Kind.enabled, forKey: .kind)
    case .accessibleName(let expectation):
      try container.encode(Kind.accessibleName, forKey: .kind)
      try container.encode(expectation, forKey: .expectation)
    }
  }
}

public enum BrowserVerificationAssertion: Codable, Hashable, Sendable {
  case pageURL(BrowserTextExpectation)
  case pageTitle(BrowserTextExpectation)
  case element(selector: String, condition: BrowserElementCondition)
  case navigationResponse(
    url: BrowserTextExpectation, statusCode: Int?, sinceSequence: UInt64)
  case download(
    url: BrowserTextExpectation, minimumBytes: Int, verifyFileExists: Bool,
    downloadID: UInt64?, sinceSequence: UInt64?)
  case external(identifier: String, payload: Data)

  private enum CodingKeys: String, CodingKey {
    case kind
    case expectation
    case selector
    case condition
    case statusCode
    case sinceSequence
    case downloadID
    case minimumBytes
    case verifyFileExists
    case identifier
    case payload
  }

  private enum Kind: String, Codable {
    case pageURL
    case pageTitle
    case element
    case navigationResponse
    case download
    case external
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .pageURL:
      self = .pageURL(try container.decode(BrowserTextExpectation.self, forKey: .expectation))
    case .pageTitle:
      self = .pageTitle(try container.decode(BrowserTextExpectation.self, forKey: .expectation))
    case .element:
      self = .element(
        selector: try container.decode(String.self, forKey: .selector),
        condition: try container.decode(BrowserElementCondition.self, forKey: .condition))
    case .navigationResponse:
      self = .navigationResponse(
        url: try container.decode(BrowserTextExpectation.self, forKey: .expectation),
        statusCode: try container.decodeIfPresent(Int.self, forKey: .statusCode),
        sinceSequence: try container.decode(UInt64.self, forKey: .sinceSequence))
    case .download:
      self = .download(
        url: try container.decode(BrowserTextExpectation.self, forKey: .expectation),
        minimumBytes: try container.decode(Int.self, forKey: .minimumBytes),
        verifyFileExists: try container.decode(Bool.self, forKey: .verifyFileExists),
        downloadID: try container.decodeIfPresent(UInt64.self, forKey: .downloadID),
        sinceSequence: try container.decodeIfPresent(UInt64.self, forKey: .sinceSequence))
    case .external:
      self = .external(
        identifier: try container.decode(String.self, forKey: .identifier),
        payload: try container.decode(Data.self, forKey: .payload))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .pageURL(let expectation):
      try container.encode(Kind.pageURL, forKey: .kind)
      try container.encode(expectation, forKey: .expectation)
    case .pageTitle(let expectation):
      try container.encode(Kind.pageTitle, forKey: .kind)
      try container.encode(expectation, forKey: .expectation)
    case .element(let selector, let condition):
      try container.encode(Kind.element, forKey: .kind)
      try container.encode(selector, forKey: .selector)
      try container.encode(condition, forKey: .condition)
    case .navigationResponse(let expectation, let statusCode, let sinceSequence):
      try container.encode(Kind.navigationResponse, forKey: .kind)
      try container.encode(expectation, forKey: .expectation)
      try container.encodeIfPresent(statusCode, forKey: .statusCode)
      try container.encode(sinceSequence, forKey: .sinceSequence)
    case .download(let expectation, let minimumBytes, let verifyFileExists, let downloadID, let sinceSequence):
      try container.encode(Kind.download, forKey: .kind)
      try container.encode(expectation, forKey: .expectation)
      try container.encode(minimumBytes, forKey: .minimumBytes)
      try container.encode(verifyFileExists, forKey: .verifyFileExists)
      try container.encodeIfPresent(downloadID, forKey: .downloadID)
      try container.encodeIfPresent(sinceSequence, forKey: .sinceSequence)
    case .external(let identifier, let payload):
      try container.encode(Kind.external, forKey: .kind)
      try container.encode(identifier, forKey: .identifier)
      try container.encode(payload, forKey: .payload)
    }
  }
}

public struct BrowserVerificationCheck: Codable, Hashable, Sendable {
  public let id: String
  public let assertion: BrowserVerificationAssertion

  public init(id: String, assertion: BrowserVerificationAssertion) {
    self.id = id
    self.assertion = assertion
  }
}

public struct BrowserVerificationPlan: Codable, Hashable, Sendable {
  public static let maximumChecks = 64
  public let pageID: PageID
  public let checks: [BrowserVerificationCheck]

  private enum CodingKeys: String, CodingKey {
    case page
    case checks
  }

  public init(pageID: PageID, checks: [BrowserVerificationCheck]) {
    self.pageID = pageID
    self.checks = checks
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pageID = PageID(rawValue: try container.decode(UInt64.self, forKey: .page))
    checks = try container.decode([BrowserVerificationCheck].self, forKey: .checks)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(pageID.rawValue, forKey: .page)
    try container.encode(checks, forKey: .checks)
  }

  public func validate() throws {
    guard pageID.rawValue > 0 else { throw BrowserVerificationInputError.invalid("pageID") }
    guard !checks.isEmpty, checks.count <= Self.maximumChecks else {
      throw BrowserVerificationInputError.invalid("checks")
    }

    var identifiers = Set<String>()
    for check in checks {
      guard Self.validIdentifier(check.id), identifiers.insert(check.id).inserted else {
        throw BrowserVerificationInputError.invalid("check id")
      }
      switch check.assertion {
      case .pageURL(let expectation), .pageTitle(let expectation):
        try validate(expectation)
      case .element(let selector, let condition):
        guard !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          selector.utf8.count <= 512
        else { throw BrowserVerificationInputError.invalid("selector") }
        if case .accessibleName(let expectation) = condition {
          try validate(expectation)
        }
      case .navigationResponse(let expectation, let statusCode, _):
        try validate(expectation)
        if let statusCode, !(100...599).contains(statusCode) {
          throw BrowserVerificationInputError.invalid("statusCode")
        }
      case .download(let expectation, let minimumBytes, _, let downloadID, let sinceSequence):
        try validate(expectation)
        guard (0...1_073_741_824).contains(minimumBytes) else {
          throw BrowserVerificationInputError.invalid("minimumBytes")
        }
        guard downloadID.map({ $0 > 0 }) ?? true,
          downloadID != nil || sinceSequence != nil
        else { throw BrowserVerificationInputError.invalid("downloadID/sinceSequence") }
      case .external(let identifier, let payload):
        guard Self.validIdentifier(identifier), payload.count <= 65_536 else {
          throw BrowserVerificationInputError.invalid("external verifier")
        }
      }
    }
  }

  private func validate(_ expectation: BrowserTextExpectation) throws {
    guard !expectation.value.isEmpty, expectation.value.utf8.count <= 2_048 else {
      throw BrowserVerificationInputError.invalid("expectation")
    }
  }

  private static func validIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 80 else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        .contains($0)
    }
  }
}

public struct BrowserVerificationEvidence: Codable, Hashable, Sendable {
  public let checkID: String
  public let status: BrowserVerificationStatus
  public let source: String
  public let summary: String

  public init(checkID: String, status: BrowserVerificationStatus, source: String, summary: String) {
    self.checkID = checkID
    self.status = status
    self.source = source
    self.summary = summary
  }
}

public struct BrowserVerificationResult: Codable, Hashable, Sendable {
  public let status: BrowserVerificationStatus
  public let pageID: PageID
  public let contextID: ContextID
  public let checkedAt: Date
  public let evidence: [BrowserVerificationEvidence]

  private enum CodingKeys: String, CodingKey {
    case status
    case page
    case context
    case checkedAt
    case evidence
  }

  public init(
    status: BrowserVerificationStatus, pageID: PageID, contextID: ContextID,
    checkedAt: Date, evidence: [BrowserVerificationEvidence]
  ) {
    self.status = status
    self.pageID = pageID
    self.contextID = contextID
    self.checkedAt = checkedAt
    self.evidence = evidence
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = try container.decode(BrowserVerificationStatus.self, forKey: .status)
    pageID = PageID(rawValue: try container.decode(UInt64.self, forKey: .page))
    contextID = ContextID(rawValue: try container.decode(UInt64.self, forKey: .context))
    checkedAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .checkedAt))
    evidence = try container.decode([BrowserVerificationEvidence].self, forKey: .evidence)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(status, forKey: .status)
    try container.encode(pageID.rawValue, forKey: .page)
    try container.encode(contextID.rawValue, forKey: .context)
    try container.encode(checkedAt.timeIntervalSince1970, forKey: .checkedAt)
    try container.encode(evidence, forKey: .evidence)
  }
}

public struct BrowserExternalVerification: Codable, Hashable, Sendable {
  public let status: BrowserVerificationStatus
  public let summary: String

  public init(status: BrowserVerificationStatus, summary: String) {
    self.status = status
    self.summary = summary
  }
}

public protocol BrowserExternalVerifier: Sendable {
  var identifier: String { get }
  func verify(payload: Data) async throws -> BrowserExternalVerification
}

public enum BrowserVerificationInputError: Error, Sendable, CustomStringConvertible {
  case invalid(String)
  case duplicateVerifier(String)

  public var description: String {
    switch self {
    case .invalid(let field): "Invalid verification plan: \(field)"
    case .duplicateVerifier(let identifier): "Duplicate external verifier: \(identifier)"
    }
  }
}
