import Foundation

public enum BrowserSearchCandidateKind: String, Sendable, Hashable {
    case navigate
    case completion
    case history
    case bookmark
    case openTab
    case web
    case google
}

public struct BrowserSearchCandidate: Sendable, Identifiable, Hashable {
    public let id: String
    public let kind: BrowserSearchCandidateKind
    public let title: String
    public let subtitle: String
    public let url: String?
    public let score: Double
    public let relevance: Double

    public init(id: String, kind: BrowserSearchCandidateKind, title: String, subtitle: String = "",
                url: String? = nil, score: Double = 0, relevance: Double = 0) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.score = score
        self.relevance = relevance
    }
}

public struct BrowserSearchOutcome: Sendable {
    public let query: String
    public let intent: String
    public let confidence: Double
    public let degraded: Bool
    public let retrievalCount: Int
    public let model: String?
    public let candidates: [BrowserSearchCandidate]

    public init(query: String, intent: String, confidence: Double, degraded: Bool,
                retrievalCount: Int, model: String?, candidates: [BrowserSearchCandidate]) {
        self.query = query
        self.intent = intent
        self.confidence = confidence
        self.degraded = degraded
        self.retrievalCount = retrievalCount
        self.model = model
        self.candidates = candidates
    }
}

public struct BrowserSearchSignal: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case history
        case bookmark
        case openTab
        case shortcut
    }

    public let kind: Kind
    public let title: String
    public let url: String
    public let visits: Int
    public let lastVisit: Double

    public init(kind: Kind, title: String, url: String, visits: Int = 1, lastVisit: Double = 0) {
        self.kind = kind
        self.title = title
        self.url = url
        self.visits = visits
        self.lastVisit = lastVisit
    }
}

public struct BrowserSearchMemory: Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let url: String
    public let excerpt: String

    public init(id: UUID, title: String, url: String, excerpt: String) {
        self.id = id
        self.title = title
        self.url = url
        self.excerpt = excerpt
    }
}

@MainActor
public protocol BrowserNativeSearchIntelligence: AnyObject {
    func rankHistory(query: String, pages: [BrowserSearchMemory]) async -> [UUID]
}

@MainActor
public protocol BrowserPageTextProviding: AnyObject {
    func indexablePageText(pageID: String) async throws -> String
}

@MainActor
public protocol BrowserSearchIntelligence: AnyObject {
    func jevSearch(query: String, local: [BrowserSearchSignal]) async throws -> BrowserSearchOutcome
    func jevCompletions(prefix: String, local: [BrowserSearchSignal], limit: Int) async throws
        -> [BrowserSearchCandidate]
    func jevIsConfigured() async -> Bool
    func jevUpdateKeys(typeSafeKey: String, search1APIKey: String) async
}
