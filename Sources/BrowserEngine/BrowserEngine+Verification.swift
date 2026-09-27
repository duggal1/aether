import BrowserVerification
import EngineRuntime

extension NativeBrowserEngine {
  public func verify(
    _ plan: BrowserVerificationPlan,
    using externalVerifiers: [any BrowserExternalVerifier] = []
  ) async throws -> BrowserVerificationResult {
    try await runtime.verify(plan, using: externalVerifiers)
  }
}
