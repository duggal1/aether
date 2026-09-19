import Foundation

public enum ReferrerPolicy: String, Sendable, Codable {
    case noReferrer = "no-referrer"
    case noReferrerWhenDowngrade = "no-referrer-when-downgrade"
    case origin = "origin"
    case originWhenCrossOrigin = "origin-when-cross-origin"
    case sameOrigin = "same-origin"
    case strictOrigin = "strict-origin"
    case strictOriginWhenCrossOrigin = "strict-origin-when-cross-origin"
    case unsafeURL = "unsafe-url"

    public static func parse(_ header: String?) -> ReferrerPolicy {
        guard let header else { return .strictOriginWhenCrossOrigin }
        let parts = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return parts.compactMap(ReferrerPolicy.init(rawValue:)).last ?? .strictOriginWhenCrossOrigin
    }

    public func value(source: URL, destination: URL) -> String? {
        guard ["http", "https"].contains(source.scheme?.lowercased() ?? ""), ["http", "https"].contains(destination.scheme?.lowercased() ?? "") else { return nil }
        let downgrade = source.scheme?.lowercased() == "https" && destination.scheme?.lowercased() == "http"
        let sameOrigin = source.scheme?.lowercased() == destination.scheme?.lowercased()
            && source.host?.lowercased() == destination.host?.lowercased()
            && effectivePort(source) == effectivePort(destination)
        var sanitized = URLComponents(url: source, resolvingAgainstBaseURL: false)
        sanitized?.user = nil
        sanitized?.password = nil
        sanitized?.fragment = nil
        guard let full = sanitized?.url?.absoluteString else { return nil }
        sanitized?.path = "/"
        sanitized?.query = nil
        let origin = sanitized?.url?.absoluteString
        switch self {
        case .noReferrer: return nil
        case .noReferrerWhenDowngrade: return downgrade ? nil : full
        case .origin: return origin
        case .originWhenCrossOrigin: return sameOrigin ? full : origin
        case .sameOrigin: return sameOrigin ? full : nil
        case .strictOrigin: return downgrade ? nil : origin
        case .strictOriginWhenCrossOrigin: return sameOrigin ? full : downgrade ? nil : origin
        case .unsafeURL: return full
        }
    }

    private func effectivePort(_ url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
