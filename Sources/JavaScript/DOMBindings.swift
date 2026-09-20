import DOM
import Foundation

public final class JSDOMContext {
  weak var runtime: JSRuntime?
  let document: DOMDocument
  let events: JSEventRegistry
  weak var mediaHost: (any JSMediaHost)?
  var eventPrototype = JSObject()
  var customEventPrototype = JSObject()
  var mouseEventPrototype = JSObject()
  var keyboardEventPrototype = JSObject()

  public init(runtime: JSRuntime?, document: DOMDocument, events: JSEventRegistry) {
    self.runtime = runtime
    self.document = document
    self.events = events
  }

  func hooks() -> JSHostHooks { runtime?.hostHooks ?? JSHostHooks() }

  func wrap(_ id: NodeID) -> JSObject {
    JSDOMBindings.nodeObject(id, context: self)
  }

  func arrayOf(_ values: [JSValue]) -> JSObject {
    guard let runtime else {
      let object = JSObject()
      for (index, value) in values.enumerated() { object.set(String(index), value) }
      object.set("length", .number(Double(values.count)))
      return object
    }
    return runtime.makeArray(values)
  }

  func proto(_ name: String) -> JSObject? {
    switch name {
    case "event": return eventPrototype
    case "custom": return customEventPrototype
    case "mouse": return mouseEventPrototype
    case "keyboard": return keyboardEventPrototype
    default: return nil
    }
  }
}

public enum JSDOMBindings {
  public static func documentObject(
    _ document: DOMDocument, events: JSEventRegistry, runtime: JSRuntime?
  ) -> JSObject {
    let context = JSDOMContext(runtime: runtime, document: document, events: events)
    return documentObject(context: context)
  }

  static func documentObject(context: JSDOMContext) -> JSObject {
    let document = context.document
    let events = context.events
    let object = JSObject(
      nativeGet: { [weak document] key in
        guard let document else { return nil }
        switch key {
        case "title": return .string(document.documentTitle())
        case "body": return firstElement("body", context: context) ?? .null
        case "head": return firstElement("head", context: context) ?? .null
        case "documentElement": return firstElement("html", context: context) ?? .null
        case "readyState": return .string("complete")
        case "characterSet": return .string("UTF-8")
        case "contentType": return .string("text/html")
        case "referrer": return .string("")
        case "activeElement": return .null
        case "cookie": return .string(context.hooks().cookieString?() ?? "")
        default: return nil
        }
      },
      nativeSet: { [weak document] key, value in
        guard let document else { return false }
        switch key {
        case "title":
          setDocumentTitle(value.description, document: document)
          return true
        case "cookie":
          context.hooks().setCookieString?(value.description)
          return true
        default:
          return false
        }
      })
    installDocumentMethods(object, context: context)
    installDocumentCollections(object, context: context)
    installDocumentListeners(object, context: context, nodeID: document.root)
    return object
  }

  static func setDocumentTitle(_ title: String, document: DOMDocument) {
    if let titleID = document.elements(named: "title").first {
      setTextContent(title, on: titleID, document: document)
      return
    }
    let element = document.createElement("title")
    let text = document.createText(title)
    document.appendChild(text, to: element)
    if let head = document.elements(named: "head").first {
      document.appendChild(element, to: head)
    } else if let html = document.elements(named: "html").first {
      document.appendChild(element, to: html)
    } else {
      document.appendChild(element, to: document.root)
    }
  }

  public static func nodeObject(
    _ id: NodeID, document: DOMDocument, events: JSEventRegistry
  ) -> JSObject {
    let context = JSDOMContext(runtime: nil, document: document, events: events)
    return nodeObject(id, context: context)
  }

