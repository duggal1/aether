import ContentBlocker
import EngineCore
import Foundation

extension BrowserRuntime {
  public func configureContentBlocking(contextID: ContextID, rules: String, enabled: Bool) async throws {
    _ = try requireContext(contextID)
    try await configureWebBlocking(contextID: contextID, rules: rules, enabled: enabled)
  }
}
