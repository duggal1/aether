import EngineCore
import Foundation
import Synchronization

public final class DOMDocument: @unchecked Sendable {
  private struct Slot: Sendable {
    var generation: UInt32
    var node: DOMNode?
  }

  private struct State: Sendable {
    var slots: [Slot]
    var free: [UInt32]
    var root: NodeID
    var mutationVersion: UInt64
    var mutations: [DOMMutation]
  }

  private let state: Mutex<State>
  private let mutationJournalLimit = 2048
  public let id: DocumentID

  public init(id: DocumentID = DocumentID(rawValue: 1)) {
    let root = NodeID(index: 0, generation: 0)
    state = Mutex(
      State(
        slots: [Slot(generation: 0, node: DOMNode(kind: .document))],
        free: [],
        root: root,
        mutationVersion: 0,
        mutations: []
      ))
    self.id = id
  }

  public var root: NodeID { state.withLock { $0.root } }
  public var mutationVersion: UInt64 { state.withLock { $0.mutationVersion } }

  public var nodeCount: Int {
    state.withLock { state in state.slots.reduce(into: 0) { $0 += $1.node == nil ? 0 : 1 } }
  }

  @discardableResult
  public func createElement(_ tag: String, attributes: [DOMAttribute] = []) -> NodeID {
    createNode(DOMNode(kind: .element(tag: Atom(tag.lowercased())), attributes: attributes))
  }

  @discardableResult
  public func createText(_ text: String) -> NodeID {
    createNode(DOMNode(kind: .text(text)))
  }

  @discardableResult
  public func createComment(_ text: String) -> NodeID {
    createNode(DOMNode(kind: .comment(text)))
  }

  public func node(_ id: NodeID) -> DOMNode? {
    state.withLock { state in
      guard let slot = validSlot(id, in: state) else { return nil }
      return slot.node
    }
  }

  public func updateNode(_ id: NodeID, _ body: (inout DOMNode) -> Void) {
    state.withLock { state in
      let index = Int(id.index)
      guard state.slots.indices.contains(index), state.slots[index].generation == id.version,
        var node = state.slots[index].node
      else { return }
      let previous = node
      body(&node)
      guard previous != node else { return }
      state.slots[index].node = node
      let type: DOMMutationType
      var attributeName: String?
      switch (previous.kind, node.kind) {
      case (.text, .text), (.comment, .comment):
        type = .characterDataChanged
      default:
        type = .attributesChanged
        let before = Dictionary(
          uniqueKeysWithValues: previous.attributes.map { ($0.name.string, $0.value) })
        let after = Dictionary(
          uniqueKeysWithValues: node.attributes.map { ($0.name.string, $0.value) })
        attributeName = Set(before.keys).union(after.keys).first { before[$0] != after[$0] }
      }
      record(type, target: id, attributeName: attributeName, state: &state)
    }
  }

  public func setText(_ text: String, on id: NodeID) {
    state.withLock { state in
      let index = Int(id.index)
      guard state.slots.indices.contains(index), state.slots[index].generation == id.version,
        var node = state.slots[index].node
      else { return }
      switch node.kind {
      case .text(let old) where old != text:
        node.kind = .text(text)
      case .comment(let old) where old != text:
        node.kind = .comment(text)
      default:
        return
      }
      state.slots[index].node = node
      record(.characterDataChanged, target: id, state: &state)
    }
  }

  public func appendChild(_ child: NodeID, to parent: NodeID) {
    state.withLock { state in
      let childIndex = Int(child.index)
      let parentIndex = Int(parent.index)
      guard state.slots.indices.contains(childIndex), state.slots.indices.contains(parentIndex),
        state.slots[childIndex].generation == child.version,
        state.slots[parentIndex].generation == parent.version,
        var childNode = state.slots[childIndex].node,
        var parentNode = state.slots[parentIndex].node
      else { return }
      guard child != parent, !isAncestor(child, of: parent, in: state) else { return }
      switch (childNode.kind, parentNode.kind) {
      case (.document, _): return
      case (_, .element), (_, .document): break
      case (_, .text), (_, .comment): return
      }

      if let oldParent = childNode.parent {
        let oldIndex = Int(oldParent.index)
        if state.slots.indices.contains(oldIndex), var oldNode = state.slots[oldIndex].node {
          oldNode.children.removeAll { $0 == child }
          state.slots[oldIndex].node = oldNode
          record(.childListChanged, target: oldParent, relatedNode: child, state: &state)
        }
        if let fresh = state.slots[parentIndex].node { parentNode = fresh }
      }

      childNode.parent = parent
      if !parentNode.children.contains(child) { parentNode.children.append(child) }
      state.slots[childIndex].node = childNode
      state.slots[parentIndex].node = parentNode
      record(.childListChanged, target: parent, relatedNode: child, state: &state)
    }
  }

