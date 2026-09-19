import DOM
import Foundation

public enum HTMLSerialization {
  public static func serialize(_ document: DOMDocument, redactSensitive: Bool = false) -> String {
    serialize(document.root, in: document, redactSensitive: redactSensitive)
  }

  private static func serialize(_ id: NodeID, in document: DOMDocument, redactSensitive: Bool)
    -> String
  {
    guard let node = document.node(id) else { return "" }
    switch node.kind {
    case .document:
      return node.children.map { serialize($0, in: document, redactSensitive: redactSensitive) }
        .joined()
    case .text(let text):
      if redactSensitive, let parent = node.parent, isRedacted(parent, in: document) { return "" }
      return escape(text)
    case .comment(let text):
      return "<!--\(text)-->"
    case .element(let tag):
      let name = tag.string
      var attributes = node.attributes
      if redactSensitive, name == "input",
        node.attribute("type")?.lowercased() == "password"
      {
        attributes = attributes.map {
          $0.name.string == "value" ? DOMAttribute(name: $0.name, value: "") : $0
        }
      }
      let rendered = attributes.map { " \($0.name.string)=\"\(escapeAttribute($0.value))\"" }
        .joined()
      let voids: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr",
      ]
      if voids.contains(name) { return "<\(name)\(rendered)>" }
      return
        "<\(name)\(rendered)>\(node.children.map { serialize($0, in: document, redactSensitive: redactSensitive) }.joined())</\(name)>"
    }
  }

  private static func isRedacted(_ id: NodeID, in document: DOMDocument) -> Bool {
    var current: NodeID? = id
    while let nodeID = current, let node = document.node(nodeID) {
      if node.attribute("data-aether-redact") != nil { return true }
      current = node.parent
    }
    return false
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  private static func escapeAttribute(_ text: String) -> String {
    escape(text).replacingOccurrences(of: "\"", with: "&quot;")
  }
}
