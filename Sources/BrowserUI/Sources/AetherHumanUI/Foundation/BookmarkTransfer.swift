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
        panel.allowedContentTypes = [.json, .html]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if url.pathExtension.lowercased() == "html" || url.pathExtension.lowercased() == "htm" {
            return try importNetscapeHTML(url)
        }
        let data = try Data(contentsOf: url)
        let items = try JSONDecoder().decode([ExportedBookmark].self, from: data)
        return items.filter { item in
            let url = URL(string: item.url)
            return ["https", "http"].contains(url?.scheme?.lowercased() ?? "") && url?.host != nil
        }
    }
    /// Search-port: Chrome/Arc/Brave `.html` one-click import (Netscape format).
    public static func importNetscapeHTML(_ url: URL) throws -> [ExportedBookmark] {
        let html = try String(contentsOf: url, encoding: .utf8)
        // <A HREF="url" ...>title</A> — tolerant, case-insensitive.
        let pattern = #"<a\s[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var out: [ExportedBookmark] = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges == 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            var title = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            guard let parsed = URL(string: href),
                  ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                  parsed.host != nil, !title.isEmpty || !href.isEmpty else { continue }
            out.append(ExportedBookmark(title: title.isEmpty ? (parsed.host ?? href) : title, url: href, folder: "Imported"))
            if out.count >= 5000 { break }
        }
        return out
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
