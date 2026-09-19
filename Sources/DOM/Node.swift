import EngineCore

public struct DOMAttribute: Hashable, Sendable, Codable {
  public var name: Atom
  public var value: String

  public init(name: String, value: String) {
    self.name = Atom(name.lowercased())
    self.value = value
  }

  public init(name: Atom, value: String) {
    self.name = name
    self.value = value
  }
}

public enum NodeKind: Hashable, Sendable, Codable {
  case document
  case element(tag: Atom)
  case text(String)
  case comment(String)
}

public struct DOMNode: Hashable, Sendable, Codable {
  public var kind: NodeKind
  public var parent: NodeID?
  public var children: [NodeID]
  public var attributes: [DOMAttribute]

  public init(
    kind: NodeKind, parent: NodeID? = nil, children: [NodeID] = [], attributes: [DOMAttribute] = []
  ) {
    self.kind = kind
    self.parent = parent
    self.children = children
    self.attributes = attributes
  }

  public var tagName: String? {
    guard case .element(let tag) = kind else { return nil }
    return tag.string
  }

  public func attribute(_ name: String) -> String? {
    let needle = name.lowercased()
    return attributes.first(where: { $0.name.string == needle })?.value
  }
}
