import ContentBlocker
import EngineCore
import Foundation

extension BrowserRuntime {
  public func configureContentBlocking(contextID: ContextID, rules: String, enabled: Bool) throws {
    let context = try requireContext(contextID)
    try context.network.blocker.replaceRules(from: rules)
    context.network.blocker.updateConfiguration(BlockerConfiguration(enabled: enabled))
  }
}
