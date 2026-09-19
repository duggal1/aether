import Foundation

/// A zero-dependency composition root. Bind these closures to the EXISTING
/// Aether renderer/DOM/CSSOM/network types in your app's engine module.
/// Do not add a browser runtime here; the engine instance already exists.
public struct EngineClosureAdapter: AetherCaptureEngine {
    public let make: @Sendable (CaptureViewport) async throws -> any AetherCaptureSession
    public init(make: @escaping @Sendable (CaptureViewport) async throws -> any AetherCaptureSession) {
        self.make = make
    }
    public func makeCaptureSession(viewport: CaptureViewport) async throws -> any AetherCaptureSession {
        try await make(viewport)
    }
}

/// Aether's page executor can adopt AetherCaptureSession directly instead;
/// this wrapper is useful when engine types live in a separate Swift module.
public struct SessionClosureAdapter: AetherCaptureSession {
    public let navigateImpl: @Sendable (URL) async throws -> Void
    public let stateImpl: @Sendable () async throws -> AetherPageState
    public let scrollImpl: @Sendable (Double) async throws -> Void
    public let stabilityImpl: @Sendable (Int) async throws -> Void
    public let renderImpl: @Sendable () async throws -> AetherRaster
    public let snapshotImpl: @Sendable (Bool, Bool) async throws -> AetherDocumentSnapshot
    public let resourceImpl: @Sendable (URL, Int) async throws -> Data?
    public let closeImpl: @Sendable () async -> Void

    public init(
        navigate: @escaping @Sendable (URL) async throws -> Void,
        state: @escaping @Sendable () async throws -> AetherPageState,
        scroll: @escaping @Sendable (Double) async throws -> Void,
        stability: @escaping @Sendable (Int) async throws -> Void,
        render: @escaping @Sendable () async throws -> AetherRaster,
        snapshot: @escaping @Sendable (Bool, Bool) async throws -> AetherDocumentSnapshot,
        resource: @escaping @Sendable (URL, Int) async throws -> Data?,
        close: @escaping @Sendable () async -> Void
    ) {
        self.navigateImpl = navigate; self.stateImpl = state
        self.scrollImpl = scroll; self.stabilityImpl = stability
        self.renderImpl = render; self.snapshotImpl = snapshot
        self.resourceImpl = resource; self.closeImpl = close
    }
    public func navigate(to url: URL) async throws { try await navigateImpl(url) }
    public func state() async throws -> AetherPageState { try await stateImpl() }
    public func scrollTo(documentY: Double) async throws { try await scrollImpl(documentY) }
    public func waitForVisualStability(maxMilliseconds: Int) async throws { try await stabilityImpl(maxMilliseconds) }
    public func renderViewport() async throws -> AetherRaster { try await renderImpl() }
    public func snapshot(includeComputedStyles: Bool, redactSensitive: Bool) async throws -> AetherDocumentSnapshot {
        try await snapshotImpl(includeComputedStyles, redactSensitive)
    }
    public func resourceBytes(for url: URL, maximumBytes: Int) async throws -> Data? {
        try await resourceImpl(url, maximumBytes)
    }
    public func close() async { await closeImpl() }
}
