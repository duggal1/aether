import EngineCore
import Foundation

/// Browser-context capabilities are issued by browserd, not supplied as owner labels.
/// A capability grants control of one context and its pages, never another context.
public actor ContextAuthority {
  private var grants: [ContextID: String] = [:]

  public init() {}

  public func issue(for context: ContextID) -> String {
    // Two independent UUIDv4 values provide ~244 unpredictable bits. Never log this value.
    let capability = UUID().uuidString + UUID().uuidString
    grants[context] = capability
    return capability
  }

  public func permits(_ capability: String, context: ContextID) -> Bool {
    guard !capability.isEmpty, let expected = grants[context] else { return false }
    return expected == capability
  }

  public func permittedContexts(for capability: String) -> Set<ContextID> {
    guard !capability.isEmpty else { return [] }
    return Set(grants.compactMap { $0.value == capability ? $0.key : nil })
  }

  public func revoke(context: ContextID) {
    grants.removeValue(forKey: context)
  }
}
