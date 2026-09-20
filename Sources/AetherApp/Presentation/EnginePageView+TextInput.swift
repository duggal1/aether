import AppKit

extension EnginePageView: NSTextInputClient {
  func insertText(_ string: Any, replacementRange: NSRange) {
    let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    guard !text.isEmpty else { return }
    let range = replacementRange.location == NSNotFound ? editingSelection : replacementRange
    markedTextValue = ""
    enqueue { [engine, pageID] in
      try await engine.runtime.insertText(pageID: pageID, text: text,
        replacement: replacementRange.location == NSNotFound ? nil : range)
    }
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    markedTextValue = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
  }
  func unmarkText() { markedTextValue = "" }
  func selectedRange() -> NSRange { editingSelection }
  func markedRange() -> NSRange {
    markedTextValue.isEmpty ? NSRange(location: NSNotFound, length: 0)
      : NSRange(location: editingSelection.location, length: (markedTextValue as NSString).length)
  }
  func hasMarkedText() -> Bool { !markedTextValue.isEmpty }
  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
    let text = editingText as NSString
    guard range.location <= text.length else { return nil }
    let bounded = NSRange(location: range.location, length: min(range.length, text.length - range.location))
    actualRange?.pointee = bounded
    return NSAttributedString(string: text.substring(with: bounded))
  }
  func characterIndex(for point: NSPoint) -> Int { editingSelection.location }
  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    actualRange?.pointee = editingSelection
    return window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
  }
  func doCommand(by selector: Selector) {
    switch selector {
    case #selector(NSResponder.insertNewline(_:)):
      enqueue { [engine, pageID] in _ = try await engine.runtime.pressKey(pageID: pageID, key: "Enter") }
    case #selector(NSResponder.deleteBackward(_:)):
      enqueue { [engine, pageID] in try await engine.runtime.deleteSelectedText(pageID: pageID, backwards: true) }
    case #selector(NSResponder.deleteForward(_:)):
      enqueue { [engine, pageID] in try await engine.runtime.deleteSelectedText(pageID: pageID, backwards: false) }
    case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)):
      let backwards = selector == #selector(NSResponder.moveLeft(_:))
      enqueue { [engine, pageID] in try await engine.runtime.moveTextCursor(pageID: pageID, backwards: backwards, extend: false) }
    case #selector(NSResponder.moveLeftAndModifySelection(_:)), #selector(NSResponder.moveRightAndModifySelection(_:)):
      let backwards = selector == #selector(NSResponder.moveLeftAndModifySelection(_:))
      enqueue { [engine, pageID] in try await engine.runtime.moveTextCursor(pageID: pageID, backwards: backwards, extend: true) }
    case #selector(NSResponder.selectAll(_:)): selectAll(nil)
    case #selector(NSResponder.cancelOperation(_:)):
      enqueue { [engine, pageID] in _ = try await engine.runtime.blur(pageID: pageID) }
    default: break
    }
  }
  override func selectAll(_ sender: Any?) {
    enqueue { [engine, pageID] in
      try await engine.runtime.selectText(pageID: pageID, range: NSRange(location: 0, length: Int.max))
    }
  }
  @objc func copy(_ sender: Any?) {
    enqueue { [engine, pageID] in
      guard let text = try await engine.runtime.selectedText(pageID: pageID), !text.isEmpty else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    }
  }
  @objc func paste(_ sender: Any?) {
    if let text = NSPasteboard.general.string(forType: .string) {
      insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
  }
}
