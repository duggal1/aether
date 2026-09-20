import AppKit
import Foundation

@MainActor
public final class DisconnectedEnginePort: BrowserEnginePort {
    public init() {}
    public var isConnected: Bool { false }
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
}
