import Foundation

public enum SearchProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case google = "Google"
    case googleAI = "Google AI Mode"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case brave = "Brave"
    case jev = "Jev"
    public var id: String { rawValue }
    public var searchName: String {
        switch self {
        case .google, .googleAI: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave"
        case .jev: "Jev"
        }
    }
    public var homepage: URL {
        switch self {
        case .google: URL(string: "https://www.google.com/")!
        case .googleAI: URL(string: "https://www.google.com/ai")!
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .bing: URL(string: "https://www.bing.com/")!
        case .brave: URL(string: "https://search.brave.com/")!
        case .jev: URL(string: "https://s1.dev")!
        }
    }
    public var searchEndpoint: URL? {
        switch self {
        case .google, .googleAI: URL(string: "https://www.google.com/search")!
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .bing: URL(string: "https://www.bing.com/search")!
        case .brave: URL(string: "https://search.brave.com/search")!
        case .jev: nil
        }
    }
    public var usesIntelligence: Bool { self == .jev }
    public var endpoint: URL? { searchEndpoint }
    public func searchURL(for query: String, locality: SearchLocality? = nil,
                          localityTerms: Bool = false) -> URL? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let searchEndpoint,
              var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)
        else { return nil }
        components.fragment = nil
        var text = cleaned
        if localityTerms, let locality {
            text += " " + locality.city + ", " + locality.regionCode
        }
        var items: [URLQueryItem] = []
        if self == .googleAI { items.append(URLQueryItem(name: "udm", value: "50")) }
        if let locality {
            switch self {
            case .google, .googleAI:
                items.append(URLQueryItem(name: "gl", value: locality.countryCode.lowercased()))
                items.append(URLQueryItem(name: "hl", value: "en"))
            case .bing:
                items.append(URLQueryItem(name: "setmkt", value: "en-US"))
                items.append(URLQueryItem(name: "setlang", value: "en-US"))
            case .duckDuckGo:
                items.append(URLQueryItem(name: "kl", value: "us-en"))
            case .brave, .jev:
                break
            }
        }
        items.append(URLQueryItem(name: "q", value: text))
        components.queryItems = items
        return components.url
    }
}

public enum AddressResolver {
    static func rememberedSite(_ raw: String, visits: [BrowserVisit],
                               bookmarks: [BrowserBookmark]) -> URL? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty, query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              directURL(query) == nil else { return nil }
        let genericNames: Set<String> = ["co", "com", "net", "org", "gov", "ac", "edu"]

        func siteURL(_ rawURL: String) -> URL? {
            guard rawURL.lowercased().contains(query) else { return nil }
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host?.lowercased(), url.user == nil else { return nil }
            let labels = host.split(separator: ".").map(String.init)
            let siteLabels = labels.first == "www" ? Array(labels.dropFirst()) : labels
            guard siteLabels.count >= 2 else { return nil }
            let rootName = siteLabels[siteLabels.count - 2]
            guard siteLabels[0] == query || (rootName == query && !genericNames.contains(query))
            else { return nil }
            var site = URLComponents()
            site.scheme = scheme
            site.host = host
            site.port = url.port
            site.path = "/"
            return site.url
        }

        for visit in visits {
            if let site = siteURL(visit.url) { return site }
        }
        for bookmark in bookmarks {
            if let site = siteURL(bookmark.url) { return site }
        }
        return nil
    }

    public static func directURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["https", "http"].contains(scheme), url.host != nil, url.user == nil { return url }
        guard !text.contains("://"), !text.contains(where: \.isWhitespace), !text.contains("@") else { return nil }
        if isLocalhost(text) { return URL(string: "http://" + text) }
        guard let candidate = URL(string: "https://" + text),
              let host = candidate.host, !host.isEmpty, candidate.user == nil else { return nil }
        if host.contains(":") || isIPv4(host) { return URL(string: "http://" + text) }
        guard isDomain(host) else { return nil }
        return candidate
    }

    static func isLocalhost(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower == "localhost"
            || lower.hasPrefix("localhost:")
            || lower.hasPrefix("localhost/")
            || lower.hasPrefix("localhost?")
            || lower.hasPrefix("localhost#")
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isNumber }),
                  let value = Int(part), value <= 255
            else { return false }
            if part.count > 1 && part.hasPrefix("0") { return false }
        }
        return true
    }

    static func isDomain(_ host: String) -> Bool {
        let clean = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard clean.count <= 253 else { return false }
        let labels = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  let first = label.first, let last = label.last,
                  first.isLetter || first.isNumber, last.isLetter || last.isNumber,
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else { return false }
        }
        guard let tld = labels.last else { return false }
        if tld.lowercased().hasPrefix("xn--") { return tld.count > 4 }
        return tld.count >= 2 && tld.allSatisfy({ $0.isLetter })
    }

    public static func resolve(_ raw: String, provider: SearchProvider = .google,
                               locality: SearchLocality? = nil,
                               localityTerms: Bool = false) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = directURL(text) { return url }
        return provider.searchURL(for: text, locality: locality, localityTerms: localityTerms)
    }
}