  public func insertBefore(_ child: NodeID, before sibling: NodeID?, in parent: NodeID) {
    state.withLock { state in
      let childIndex = Int(child.index)
      let parentIndex = Int(parent.index)
      guard state.slots.indices.contains(childIndex), state.slots.indices.contains(parentIndex),
        state.slots[childIndex].generation == child.version,
        state.slots[parentIndex].generation == parent.version,
        var childNode = state.slots[childIndex].node,
        var parentNode = state.slots[parentIndex].node
      else { return }
      guard child != parent, !isAncestor(child, of: parent, in: state) else { return }
      switch (childNode.kind, parentNode.kind) {
      case (.document, _): return
      case (_, .element), (_, .document): break
      case (_, .text), (_, .comment): return
      }
      if let sibling {
        guard parentNode.children.contains(sibling), sibling != child else {
          if sibling == child { return }
          return
        }
      }
      if let oldParent = childNode.parent {
        let oldIndex = Int(oldParent.index)
        if state.slots.indices.contains(oldIndex), var oldNode = state.slots[oldIndex].node {
          oldNode.children.removeAll { $0 == child }
          state.slots[oldIndex].node = oldNode
          record(.childListChanged, target: oldParent, relatedNode: child, state: &state)
        }
      }
      childNode.parent = parent
      state.slots[childIndex].node = childNode
      parentNode.children.removeAll { $0 == child }
      if let sibling, let at = parentNode.children.firstIndex(of: sibling) {
        parentNode.children.insert(child, at: at)
      } else {
        parentNode.children.append(child)
      }
      state.slots[parentIndex].node = parentNode
      record(.childListChanged, target: parent, relatedNode: child, state: &state)
    }
  }

  public func remove(_ id: NodeID) {
    state.withLock { state in
      guard validSlot(id, in: state)?.node != nil else { return }
      let parent = state.slots[Int(id.index)].node?.parent
      remove(id, state: &state)
      record(.nodeRemoved, target: id, relatedNode: parent, state: &state)
    }
  }

  public func setAttribute(_ name: String, value: String, on id: NodeID) {
    let normalized = name.lowercased()
    state.withLock { state in
      let index = Int(id.index)
      guard state.slots.indices.contains(index), state.slots[index].generation == id.version,
        var node = state.slots[index].node
      else { return }
      let atom = Atom(normalized)
      if let attributeIndex = node.attributes.firstIndex(where: { $0.name == atom }) {
        guard node.attributes[attributeIndex].value != value else { return }
        node.attributes[attributeIndex].value = value
      } else {
        node.attributes.append(DOMAttribute(name: atom, value: value))
      }
      state.slots[index].node = node
      record(.attributesChanged, target: id, attributeName: normalized, state: &state)
    }
  }

  public func removeAttribute(_ name: String, from id: NodeID) {
    let normalized = name.lowercased()
    state.withLock { state in
      let index = Int(id.index)
      guard state.slots.indices.contains(index), state.slots[index].generation == id.version,
        var node = state.slots[index].node
      else { return }
      let oldCount = node.attributes.count
      node.attributes.removeAll { $0.name.string == normalized }
      guard node.attributes.count != oldCount else { return }
      state.slots[index].node = node
      record(.attributesChanged, target: id, attributeName: normalized, state: &state)
    }
  }

  public func children(of id: NodeID) -> [NodeID] { node(id)?.children ?? [] }
  public func parent(of id: NodeID) -> NodeID? { node(id)?.parent }

  public func hasAttribute(_ name: String, on id: NodeID) -> Bool {
    node(id)?.attribute(name.lowercased()) != nil
  }

