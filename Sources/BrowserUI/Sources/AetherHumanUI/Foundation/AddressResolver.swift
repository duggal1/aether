import Foundation

public enum SearchProvider: String, CaseIterable, Codable, Identifiable {
    case google = "Google"
    case googleAI = "Google AI Mode"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case brave = "Brave"
    public var id: String { rawValue }
    public var template: String {
        switch self {
        case .google: "https://www.google.com/search?q="
        case .googleAI: "https://www.google.com/search?udm=50&q="
        case .duckDuckGo: "https://duckduckgo.com/?q="
        case .bing: "https://www.bing.com/search?q="
        case .brave: "https://search.brave.com/search?q="
        }
    }
    public var searchName: String {
        switch self {
        case .google, .googleAI: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave"
        }
    }
    public var endpoint: URL? { URL(string: template) }
}

public enum AddressResolver {
    public static func resolve(_ raw: String, provider: SearchProvider = .google) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil { return url }
        if !text.contains(where: \.isWhitespace) {
            if text == "localhost" || text.hasPrefix("localhost:") || text.hasPrefix("127.0.0.1") {
                return URL(string: "http://" + text)
            }
            if text.contains("."), let url = URL(string: "https://" + text), url.host != nil { return url }
        }
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+?#"))) else { return nil }
        return URL(string: provider.template + encoded)
    }
}
