import Foundation

public struct InspectionNode: Identifiable, Sendable {
    public let id: String
    public let depth: Int
    public let summary: String
    public let html: String
    public init(id: String, depth: Int, summary: String, html: String) {
        self.id = id; self.depth = depth; self.summary = summary; self.html = html
    }
}

public struct BrowserInspectionSnapshot: Sendable {
    public let nodes: [InspectionNode]
    public let documentHTML: String
    public let availableCSS: String
    public let consoleMessages: [String]
    public let networkRequests: [String]
    public init(nodes: [InspectionNode], documentHTML: String, availableCSS: String,
                consoleMessages: [String], networkRequests: [String]) {
        self.nodes = nodes; self.documentHTML = documentHTML; self.availableCSS = availableCSS
        self.consoleMessages = consoleMessages; self.networkRequests = networkRequests
    }
}

@MainActor public protocol BrowserInspectionProviding: AnyObject {
    func inspect(pageID: String) async throws -> BrowserInspectionSnapshot
    func highlight(nodeID: String, pageID: String) async throws
}

@MainActor public protocol BrowserReaderProviding: AnyObject {
    func markdown(pageID: String) async throws -> String
}

public struct BrowserDownloadRecord: Identifiable, Sendable {
    public let id: String
    public let fileName: String
    public let bytesReceived: Int64
    public let totalBytes: Int64?
    public let isComplete: Bool
    public let localFileURL: URL?
    public init(id: String, fileName: String, bytesReceived: Int64, totalBytes: Int64?,
                isComplete: Bool, localFileURL: URL?) {
        self.id = id; self.fileName = fileName; self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes; self.isComplete = isComplete; self.localFileURL = localFileURL
    }
}

@MainActor public protocol BrowserDownloadsProviding: AnyObject {
    func downloads(profileID: UUID) async throws -> [BrowserDownloadRecord]
    func cancelDownload(id: String, profileID: UUID) async throws
}

@MainActor public protocol BrowserFindProviding: AnyObject {
    func find(pageID: String, query: String, forward: Bool) async throws -> Int
}

public struct BrowserProfileLibrary: Codable, Sendable {
    public var bookmarks: [BrowserBookmark]
    public var visits: [BrowserVisit]
    public init(bookmarks: [BrowserBookmark], visits: [BrowserVisit]) {
        self.bookmarks = bookmarks; self.visits = visits
    }
}

@MainActor public protocol BrowserLibraryProviding: AnyObject {
    func loadLibrary(profileID: UUID) async throws -> BrowserProfileLibrary?
    func saveLibrary(profileID: UUID, library: BrowserProfileLibrary) async throws
}

@MainActor public protocol BrowserProfileManaging: AnyObject {
    func deleteProfile(profileID: UUID) async throws
    func restoredPages(profileID: UUID) async throws -> [EnginePageSnapshot]
}

@MainActor public protocol BrowserNetworkRouting: AnyObject {
    func applyNetworkRoute(profileID: UUID, route: BrowserNetworkRoute, endpoint: RouteEndpoint?) async throws -> NetworkRouteStatus
    func currentRouteStatus(profileID: UUID) -> NetworkRouteStatus
    func observedExitIP(profileID: UUID) -> String?
}

@MainActor public protocol BrowserProxyCredentialStoring: AnyObject {
    func saveProxyCredential(endpointID: String, username: String, password: String) throws
    func deleteProxyCredential(endpointID: String) throws
}

public struct BrowserCredentialSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let profileID: UUID
    public let origin: String
    public let username: String
    public let label: String

    public init(id: String, profileID: UUID, origin: String, username: String, label: String) {
        self.id = id
        self.profileID = profileID
        self.origin = origin
        self.username = username
        self.label = label
    }
}

@MainActor public protocol BrowserCredentialVaultProviding: AnyObject {
    func savedCredentials(profileID: UUID, origin: String?) async throws -> [BrowserCredentialSummary]
    func saveCredential(profileID: UUID, origin: String, username: String, password: String) async throws
    func deleteCredential(profileID: UUID, credentialID: String) async throws
    func fillCredential(pageID: String, credentialID: String, fillUsername: Bool) async throws
    /// The one way a saved password comes back, for a person to read or copy.
    /// Filling a form is not this: that goes through `fillCredential`, and the
    /// secret never leaves the engine. Callers prove it is the person the Mac
    /// belongs to first — `AetherLocalAuth.prove` — as Safari asks before it
    /// shows one.
    func savedPassword(profileID: UUID, credentialID: String) async throws -> String
}

public enum PasskeyAuthorizationState: String, Sendable, Equatable, CaseIterable {
    case authorized
    case denied
    case notDetermined
    case unavailable

    public var label: String {
        switch self {
        case .authorized: "Allowed"
        case .denied: "Denied in System Settings"
        case .notDetermined: "Not requested yet"
        case .unavailable: "Not available"
        }
    }
}

@MainActor public protocol BrowserPasskeyCapability: AnyObject {
    var passkeyDeviceConfigured: Bool { get }
    var passkeyLocalAuthAvailable: Bool { get }
    func passkeyAuthorizationState() -> PasskeyAuthorizationState
    func requestPasskeyAuthorization() async -> PasskeyAuthorizationState
}

@MainActor public protocol BrowserAutomationProviding: AnyObject {
    func authorizeAutomation(profileID: UUID) async throws -> String
}

public enum EngineSessionState: String, Sendable, Equatable, CaseIterable {
    case notLoaded
    case loading
    case navigated
    case reauthenticationRequired
    case failed

    public var label: String {
        switch self {
        case .notLoaded: "Not loaded"
        case .loading: "Loading"
        case .navigated: "Loaded"
        case .reauthenticationRequired: "Reauthentication required"
        case .failed: "Failed"
        }
    }

    public var detail: String {
        switch self {
        case .notLoaded: "This tab has not navigated yet."
        case .loading: "The page is still loading."
        case .navigated: "The page loaded. This does not prove anyone is signed in."
        case .reauthenticationRequired: "The site refused the session or redirected to sign in. Nothing was cleared; sign in normally."
        case .failed: "Navigation failed before the site could respond."
        }
    }
}

@MainActor public protocol BrowserSessionStateProviding: AnyObject {
    func sessionState(pageID: String) async -> EngineSessionState
}

/// WebKit's own inspector on the live page — the same one the right-click
/// menu's Inspect Element opens, from the menu bar and its keys.
@MainActor public protocol BrowserWebInspectorProviding: AnyObject {
    func toggleWebInspector(pageID: String) async throws
    func showWebConsole(pageID: String) async throws
    func pickWebElement(pageID: String) async throws
}
