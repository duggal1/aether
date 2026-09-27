import BrowserVerification
import Foundation

public enum TaskVerify: AgentProcedure {
  public static let method: AgentMethod = .taskVerify

  public struct Input: Codable, Hashable, Sendable {
    public let plan: BrowserVerificationPlan

    public init(plan: BrowserVerificationPlan) {
      self.plan = plan
    }

    public func validate() throws {
      do {
        try plan.validate()
      } catch {
        throw AgentProcedureError(code: "badParameter", message: String(describing: error))
      }
    }
  }

  public typealias Output = BrowserVerificationResult
}

public struct AgentEventEnvelope: Codable, Hashable, Sendable {
  public let sequence: UInt64
  public let timestamp: Double
  public let family: String
  public let name: String
  public let context: UInt64?
  public let page: UInt64?
  public let navigation: UInt64?
  public let branch: String?
  public let session: UInt64?
  public let details: [String: String]

  public init(
    sequence: UInt64, timestamp: Double, family: String, name: String,
    context: UInt64?, page: UInt64?, navigation: UInt64?, branch: String?,
    session: UInt64?, details: [String: String]
  ) {
    self.sequence = sequence
    self.timestamp = timestamp
    self.family = family
    self.name = name
    self.context = context
    self.page = page
    self.navigation = navigation
    self.branch = branch
    self.session = session
    self.details = details
  }
}

public enum EventsRecent: AgentProcedure {
  public static let method: AgentMethod = .eventsRecent

  public struct Input: Codable, Hashable, Sendable {
    public let family: String?
    public let context: UInt64?
    public let page: UInt64?
    public let since: UInt64?
    public let limit: Int?

    public var effectiveSince: UInt64 { since ?? 0 }
    public var effectiveLimit: Int { limit ?? 100 }

    public init(
      family: String? = nil, context: UInt64? = nil, page: UInt64? = nil,
      since: UInt64? = nil, limit: Int? = nil
    ) {
      self.family = family
      self.context = context
      self.page = page
      self.since = since
      self.limit = limit
    }

    public func validate() throws {
      let families: Set<String> = [
        "page", "navigation", "document", "console", "network", "download", "popup",
        "dialog", "permission", "authentication", "fileChooser", "focus", "context",
        "branch", "handoff", "execution", "lease",
      ]
      guard family.map(families.contains) ?? true else {
        throw AgentProcedureError(code: "badParameter", message: "family")
      }
      guard context.map({ $0 > 0 }) ?? true else {
        throw AgentProcedureError(code: "badParameter", message: "context")
      }
      guard page.map({ $0 > 0 }) ?? true else {
        throw AgentProcedureError(code: "badParameter", message: "page")
      }
      guard context != nil || page != nil else {
        throw AgentProcedureError(code: "badParameter", message: "context/page")
      }
      guard (1...512).contains(effectiveLimit) else {
        throw AgentProcedureError(code: "badParameter", message: "limit")
      }
    }
  }

  public struct Output: Codable, Hashable, Sendable {
    public let events: [AgentEventEnvelope]
    public let nextSequence: UInt64

    public init(events: [AgentEventEnvelope], nextSequence: UInt64) {
      self.events = events
      self.nextSequence = nextSequence
    }
  }
}