  static func nodeObject(_ id: NodeID, context: JSDOMContext) -> JSObject {
    let document = context.document
    let events = context.events
    let object = JSObject(
      nativeGet: { [weak document] key in
        guard let document, let node = document.node(id) else { return .undefined }
        switch key {
        case "nodeId": return .string(id.description)
        case "nodeType": return .number(Double(nodeType(of: node)))
        case "nodeName":
          if let tag = node.tagName { return .string(tag.uppercased()) }
          switch node.kind {
          case .text: return .string("#text")
          case .comment: return .string("#comment")
          case .document: return .string("#document")
          case .element: return .string("#element")
          }
        case "tagName": return node.tagName.map { .string($0.uppercased()) } ?? .undefined
        case "textContent": return .string(document.textContent(of: id))
        case "innerText": return .string(document.textContent(of: id))
        case "value": return .string(inputValue(node: node, id: id, document: document))
        case "checked":
          return .bool(node.attribute("checked") != nil && node.tagName == "input")
        case "disabled": return .bool(node.attribute("disabled") != nil)
        case "href": return node.attribute("href").map(JSValue.string) ?? .undefined
        case "src": return node.attribute("src").map(JSValue.string) ?? .undefined
        case "id": return .string(node.attribute("id") ?? "")
        case "className": return .string(node.attribute("class") ?? "")
        case "title": return .string(node.attribute("title") ?? "")
        case "name": return .string(node.attribute("name") ?? "")
      case "type":
        if node.tagName == "input" {
          return .string(node.attribute("type") ?? "text")
        }
        if node.tagName == "button" {
          return .string(node.attribute("type") ?? "submit")
        }
        return .undefined
        case "parentNode", "parentElement":
          return node.parent.map { .object(context.wrap($0)) } ?? .null
        case "firstChild":
          return node.children.first.map { .object(context.wrap($0)) } ?? .null
        case "lastChild":
          return node.children.last.map { .object(context.wrap($0)) } ?? .null
        case "previousSibling":
          return anySibling(of: id, document: document, context: context, forward: false)
        case "previousElementSibling":
          return sibling(of: id, document: document, context: context, forward: false)
        case "nextSibling":
          return anySibling(of: id, document: document, context: context, forward: true)
        case "nextElementSibling":
          return sibling(of: id, document: document, context: context, forward: true)
        case "children":
          return .object(
            context.arrayOf(
              node.children.compactMap { child in
                guard document.node(child)?.tagName != nil else { return nil }
                return .object(context.wrap(child))
              }))
        case "childNodes":
          return .object(
            context.arrayOf(node.children.map { .object(context.wrap($0)) }))
        case "childElementCount":
          return .number(
            Double(
              node.children.filter { document.node($0)?.tagName != nil }.count))
        case "options":
          return .object(context.arrayOf(optionElements(of: id, document: document,
            context: context)))
        case "selectedIndex": return .number(Double(selectedIndex(of: id, document: document)))
        case "rows":
          return .object(
            context.arrayOf(
              document.querySelectorAll("tr").filter { descendant($0, of: id, document: document) }
                .map { .object(context.wrap($0)) }))
        case "cells":
          return .object(
            context.arrayOf(
              document.querySelectorAll("td,th").filter {
                descendant($0, of: id, document: document)
              }.map { .object(context.wrap($0)) }))
        default:
          if let media = JSMediaElement.property(id, context: context, name: key) {
            return media
          }
          return node.attribute(key).map(JSValue.string)
        }
      },
      nativeSet: { [weak document] key, value in
        guard let document, document.node(id) != nil else { return false }
        switch key {
        case "value":
          document.setAttribute("value", value: value.description, on: id)
          return true
        case "id":
          document.setAttribute("id", value: value.description, on: id)
          return true
        case "className":
          document.setAttribute("class", value: value.description, on: id)
          return true
        case "textContent", "innerText":
          setTextContent(value.description, on: id, document: document)
          return true
        case "checked":
          if value.truthy {
            document.setAttribute("checked", value: "", on: id)
          } else {
            document.removeAttribute("checked", from: id)
          }
          return true
        case "selectedIndex":
          setSelectedIndex(value, of: id, document: document)
          return true
        default:
          if JSMediaElement.setProperty(id, context: context, name: key, value: value) {
            return true
          }
          return false
        }
      }, nativeNodeID: id)
    installNodeMethods(object, id: id, context: context)
    installNodeListeners(object, id: id, events: events)
    installNodeProperties(object, id: id, context: context)
    return object
  }

