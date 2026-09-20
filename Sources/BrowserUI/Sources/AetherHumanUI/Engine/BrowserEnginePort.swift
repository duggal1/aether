import AppKit
import Foundation

public struct EnginePageSnapshot: Sendable {
    public let id: String
    public let url: String?
    public let title: String
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let isLoading: Bool
    public let isSecure: Bool
    public let error: String?
    public let closed: Bool
    public init(id: String, url: String?, title: String, canGoBack: Bool, canGoForward: Bool,
                isLoading: Bool = false, isSecure: Bool = true, error: String? = nil, closed: Bool = false) {
        self.id = id; self.url = url; self.title = title
        self.canGoBack = canGoBack; self.canGoForward = canGoForward
        self.isLoading = isLoading; self.isSecure = isSecure
        self.error = error; self.closed = closed
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
}

public struct BrowserPrivacyPolicy: Equatable, Sendable {
    public var blockAds: Bool
    public var blockTrackers: Bool
    public var handleCookieBanners: Bool
    public init(blockAds: Bool = true, blockTrackers: Bool = true, handleCookieBanners: Bool = true) {
        self.blockAds = blockAds; self.blockTrackers = blockTrackers
        self.handleCookieBanners = handleCookieBanners
    }
}

@MainActor public protocol BrowserPageObserving: AnyObject {
    func pageUpdates() -> AsyncStream<EnginePageSnapshot>
}

@MainActor
public protocol BrowserPageActivating: AnyObject {
    func activate(pageID: String) async throws
}