  public func replaceChild(_ newChild: NodeID, for oldChild: NodeID, in parent: NodeID) {
    state.withLock { state in
      let newIndex = Int(newChild.index)
      let parentIndex = Int(parent.index)
      guard state.slots.indices.contains(newIndex), state.slots.indices.contains(parentIndex),
        state.slots[newIndex].generation == newChild.version,
        state.slots[parentIndex].generation == parent.version,
        var newNode = state.slots[newIndex].node,
        var parentNode = state.slots[parentIndex].node,
        parentNode.children.contains(oldChild)
      else { return }
      guard newChild != parent, newChild != oldChild,
        !isAncestor(newChild, of: parent, in: state)
      else { return }
      switch (newNode.kind, parentNode.kind) {
      case (.document, _): return
      case (_, .element), (_, .document): break
      case (_, .text), (_, .comment): return
      }
      if let oldParent = newNode.parent {
        let oldIndex = Int(oldParent.index)
        if state.slots.indices.contains(oldIndex), var oldNode = state.slots[oldIndex].node {
          oldNode.children.removeAll { $0 == newChild }
          state.slots[oldIndex].node = oldNode
          record(.childListChanged, target: oldParent, relatedNode: newChild, state: &state)
        }
      }
      newNode.parent = parent
      state.slots[newIndex].node = newNode
      parentNode.children.removeAll { $0 == newChild }
      if let at = parentNode.children.firstIndex(of: oldChild) {
        parentNode.children[at] = newChild
      }
      state.slots[parentIndex].node = parentNode
      record(.childListChanged, target: parent, relatedNode: newChild, state: &state)
    }
  }

  public func eventPath(from id: NodeID) -> [NodeID] {
    var path: [NodeID] = []
    var current: NodeID? = id
    while let node = current {
      path.append(node)
      current = self.parent(of: node)
    }
    return path
  }

  public func isInclusiveAncestor(_ ancestor: NodeID, of descendant: NodeID) -> Bool {
    var current: NodeID? = descendant
    while let node = current {
      if node == ancestor { return true }
      current = self.parent(of: node)
    }
    return false
  }

  public func validateInvariants() -> [String] {
    state.withLock { state in
      var problems: [String] = []
      for (index, slot) in state.slots.enumerated() {
        guard let node = slot.node else { continue }
        let id = NodeID(index: UInt32(index), generation: slot.generation)
        if let parent = node.parent {
          let parentIndex = Int(parent.index)
          guard state.slots.indices.contains(parentIndex),
            state.slots[parentIndex].generation == parent.version,
            let parentNode = state.slots[parentIndex].node
          else {
            problems.append("dangling parent \(parent) from \(id)")
            continue
          }
          if !parentNode.children.contains(id) {
            problems.append("parent \(parent) missing child \(id)")
          }
        }
        var seen = Set<NodeID>()
        for child in node.children {
          if !seen.insert(child).inserted {
            problems.append("duplicate child \(child) in \(id)")
          }
          let childIndex = Int(child.index)
          guard state.slots.indices.contains(childIndex),
            state.slots[childIndex].generation == child.version,
            let childNode = state.slots[childIndex].node
          else {
            problems.append("dangling child \(child) in \(id)")
            continue
          }
          if childNode.parent != id {
            problems.append("child \(child) parent mismatch in \(id)")
          }
        }
        var names = Set<String>()
        for attribute in node.attributes {
          if !names.insert(attribute.name.string).inserted {
            problems.append("duplicate attribute \(attribute.name.string) in \(id)")
          }
        }
      }
      return problems
    }
  }

  public func elements(named tag: String) -> [NodeID] {
    let needle = tag.lowercased()
    return allNodeIDs().filter { node($0)?.tagName == needle }
  }

  public func element(withID idValue: String) -> NodeID? {
    allNodeIDs().first { node($0)?.attribute("id") == idValue }
  }

  public func querySelector(_ selector: String) -> NodeID? {
    querySelectorAll(selector).first
  }

  public func querySelectorAll(_ selector: String) -> [NodeID] {
    let selectors = selector.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard !selectors.isEmpty else { return [] }
    var seen = Set<NodeID>()
    var result: [NodeID] = []
    for id in depthFirst() {
      guard let node = node(id), node.tagName != nil else { continue }
      if selectors.contains(where: { matchesSimpleSelector($0, node: node) }),
        seen.insert(id).inserted
      {
        result.append(id)
      }
    }
    return result
  }

  public func textContent(of id: NodeID) -> String {
    guard let node = node(id) else { return "" }
    switch node.kind {
    case .text(let text): return text
    case .comment: return ""
    case .document, .element:
      return node.children.map { textContent(of: $0) }.joined()
    }
  }