  static func defaultInputType(node: DOMNode) -> String {
    node.tagName == "input" ? "text" : ""
  }

  static func nodeType(of node: DOMNode) -> Int {
    switch node.kind {
    case .element: return 1
    case .text: return 3
    case .comment: return 8
    case .document: return 9
    }
  }

  static func inputValue(node: DOMNode, id: NodeID, document: DOMDocument) -> String {
    if let value = node.attribute("value") { return value }
    if node.tagName == "textarea" { return document.textContent(of: id) }
    if node.tagName == "option" { return document.textContent(of: id) }
    if node.tagName == "select" {
      let options = optionElements(of: id, document: document, context: nil)
      for option in options {
        if case .object(let object) = option,
          let nodeID = object.nativeNodeID,
          document.node(nodeID)?.attribute("selected") != nil
        {
          return document.textContent(of: nodeID)
        }
      }
      if case .object(let first) = options.first, let nodeID = first.nativeNodeID {
        return document.textContent(of: nodeID)
      }
      return ""
    }
    return ""
  }

  static func optionElements(
    of id: NodeID, document: DOMDocument, context: JSDOMContext?
  ) -> [JSValue] {
    document.querySelectorAll("option").filter { descendant($0, of: id, document: document) }
      .map { option in
        if let context { return .object(context.wrap(option)) }
        let placeholder = JSObject(nativeNodeID: option)
        return .object(placeholder)
      }
  }

  static func selectedIndex(of id: NodeID, document: DOMDocument) -> Int {
    let options = document.querySelectorAll("option").filter {
      descendant($0, of: id, document: document)
    }
    for (index, option) in options.enumerated() {
      if document.node(option)?.attribute("selected") != nil { return index }
    }
    return options.isEmpty ? -1 : 0
  }

  static func setSelectedIndex(_ value: JSValue, of id: NodeID, document: DOMDocument) {
    guard case .number(let number) = value else { return }
    let options = document.querySelectorAll("option").filter {
      descendant($0, of: id, document: document)
    }
    let index = Int(number)
    for option in options { document.removeAttribute("selected", from: option) }
    if options.indices.contains(index) {
      document.setAttribute("selected", value: "", on: options[index])
    }
  }

  static func sibling(
    of id: NodeID, document: DOMDocument, context: JSDOMContext, forward: Bool
  ) -> JSValue {
    elementSibling(of: id, document: document, context: context, forward: forward)
  }

  static func elementSibling(
    of id: NodeID, document: DOMDocument, context: JSDOMContext, forward: Bool
  ) -> JSValue {
    guard let node = document.node(id), let parent = node.parent,
      let siblings = document.node(parent)?.children,
      let position = siblings.firstIndex(of: id)
    else {
      return .null
    }
    if forward {
      for candidate in siblings[(position + 1)...] {
        if document.node(candidate)?.tagName != nil {
          return .object(context.wrap(candidate))
        }
      }
    } else {
      for candidate in siblings[..<position].reversed() {
        if document.node(candidate)?.tagName != nil {
          return .object(context.wrap(candidate))
        }
      }
    }
    return .null
  }

  static func anySibling(
    of id: NodeID, document: DOMDocument, context: JSDOMContext, forward: Bool
  ) -> JSValue {
    guard let node = document.node(id), let parent = node.parent,
      let siblings = document.node(parent)?.children,
      let position = siblings.firstIndex(of: id)
    else {
      return .null
    }
    if forward {
      if position + 1 < siblings.count { return .object(context.wrap(siblings[position + 1])) }
    } else {
      if position > 0 { return .object(context.wrap(siblings[position - 1])) }
    }
    return .null
  }

