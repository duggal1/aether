import Foundation

public enum SearchProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case google = "Google"
    case googleAI = "Google AI Mode"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case brave = "Brave"
    case qwant = "Qwant"
    case ecosia = "Ecosia"
    case startpage = "Startpage"
    case kagi = "Kagi"
    case custom = "Custom"
    case jev = "Jev"
    public var id: String { rawValue }
    public var searchName: String {
        switch self {
        case .google, .googleAI: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .kagi: "Kagi"
        case .brave: "Brave"
        case .qwant: "Qwant"
        case .custom: customHost ?? "Custom"
        case .jev: "Jev"
        }
    }
    /// Search-port: host of custom template for display. Set via resolve path.
    public static var customHost: String? = nil
    public var customHost: String? { Self.customHost }
    public var homepage: URL {
        switch self {
        case .google: URL(string: "https://www.google.com/")!
        case .googleAI: URL(string: "https://www.google.com/ai")!
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .bing: URL(string: "https://www.bing.com/")!
        case .ecosia: URL(string: "https://www.ecosia.org/")!
        case .startpage: URL(string: "https://www.startpage.com/")!
        case .kagi: URL(string: "https://kagi.com/")!
        case .brave: URL(string: "https://search.brave.com/")!
        case .qwant: URL(string: "https://www.qwant.com/")!
        case .custom: URL(string: "https://www.google.com/")!
        case .jev: URL(string: "https://s1.dev")!
        }
    }
    public var searchEndpoint: URL? {
        switch self {
        case .google, .googleAI: URL(string: "https://www.google.com/search")!
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .bing: URL(string: "https://www.bing.com/search")!
        case .ecosia: URL(string: "https://www.ecosia.org/search")!
        case .startpage: URL(string: "https://www.startpage.com/sp/search")!
        case .kagi: URL(string: "https://kagi.com/search")!
        case .brave: URL(string: "https://search.brave.com/search")!
        case .qwant: URL(string: "https://www.qwant.com/")!
        case .custom, .jev: nil
        }
    }
    /// Search-port: Engine.template equivalent — %s templates for all providers.
    public func template(custom: String) -> String {
        switch self {
        case .google, .googleAI: return "https://www.google.com/search?q=%s"
        case .duckDuckGo: return "https://duckduckgo.com/?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .ecosia: return "https://www.ecosia.org/search?q=%s"
        case .startpage: return "https://www.startpage.com/sp/search?query=%s"
        case .kagi: return "https://kagi.com/search?q=%s"
        case .brave: return "https://search.brave.com/search?q=%s"
        case .qwant: return "https://www.qwant.com/?q=%s"
        case .custom:
            let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.acceptsTemplate(t) ? t : "https://www.google.com/search?q=%s"
        case .jev: return "https://www.google.com/search?q=%s"
        }
    }
    public static func url(for text: String, template: String) -> URL? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mark = "SEARCHWORDSGOHERE"
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard !words.isEmpty,
              let escaped = words.addingPercentEncoding(withAllowedCharacters: unreserved),
              let base = URL(string: template.replacingOccurrences(of: "%s", with: mark))?.absoluteString
        else { return nil }
        return URL(string: base.replacingOccurrences(of: mark, with: escaped))
    }
    public static func acceptsTemplate(_ template: String) -> Bool {
        let t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains("%s"),
              let a = URLComponents(string: t.replacingOccurrences(of: "%s", with: "a")),
              let b = URLComponents(string: t.replacingOccurrences(of: "%s", with: "b")),
              let scheme = a.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = a.host, !host.isEmpty, host == b.host
        else { return false }
        return true
    }
    public var usesIntelligence: Bool { self == .jev }
    public var endpoint: URL? { searchEndpoint }
    public func searchURL(for query: String, locality: SearchLocality? = nil,
                          localityTerms: Bool = false, customTemplate: String = "") -> URL? {
        // Search-port: custom %s template path (Engine.url equivalent).
        if self == .custom {
            var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if localityTerms, let locality { text += " " + locality.city + ", " + locality.regionCode }
            return Self.url(for: text, template: template(custom: customTemplate))
        }
        // Search-port: startpage uses `query`, others use `q`.
        if self == .startpage {
            let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, let searchEndpoint,
                  var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)
            else { return nil }
            components.fragment = nil
            var text = cleaned
            if localityTerms, let locality { text += " " + locality.city + ", " + locality.regionCode }
            components.queryItems = [URLQueryItem(name: "query", value: text)]
            return components.url
        }
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
            case .ecosia, .startpage, .kagi, .brave, .qwant, .custom, .jev:
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

        func siteURL(_ rawURL: String) -> (url: URL, score: Int)? {
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host?.lowercased(), url.user == nil else { return nil }
            let labels = host.split(separator: ".").map(String.init)
            let siteLabels = labels.first == "www" ? Array(labels.dropFirst()) : labels
            guard siteLabels.count >= 2 else { return nil }
            let rootName = siteLabels[siteLabels.count - 2]
            let names = [siteLabels[0], rootName].filter { !genericNames.contains($0) }
            let score: Int
            if names.contains(query) { score = 3 }
            else if names.contains(where: { $0.hasPrefix(query) }) { score = 2 }
            else if query.count >= 3 && names.contains(where: { oneEditApart(query, $0) }) { score = 1 }
            else { return nil }
            var site = URLComponents()
            site.scheme = scheme
            site.host = host
            site.port = url.port
            site.path = "/"
            guard let siteURL = site.url else { return nil }
            return (siteURL, score)
        }

        var best: (url: URL, score: Int)?
        for visit in visits {
            guard let candidate = siteURL(visit.url) else { continue }
            if candidate.score == 3 { return candidate.url }
            if let current = best {
                if candidate.score > current.score { best = candidate }
            } else { best = candidate }
        }
        for bookmark in bookmarks {
            guard let candidate = siteURL(bookmark.url) else { continue }
            if candidate.score == 3 { return candidate.url }
            if let current = best {
                if candidate.score > current.score { best = candidate }
            } else { best = candidate }
        }
        return best?.url
    }

    private static func oneEditApart(_ typed: String, _ name: String) -> Bool {
        guard abs(typed.count - name.count) <= 1 else { return false }
        let lhs = Array(typed)
        let rhs = Array(name)
        var left = 0
        var right = 0
        var edits = 0
        while left < lhs.count && right < rhs.count {
            if lhs[left] == rhs[right] {
                left += 1
                right += 1
            } else {
                edits += 1
                guard edits <= 1 else { return false }
                if lhs.count >= rhs.count { left += 1 }
                if lhs.count <= rhs.count { right += 1 }
            }
        }
        return edits + (lhs.count - left) + (rhs.count - right) == 1
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
                               localityTerms: Bool = false, customTemplate: String = "") -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = directURL(text) { return url }
        return provider.searchURL(for: text, locality: locality, localityTerms: localityTerms, customTemplate: customTemplate)
    }
}
