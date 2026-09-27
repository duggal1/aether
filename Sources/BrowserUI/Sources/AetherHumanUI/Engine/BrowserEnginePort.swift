import AppKit
import EngineRuntime
import Foundation

public struct EnginePageSnapshot: Sendable {
    public let id: String
    public let url: String?
    public let title: String
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let isLoading: Bool
    public let contentReady: Bool
    public let paintReady: Bool
    public let progress: Double
    public let isSecure: Bool
    public let error: String?
    public let closed: Bool
    public let semanticSignals: BrowserSemanticSignals?
    public init(id: String, url: String?, title: String, canGoBack: Bool, canGoForward: Bool,
                isLoading: Bool = false, contentReady: Bool = false, paintReady: Bool = false, progress: Double = 0, isSecure: Bool = true, error: String? = nil, closed: Bool = false, semanticSignals: BrowserSemanticSignals? = nil) {
        self.id = id; self.url = url; self.title = title
        self.canGoBack = canGoBack; self.canGoForward = canGoForward
        self.isLoading = isLoading; self.contentReady = contentReady; self.paintReady = paintReady; self.progress = progress; self.isSecure = isSecure
        self.error = error; self.closed = closed; self.semanticSignals = semanticSignals
    }
}

public enum BrowserPortError: LocalizedError {
    case notConnected
    case pageUnavailable
    case unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .notConnected: "Connect the existing Aether BrowserRuntime through BrowserEnginePort to browse the web."
        case .pageUnavailable: "The page is unavailable."
        case .unsupported(let feature): "Aether's current engine does not expose \(feature) yet."
        }
    }
}

@MainActor
public protocol BrowserEnginePort: AnyObject {
    var isConnected: Bool { get }
    func createPage(profileID: UUID) async throws -> String
    func snapshot(pageID: String) async throws -> EnginePageSnapshot
    func navigate(pageID: String, url: URL) async throws
    func goBack(pageID: String) async throws
    func goForward(pageID: String) async throws
    func reload(pageID: String) async throws
    func stop(pageID: String) async throws
    func close(pageID: String) async
    func surface(pageID: String) -> NSView?
    func updatePrivacy(profileID: UUID, policy: BrowserPrivacyPolicy) async throws
    func setProfileEphemeral(profileID: UUID, enabled: Bool) async throws
}

public struct BrowserPrivacyPolicy: Equatable, Sendable {
    public var blockAds: Bool
    public var blockTrackers: Bool
    public var handleCookieBanners: Bool
    public var hideIP: Bool
    public init(blockAds: Bool = true, blockTrackers: Bool = true, handleCookieBanners: Bool = true,
                hideIP: Bool = false) {
        self.blockAds = blockAds; self.blockTrackers = blockTrackers
        self.handleCookieBanners = handleCookieBanners; self.hideIP = hideIP
    }
}

@MainActor public protocol BrowserPageObserving: AnyObject {
    func pageUpdates() -> AsyncStream<EnginePageSnapshot>
}

@MainActor
public protocol BrowserAgentInteractionObserving: AnyObject {
    func agentInteractionUpdates() async -> AsyncStream<AgentInteractionUpdate>
    func cancelAgentInteraction(pageID: String) async
}

@MainActor
public protocol BrowserPageActivating: AnyObject {
    func activate(pageID: String) async throws
}

@MainActor
public protocol BrowserNativeSemanticActions: AnyObject {
    func joinMeeting(pageID: String) async
}
