import Foundation
import AetherCapture

/// Bind this function from Aether's existing CLI/MCP tool registry.
/// No standalone browser binary, launch command, or network service needed.
public func runAgentCapture(
    engine: any AetherCaptureEngine,
    url: URL,
    outputDirectory: URL,
    preferredFormat: CaptureFormat = .webp
) async throws -> CaptureResult {
    var options = CaptureOptions()
    options.preferredFormat = preferredFormat
    let coordinator = CaptureCoordinator(engine: engine)
    return try await coordinator.capture(url, into: outputDirectory, options: options)
}