  static func firstElement(_ tag: String, context: JSDOMContext) -> JSValue? {
    guard let id = context.document.elements(named: tag).first else { return nil }
    return .object(context.wrap(id))
  }

  static func descendant(
    _ candidate: NodeID, of ancestor: NodeID, document: DOMDocument
  ) -> Bool {
    if candidate == ancestor { return true }
    var current = document.parent(of: candidate)
    while let id = current {
      if id == ancestor { return true }
      current = document.parent(of: id)
    }
    return false
  }

  static func setTextContent(_ value: String, on id: NodeID, document: DOMDocument) {
    guard let node = document.node(id) else { return }
    switch node.kind {
    case .text, .comment:
      document.setText(value, on: id)
    case .document, .element:
      for child in node.children { document.remove(child) }
      if !value.isEmpty {
        let text = document.createText(value)
        document.appendChild(text, to: id)
      }
    }
  }

  static func installDocumentMethods(_ object: JSObject, context: JSDOMContext) {
    let document = context.document
    object.defineNative("querySelector") { args in
      guard case .string(let selector) = args.first,
        let id = document.querySelector(selector)
      else {
        return .null
      }
      return .object(context.wrap(id))
    }
    object.defineNative("querySelectorAll") { args in
      guard case .string(let selector) = args.first else {
        return .object(context.arrayOf([]))
      }
      return .object(
        context.arrayOf(
          document.querySelectorAll(selector).map { .object(context.wrap($0)) }))
    }
    object.defineNative("getElementById") { args in
      guard case .string(let value) = args.first,
        let id = document.element(withID: value)
      else {
        return .null
      }
      return .object(context.wrap(id))
    }
    object.defineNative("getElementsByTagName") { args in
      guard case .string(let tag) = args.first else {
        return .object(context.arrayOf([]))
      }
      let needle = tag.lowercased()
      let matches: [NodeID]
      if needle == "*" {
        matches = document.allNodeIDs().filter { document.node($0)?.tagName != nil }
      } else {
        matches = document.elements(named: needle)
      }
      return .object(context.arrayOf(matches.map { .object(context.wrap($0)) }))
    }
    object.defineNative("getElementsByClassName") { args in
      guard case .string(let names) = args.first else {
        return .object(context.arrayOf([]))
      }
      let required = Set(names.split(whereSeparator: { $0.isWhitespace }).map(String.init))
      if required.isEmpty { return .object(context.arrayOf([])) }
      let matches = document.allNodeIDs().filter { id in
        guard let node = document.node(id), node.tagName != nil else { return false }
        let classes = Set(
          (node.attribute("class") ?? "").split(whereSeparator: { $0.isWhitespace }).map(
            String.init))
        return required.isSubset(of: classes)
      }
      return .object(context.arrayOf(matches.map { .object(context.wrap($0)) }))
    }
    object.defineNative("getElementsByName") { args in
      guard case .string(let name) = args.first else {
        return .object(context.arrayOf([]))
      }
      let matches = document.allNodeIDs().filter {
        document.node($0)?.attribute("name") == name
      }
      return .object(context.arrayOf(matches.map { .object(context.wrap($0)) }))
    }
    object.defineNative("createElement") { args in
      guard case .string(let tag) = args.first, !tag.isEmpty else { return .null }
      return .object(context.wrap(document.createElement(tag)))
    }
    object.defineNative("createElementNS") { args in
      guard args.count > 1, case .string(let tag) = args[1], !tag.isEmpty else {
        return .null
      }
      return .object(context.wrap(document.createElement(tag)))
    }
    object.defineNative("createTextNode") { args in
      let value = args.first?.description ?? ""
      return .object(context.wrap(document.createText(value)))
    }
    object.defineNative("createComment") { args in
      let value = args.first?.description ?? ""
      return .object(context.wrap(document.createComment(value)))
    }
    object.defineNative("createEvent") { args in
      guard case .string(let kind) = args.first else {
        throw JSError.type("Event interface name required")
      }
      return .object(JSDOMEvents.makeEvent(kind: kind, context: context))
    }
    object.defineNative("hasFocus") { _ in .bool(true) }
    object.defineNative("open") { _ in .undefined }
    object.defineNative("close") { _ in .undefined }
    object.defineNative("write") { _ in .undefined }
    object.defineNative("writeln") { _ in .undefined }
    object.defineNative("importNode") { args in
      guard case .object(let node) = args.first, let nodeID = node.nativeNodeID else {
        return .null
      }
      let deep = args.count > 1 ? args[1].truthy : true
      return .object(context.wrap(cloneSubtree(nodeID, deep: deep, context: context)))
    }
  }

