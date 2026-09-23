import Foundation

public struct OmniboxSuggestion: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case open
        case completion
        case tab
        case bookmark
        case history
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let host: String?
    public let url: String?
    public let completion: String?
    public let tabID: UUID?
    public let matched: Int
    public let score: Double

    public init(kind: Kind, title: String, host: String? = nil, url: String? = nil,
                completion: String? = nil, tabID: UUID? = nil, matched: Int = 0, score: Double = 0) {
        self.kind = kind
        self.title = title
        self.host = host
        self.url = url
        self.completion = completion
        self.tabID = tabID
        self.matched = matched
        self.score = score
        id = kind.rawValue + "|" + (completion ?? url ?? title).lowercased()
    }

    public var completionText: String? { completion ?? url }
}

struct OmniboxTabSource: Sendable {
    let id: UUID
    let title: String
    let url: String?

    init(id: UUID, title: String, url: String?) {
        self.id = id
        self.title = title
        self.url = url
    }
}

enum OmniboxSuggestionBuilder {
    static let visitScan = 800

    static func rows(prefix raw: String, provider: SearchProvider, tabs: [OmniboxTabSource],
                     bookmarks: [BrowserBookmark], visits: [BrowserVisit],
                     completions: [String], accepted: [String: Int], rememberedSite: URL? = nil,
                     limit: Int = 9) -> [OmniboxSuggestion] {
        let prefix = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return [] }
        let needle = prefix.lowercased()
        var rows: [OmniboxSuggestion] = [intentRow(prefix: prefix, provider: provider,
                                                   rememberedSite: rememberedSite)]
        var seenHosts = Set<String>()
        var seenTitles = Set<String>()

        func accept(url: String?, title: String) -> Bool {
            if let url, let host = URL(string: url)?.host?.lowercased() {
                guard seenHosts.insert(host).inserted else { return false }
            }
            return seenTitles.insert(title.lowercased()).inserted
        }

        for tab in tabs {
            guard let score = matchScore(needle: needle, host: host(of: tab.url), text: tab.title),
                  accept(url: tab.url, title: tab.title) else { continue }
            rows.append(OmniboxSuggestion(kind: .tab, title: tab.title, host: host(of: tab.url),
                                          url: tab.url, tabID: tab.id, matched: matched(needle, tab.title),
                                          score: score + 30 + boost(needle, tab.title, accepted)))
        }
        for bookmark in bookmarks {
            guard let score = matchScore(needle: needle, host: host(of: bookmark.url), text: bookmark.title),
                  accept(url: bookmark.url, title: bookmark.title) else { continue }
            rows.append(OmniboxSuggestion(kind: .bookmark, title: bookmark.title, host: host(of: bookmark.url),
                                          url: bookmark.url, matched: matched(needle, bookmark.title),
                                          score: score + 18 + boost(needle, bookmark.title, accepted)))
        }
        for visit in visits.prefix(visitScan) {
            guard let score = matchScore(needle: needle, host: host(of: visit.url), text: visit.title),
                  accept(url: visit.url, title: visit.title) else { continue }
            rows.append(OmniboxSuggestion(kind: .history, title: visit.title, host: host(of: visit.url),
                                          url: visit.url, matched: matched(needle, visit.title),
                                          score: score + frecency(visit.visitedAt) + boost(needle, visit.title, accepted)))
        }
        for (index, completion) in completions.enumerated() {
            guard accept(url: nil, title: completion) else { continue }
            rows.append(OmniboxSuggestion(kind: .completion, title: completion,
                                          completion: completion, matched: needle.count,
                                          score: 240 - Double(index) + boost(needle, completion, accepted)))
        }
        let head = rows.prefix(1)
        let tail = rows.dropFirst().sorted { left, right in
            left.score == right.score ? left.title.count < right.title.count : left.score > right.score
        }
        return Array((head + tail).prefix(limit))
    }

    static func intentRow(prefix: String, provider: SearchProvider,
                          rememberedSite: URL? = nil) -> OmniboxSuggestion {
        if let address = addressIntent(prefix) {
            return OmniboxSuggestion(kind: .open, title: address.title, url: address.url,
                                     matched: prefix.count, score: .infinity)
        }
        if let rememberedSite, let host = rememberedSite.host {
            return OmniboxSuggestion(kind: .open, title: "Open \(host)", url: rememberedSite.absoluteString,
                                     matched: prefix.count, score: .infinity)
        }
        return OmniboxSuggestion(kind: .open, title: "Search \(provider.searchName) for “\(prefix)”",
                                 completion: prefix, matched: prefix.count, score: .infinity)
    }

    private static func addressIntent(_ prefix: String) -> (title: String, url: String)? {
        guard !prefix.contains(where: { $0.isWhitespace }), !prefix.contains("@") else { return nil }
        let scheme = ["https://", "http://"].first { prefix.lowercased().hasPrefix($0) }
        if scheme != nil {
            guard let url = URL(string: prefix),
                  let urlScheme = url.scheme?.lowercased(), ["https", "http"].contains(urlScheme),
                  url.host != nil, url.user == nil
            else { return nil }
            return ("Open \(url.absoluteString)", url.absoluteString)
        }
        guard let direct = AddressResolver.directURL(prefix) else { return nil }
        let host = URL(string: direct.absoluteString)?.host ?? direct.absoluteString
        return ("Open \(host)", direct.absoluteString)
    }

    // What Enter should open. A typed address always wins over a hover or a
    // provider completion: a valid website address must never be routed into a
    // search merely because it lacked an explicit scheme. A deliberate selection
    // of a library row (tab, bookmark, history) is still honoured.
    static func commitTarget(draft: String, selected: OmniboxSuggestion?,
                             rememberedSite: URL? = nil) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = AddressResolver.directURL(trimmed) {
            if let selected, [.tab, .bookmark, .history].contains(selected.kind),
               let url = selected.url {
                return url
            }
            return direct.absoluteString
        }
        if let selected, [.tab, .bookmark, .history].contains(selected.kind),
           let url = selected.url { return url }
        if let rememberedSite { return rememberedSite.absoluteString }
        guard let selected else { return nil }
        return selected.url ?? selected.completionText ?? trimmed
    }

    static func matchScore(needle: String, host: String?, text: String) -> Double? {
        if let host {
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if bare.hasPrefix(needle) || host.hasPrefix(needle) { return 300 }
        }
        let title = text.lowercased()
        if title.hasPrefix(needle) { return 260 }
        if title.contains(needle) || (host?.contains(needle) == true) { return 120 }
        return nil
    }

    static func matched(_ needle: String, _ text: String) -> Int {
        guard text.lowercased().hasPrefix(needle) else { return 0 }
        return min(needle.count, text.count)
    }

    static func boost(_ needle: String, _ text: String, _ accepted: [String: Int]) -> Double {
        var total = Double(min(accepted[text.lowercased()] ?? 0, 4)) * 8
        if let prefixBoost = accepted["#" + needle] { total += Double(min(prefixBoost, 3)) * 14 }
        return total
    }

    static func frecency(_ date: Date) -> Double {
        let age = max(0, Date().timeIntervalSince(date))
        let halfLife: Double = 60 * 60 * 24 * 7
        return 24 * pow(0.5, age / halfLife)
    }

    static func host(of url: String?) -> String? {
        guard let url, let host = URL(string: url)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
