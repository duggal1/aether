import AppKit
import Foundation

@MainActor
public final class DisconnectedEnginePort: BrowserEnginePort, BrowserSearchSuggesting {
    public init() {}
    public var isConnected: Bool { false }
    public func searchCompletions(prefix: String, limit: Int, providerEndpoint: URL?) async throws -> [String] { [] }
    public func warmSearchCompletions(providerEndpoint: URL?) async {}
    public func createPage(profileID: UUID) async throws -> String { throw BrowserPortError.notConnected }
    public func snapshot(pageID: String) async throws -> EnginePageSnapshot { throw BrowserPortError.notConnected }
    public func navigate(pageID: String, url: URL) async throws { throw BrowserPortError.notConnected }
    public func goBack(pageID: String) async throws { throw BrowserPortError.notConnected }
    public func goForward(pageID: String) async throws { throw BrowserPortError.notConnected }
    public func reload(pageID: String) async throws { throw BrowserPortError.notConnected }
    public func stop(pageID: String) async throws { throw BrowserPortError.notConnected }
    public func close(pageID: String) async {}
    public func surface(pageID: String) -> NSView? { nil }
    public func updatePrivacy(profileID: UUID, policy: BrowserPrivacyPolicy) async throws { throw BrowserPortError.notConnected }
    public func setProfileEphemeral(profileID: UUID, enabled: Bool) async throws { throw BrowserPortError.notConnected }
}

extension DisconnectedEnginePort: BrowserNetworkRouting {
    public func applyNetworkRoute(profileID: UUID, route: BrowserNetworkRoute, endpoint: RouteEndpoint?) async throws -> NetworkRouteStatus {
        throw BrowserPortError.notConnected
    }
    public func currentRouteStatus(profileID: UUID) -> NetworkRouteStatus { .unknown }
    public func observedExitIP(profileID: UUID) -> String? { nil }
}

extension DisconnectedEnginePort: BrowserPasskeyCapability {
    public var passkeyDeviceConfigured: Bool { false }
    public var passkeyLocalAuthAvailable: Bool { false }
    public func passkeyAuthorizationState() -> PasskeyAuthorizationState { .unavailable }
    public func requestPasskeyAuthorization() async -> PasskeyAuthorizationState { .unavailable }
}

extension DisconnectedEnginePort: BrowserSessionStateProviding {
    public func sessionState(pageID: String) async -> EngineSessionState { .notLoaded }
}