  static func installDocumentCollections(_ object: JSObject, context: JSDOMContext) {
    let document = context.document
    object.nativeGet = extendGetter(
      object.nativeGet,
      extra: { [weak document] key in
        guard document != nil else { return nil }
        switch key {
        case "forms":
          return .object(
            context.arrayOf(
              document!.elements(named: "form").map { .object(context.wrap($0)) }))
        case "images":
          return .object(
            context.arrayOf(
              document!.elements(named: "img").map { .object(context.wrap($0)) }))
        case "links":
          return .object(
            context.arrayOf(
              document!.elements(named: "a").filter {
                document!.node($0)?.attribute("href") != nil
              }.map { .object(context.wrap($0)) }))
        case "scripts":
          return .object(
            context.arrayOf(
              document!.elements(named: "script").map { .object(context.wrap($0)) }))
        case "embeds":
          return .object(
            context.arrayOf(
              document!.elements(named: "embed").map { .object(context.wrap($0)) }))
        case "plugins":
          return .object(
            context.arrayOf(
              document!.elements(named: "embed").map { .object(context.wrap($0)) }))
        case "anchors":
          return .object(
            context.arrayOf(
              document!.elements(named: "a").filter {
                document!.node($0)?.attribute("name") != nil
              }.map { .object(context.wrap($0)) }))
        case "applets": return .object(context.arrayOf([]))
        default: return nil
        }
      })
  }

  static func extendGetter(
    _ existing: ((String) -> JSValue?)?, extra: @escaping (String) -> JSValue?
  ) -> (String) -> JSValue? {
    { key in
      if let value = existing?(key) { return value }
      return extra(key)
    }
  }

