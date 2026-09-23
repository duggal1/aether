import Foundation

public struct BrowserArchive: Codable, Sendable {
    public var profiles: [BrowserProfile]
    public var bookmarks: [BrowserBookmark]
    public var visits: [BrowserVisit]
    public var shortcuts: [BrowserShortcut]
    public var defaultProfileID: UUID?
    public init(profiles: [BrowserProfile] = [], bookmarks: [BrowserBookmark] = [],
                visits: [BrowserVisit] = [], shortcuts: [BrowserShortcut] = [], defaultProfileID: UUID? = nil) {
        self.profiles = profiles; self.bookmarks = bookmarks; self.visits = visits
        self.shortcuts = shortcuts; self.defaultProfileID = defaultProfileID
    }
}

public struct BrowserSessionTab: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var profileID: UUID
    public var title: String
    public var url: String?
    public var isPinned: Bool
    public init(id: UUID, profileID: UUID, title: String, url: String?, isPinned: Bool) {
        self.id = id; self.profileID = profileID; self.title = title
        self.url = url; self.isPinned = isPinned
    }
    @MainActor public init?(tab: BrowserTab) {
        let isSearch: Bool
        if case .search = tab.loadState { isSearch = true } else { isSearch = false }
        guard !isSearch else { return nil }
        id = tab.id; profileID = tab.profileID; title = tab.title
        url = tab.url; isPinned = tab.isPinned
    }
}

public struct BrowserSessionWindow: Codable, Equatable, Sendable {
    public var id: UUID
    public var activeProfileID: UUID
    public var arrangement: TabArrangement
    public var sidebarCollapsed: Bool
    public var selectedByProfile: [UUID: UUID]
    public var tabs: [BrowserSessionTab]
    public init(id: UUID, activeProfileID: UUID, arrangement: TabArrangement,
                sidebarCollapsed: Bool, selectedByProfile: [UUID: UUID],
                tabs: [BrowserSessionTab]) {
        self.id = id; self.activeProfileID = activeProfileID; self.arrangement = arrangement
        self.sidebarCollapsed = sidebarCollapsed; self.selectedByProfile = selectedByProfile
        self.tabs = tabs
    }
}

public struct BrowserSessionArchive: Codable, Equatable, Sendable {
    public var windows: [BrowserSessionWindow]
    public var savedAt: Date
    public init(windows: [BrowserSessionWindow] = [], savedAt: Date = Date()) {
        self.windows = windows; self.savedAt = savedAt
    }
}

public enum BrowserPersistence {
    private static let key = "aether.human.archive.v1"
    private static let sessionKey = "aether.human.session.v1"
    public static func load(defaults: UserDefaults = .standard) -> BrowserArchive {
        guard let data = defaults.data(forKey: key), let archive = try? JSONDecoder().decode(BrowserArchive.self, from: data) else { return BrowserArchive() }
        return archive
    }
    public static func save(_ archive: BrowserArchive, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: key) }
    }
    public static func save(_ archive: BrowserArchive, session: BrowserSessionArchive,
                            defaults: UserDefaults = .standard) {
        save(archive, defaults: defaults)
        saveSession(session, defaults: defaults)
    }
    public static func loadSession(defaults: UserDefaults = .standard) -> BrowserSessionArchive {
        guard let data = defaults.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(BrowserSessionArchive.self, from: data)
        else { return BrowserSessionArchive() }
        return session
    }
    public static func saveSession(_ session: BrowserSessionArchive, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: sessionKey) }
    }
}
