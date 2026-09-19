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
        return accepted.enumerated().map { index, node in
            let tag = node.tag.lowercased()
            let kind: String = switch tag {
            case "nav": "navigation"
            case "header": index == 0 ? "hero" : "header"
            case "footer": "footer"
            case "article": "article"
            case "aside": "aside"
            default: "section"
            }
            return CaptureSection(
                id: String(format: "section-%03d", index + 1), kind: kind,
                title: String((node.text ?? kind).prefix(100)),
                selector: node.selector,
                bounds: node.bounds,
                screenshot: nil, screenshotParts: []
            )
        }
    }
}