  static func installNodeMethods(_ object: JSObject, id: NodeID, context: JSDOMContext) {
    let document = context.document
    let events = context.events
    object.defineNative("getAttribute") { args in
      guard case .string(let name) = args.first,
        let node = document.node(id), let value = node.attribute(name)
      else {
        return .null
      }
      return .string(value)
    }
    object.defineNative("setAttribute") { args in
      guard case .string(let name) = args.first, args.count > 1 else { return .undefined }
      document.setAttribute(name, value: args[1].description, on: id)
      return .undefined
    }
    object.defineNative("setAttributeNS") { args in
      guard args.count > 2, case .string(let name) = args[1] else { return .undefined }
      document.setAttribute(name, value: args[2].description, on: id)
      return .undefined
    }
    object.defineNative("removeAttribute") { args in
      guard case .string(let name) = args.first else { return .undefined }
      document.removeAttribute(name, from: id)
      return .undefined
    }
    object.defineNative("hasAttribute") { args in
      guard case .string(let name) = args.first,
        let node = document.node(id)
      else {
        return .bool(false)
      }
      return .bool(node.attribute(name) != nil)
    }
    object.defineNative("toggleAttribute") { args in
      guard case .string(let name) = args.first,
        document.node(id) != nil
      else {
        return .bool(false)
      }
      let force: Bool? = args.count > 1 ? args[1].truthy : nil
      let present = document.node(id)?.attribute(name) != nil
      if let force {
        if force { document.setAttribute(name, value: "", on: id) }
        else { document.removeAttribute(name, from: id) }
        return .bool(force)
      }
      if present {
        document.removeAttribute(name, from: id)
        return .bool(false)
      }
      document.setAttribute(name, value: "", on: id)
      return .bool(true)
    }
    object.defineNative("appendChild") { args in
      guard case .object(let child) = args.first, let childID = child.nativeNodeID,
        document.node(childID) != nil
      else {
        return .null
      }
      document.appendChild(childID, to: id)
      return .object(context.wrap(childID))
    }
    object.defineNative("removeChild") { args in
      guard case .object(let child) = args.first, let childID = child.nativeNodeID else {
        throw JSError.type("Child must be a node")
      }
      document.remove(childID)
      return .object(context.wrap(childID))
    }
    object.defineNative("insertBefore") { args in
      guard case .object(let child) = args.first, let childID = child.nativeNodeID else {
        return .null
      }
      var sibling: NodeID?
      if args.count > 1, case .object(let other) = args[1] {
        sibling = other.nativeNodeID
      }
      document.insertBefore(childID, before: sibling, in: id)
      return .object(context.wrap(childID))
    }
    object.defineNative("replaceChild") { args in
      guard args.count > 1, case .object(let child) = args[0],
        let childID = child.nativeNodeID,
        case .object(let old) = args[1], let oldID = old.nativeNodeID
      else {
        return .null
      }
      document.insertBefore(childID, before: oldID, in: id)
      document.remove(oldID)
      return .object(context.wrap(oldID))
    }
    object.defineNative("cloneNode") { args in
      let deep = args.first?.truthy ?? false
      return .object(context.wrap(cloneSubtree(id, deep: deep, context: context)))
    }
    object.defineNative("contains") { args in
      guard case .object(let other) = args.first, let otherID = other.nativeNodeID else {
        return .bool(false)
      }
      return .bool(descendant(otherID, of: id, document: document))
    }
    object.defineNative("matches") { args in
      guard case .string(let selector) = args.first,
        let node = document.node(id), node.tagName != nil
      else {
        return .bool(false)
      }
      return .bool(document.querySelectorAll(selector).contains(id))
    }
    object.defineNative("closest") { args in
      guard case .string(let selector) = args.first else { return .null }
      let matches = Set(document.querySelectorAll(selector))
      var current: NodeID? = id
      while let candidate = current {
        if matches.contains(candidate) { return .object(context.wrap(candidate)) }
        current = document.parent(of: candidate)
      }
      return .null
    }
    object.defineNative("querySelector") { args in
      guard case .string(let selector) = args.first else { return .null }
      let matches = document.querySelectorAll(selector)
      guard let found = matches.first(where: { descendant($0, of: id, document: document) })
      else {
        return .null
      }
      return .object(context.wrap(found))
    }
    object.defineNative("querySelectorAll") { args in
      guard case .string(let selector) = args.first else {
        return .object(context.arrayOf([]))
      }
      let matches = document.querySelectorAll(selector).filter {
        $0 != id && descendant($0, of: id, document: document)
      }
      return .object(context.arrayOf(matches.map { .object(context.wrap($0)) }))
    }
    object.defineNative("getElementsByTagName") { args in
      guard case .string(let tag) = args.first else {
        return .object(context.arrayOf([]))
      }
      let needle = tag.lowercased()
      var matches: [NodeID] = []
      for candidate in document.depthFirst(from: id) {
        if candidate == id { continue }
        guard descendant(candidate, of: id, document: document) else { continue }
        guard let node = document.node(candidate), let tagName = node.tagName else {
          continue
        }
        if needle == "*" || tagName == needle { matches.append(candidate) }
      }
      return .object(context.arrayOf(matches.map { .object(context.wrap($0)) }))
    }
    object.defineNative("getElementsByClassName") { args in
      guard case .string(let names) = args.first else {
        return .object(context.arrayOf([]))
      }
      let required = Set(names.split(whereSeparator: { $0.isWhitespace }).map(String.init))
      if required.isEmpty { return .object(context.arrayOf([])) }
      var matches: [NodeID] = []
      for candidate in document.depthFirst(from: id) {
        if candidate == id { continue }
        guard descendant(candidate, of: id, document: document) else { continue }
        guard let node = document.node(candidate), node.tagName != nil else { continue }
        let classes = Set(
          (node.attribute("class") ?? "").split(whereSeparator: { $0.isWhitespace }).map(
            String.init))
        if required.isSubset(of: classes) { matches.append(candidate) }
      }
      return .object(context.arrayOf(matches.map { .object(context.wrap($0)) }))
    }
    object.defineNative("append") { args in
      for argument in args {
        if case .object(let child) = argument, let childID = child.nativeNodeID,
          document.node(childID) != nil
        {
          document.appendChild(childID, to: id)
        } else {
          document.appendChild(document.createText(argument.description), to: id)
        }
      }
      return .undefined
    }
    object.defineNative("prepend") { args in
      let first = document.node(id)?.children.first
      for argument in args.reversed() {
        if case .object(let child) = argument, let childID = child.nativeNodeID,
          document.node(childID) != nil
        {
          document.insertBefore(childID, before: first, in: id)
        } else {
          document.insertBefore(
            document.createText(argument.description), before: first, in: id)
        }
      }
      return .undefined
    }
    object.defineNative("before") { args in
      guard let parent = document.node(id)?.parent else { return .undefined }
      for argument in args {
        if case .object(let child) = argument, let childID = child.nativeNodeID,
          document.node(childID) != nil
        {
          document.insertBefore(childID, before: id, in: parent)
        } else {
          document.insertBefore(
            document.createText(argument.description), before: id, in: parent)
        }
      }
      return .undefined
    }
    object.defineNative("after") { args in
      guard let parent = document.node(id)?.parent,
        let siblings = document.node(parent)?.children,
        let position = siblings.firstIndex(of: id)
      else {
        return .undefined
      }
      let next: NodeID? = position + 1 < siblings.count ? siblings[position + 1] : nil
      for argument in args {
        if case .object(let child) = argument, let childID = child.nativeNodeID,
          document.node(childID) != nil
        {
          document.insertBefore(childID, before: next, in: parent)
        } else {
          document.insertBefore(
            document.createText(argument.description), before: next, in: parent)
        }
      }
      return .undefined
    }
    object.defineNative("replaceWith") { args in
      guard let parent = document.node(id)?.parent else { return .undefined }
      for argument in args {
        if case .object(let child) = argument, let childID = child.nativeNodeID,
          document.node(childID) != nil
        {
          document.insertBefore(childID, before: id, in: parent)
        } else {
          document.insertBefore(
            document.createText(argument.description), before: id, in: parent)
        }
      }
      document.remove(id)
      return .undefined
    }
    object.defineNative("remove") { _ in
      document.remove(id)
      return .undefined
    }
    object.defineNative("click") { _ in
      guard document.node(id) != nil else { return .undefined }
      let event = JSDOMEvents.makeEvent(kind: "MouseEvents", context: context)
      event.set("type", .string("click"))
      event.set("bubbles", .bool(true))
      event.set("cancelable", .bool(true))
      let prevented = events.dispatch?(event, id) ?? false
      if !prevented {
        defaultClickAction(id: id, context: context)
      }
      return .undefined
    }
    object.defineNative("focus") { _ in
      guard document.node(id) != nil else { return .undefined }
      let event = JSDOMEvents.makeEvent(kind: "Event", context: context)
      event.set("type", .string("focus"))
      event.set("bubbles", .bool(false))
      _ = events.dispatch?(event, id)
      return .undefined
    }
    object.defineNative("blur") { _ in
      guard document.node(id) != nil else { return .undefined }
      let event = JSDOMEvents.makeEvent(kind: "Event", context: context)
      event.set("type", .string("blur"))
      event.set("bubbles", .bool(false))
      _ = events.dispatch?(event, id)
      return .undefined
    }
    object.defineNative("submit") { _ in
      context.hooks().formSubmitHandler?(id)
      return .undefined
    }
    object.defineNative("reset") { _ in
      guard let node = document.node(id), node.tagName == "form" else { return .undefined }
      for input in document.querySelectorAll("input").filter({
        descendant($0, of: id, document: document)
      }) {
        document.removeAttribute("value", from: input)
        document.removeAttribute("checked", from: input)
      }
      return .undefined
    }
    object.defineNative("scrollIntoView") { _ in .undefined }
  }

