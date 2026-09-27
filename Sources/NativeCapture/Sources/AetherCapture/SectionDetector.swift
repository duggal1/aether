import Foundation

/// Structural boundaries are based on the engine's laid-out document, not
/// fixed screenshot slices or a speculative AI classification pass.
public enum SectionDetector {
    public static func detect(nodes: [AetherDocumentNode], documentHeight: Double) -> [CaptureSection] {
        let structural: Set<String> = ["main", "section", "header", "footer", "nav", "article", "aside"]
        let candidates = nodes.filter {
            $0.bounds.isValid && $0.bounds.height >= 36 && $0.bounds.y < documentHeight &&
            (structural.contains($0.tag.lowercased()) || $0.role == "region")
        }.sorted {
            if $0.bounds.y != $1.bounds.y { return $0.bounds.y < $1.bounds.y }
            return $0.bounds.height > $1.bounds.height
        }
        var accepted: [AetherDocumentNode] = []
        for node in candidates {
            let isNested = accepted.contains {
                $0.bounds.y <= node.bounds.y + 2 && $0.bounds.bottom >= node.bounds.bottom - 2 &&
                $0.bounds.x <= node.bounds.x + 2 &&
                $0.bounds.x + $0.bounds.width >= node.bounds.x + node.bounds.width - 2
            }
            // Avoid one giant <main> swallowing all <section> elements.
            if node.tag.lowercased() == "main" && candidates.contains(where: {
                $0.tag.lowercased() == "section" && $0.bounds.y >= node.bounds.y &&
                $0.bounds.bottom <= node.bounds.bottom
            }) { continue }
            if !isNested { accepted.append(node) }
        }
        var sections: [CaptureSection] = []
        for (index, node) in accepted.enumerated() {
            let tag = node.tag.lowercased()
            let kind: String = switch tag {
            case "nav": "navigation"
            case "header": index == 0 ? "hero" : "header"
            case "footer": "footer"
            case "article": "article"
            case "aside": "aside"
            default: "section"
            }
            // Clean file-ready names — hero, header, navigation, footer —
            // with a numeric suffix only when a kind repeats.
            var id = kind
            var suffix = 2
            while sections.contains(where: { $0.id == id }) {
                id = "\(kind)-\(suffix)"
                suffix += 1
            }
            let text = (node.text ?? "")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(CaptureSection(
                id: id, kind: kind,
                title: String((text.isEmpty ? kind.capitalized : text).prefix(100)),
                selector: node.selector,
                bounds: node.bounds,
                screenshot: nil, screenshotParts: []
            ))
        }
        return sections
    }

    /// Screen-tall fallback bands when a page has no semantic structure at
    /// all, so a capture still yields named per-part images.
    public static func bands(documentHeight: Double, viewportWidth: Double, viewportHeight: Double) -> [CaptureSection] {
        let step = max(1, viewportHeight)
        var out: [CaptureSection] = []
        var y = 0.0
        var index = 0
        while y < documentHeight - 0.5 {
            index += 1
            let height = min(step, documentHeight - y)
            out.append(CaptureSection(
                id: index == 1 ? "hero" : "part-\(index)",
                kind: index == 1 ? "hero" : "section",
                title: index == 1 ? "Hero" : "Part \(index)",
                selector: "body",
                bounds: CaptureRect(x: 0, y: y, width: max(0, viewportWidth), height: height),
                screenshot: nil, screenshotParts: []))
            y += height
        }
        return out
    }
}
