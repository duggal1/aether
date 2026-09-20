import Foundation

public enum TabArrangement: String, Codable, CaseIterable, Identifiable {
    case top = "Top tabs"
    case sidebar = "Sidebar"
    public var id: String { rawValue }
}

public enum TabLoadState: Equatable {
    case newTab
    case loading
    case ready
    case failed(String)
}

public struct BrowserProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var symbol: String
    public init(id: UUID = UUID(), name: String, symbol: String = "circle.fill") {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.createdAt = Date()
    }
}

public struct BrowserShortcut: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public init(id: UUID = UUID(), name: String, url: String) {
        self.id = id; self.name = name; self.url = url
    }
}

public struct BrowserBookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var profileID: UUID
    public var title: String
    public var url: String
    public var folder: String
    public var createdAt: Date
    public init(id: UUID = UUID(), profileID: UUID, title: String, url: String, folder: String = "Favorites") {
        self.id = id; self.profileID = profileID; self.title = title; self.url = url; self.folder = folder
        self.createdAt = Date()
    }
}

public struct BrowserVisit: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var profileID: UUID
    public var title: String
    public var url: String
    public var visitedAt: Date
    public init(profileID: UUID, title: String, url: String) {
        id = UUID(); self.profileID = profileID; self.title = title; self.url = url; visitedAt = Date()
    }
}

public struct ClosedTab: Identifiable {
    public let id = UUID()
    public let title: String
    public let url: String?
    public let profileID: UUID
    public let closedAt = Date()
}