  static func defaultClickAction(id: NodeID, context: JSDOMContext) {
    let document = context.document
    guard let node = document.node(id), let tag = node.tagName else { return }
    if tag == "input", node.attribute("type")?.lowercased() == "checkbox" {
      if node.attribute("checked") != nil {
        document.removeAttribute("checked", from: id)
      } else {
        document.setAttribute("checked", value: "", on: id)
      }
      return
    }
    if tag == "input", node.attribute("type")?.lowercased() == "radio" {
      if let name = node.attribute("name") {
        for candidate in document.allNodeIDs() {
          guard let other = document.node(candidate),
            other.tagName == "input",
            other.attribute("type")?.lowercased() == "radio",
            other.attribute("name") == name
          else {
            continue
          }
          document.removeAttribute("checked", from: candidate)
        }
      }
      document.setAttribute("checked", value: "", on: id)
      return
    }
    let submitTypes: Set<String> = ["submit", "image"]
    if (tag == "input" && submitTypes.contains(node.attribute("type")?.lowercased() ?? ""))
      || (tag == "button"
        && (node.attribute("type")?.lowercased() ?? "submit") == "submit")
    {
      var current: NodeID? = id
      while let candidate = current {
        if document.node(candidate)?.tagName == "form" {
          context.hooks().formSubmitHandler?(candidate)
          return
        }
        current = document.parent(of: candidate)
      }
    }
  }

