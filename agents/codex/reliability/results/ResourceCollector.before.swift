import Foundation

public enum ResourceCollector {
    /// URLSession is intentionally absent: the engine's authenticated resource
    /// cache is authoritative, including redirects, cookies and blob contents.
    public static func candidates(snapshot: AetherDocumentSnapshot, baseURL: URL) -> [AetherResourceReference] {
        var ordered = snapshot.resources
        for sheet in snapshot.stylesheets {
            if let src = sheet.sourceURL { ordered.append(.init(url: src, kind: "css")) }
            let stylesheetBase = sheet.sourceURL.flatMap(URL.init(string:)) ?? baseURL
            for ref in CSSURLScanner.references(in: sheet.css) {
                if let resolved = URL(string: ref, relativeTo: stylesheetBase)?.absoluteURL {
                    let ext = resolved.pathExtension.lowercased()
                    let kind: String = switch ext {
                    case "woff", "woff2", "ttf", "otf": "font"
                    case "svg": "svg"
                    default: "asset"
                    }
                    ordered.append(.init(url: resolved.absoluteString, kind: kind))
                }
            }
        }
        var seen: Set<String> = []
        return ordered.compactMap { resource in
            guard let parsed = URL(string: resource.url, relativeTo: baseURL)?.absoluteURL,
                  ["https", "http"].contains(parsed.scheme?.lowercased() ?? "") else { return nil }
            let key = parsed.absoluteString
            guard seen.insert(key).inserted else { return nil }
            return .init(url: key, kind: resource.kind)
        }
    }

    public static func extensionFor(mime: String?, url: URL, kind: String) -> String {
        let ext = url.pathExtension.lowercased()
        let allowed = ["svg", "png", "jpg", "jpeg", "webp", "gif", "avif", "woff", "woff2", "ttf", "otf", "css", "ico", "bmp"]
        if allowed.contains(ext) { return ext }
        switch kind.lowercased() {
        case "svg": return "svg"
        case "font": return "woff2"
        case "css": return "css"
        default: return "bin"
        }
    }

    public static func safeRelativePath(for url: URL, kind: String) -> String {
        // Stable, non-cryptographic filename hash; never use untrusted URL paths.
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in url.absoluteString.utf8 { h = (h ^ UInt64(byte)) &* 1_099_511_628_211 }
        let bucket: String = switch kind.lowercased() {
        case "svg": "svg"
        case "font": "fonts"
        case "css": "css"
        default: "images"
        }
        return "assets/\(bucket)/\(String(h, radix: 16)).\(extensionFor(mime: nil, url: url, kind: kind))"
    }
}

/// A bounded CSS url() scanner; not a CSS minifier. Ignores comments,
/// quoted strings outside url(), data URLs, fragments and var() expressions.
public enum CSSURLScanner {
    public static func references(in css: String) -> [String] {
        let input = Array(css.utf8)
        var result: [String] = []
        var i = 0
        while i < input.count {
            if i + 1 < input.count && input[i] == 47 && input[i + 1] == 42 {
                i += 2
                while i + 1 < input.count && !(input[i] == 42 && input[i + 1] == 47) { i += 1 }
                i = min(input.count, i + 2)
                continue
            }
            if input[i] == 34 || input[i] == 39 {
                let quote = input[i]; i += 1
                while i < input.count {
                    if input[i] == 92 { i = min(input.count, i + 2); continue }
                    if input[i] == quote { i += 1; break }
                    i += 1
                }
                continue
            }
            if i + 4 <= input.count && String(decoding: input[i..<i+4], as: UTF8.self).lowercased() == "url(" {
                i += 4
                while i < input.count && [9, 10, 13, 32].contains(input[i]) { i += 1 }
                let quote: UInt8? = i < input.count && (input[i] == 34 || input[i] == 39) ? input[i] : nil
                if quote != nil { i += 1 }
                let start = i
                while i < input.count {
                    if input[i] == 92 { i = min(input.count, i + 2); continue }
                    if let quote, input[i] == quote { break }
                    if quote == nil && input[i] == 41 { break }
                    i += 1
                }
                let value = String(decoding: input[start..<i], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && !value.lowercased().hasPrefix("data:") &&
                   !value.lowercased().hasPrefix("blob:") && !value.hasPrefix("#") &&
                   !value.lowercased().hasPrefix("var(") { result.append(value) }
                if quote != nil && i < input.count { i += 1 }
                while i < input.count && input[i] != 41 { i += 1 }
                if i < input.count { i += 1 }
                continue
            }
            i += 1
        }
        return result
    }
}
