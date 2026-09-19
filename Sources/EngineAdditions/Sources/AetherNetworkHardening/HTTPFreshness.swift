import Foundation

public struct HTTPFreshness: Sendable, Equatable {
    public let storable: Bool
    public let requiresValidation: Bool
    public let maxAge: TimeInterval?
    public let staleWhileRevalidate: TimeInterval
    public let etag: String?
    public let lastModified: String?
    public let vary: [String]

    public init(headers: [String: String], requestHasAuthorization: Bool = false) {
        let normalized = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, latest in latest })
        let directives = HTTPFreshness.parseDirectives(normalized["cache-control"] ?? "")
        storable = !(normalized["vary"] ?? "").split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "*" }) && !directives.keys.contains("no-store") && !directives.keys.contains("private") && (!requestHasAuthorization || directives.keys.contains("public") || directives.keys.contains("s-maxage"))
        requiresValidation = directives.keys.contains("no-cache") || directives.keys.contains("must-revalidate")
        maxAge = HTTPFreshness.seconds(directives["s-maxage"] ?? directives["max-age"] ?? nil)
        staleWhileRevalidate = HTTPFreshness.seconds(directives["stale-while-revalidate"] ?? nil) ?? 0
        etag = normalized["etag"]
        lastModified = normalized["last-modified"]
        vary = (normalized["vary"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
    }

    public func isFresh(age: TimeInterval) -> Bool {
        guard storable, !requiresValidation, let maxAge else { return false }
        return age < maxAge
    }

    public func revalidationHeaders() -> [String: String] {
        var result: [String: String] = [:]
        if let etag { result["If-None-Match"] = etag }
        if let lastModified { result["If-Modified-Since"] = lastModified }
        return result
    }

    private static func seconds(_ raw: String?) -> TimeInterval? {
        guard let raw, let value = Double(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func parseDirectives(_ header: String) -> [String: String?] {
        var result: [String: String?] = [:]
        for piece in header.split(separator: ",") {
            let fields = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = fields[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { continue }
            result[name] = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        return result
    }
}
