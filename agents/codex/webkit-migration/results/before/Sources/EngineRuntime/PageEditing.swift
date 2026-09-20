import DOM
import EngineCore
import Foundation

public struct RuntimeEditingState: Sendable {
  public let text: String
  public let selection: NSRange
  public let secret: Bool
}

extension BrowserRuntime {
  public func editingState(pageID: PageID) throws -> RuntimeEditingState? {
    let page = try requirePage(pageID)
    guard let id = page.focused, let loaded = page.loaded,
      let node = loaded.document.node(id) else { return nil }
    let text = currentValue(id, document: loaded.document)
    let count = (text as NSString).length
    let selected = page.textSelection ?? NSRange(location: count, length: 0)
    let location = min(selected.location, count)
    let safe = NSRange(location: location, length: min(selected.length, count - location))
    let secret = node.attribute("type")?.lowercased() == "password"
    return RuntimeEditingState(text: secret ? String(repeating: "•", count: count) : text,
      selection: safe, secret: secret)
  }

  public func selectText(pageID: PageID, range: NSRange) throws {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID], let loaded = page.loaded, let id = page.focused
    else { return }
    let count = (currentValue(id, document: loaded.document) as NSString).length
    let start = range.location == NSNotFound ? count : min(range.location, count)
    page.textSelection = NSRange(location: start, length: min(range.length, count - start))
    context.pages[pageID] = page
    contexts[contextID] = context
  }

  public func insertText(pageID: PageID, text: String, replacement: NSRange? = nil) throws {
    let page = try requirePage(pageID)
    guard let id = page.focused, let loaded = page.loaded else { return }
    let current = currentValue(id, document: loaded.document) as NSString
    let selection = replacement ?? page.textSelection ?? NSRange(location: current.length, length: 0)
    let start = min(selection.location, current.length)
    let bounded = NSRange(location: start, length: min(selection.length, current.length - start))
    try setValue(pageID: pageID, nodeID: id, value: current.replacingCharacters(in: bounded, with: text))
    try selectText(pageID: pageID, range: NSRange(location: start + (text as NSString).length, length: 0))
  }

  public func deleteSelectedText(pageID: PageID, backwards: Bool) throws {
    let page = try requirePage(pageID)
    guard let id = page.focused, let loaded = page.loaded else { return }
    let text = currentValue(id, document: loaded.document) as NSString
    var range = page.textSelection ?? NSRange(location: text.length, length: 0)
    if range.length == 0 {
      let position = backwards ? range.location - 1 : range.location
      guard position >= 0, position < text.length else { return }
      range = text.rangeOfComposedCharacterSequence(at: position)
    }
    try insertText(pageID: pageID, text: "", replacement: range)
  }

  public func moveTextCursor(pageID: PageID, backwards: Bool, extend: Bool) throws {
    guard let current = try editingState(pageID: pageID) else { return }
    let text = current.text as NSString
    let position = backwards ? max(0, current.selection.location - 1)
      : min(text.length, NSMaxRange(current.selection) + 1)
    let range: NSRange
    if extend {
      range = backwards ? NSRange(location: position, length: NSMaxRange(current.selection) - position)
        : NSRange(location: current.selection.location, length: position - current.selection.location)
    } else { range = NSRange(location: position, length: 0) }
    try selectText(pageID: pageID, range: range)
  }

  public func selectedText(pageID: PageID) throws -> String? {
    guard let state = try editingState(pageID: pageID), !state.secret else { return nil }
    return (state.text as NSString).substring(with: state.selection)
  }
}