  static func cloneSubtree(_ id: NodeID, deep: Bool, context: JSDOMContext) -> NodeID {
    let document = context.document
    guard let node = document.node(id) else { return id }
    let copy: NodeID
    switch node.kind {
    case .element(let tag):
      copy = document.createElement(tag.string)
    case .text(let text):
      copy = document.createText(text)
      return copy
    case .comment(let text):
      copy = document.createComment(text)
      return copy
    case .document:
      copy = document.createElement("div")
    }
    for attribute in node.attributes {
      document.setAttribute(attribute.name.string, value: attribute.value, on: copy)
    }
    if deep {
      for child in node.children {
        document.appendChild(cloneSubtree(child, deep: true, context: context), to: copy)
      }
    }
    return copy
  }

  static func installNodeProperties(_ object: JSObject, id: NodeID, context: JSDOMContext) {
    JSDOMEvents.installNodeExtras(object, id: id, context: context)
    JSMediaElement.installExtras(object, id: id, context: context)
  }

  static func installNodeListeners(
    _ object: JSObject, id: NodeID, events: JSEventRegistry
  ) {
    object.defineNative("addEventListener") { args in
      guard args.count > 1, case .string(let type) = args[0],
        case .function(let function) = args[1]
      else {
        return .undefined
      }
      events.add(function, type: type, nodeID: id)
      return .undefined
    }
    object.defineNative("removeEventListener") { args in
      guard args.count > 1, case .string(let type) = args[0],
        case .function(let function) = args[1]
      else {
        return .undefined
      }
      events.remove(function, type: type, nodeID: id)
      return .undefined
    }
    object.defineNative("dispatchEvent") { args in
      guard case .object(let event) = args.first else {
        throw JSError.type("Argument must be an event")
      }
      return .bool(!(events.dispatch?(event, id) ?? false))
    }
  }

  static func installDocumentListeners(
    _ object: JSObject, context: JSDOMContext, nodeID: NodeID
  ) {
    installNodeListeners(object, id: nodeID, events: context.events)
  }
}