  public func documentTitle() -> String {
    guard let title = elements(named: "title").first else { return "" }
    return textContent(of: title).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func allNodeIDs() -> [NodeID] {
    state.withLock { state in
      state.slots.enumerated().compactMap { index, slot in
        guard slot.node != nil else { return nil }
        return NodeID(index: UInt32(index), generation: slot.generation)
      }
    }
  }

  public func depthFirst(from start: NodeID? = nil) -> [NodeID] {
    let root = start ?? self.root
    var result: [NodeID] = []
    var stack: [NodeID] = [root]
    while let current = stack.popLast() {
      result.append(current)
      let children = self.children(of: current)
      stack.append(contentsOf: children.reversed())
    }
    return result
  }

  public func mutations(since version: UInt64) -> [DOMMutation] {
    state.withLock { $0.mutations.filter { $0.version > version } }
  }

  private func createNode(_ node: DOMNode) -> NodeID {
    state.withLock { state in
      let id: NodeID
      if let index = state.free.popLast() {
        let i = Int(index)
        state.slots[i].node = node
        id = NodeID(index: index, generation: state.slots[i].generation)
      } else {
        let index = UInt32(state.slots.count)
        state.slots.append(Slot(generation: 0, node: node))
        id = NodeID(index: index, generation: 0)
      }
      record(.nodeCreated, target: id, state: &state)
      return id
    }
  }

  private func validSlot(_ id: NodeID, in state: State) -> Slot? {
    let index = Int(id.index)
    guard state.slots.indices.contains(index), state.slots[index].generation == id.version else {
      return nil
    }
    return state.slots[index]
  }

  private func isAncestor(_ ancestor: NodeID, of descendant: NodeID, in state: State) -> Bool {
    var current = state.slots[Int(descendant.index)].node?.parent
    while let node = current {
      if node == ancestor { return true }
      let index = Int(node.index)
      guard state.slots.indices.contains(index) else { return false }
      current = state.slots[index].node?.parent
    }
    return false
  }

  private func remove(_ id: NodeID, state: inout State) {
    let index = Int(id.index)
    guard state.slots.indices.contains(index), state.slots[index].generation == id.version,
      let node = state.slots[index].node
    else { return }
    for child in node.children { remove(child, state: &state) }
    if let parent = node.parent {
      let parentIndex = Int(parent.index)
      if state.slots.indices.contains(parentIndex), var parentNode = state.slots[parentIndex].node {
        parentNode.children.removeAll { $0 == id }
        state.slots[parentIndex].node = parentNode
      }
    }
    state.slots[index].node = nil
    state.slots[index].generation &+= 1
    state.free.append(id.index)
  }

  private func record(
    _ type: DOMMutationType, target: NodeID, relatedNode: NodeID? = nil,
    attributeName: String? = nil, state: inout State
  ) {
    state.mutationVersion &+= 1
    state.mutations.append(
      DOMMutation(
        version: state.mutationVersion, type: type, target: target, relatedNode: relatedNode,
        attributeName: attributeName))
    if state.mutations.count > mutationJournalLimit {
      state.mutations.removeFirst(state.mutations.count - mutationJournalLimit)
    }
  }

  private func matchesSimpleSelector(_ selector: String, node: DOMNode) -> Bool {
    var source = selector.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, let tagName = node.tagName else { return false }
    if source.contains(" ") || source.contains(">") || source.contains("+") || source.contains("~")
    {
      return false
    }

    var attributeName: String?
    var attributeValue: String?
    if let open = source.firstIndex(of: "["), let close = source.lastIndex(of: "]"), open < close {
      let inner = source[source.index(after: open)..<close]
      let parts = inner.split(separator: "=", maxSplits: 1).map(String.init)
      attributeName = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if parts.count == 2 {
        attributeValue = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
      }
      source.removeSubrange(open...close)
    }

    var idValue: String?
    if let hash = source.firstIndex(of: "#") {
      let tail = source[source.index(after: hash)...]
      let end = tail.firstIndex(of: ".") ?? tail.endIndex
      idValue = String(tail[..<end])
      source.removeSubrange(hash..<end)
    }

    var classNames: [String] = []
    let components = source.split(separator: ".", omittingEmptySubsequences: false)
    let tag = components.first.map(String.init) ?? ""
    if components.count > 1 {
      classNames = components.dropFirst().map(String.init).filter { !$0.isEmpty }
    }

    if !tag.isEmpty && tag != "*" && tag.lowercased() != tagName { return false }
    if let idValue, node.attribute("id") != idValue { return false }
    if !classNames.isEmpty {
      let classes = Set(
        (node.attribute("class") ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
      if classNames.contains(where: { !classes.contains($0) }) { return false }
    }
    if let attributeName {
      guard let actual = node.attribute(attributeName) else { return false }
      if let attributeValue, actual != attributeValue { return false }
    }
    return true
  }
}
