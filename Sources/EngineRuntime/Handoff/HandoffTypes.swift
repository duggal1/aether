import EngineCore
import Foundation

public enum HumanRequestKind: String, Hashable, Sendable, Codable, CaseIterable {
  case handoff
  case approval
}

public enum HumanRequestCategory: String, Hashable, Sendable, Codable, CaseIterable {
  case mfa
  case captcha
  case passkey
  case credentials
  case payment
  case sensitiveForm
  case destructiveAction
  case permission
  case explicit
  case other
}

public enum HumanRequestState: String, Hashable, Sendable, Codable, CaseIterable {
  case pending
  case active
  case completed
  case approved
  case denied
  case cancelled
  case expired
  case interrupted
  case resumed

  public var isOpen: Bool { self == .pending || self == .active }

  public var blocksAgentControl: Bool {
    self == .pending || self == .active || self == .completed || self == .interrupted
  }

  public var isSettled: Bool {
    switch self {
    case .pending, .active: return false
    default: return true
    }
  }
}

public struct HumanRequestObservation: Hashable, Sendable, Codable {
  public var url: String?
  public var title: String
  public var sessionState: String
  public var loaded: Bool
  public var statusCode: Int
  public var error: String?
  public var sequence: UInt64
  public var at: Double

  public init(
    url: String?, title: String, sessionState: String, loaded: Bool, statusCode: Int,
    error: String?, sequence: UInt64, at: Double
  ) {
    self.url = url
    self.title = title
    self.sessionState = sessionState
    self.loaded = loaded
    self.statusCode = statusCode
    self.error = error
    self.sequence = sequence
    self.at = at
  }
}

public struct HumanRequestRecord: Hashable, Sendable, Codable {
  public var id: String
  public var kind: HumanRequestKind
  public var state: HumanRequestState
  public var category: HumanRequestCategory
  public var agent: String
  public var reason: String
  public var context: ContextID
  public var contextName: String
  public var page: PageID?
  public var pageURL: String?
  public var pageTitle: String?
  public var session: SessionID?
  public var branchID: String?
  public var checkpointID: String?
  public var executionID: String?
  public var createdAt: Double
  public var updatedAt: Double
  public var claimedAt: Double?
  public var completedAt: Double?
  public var expiresAt: Double?
  public var claimedBy: String?
  public var completedBy: String?
  public var resolution: String?
  public var observed: HumanRequestObservation?

  public init(
    id: String, kind: HumanRequestKind, state: HumanRequestState,
    category: HumanRequestCategory, agent: String, reason: String, context: ContextID,
    contextName: String, page: PageID?, pageURL: String?, pageTitle: String?,
    session: SessionID?, branchID: String?, checkpointID: String? = nil,
    executionID: String?, createdAt: Double,
    updatedAt: Double, claimedAt: Double? = nil, completedAt: Double? = nil,
    expiresAt: Double? = nil, claimedBy: String? = nil, completedBy: String? = nil,
    resolution: String? = nil, observed: HumanRequestObservation? = nil
  ) {
    self.id = id
    self.kind = kind
    self.state = state
    self.category = category
    self.agent = agent
    self.reason = reason
    self.context = context
    self.contextName = contextName
    self.page = page
    self.pageURL = pageURL
    self.pageTitle = pageTitle
    self.session = session
    self.branchID = branchID
    self.checkpointID = checkpointID
    self.executionID = executionID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.claimedAt = claimedAt
    self.completedAt = completedAt
    self.expiresAt = expiresAt
    self.claimedBy = claimedBy
    self.completedBy = completedBy
    self.resolution = resolution
    self.observed = observed
  }
}

public enum HumanRequestError: Error, Sendable, CustomStringConvertible {
  case notFound(String)
  case illegalState(String)
  case badParameter(String)
  case blocked(String)
  case timeout(String)

  public var code: String {
    switch self {
    case .notFound: return "handoff_not_found"
    case .illegalState: return "handoff_state"
    case .badParameter: return "bad_parameter"
    case .blocked: return "handoff_active"
    case .timeout: return "timeout"
    }
  }

  public var description: String {
    switch self {
    case .notFound(let value): return value
    case .illegalState(let value): return value
    case .badParameter(let value): return value
    case .blocked(let value): return value
    case .timeout(let value): return value
    }
  }
}

public enum HumanRequestLimits {
  static let maximumReasonLength = 512
  static let maximumNoteLength = 512
  static let maximumAgentLength = 128
  static let maximumRecords = 512
  static let defaultApprovalSeconds: Double = 600
  public static let defaultWaitMilliseconds = 30_000
  static let maximumWaitMilliseconds = 600_000
}
