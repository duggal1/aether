import EngineCore
import Foundation

public struct DOMSnapshotNode: Hashable, Sendable, Codable {
  public var id: NodeID
  public var parent: NodeID?
  public var children: [NodeID]
  public var kind: String
  public var tag: String?
  public var text: String?
  public var attributes: [String: String]
  public var role: String?
  public var name: String

  public init(
    id: NodeID, parent: NodeID?, children: [NodeID], kind: String, tag: String?, text: String?,
    attributes: [String: String], role: String?, name: String
  ) {
    self.id = id
    self.parent = parent
    self.children = children
    self.kind = kind
    self.tag = tag
    self.text = text
    self.attributes = attributes
    self.role = role
    self.name = name
  }
}

public struct DOMSnapshot: Hashable, Sendable, Codable {
  public var documentID: DocumentID
  public var mutationVersion: UInt64
  public var root: NodeID
  public var nodes: [DOMSnapshotNode]

  public init(
    documentID: DocumentID, mutationVersion: UInt64, root: NodeID, nodes: [DOMSnapshotNode]
  ) {
    self.documentID = documentID
    self.mutationVersion = mutationVersion
    self.root = root
    self.nodes = nodes
  }
}

extension DOMDocument {
  public func snapshot() -> DOMSnapshot {
    let ids = depthFirst()
    let nodes = ids.compactMap { id -> DOMSnapshotNode? in
      guard let node = node(id) else { return nil }
      let kind: String
      let tag: String?
      let text: String?
      switch node.kind {
      case .document:
        kind = "document"
        tag = nil
        text = nil
      case .element(let atom):
        kind = "element"
        tag = atom.string
        text = nil
      case .text(let value):
        kind = "text"
        tag = nil
        text = value
      case .comment(let value):
        kind = "comment"
        tag = nil
        text = value
      }
      var attributes: [String: String] = [:]
      attributes.reserveCapacity(node.attributes.count)
      for attribute in node.attributes { attributes[attribute.name.string] = attribute.value }
      return DOMSnapshotNode(
        id: id,
        parent: node.parent,
        children: node.children,
        kind: kind,
        tag: tag,
        text: text,
        attributes: attributes,
        role: DOMSemantics.role(for: node),
        name: DOMSemantics.name(for: id, in: self)
      )
    }
    return DOMSnapshot(documentID: id, mutationVersion: mutationVersion, root: root, nodes: nodes)
  }
}
