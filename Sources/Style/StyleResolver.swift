import CSS
import DOM
import EngineCore
import Foundation

public enum StyleResolver {
  private struct CascadeKey: Comparable {
    var important: Int
    var effectiveRank: Int
    var specificity: CSSSpecificity
    var sourceOrder: Int

    static func < (lhs: CascadeKey, rhs: CascadeKey) -> Bool {
      if lhs.important != rhs.important { return lhs.important < rhs.important }
      if lhs.effectiveRank != rhs.effectiveRank { return lhs.effectiveRank < rhs.effectiveRank }
      if lhs.specificity != rhs.specificity { return lhs.specificity < rhs.specificity }
      return lhs.sourceOrder < rhs.sourceOrder
    }
  }

  public static func resolve(
    document: DOMDocument, stylesheets: [Stylesheet],
    viewport: Size = Size(width: 1280, height: 800)
  ) -> StyledDocument {
    var layerOrder = LayerOrder()
    for sheet in stylesheets {
      for name in sheet.layerOrder { layerOrder.declare(name) }
    }
    let rules = stylesheets.flatMap(\.rules)
    var prepared: [(rank: Int, rule: CSSRule)] = []
    for rule in rules {
      if let media = rule.media, !MediaQuery.matchesAny(media, viewport: viewport) { continue }
      prepared.append((layerOrder.rank(of: rule.layer), rule))
    }
    var computed: [NodeID: ComputedStyle] = [:]
    var customProps: [NodeID: [String: String]] = [:]
    var rootFontSize = 16.0
    for id in document.depthFirst() {
      guard let node = document.node(id) else { continue }
      let parentStyle = node.parent.flatMap { computed[$0] }
      let parentProps = node.parent.flatMap { customProps[$0] } ?? [:]
      var style = initialStyle(for: node, parent: parentStyle)
      var winners: [String: (CascadeKey, CSSDeclaration)] = [:]

      if case .element = node.kind {
        for entry in prepared {
          let rank = entry.rank
          let rule = entry.rule
          for selector in rule.selectors
          where SelectorMatcher.matches(selector, node: id, document: document) {
            let specificity = selector.specificity
            for declaration in rule.declarations {
              let important = declaration.important ? 2 : 0
              let key = CascadeKey(
                important: important,
                effectiveRank: declaration.important ? -rank : rank,
                specificity: specificity,
                sourceOrder: rule.sourceOrder)
              if let existing = winners[declaration.property], existing.0 > key { continue }
              winners[declaration.property] = (key, declaration)
            }
          }
        }

        if let inline = node.attribute("style") {
          for declaration in CSSParser.parseDeclarations(inline) {
            let key = CascadeKey(
              important: declaration.important ? 3 : 1,
              effectiveRank: 0,
              specificity: CSSSpecificity(ids: 1_000, classes: 0, types: 0), sourceOrder: Int.max)
            winners[declaration.property] = (key, declaration)
          }
        }
      }

      var props = parentProps
      for (_, pair) in winners where pair.1.isCustomProperty {
        props[pair.1.property] = pair.1.value
      }
      customProps[id] = props
      for (_, pair) in winners.sorted(by: { $0.key < $1.key }) {
        if pair.1.isCustomProperty { continue }
        apply(pair.1, to: &style, customProps: props, rootFontSize: rootFontSize, viewport: viewport)
      }
      if node.tagName == "html" { rootFontSize = style.fontSize }
      computed[id] = style
    }
    return StyledDocument(
      document: document, styles: computed, sourceMutationVersion: document.mutationVersion)
  }

  private static func initialStyle(for node: DOMNode, parent: ComputedStyle?) -> ComputedStyle {
    var style = ComputedStyle()
    if let parent {
      style.color = parent.color
      style.fontSize = parent.fontSize
      style.fontWeight = parent.fontWeight
      style.fontFamily = parent.fontFamily
      style.lineHeight = parent.lineHeight
      style.visibility = parent.visibility
    }
    guard let tag = node.tagName else {
      style.display = .inline
      return style
    }
    switch tag {
    case "html", "body", "div", "main", "section", "article", "header", "footer", "nav", "aside",
      "form", "p", "ul", "ol", "li", "pre", "blockquote":
      style.display = .block
    case "h1":
      style.display = .block
      style.fontSize = 32
      style.fontWeight = 700
    case "h2":
      style.display = .block
      style.fontSize = 24
      style.fontWeight = 700
    case "h3":
      style.display = .block
      style.fontSize = 20
      style.fontWeight = 700
    case "h4", "h5", "h6":
      style.display = .block
      style.fontWeight = 700
    case "table": style.display = .table
    case "script", "style", "head", "meta", "link", "title": style.display = .none
    case "button", "input", "textarea", "select", "img": style.display = .inlineBlock
    default: style.display = .inline
    }
    return style
  }

