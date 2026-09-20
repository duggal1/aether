import Foundation

public struct BrowserArchive: Codable {
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

public enum BrowserPersistence {
    private static let key = "aether.human.archive.v1"
    public static func load(defaults: UserDefaults = .standard) -> BrowserArchive {
        guard let data = defaults.data(forKey: key), let archive = try? JSONDecoder().decode(BrowserArchive.self, from: data) else { return BrowserArchive() }
        return archive
    }
    public static func save(_ archive: BrowserArchive, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: key) }
    }
}
