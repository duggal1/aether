import AppKit
import Foundation
import UniformTypeIdentifiers

public enum BookmarkTransfer {
    public static func export(_ bookmarks: [BrowserBookmark], profileName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Aether-\(profileName)-Bookmarks.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let records = bookmarks.map { ExportedBookmark(title: $0.title, url: $0.url, folder: $0.folder) }
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
        return url
    }
    public static func importBookmarks() throws -> [ExportedBookmark]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try Data(contentsOf: url)
        let items = try JSONDecoder().decode([ExportedBookmark].self, from: data)
        return items.filter { item in
            let url = URL(string: item.url)
            return ["https", "http"].contains(url?.scheme?.lowercased() ?? "") && url?.host != nil
        }
    }
}

public struct ExportedBookmark: Codable {
    public let title: String
    public let url: String
    public let folder: String
    public init(title: String, url: String, folder: String) {
        self.title = title; self.url = url; self.folder = folder
    }
}
