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
    public func searchURL(for query: String) -> URL? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let searchEndpoint,
              var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)
        else { return nil }
        components.fragment = nil
        var items: [URLQueryItem] = []
        if self == .googleAI { items.append(URLQueryItem(name: "udm", value: "50")) }
        items.append(URLQueryItem(name: "q", value: cleaned))
        components.queryItems = items
        return components.url
    }
}

public enum AddressResolver {
    public static func directURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["https", "http"].contains(scheme), url.host != nil { return url }
        guard !text.contains(where: \.isWhitespace) else { return nil }
        if text == "localhost" || text.hasPrefix("localhost:") || text.hasPrefix("127.0.0.1") {
            return URL(string: "http://" + text)
        }
        if text.contains("."), let url = URL(string: "https://" + text), url.host != nil { return url }
        return nil
    }

    public static func resolve(_ raw: String, provider: SearchProvider = .google) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = directURL(text) { return url }
        return provider.searchURL(for: text)
    }
}