  private static func apply(
    _ declaration: CSSDeclaration, to style: inout ComputedStyle,
    customProps: [String: String], rootFontSize: Double, viewport: Size
  ) {
    let substituted = CSSCalc.substituteVars(
      declaration.value, customProps: customProps, depth: 0)
    let value = substituted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch declaration.property {
    case "display":
      style.display =
        DisplayType(rawValue: value.replacingOccurrences(of: "inline-block", with: "inlineBlock"))
        ?? style.display
    case "position": style.position = PositionType(rawValue: value) ?? style.position
    case "color": if let color = RGBAColor.parse(value) { style.color = color }
    case "background", "background-color":
      if let color = RGBAColor.parse(value) { style.backgroundColor = color }
    case "font-size":
      if let resolved = CSSCalc.resolveValue(
        value, customProps: customProps, reference: style.fontSize, fontSize: style.fontSize,
        rootFontSize: rootFontSize, viewport: viewport)
      {
        style.fontSize = max(1, resolved)
      }
    case "font-weight":
      if value == "bold" {
        style.fontWeight = 700
      } else if value == "normal" {
        style.fontWeight = 400
      } else if let number = Int(value) {
        style.fontWeight = number
      }
    case "font-family":
      let family = substituted.split(separator: ",").first.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      } ?? ""
      if !family.isEmpty { style.fontFamily = family }
    case "line-height":
      if value == "normal" {
        style.lineHeight = 1.2
      } else if let number = Double(value) {
        style.lineHeight = max(0.5, number)
      } else if let resolved = CSSCalc.resolveValue(
        value, customProps: customProps, reference: style.fontSize, fontSize: style.fontSize,
        rootFontSize: rootFontSize, viewport: viewport)
      {
        style.lineHeight = max(0.5, resolved / max(1, style.fontSize))
      }
    case "visibility":
      style.visibility = VisibilityMode(rawValue: value) ?? style.visibility
    case "contain": style.contain = ContainFlags.parse(value)
    case "content-visibility":
      style.contentVisibility = ContentVisibility(rawValue: value) ?? style.contentVisibility
    case "width":
      if let length = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.width = length }
    case "height":
      if let length = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.height = length }
    case "min-width":
      if let length = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.minWidth = length }
    case "max-width":
      if let length = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.maxWidth = length }
    case "margin":
      style.margin = parseBox(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
    case "margin-top":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.margin.top = l }
    case "margin-right":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.margin.right = l }
    case "margin-bottom":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.margin.bottom = l }
    case "margin-left":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.margin.left = l }
    case "padding":
      style.padding = parseBox(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
    case "padding-top":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.padding.top = l }
    case "padding-right":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.padding.right = l }
    case "padding-bottom":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.padding.bottom = l }
    case "padding-left":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.padding.left = l }
    case "border-width":
      style.borderWidth = parseBox(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
    case "border-color": if let color = RGBAColor.parse(value) { style.borderColor = color }
    case "flex-direction":
      style.flexDirection = FlexDirection(rawValue: value) ?? style.flexDirection
    case "flex-grow": style.flexGrow = Double(value) ?? style.flexGrow
    case "gap":
      if let resolved = CSSCalc.resolveValue(
        value, customProps: customProps, reference: 0, fontSize: style.fontSize,
        rootFontSize: rootFontSize, viewport: viewport)
      {
        style.gap = resolved
      }
    case "grid-template-columns":
      style.gridColumns = max(1, value.split(whereSeparator: { $0.isWhitespace }).count)
    case "overflow":
      let mode = OverflowMode(rawValue: value) ?? .visible
      style.overflowX = mode
      style.overflowY = mode
    case "overflow-x": style.overflowX = OverflowMode(rawValue: value) ?? style.overflowX
    case "overflow-y": style.overflowY = OverflowMode(rawValue: value) ?? style.overflowY
    case "opacity": style.opacity = min(1, max(0, Double(value) ?? style.opacity))
    case "left":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.left = l }
    case "top":
      if let l = parseLength(
        value, customProps: customProps, fontSize: style.fontSize, rootFontSize: rootFontSize,
        viewport: viewport)
      { style.top = l }
    case "z-index": style.zIndex = Int(value) ?? style.zIndex
    default: break
    }
  }

  private static func parseLength(
    _ value: String, customProps: [String: String], fontSize: Double, rootFontSize: Double,
    viewport: Size
  ) -> CSSLength? {
    if let direct = CSSLength.parse(value) { return direct }
    if let resolved = CSSCalc.resolveValue(
      value, customProps: customProps, reference: 0, fontSize: fontSize,
      rootFontSize: rootFontSize, viewport: viewport)
    {
      return .px(resolved)
    }
    return nil
  }

  private static func parseBox(
    _ value: String, customProps: [String: String], fontSize: Double, rootFontSize: Double,
    viewport: Size
  ) -> StyleLength {
    let substituted = CSSCalc.substituteVars(value, customProps: customProps, depth: 0)
    let items = substituted.split(whereSeparator: { $0.isWhitespace }).compactMap { token -> CSSLength? in
      let text = String(token)
      if let direct = CSSLength.parse(text) { return direct }
      if let resolved = CSSCalc.resolveValue(
        text, customProps: customProps, reference: 0, fontSize: fontSize,
        rootFontSize: rootFontSize, viewport: viewport)
      {
        return .px(resolved)
      }
      return nil
    }
    switch items.count {
    case 1: return StyleLength(top: items[0], right: items[0], bottom: items[0], left: items[0])
    case 2: return StyleLength(top: items[0], right: items[1], bottom: items[0], left: items[1])
    case 3: return StyleLength(top: items[0], right: items[1], bottom: items[2], left: items[1])
    case 4: return StyleLength(top: items[0], right: items[1], bottom: items[2], left: items[3])
    default: return .zero
    }
  }
}
