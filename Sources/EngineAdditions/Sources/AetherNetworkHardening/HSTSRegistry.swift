import Foundation

public struct HSTSRule: Sendable, Codable, Equatable {
    public let host: String
    public let expiresAt: Date
    public let includesSubdomains: Bool
}

public actor HSTSRegistry {
    private var rules: [String: HSTSRule] = [:]
    private let maxAge: TimeInterval

    public init(maxAge: TimeInterval = 63_072_000) { self.maxAge = max(0, maxAge) }

    public func observe(url: URL, headers: [String: String], now: Date = Date()) {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else { return }
        guard let header = headers.first(where: { $0.key.lowercased() == "strict-transport-security" })?.value else { return }
        let directives = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let rawAge = directives.first(where: { $0.hasPrefix("max-age=") })?.dropFirst(8), let age = TimeInterval(rawAge.trimmingCharacters(in: CharacterSet(charactersIn: "\""))), age.isFinite, age >= 0 else { return }
        if age == 0 { rules.removeValue(forKey: host); return }
        rules[host] = HSTSRule(host: host, expiresAt: now.addingTimeInterval(min(maxAge, age)), includesSubdomains: directives.contains("includesubdomains"))
    }

    public func upgrade(_ url: URL, now: Date = Date()) -> URL {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased(), applies(host: host, now: now) else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        if components.port == 80 { components.port = 443 }
        return components.url ?? url
    }

    public func snapshot(now: Date = Date()) -> [HSTSRule] {
        rules.values.filter { $0.expiresAt > now }.sorted { $0.host < $1.host }
    }

    private func applies(host: String, now: Date) -> Bool {
        if let rule = rules[host], rule.expiresAt > now { return true }
        let labels = host.split(separator: ".")
        guard labels.count > 1 else { return false }
        for index in 1..<labels.count {
            let parent = labels[index...].joined(separator: ".")
            if let rule = rules[parent], rule.expiresAt > now, rule.includesSubdomains { return true }
        }
        return false
    }
}
