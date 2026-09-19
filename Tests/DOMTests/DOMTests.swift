import DOM
import Testing

@Test func stableGenerationalIdsRejectRemovedNodes() {
  let document = DOMDocument()
  let first = document.createElement("div")
  document.appendChild(first, to: document.root)
  document.remove(first)
  let second = document.createElement("span")
  #expect(first.index == second.index)
  #expect(first.version != second.version)
  #expect(document.node(first) == nil)
  #expect(document.node(second) != nil)
}

@Test func querySelectorFindsBasicSelectors() {
  let document = DOMDocument()
  let node = document.createElement(
    "button",
    attributes: [
      DOMAttribute(name: "id", value: "go"), DOMAttribute(name: "class", value: "primary action"),
    ])
  document.appendChild(node, to: document.root)
  #expect(document.querySelector("#go") == node)
  #expect(document.querySelector(".action") == node)
  #expect(document.querySelector("button") == node)
}

@Test func querySelectorAllSupportsCompactCompoundSelectors() {
  let document = DOMDocument()
  let first = document.createElement(
    "button",
    attributes: [
      DOMAttribute(name: "class", value: "primary action"),
      DOMAttribute(name: "data-kind", value: "save"),
    ])
  let second = document.createElement(
    "button",
    attributes: [
      DOMAttribute(name: "class", value: "secondary action"),
      DOMAttribute(name: "data-kind", value: "cancel"),
    ])
  document.appendChild(first, to: document.root)
  document.appendChild(second, to: document.root)
  #expect(document.querySelectorAll("button.action").count == 2)
  #expect(document.querySelectorAll("button.primary[data-kind=save]") == [first])
}

@Test func mutationJournalAndSnapshotTrackChanges() {
  let document = DOMDocument()
  let start = document.mutationVersion
  let node = document.createElement("input")
  document.appendChild(node, to: document.root)
  document.setAttribute("value", value: "alpha", on: node)
  let mutations = document.mutations(since: start)
  #expect(mutations.count == 3)
  #expect(mutations.last?.attributeName == "value")
  let snapshot = document.snapshot()
  #expect(snapshot.mutationVersion == document.mutationVersion)
  #expect(snapshot.nodes.contains(where: { $0.id == node && $0.attributes["value"] == "alpha" }))
}
