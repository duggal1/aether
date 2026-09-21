import DOM
import Foundation

public final class HTMLTreeBuilder {
  private let document: DOMDocument
  private var openElements: [NodeID]
  private var activeFormatting: [FormattingEntry]
  private var templateDepth = 0
  private var htmlElement: NodeID?
  private var headElement: NodeID?
  private var bodyElement: NodeID?
  private var formElement: NodeID?
  private static let voidElements: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
    "track", "wbr",
  ]
  private static let rawTextNames: Set<String> = [
    "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "noscript",
  ]
  private static let formattingTags: Set<String> = [
    "b", "big", "code", "em", "font", "i", "s", "small", "strike", "strong", "tt", "u",
  ]
  private static let specialTags: Set<String> = [
    "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl",
    "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "main", "menu", "nav", "ol",
    "p", "section", "table", "ul", "pre", "listing", "form", "plaintext", "xmp",
    "h1", "h2", "h3", "h4", "h5", "h6",
  ]
  private static let tableContextTags: Set<String> = ["table", "tbody", "thead", "tfoot", "tr"]
  private static let impliedEndTags: Set<String> = ["dd", "dt", "li", "option", "optgroup", "p", "rp", "rt"]
  private static let cellTags: Set<String> = ["td", "th"]
  private static let breakOutOfParagraph: Set<String> = [
    "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl",
    "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
    "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "section", "table", "ul",
  ]

  enum FormattingEntry {
    case marker
    case element(name: String, id: NodeID)
  }

  public init(document: DOMDocument) {
    self.document = document
    self.openElements = [document.root]
    self.activeFormatting = []
  }

  public init(document: DOMDocument, fragmentContext: String) {
    self.document = document
    let context = document.createElement(fragmentContext.lowercased())
    document.appendChild(context, to: document.root)
    self.openElements = [document.root, context]
    self.activeFormatting = []
  }

  public func consume(_ tokens: [HTMLToken]) {
    for token in tokens { consume(token) }
  }

  public func consume(_ token: HTMLToken) {
    switch token {
    case .doctype:
      return
    case .comment(let text):
      let node = document.createComment(text)
      insertNode(node)
    case .character(let text):
      insertCharacters(text)
    case .startTag(let name, let attributes, let selfClosing):
      insertStartTag(name: name, attributes: attributes, selfClosing: selfClosing)
    case .endTag(let name):
      insertEndTag(name)
    }
  }

  private var currentParent: NodeID { openElements.last ?? document.root }

  private func tagName(of id: NodeID) -> String? {
    document.node(id)?.tagName
  }

  private func insertNode(_ id: NodeID) {
    if shouldFosterParent() {
      fosterAppend(id)
    } else {
      document.appendChild(id, to: currentParent)
    }
  }

  private func insertCharacters(_ text: String) {
    guard !text.isEmpty else { return }
    if shouldFosterParent() {
      if text.allSatisfy({ $0.isWhitespace }) {
        appendTextToFosterParent(text)
      } else {
        fosterAppendText(text)
      }
      return
    }
    reconstructFormatting()
    if let last = document.children(of: currentParent).last,
      let node = document.node(last),
      case .text(let existing) = node.kind
    {
      document.updateNode(last) { $0.kind = .text(existing + text) }
    } else {
      let node = document.createText(text)
      document.appendChild(node, to: currentParent)
    }
  }

  private func insertStartTag(
    name: String, attributes: [HTMLAttributeToken], selfClosing: Bool
  ) {
    switch name {
    case "html":
      if let htmlElement {
        mergeAttributes(attributes, onto: htmlElement)
        return
      }
    case "head":
      if headElement != nil { return }
    case "body":
      if let bodyElement {
        mergeAttributes(attributes, onto: bodyElement)
        return
      }
      if inScope("head") { close("head") }
    case "br":
      closeParagraphIfInButtonScope()
      let node = makeElement(name: name, attributes: attributes)
      insertNode(node)
      return
    case "hr":
      closeParagraphIfInButtonScope()
      let node = makeElement(name: name, attributes: attributes)
      insertNode(node)
      return
    case "link", "meta", "base", "col", "embed", "source", "track", "wbr", "img", "input", "area",
      "param":
      let node = makeElement(name: name, attributes: attributes)
      insertNode(node)
      return
    case "a":
      if let existing = activeFormatting.lastIndex(where: {
        if case .element(let entryName, _) = $0 { return entryName == "a" }
        return false
      }),
        case .element(_, let existingID) = activeFormatting[existing]
      {
        closeFormattingElement(name: "a", id: existingID)
        if activeFormatting.indices.contains(existing),
          activeFormatting[existing].elementID() == existingID
        {
          activeFormatting.remove(at: existing)
        }
      }
      reconstructFormatting()
      pushFormattingElement(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "nobr":
      reconstructFormatting()
      if inScope("nobr") {
        closeFormattingByName("nobr")
      }
      pushFormattingElement(name: "nobr", attributes: attributes, selfClosing: selfClosing)
      return
    case "p":
      closeParagraphIfInButtonScope()
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "li":
      closeImplied(["li"])
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "dt", "dd":
      closeImplied(["dt", "dd"])
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "h1", "h2", "h3", "h4", "h5", "h6":
      closeParagraphIfInButtonScope()
      if let current = tagName(of: currentParent),
        ["h1", "h2", "h3", "h4", "h5", "h6"].contains(current)
      {
        popUntil(predicate: { $0 == current })
      }
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "tr":
      closeTableCell()
      closeImplied(["tr"])
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "td", "th":
      closeTableCell()
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "caption", "colgroup", "tbody", "tfoot", "thead":
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "table":
      closeParagraphIfInButtonScope()
      activeFormatting.append(.marker)
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "form":
      if formElement != nil, templateDepth == 0 { return }
      closeParagraphIfInButtonScope()
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      if templateDepth == 0, let last = openElements.last, tagName(of: last) == "form" {
        formElement = last
      }
      return
    case "template":
      activeFormatting.append(.marker)
      templateDepth += 1
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "svg", "math":
      reconstructFormatting()
      pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    case "plaintext":
      pushOrdinary(name: name, attributes: attributes, selfClosing: false)
      return
    default:
      break
    }
    if Self.formattingTags.contains(name) {
      reconstructFormatting()
      pushFormattingElement(name: name, attributes: attributes, selfClosing: selfClosing)
      return
    }
    if Self.breakOutOfParagraph.contains(name) {
      closeParagraphIfInButtonScope()
    }
    if name == "option" || name == "optgroup" {
      if tagName(of: currentParent) == "option" { popOne() }
    }
    if name == "rp" || name == "rt" {
      closeImplied(["rtc"])
    }
    pushOrdinary(name: name, attributes: attributes, selfClosing: selfClosing)
  }

  private func insertEndTag(_ name: String) {
    switch name {
    case "br":
      let node = document.createElement("br")
      insertNode(node)
      return
    case "p":
      if !inButtonScope("p") {
        createParagraphElement()
      }
      closeParagraph()
      return
    case "li", "dt", "dd", "option", "optgroup", "rp", "rt":
      closeImplied(except: name)
      if tagName(of: currentParent) == name { popOne() }
      return
    case "h1", "h2", "h3", "h4", "h5", "h6":
      closeImplied(except: nil)
      popUntilOneOf(["h1", "h2", "h3", "h4", "h5", "h6"])
      return
    case "a", "nobr":
      closeFormattingByName(name)
      return
    case "head":
      if inScope("head") { close("head") }
      return
    case "body", "html":
      return
    case "template":
      if templateDepth > 0 { templateDepth -= 1 }
      clearFormattingToMarker()
      if inScope("template") { close("template") }
      return
    case "form":
      guard formElement != nil else { return }
      formElement = nil
      if !inScope("form") { return }
      close("form")
      return
    case "table":
      if !inTableScope("table") { return }
      popUntil(predicate: { $0 == "table" })
      clearFormattingToMarker()
      return
    case "tbody", "tfoot", "thead", "tr", "caption", "colgroup":
      if !inScope(name) { return }
      close(name)
      return
    case "td", "th":
      if !inTableScope(name) { return }
      closeTableCell()
      close(name)
      return
    case "svg", "math":
      if inScope(name) { close(name) }
      return
    default:
      break
    }
    if Self.formattingTags.contains(name) {
      closeFormattingByName(name)
      return
    }
    closeImplied(except: name)
    if tagName(of: currentParent) == name {
      popOne()
    } else {
      close(name)
    }
  }

  private func makeElement(name: String, attributes: [HTMLAttributeToken]) -> NodeID {
    var seen = Set<String>()
    var deduped: [DOMAttribute] = []
    for attribute in attributes {
      guard seen.insert(attribute.name).inserted else { continue }
      deduped.append(DOMAttribute(name: attribute.name, value: attribute.value))
    }
    let adjustedTag = Self.adjustForeignTag(name, inForeign: inForeignContext())
    let adjustedAttributes = Self.adjustForeignAttributes(deduped, for: adjustedTag)
    return document.createElement(adjustedTag, attributes: adjustedAttributes)
  }

  private func pushOrdinary(name: String, attributes: [HTMLAttributeToken], selfClosing: Bool) {
    if shouldFosterParent(), !isTableAllowed(name) {
      let node = makeElement(name: name, attributes: attributes)
      fosterAppend(node)
      if !Self.voidElements.contains(name) { openElements.append(node) }
      trackDocumentStructure(name: name, id: node)
      return
    }
    reconstructFormattingIfInline(name: name)
    let node = makeElement(name: name, attributes: attributes)
    document.appendChild(node, to: currentParent)
    trackDocumentStructure(name: name, id: node)
    if Self.voidElements.contains(name) { return }
    if inForeignContext() {
      if !selfClosing { openElements.append(node) }
      return
    }
    openElements.append(node)
  }

  private func pushFormattingElement(
    name: String, attributes: [HTMLAttributeToken], selfClosing: Bool
  ) {
    let node = makeElement(name: name, attributes: attributes)
    if shouldFosterParent() {
      fosterAppend(node)
    } else {
      document.appendChild(node, to: currentParent)
    }
    if Self.voidElements.contains(name) { return }
    if inForeignContext(), selfClosing { return }
    openElements.append(node)
    if activeFormatting.filter({ $0.isElement(named: name) }).count >= 3 {
      if let first = activeFormatting.firstIndex(where: { $0.isElement(named: name) }) {
        activeFormatting.remove(at: first)
      }
    }
    activeFormatting.append(.element(name: name, id: node))
  }

  private func reconstructFormatting() {
    guard let last = activeFormatting.last else { return }
    guard case .element(_, let lastID) = last else { return }
    guard !openElements.contains(lastID) else { return }
    var redoFrom: Int?
    for (index, entry) in activeFormatting.enumerated().reversed() {
      if case .marker = entry {
        redoFrom = index + 1
        break
      }
      if case .element(_, let entryID) = entry, openElements.contains(entryID) {
        redoFrom = index + 1
        break
      }
    }
    let start = redoFrom ?? 0
    guard start < activeFormatting.count else { return }
    for index in start..<activeFormatting.count {
      guard case .element(let entryName, let entryID) = activeFormatting[index] else { continue }
      guard let source = document.node(entryID) else { continue }
      let clone = document.createElement(
        entryName, attributes: source.attributes)
      document.appendChild(clone, to: currentParent)
      openElements.append(clone)
      activeFormatting[index] = .element(name: entryName, id: clone)
    }
  }

  private func reconstructFormattingIfInline(name: String) {
    if Self.formattingTags.contains(name) || name == "a" || name == "nobr" { return }
    reconstructFormatting()
  }

  private func closeFormattingByName(_ name: String) {
    guard let entryIndex = activeFormatting.lastIndex(where: { $0.isElement(named: name) }) else {
      if openElements.contains(where: { tagName(of: $0) == name }) {
        close(name)
      }
      return
    }
    guard case .element(_, let formattingID) = activeFormatting[entryIndex] else { return }
    guard openElements.contains(formattingID) else {
      activeFormatting.remove(at: entryIndex)
      return
    }
    guard let formattingPos = openElements.lastIndex(of: formattingID) else {
      activeFormatting.remove(at: entryIndex)
      return
    }
    if openElements.last == formattingID {
      openElements.removeLast()
      activeFormatting.remove(at: entryIndex)
      return
    }
    adoptionAgency(name: name, formattingID: formattingID, entryIndex: entryIndex, formattingPos: formattingPos)
  }

  private func closeFormattingElement(name: String, id: NodeID) {
    guard openElements.contains(id) else { return }
    if openElements.last == id {
      openElements.removeLast()
      return
    }
    adoptionAgency(
      name: name, formattingID: id,
      entryIndex: activeFormatting.lastIndex(where: { $0.elementID() == id }),
      formattingPos: openElements.lastIndex(of: id))
  }

  private func adoptionAgency(
    name: String, formattingID: NodeID, entryIndex: Int?, formattingPos: Int?
  ) {
    guard formattingPos != nil, entryIndex != nil else {
      close(name)
      return
    }
    var outer = 0
    var currentFormattingID = formattingID
    var currentEntryIndex = entryIndex
    while outer < 8 {
      outer += 1
      guard let pos = openElements.lastIndex(of: currentFormattingID) else { break }
      guard pos + 1 < openElements.count else { break }
      var furthestBlock: NodeID?
      for id in openElements[(pos + 1)...] {
        if let tag = tagName(of: id), Self.specialTags.contains(tag) || Self.cellTags.contains(tag)
          || tag == "caption"
        {
          furthestBlock = id
          break
        }
      }
      guard let block = furthestBlock,
        let blockPos = openElements.lastIndex(of: block)
      else {
        popThrough(formattingID: currentFormattingID)
        break
      }
      guard let ancestorID = pos > 0 ? openElements[pos - 1] : nil else { break }
      _ = ancestorID
      guard let source = document.node(currentFormattingID) else { break }
      let clone = document.createElement(name, attributes: source.attributes)
      var bookmark = currentEntryIndex ?? activeFormatting.count - 1
      if let idx = currentEntryIndex {
        activeFormatting.remove(at: idx)
        bookmark = idx
      }
      document.insertBefore(clone, before: block, in: parentOf(block) ?? document.root)
      var node = block
      var inner = openElements.count - 1
      while inner > blockPos {
        let candidate = openElements[inner]
        document.appendChild(candidate, to: node)
        if openElements.indices.contains(inner) {
          openElements.remove(at: inner)
        }
        node = candidate
        inner -= 1
      }
      document.appendChild(block, to: clone)
      if let newPos = openElements.lastIndex(of: currentFormattingID) {
        openElements.remove(at: newPos)
        let insertAt = min(blockPos, openElements.count)
        openElements.insert(clone, at: insertAt)
      }
      let capped = min(bookmark, activeFormatting.count)
      activeFormatting.insert(.element(name: name, id: clone), at: capped)
      currentFormattingID = clone
      currentEntryIndex = capped
      if name == (tagName(of: clone) ?? "") { break }
    }
    close(name)
  }

  private func parentOf(_ id: NodeID) -> NodeID? {
    document.parent(of: id)
  }

  private func popThrough(formattingID: NodeID) {
    while openElements.count > 1 {
      let removed = openElements.removeLast()
      if removed == formattingID { break }
    }
    if let index = activeFormatting.lastIndex(where: { $0.elementID() == formattingID }) {
      activeFormatting.remove(at: index)
    }
  }

  private func close(_ name: String) {
    guard openElements.count > 1 else { return }
    var match: Int?
    for index in openElements.indices.reversed() where index > 0 {
      if tagName(of: openElements[index]) == name {
        match = index
        break
      }
    }
    guard let found = match else { return }
    openElements.removeSubrange(found..<openElements.count)
    if let form = formElement, !openElements.contains(form) { formElement = nil }
    if let entry = activeFormatting.lastIndex(where: { $0.isElement(named: name) }),
      case .element(_, let id) = activeFormatting[entry],
      !openElements.contains(id)
    {
      activeFormatting.remove(at: entry)
    }
  }

  private func popOne() {
    if openElements.count > 1 { openElements.removeLast() }
    if let form = formElement, !openElements.contains(form) { formElement = nil }
  }

  private func popUntil(predicate: (String) -> Bool) {
    while openElements.count > 1 {
      guard let tag = tagName(of: openElements.last ?? document.root) else {
        openElements.removeLast()
        continue
      }
      openElements.removeLast()
      if predicate(tag) { break }
    }
    if let form = formElement, !openElements.contains(form) { formElement = nil }
  }

  private func popUntilOneOf(_ names: [String]) {
    while openElements.count > 1 {
      guard let tag = tagName(of: openElements.last ?? document.root) else {
        openElements.removeLast()
        continue
      }
      openElements.removeLast()
      if names.contains(tag) { break }
    }
    if let form = formElement, !openElements.contains(form) { formElement = nil }
  }

  private func closeImplied(_ names: [String]) {
    while let tag = tagName(of: currentParent), names.contains(tag), openElements.count > 1 {
      openElements.removeLast()
    }
  }

  private func closeImplied(except name: String?) {
    while let tag = tagName(of: currentParent), Self.impliedEndTags.contains(tag), tag != name,
      openElements.count > 1
    {
      openElements.removeLast()
    }
  }

  private func closeParagraphIfInButtonScope() {
    if inButtonScope("p") { closeParagraph() }
  }

  private func closeParagraph() {
    closeImplied(except: "p")
    if tagName(of: currentParent) == "p" { popOne() }
  }

  private func createParagraphElement() {
    let node = document.createElement("p")
    insertNode(node)
    openElements.append(node)
  }

  private func closeTableCell() {
    if let tag = tagName(of: currentParent), Self.cellTags.contains(tag) {
      close(tag)
    }
  }

  private func clearFormattingToMarker() {
    while let last = activeFormatting.last {
      if case .marker = last { break }
      activeFormatting.removeLast()
    }
  }

  private func inScope(_ name: String) -> Bool {
    for id in openElements.reversed() {
      if tagName(of: id) == name { return true }
      if let tag = tagName(of: id),
        ["applet", "caption", "html", "table", "td", "th", "marquee", "object", "template"].contains(
          tag)
      {
        return false
      }
    }
    return false
  }

  private func inButtonScope(_ name: String) -> Bool {
    for id in openElements.reversed() {
      if tagName(of: id) == name { return true }
      if let tag = tagName(of: id),
        ["applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "button"]
          .contains(tag)
      {
        return false
      }
    }
    return false
  }

  private func inTableScope(_ name: String) -> Bool {
    for id in openElements.reversed() {
      if tagName(of: id) == name { return true }
      if let tag = tagName(of: id), ["html", "table", "template"].contains(tag) { return false }
    }
    return false
  }

  private func inForeignContext() -> Bool {
    for id in openElements.reversed() {
      guard let tag = tagName(of: id) else { continue }
      if tag == "svg" || tag == "math" { return true }
      if tag == "html" { return false }
    }
    return false
  }

  private func shouldFosterParent() -> Bool {
    guard let tag = tagName(of: currentParent) else { return false }
    if templateDepth > 0 { return false }
    return Self.tableContextTags.contains(tag)
  }

  private func isTableAllowed(_ name: String) -> Bool {
    ["caption", "colgroup", "tbody", "tfoot", "thead", "tr", "td", "th", "col", "style", "script", "template"].contains(name)
  }

  private func fosterTable() -> NodeID? {
    for id in openElements.reversed() {
      if tagName(of: id) == "table" { return id }
    }
    return nil
  }

  private func fosterAppend(_ id: NodeID) {
    guard let table = fosterTable(), let parent = document.parent(of: table) else {
      document.appendChild(id, to: currentParent)
      return
    }
    document.insertBefore(id, before: table, in: parent)
  }

  private func fosterAppendText(_ text: String) {
    let node = document.createText(text)
    fosterAppend(node)
  }

  private func appendTextToFosterParent(_ text: String) {
    guard let table = fosterTable(), let parent = document.parent(of: table) else {
      insertCharactersNonFostered(text)
      return
    }
    if let last = document.children(of: parent).last,
      last != table,
      let node = document.node(last),
      case .text(let existing) = node.kind
    {
      document.updateNode(last) { $0.kind = .text(existing + text) }
    } else {
      let node = document.createText(text)
      document.insertBefore(node, before: table, in: parent)
    }
  }

  private func insertCharactersNonFostered(_ text: String) {
    if let last = document.children(of: currentParent).last,
      let node = document.node(last),
      case .text(let existing) = node.kind
    {
      document.updateNode(last) { $0.kind = .text(existing + text) }
    } else {
      let node = document.createText(text)
      document.appendChild(node, to: currentParent)
    }
  }

  private func mergeAttributes(_ attributes: [HTMLAttributeToken], onto id: NodeID) {
    for attribute in attributes {
      if document.node(id)?.attribute(attribute.name) == nil {
        document.setAttribute(attribute.name, value: attribute.value, on: id)
      }
    }
  }

  private static let foreignTagAdjustments: [String: String] = [
    "foreignobject": "foreignObject", "animatetransform": "animateTransform",
    "lineargradient": "linearGradient", "radialgradient": "radialGradient",
    "textpath": "textPath",
  ]

  private static let foreignAttributeAdjustments: [String: String] = [
    "viewbox": "viewBox", "preserveaspectratio": "preserveAspectRatio",
    "gradienttransform": "gradientTransform", "patterntransform": "patternTransform",
    "refx": "refX", "refy": "refY", "textlength": "textLength",
    "lengthadjust": "lengthAdjust", "attributename": "attributeName",
  ]

  private static func adjustForeignTag(_ name: String, inForeign: Bool) -> String {
    guard inForeign else { return name }
    return foreignTagAdjustments[name] ?? name
  }

  private static func adjustForeignAttributes(_ attributes: [DOMAttribute], for tag: String)
    -> [DOMAttribute]
  {
    guard tag == "foreignObject" || foreignTagAdjustments.values.contains(tag)
      || tag == "svg" || tag == "math"
    else { return attributes }
    return attributes.map { attribute in
      guard let fixed = foreignAttributeAdjustments[attribute.name.string] else {
        return attribute
      }
      return DOMAttribute(name: fixed, value: attribute.value)
    }
  }

  private func trackDocumentStructure(name: String, id: NodeID) {
    switch name {
    case "html": if htmlElement == nil { htmlElement = id }
    case "head": if headElement == nil { headElement = id }
    case "body": if bodyElement == nil { bodyElement = id }
    default: break
    }
  }
}

extension HTMLTreeBuilder.FormattingEntry {
  func isElement(named name: String) -> Bool {
    if case .element(let entryName, _) = self { return entryName == name }
    return false
  }

  func elementID() -> NodeID? {
    if case .element(_, let id) = self { return id }
    return nil
  }
}
