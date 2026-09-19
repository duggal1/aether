import Foundation

public enum DownloadName {
    public static func suggested(from header: String?, fallback: String = "download") -> String {
        guard let header else { return sanitize(fallback) }
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let encoded = parts.first(where: { $0.lowercased().hasPrefix("filename*=") }) {
            let value = String(encoded.dropFirst(10)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
            if pieces.count == 3, pieces[0].lowercased() == "utf-8", let decoded = pieces[2].removingPercentEncoding {
                return sanitize(decoded)
            }
        }
        if let named = parts.first(where: { $0.lowercased().hasPrefix("filename=") }) {
            return sanitize(String(named.dropFirst(9)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return sanitize(fallback)
    }

    public static func sanitize(_ raw: String) -> String {
        let basename = raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let filtered = String(basename.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 && $0 != ":" })
        let result = filtered.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return result.isEmpty || result == ".." ? "download" : String(result.prefix(255))
    }
}
