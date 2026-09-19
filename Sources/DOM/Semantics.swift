import EngineCore
import Foundation

public struct SemanticNode: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var role: String
  public var name: String
  public var value: String?
  public var href: String?
  public var enabled: Bool
  public var editable: Bool
  public var visible: Bool
  public var bounds: Rect?

  public init(
    nodeID: NodeID, role: String, name: String, value: String? = nil, href: String? = nil,
    enabled: Bool = true, editable: Bool = false, visible: Bool = true, bounds: Rect? = nil
  ) {
    self.nodeID = nodeID
    self.role = role
    self.name = name
    self.value = value
    self.href = href
    self.enabled = enabled
    self.editable = editable
    self.visible = visible
    self.bounds = bounds
  }
}

public enum DOMSemantics {
  public static func role(for node: DOMNode) -> String? {
    if let explicit = node.attribute("role"), !explicit.isEmpty { return explicit }
    switch node.tagName {
    case "a": return node.attribute("href") == nil ? nil : "link"
    case "button": return "button"
    case "input":
      switch node.attribute("type")?.lowercased() {
      case "checkbox": return "checkbox"
      case "radio": return "radio"
      case "submit", "button", "reset": return "button"
      default: return "textbox"
      }
    case "textarea": return "textbox"
    case "select": return "combobox"
    case "option": return "option"
    case "img": return "img"
    case "h1", "h2", "h3", "h4", "h5", "h6": return "heading"
    case "form": return "form"
    default: return nil
    }
  }

  public static func name(for id: NodeID, in document: DOMDocument) -> String {
    guard let node = document.node(id) else { return "" }
    if let aria = node.attribute("aria-label"), !aria.isEmpty { return aria }
    if let alt = node.attribute("alt"), !alt.isEmpty { return alt }
    if let placeholder = node.attribute("placeholder"), !placeholder.isEmpty { return placeholder }
    if let title = node.attribute("title"), !title.isEmpty { return title }
    return document.textContent(of: id).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func interactiveNodes(in document: DOMDocument) -> [SemanticNode] {
    document.depthFirst().compactMap { id in
      guard let node = document.node(id), let role = role(for: node) else { return nil }
      let disabled = node.attribute("disabled") != nil || node.attribute("aria-disabled") == "true"
      let editable = role == "textbox" || node.attribute("contenteditable") == "true"
      return SemanticNode(
        nodeID: id,
        role: role,
        name: name(for: id, in: document),
        value: node.attribute("value"),
        href: node.attribute("href"),
        enabled: !disabled,
        editable: editable,
        visible: node.attribute("hidden") == nil
      )
    }
  }
}
