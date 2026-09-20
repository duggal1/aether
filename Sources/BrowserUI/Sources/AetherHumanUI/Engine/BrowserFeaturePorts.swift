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

@MainActor public protocol BrowserAutomationProviding: AnyObject {
    func authorizeAutomation(profileID: UUID) async throws -> String
}
