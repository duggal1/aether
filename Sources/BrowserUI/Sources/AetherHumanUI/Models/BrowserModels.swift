import Foundation

public enum TabArrangement: String, Codable, CaseIterable, Identifiable, Sendable {
    case top = "Top tabs"
    case sidebar = "Sidebar"
    public var id: String { rawValue }
}

public enum TabLoadState: Equatable {
    case newTab
    case loading
    case ready
    case search(String)
    case failed(String)
}

public struct BrowserProfile: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var symbol: String
    public var colorIndex: Int
    public var isIncognito: Bool
    public init(id: UUID = UUID(), name: String, symbol: String = "circle.fill", colorIndex: Int = -1,
                isIncognito: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.isIncognito = isIncognito
        self.createdAt = Date()
    }
}

extension BrowserProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, symbol, colorIndex, isIncognito
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "circle.fill"
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? -1
        isIncognito = try container.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(colorIndex, forKey: .colorIndex)
        try container.encode(isIncognito, forKey: .isIncognito)
    }
}

public struct BrowserShortcut: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public var isPinned: Bool
    public init(id: UUID = UUID(), name: String, url: String, isPinned: Bool = false) {
        self.id = id; self.name = name; self.url = url; self.isPinned = isPinned
    }
    enum CodingKeys: String, CodingKey { case id, name, url, isPinned }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(isPinned, forKey: .isPinned)
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
    public var excerpt: String?
    public init(profileID: UUID, title: String, url: String) {
        id = UUID(); self.profileID = profileID; self.title = title; self.url = url; visitedAt = Date()
        excerpt = nil
    }
}

public struct ClosedTab: Identifiable {
    public let id = UUID()
    public let title: String
    public let url: String?
    public let profileID: UUID
    public let closedAt = Date()
}
