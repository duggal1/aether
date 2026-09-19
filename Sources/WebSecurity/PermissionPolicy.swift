import Foundation

public enum WebPermission: String, Hashable, Sendable, Codable, CaseIterable {
  case camera
  case microphone
  case geolocation
  case notifications
  case clipboardRead
  case clipboardWrite
  case filesystem
}

public enum PermissionDecision: String, Hashable, Sendable, Codable {
  case allow
  case deny
  case prompt
}

public actor PermissionStore {
  private var decisions: [Origin: [WebPermission: PermissionDecision]] = [:]

  public init() {}

  public func decision(for permission: WebPermission, origin: Origin) -> PermissionDecision {
    decisions[origin]?[permission] ?? .prompt
  }

  public func effectiveDecision(
    for permission: WebPermission, origin: Origin, isTopLevel: Bool
  ) -> PermissionDecision {
    guard PermissionBoundary.allows(permission, origin: origin, isTopLevel: isTopLevel) else {
      return .deny
    }
    return decisions[origin]?[permission] ?? .prompt
  }

  public func set(_ decision: PermissionDecision, for permission: WebPermission, origin: Origin) {
    decisions[origin, default: [:]][permission] = decision
  }

  public func snapshot() -> [Origin: [WebPermission: PermissionDecision]] {
    decisions
  }

  public func restore(_ snapshot: [Origin: [WebPermission: PermissionDecision]]) {
    decisions = snapshot
  }
}
