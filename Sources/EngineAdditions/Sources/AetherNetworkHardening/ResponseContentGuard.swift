import Foundation

public enum DestinationKind: Sendable { case document, script, stylesheet, image, font, other }
public enum ResponseGuardError: Error, Sendable, Equatable { case opaqueMediaType, nosniffBlocked, invalidStatus }

public enum ResponseContentGuard {
    public static func validate(status: Int, headers: [String: String], destination: DestinationKind) throws {
        guard (200..<400).contains(status) else { throw ResponseGuardError.invalidStatus }
        let lower = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        guard lower["x-content-type-options"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "nosniff" else { return }
        let mime = lower["content-type"]?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch destination {
        case .script:
            let javascript = ["text/javascript", "application/javascript", "application/ecmascript", "text/ecmascript"]
            guard javascript.contains(mime) else { throw ResponseGuardError.nosniffBlocked }
        case .stylesheet:
            guard mime == "text/css" else { throw ResponseGuardError.nosniffBlocked }
        default: break
        }
    }
}
