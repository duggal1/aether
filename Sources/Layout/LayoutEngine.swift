import CSS
import DOM
import EngineCore
import Foundation
import Style
import Text

public struct LayoutEngine: Sendable {
  private let textMeasurer: any TextMeasuring

  public init(textMeasurer: any TextMeasuring = SystemTextMeasurer()) {
    self.textMeasurer = textMeasurer
  }

  public func layout(_ styled: StyledDocument, viewport: Size) -> LayoutTree {
    var state = State(styled: styled, viewport: viewport, textMeasurer: textMeasurer)
    let root = styled.document.root
    let rootConstraint = Rect(x: 0, y: 0, width: viewport.width, height: viewport.height)
    _ = state.layoutNode(root, containing: rootConstraint, forcedWidth: viewport.width)
    let maxY = state.boxes.values.map(\.frame.maxY).max() ?? viewport.height
    let maxX = state.boxes.values.map(\.frame.maxX).max() ?? viewport.width
    return LayoutTree(
      boxes: state.boxes,
      paintOrder: state.paintOrder,
      contentSize: Size(width: max(viewport.width, maxX), height: max(viewport.height, maxY)),
      viewport: viewport,
      sourceMutationVersion: styled.sourceMutationVersion
    )
  }

  private struct State {
    let styled: StyledDocument
    let viewport: Size
    let textMeasurer: any TextMeasuring
    var boxes: [NodeID: LayoutBox] = [:]
    var paintOrder: [NodeID] = []

    mutating func layoutNode(_ id: NodeID, containing: Rect, forcedWidth: Double? = nil) -> Size {
      guard let node = styled.document.node(id) else { return .zero }
      let style = styled.style(for: id)
      guard style.display != .none else { return .zero }

      if case .text(let text) = node.kind {
        let available = max(0, forcedWidth ?? containing.width)
        let metrics = textMeasurer.measure(
          text, fontSize: style.fontSize, fontWeight: style.fontWeight,
          maxWidth: available > 0 ? available : nil)
        let frame = Rect(
          x: containing.minX, y: containing.minY,
          width: min(available > 0 ? available : metrics.size.width, metrics.size.width),
          height: metrics.size.height)
        boxes[id] = LayoutBox(
          nodeID: id, frame: frame, contentFrame: frame, style: style, baseline: metrics.ascent)
        paintOrder.append(id)
        return frame.size
      }

      let margins = resolve(style.margin, reference: containing.width, fontSize: style.fontSize)
      let padding = resolve(style.padding, reference: containing.width, fontSize: style.fontSize)
      let borders = resolve(
        style.borderWidth, reference: containing.width, fontSize: style.fontSize)
      let horizontalChrome = padding.horizontal + borders.horizontal
      let verticalChrome = padding.vertical + borders.vertical
      let availableWidth = max(0, containing.width - margins.horizontal)
      let intrinsic = intrinsicSize(
        for: id, node: node, style: style, availableWidth: availableWidth)
      var width =
        forcedWidth ?? resolve(style.width, reference: availableWidth, fontSize: style.fontSize)
      if width == nil {
        width = intrinsic?.width ?? max(0, availableWidth - horizontalChrome)
      }
      width = clampWidth(width ?? 0, style: style, reference: availableWidth)

      var x = containing.minX + margins.left
      var y = containing.minY + margins.top
      if style.position == .absolute || style.position == .fixed {
        if let left = resolve(style.left, reference: containing.width, fontSize: style.fontSize) {
          x = containing.minX + left
        }
        if let top = resolve(style.top, reference: containing.height, fontSize: style.fontSize) {
          y = containing.minY + top
        }
      } else if style.position == .relative {
        x += resolve(style.left, reference: containing.width, fontSize: style.fontSize) ?? 0
        y += resolve(style.top, reference: containing.height, fontSize: style.fontSize) ?? 0
      }

      let contentX = x + borders.left + padding.left
      let contentY = y + borders.top + padding.top
      let contentWidth = max(0, (width ?? 0))
      let contentConstraint = Rect(
        x: contentX, y: contentY, width: contentWidth, height: max(0, containing.height))

      let children = node.children.filter { styled.style(for: $0).display != .none }
      let contentHeight: Double
      switch style.display {
      case .flex:
        contentHeight = layoutFlex(children, in: contentConstraint, style: style)
      case .grid:
        contentHeight = layoutGrid(children, in: contentConstraint, style: style)
      default:
        contentHeight = layoutFlow(children, in: contentConstraint, parentStyle: style)
      }

      let explicitHeight = resolve(
        style.height, reference: containing.height, fontSize: style.fontSize)
      let innerHeight = explicitHeight ?? max(contentHeight, intrinsic?.height ?? 0)
      let frame = Rect(
        x: x,
        y: y,
        width: max(0, (width ?? 0) + horizontalChrome),
        height: max(0, innerHeight + verticalChrome)
      )
      let contentFrame = Rect(
        x: contentX, y: contentY, width: contentWidth, height: max(0, innerHeight))
      boxes[id] = LayoutBox(nodeID: id, frame: frame, contentFrame: contentFrame, style: style)
      paintOrder.append(id)
      return Size(width: frame.width + margins.horizontal, height: frame.height + margins.vertical)
    }

    mutating func layoutFlow(_ children: [NodeID], in content: Rect, parentStyle: ComputedStyle)
      -> Double
    {
      var y = content.minY
      var lineX = content.minX
      var lineHeight: Double = 0
      var hasInline = false

      func isBlock(_ display: DisplayType) -> Bool {
        display == .block || display == .flex || display == .grid || display == .table
      }

      for child in children {
        let childStyle = styled.style(for: child)
        if childStyle.position == .absolute || childStyle.position == .fixed {
          _ = layoutNode(child, containing: content)
          continue
        }

        if isBlock(childStyle.display) {
          if hasInline {
            y += lineHeight
            lineX = content.minX
            lineHeight = 0
            hasInline = false
          }
          let childContaining = Rect(
            x: content.minX, y: y, width: content.width, height: max(0, viewport.height - y))
          let size = layoutNode(child, containing: childContaining)
          y += size.height
        } else {
          let remaining = max(0, content.maxX - lineX)
          var childContaining = Rect(
            x: lineX, y: y, width: remaining, height: max(0, viewport.height - y))
          var size = layoutNode(
            child, containing: childContaining,
            forcedWidth: childStyle.display == .inlineBlock ? nil : remaining)
          if size.width > remaining, lineX > content.minX {
            y += max(lineHeight, parentStyle.fontSize * 1.2)
            lineX = content.minX
            lineHeight = 0
            childContaining = Rect(
              x: lineX, y: y, width: content.width, height: max(0, viewport.height - y))
            size = layoutNode(
              child, containing: childContaining,
              forcedWidth: childStyle.display == .inlineBlock ? nil : content.width)
          }
          lineX += size.width
          lineHeight = max(lineHeight, size.height)
          hasInline = true
        }
      }

      if hasInline { y += lineHeight }
      return max(0, y - content.minY)
    }

    mutating func layoutFlex(_ children: [NodeID], in content: Rect, style: ComputedStyle) -> Double
    {
      guard !children.isEmpty else { return 0 }
      if style.flexDirection == .column {
        var y = content.minY
        for (index, child) in children.enumerated() {
          let containing = Rect(
            x: content.minX, y: y, width: content.width, height: max(0, viewport.height - y))
          let size = layoutNode(child, containing: containing)
          y += size.height
          if index < children.count - 1 { y += style.gap }
        }
        return y - content.minY
      }

      let gapTotal = style.gap * Double(max(0, children.count - 1))
      let fixed = children.reduce(0.0) { total, id in
        let childStyle = styled.style(for: id)
        return total
          + (resolve(childStyle.width, reference: content.width, fontSize: childStyle.fontSize) ?? 0)
      }
      let growTotal = children.reduce(0.0) { $0 + max(0, styled.style(for: $1).flexGrow) }
      let remaining = max(0, content.width - fixed - gapTotal)
      var x = content.minX
      var maxHeight: Double = 0

      for child in children {
        let childStyle = styled.style(for: child)
        let explicit = resolve(
          childStyle.width, reference: content.width, fontSize: childStyle.fontSize)
        let distributed =
          growTotal > 0
          ? remaining * max(0, childStyle.flexGrow) / growTotal
          : max(0, (content.width - gapTotal) / Double(children.count))
        let childWidth = explicit ?? distributed
        let size = layoutNode(
          child, containing: Rect(x: x, y: content.minY, width: childWidth, height: content.height),
          forcedWidth: childWidth)
        x += childWidth + style.gap
        maxHeight = max(maxHeight, size.height)
      }
      return maxHeight
    }

    mutating func layoutGrid(_ children: [NodeID], in content: Rect, style: ComputedStyle) -> Double
    {
      guard !children.isEmpty else { return 0 }
      let columns = max(1, style.gridColumns)
      let totalGap = style.gap * Double(max(0, columns - 1))
      let columnWidth = max(0, (content.width - totalGap) / Double(columns))
      var rowY = content.minY
      var rowHeight: Double = 0

      for (index, child) in children.enumerated() {
        let column = index % columns
        if column == 0, index > 0 {
          rowY += rowHeight + style.gap
          rowHeight = 0
        }
        let x = content.minX + Double(column) * (columnWidth + style.gap)
        let size = layoutNode(
          child, containing: Rect(x: x, y: rowY, width: columnWidth, height: content.height),
          forcedWidth: columnWidth)
        rowHeight = max(rowHeight, size.height)
      }
      return rowY - content.minY + rowHeight
    }

    func intrinsicSize(for id: NodeID, node: DOMNode, style: ComputedStyle, availableWidth: Double)
      -> Size?
    {
      guard let tag = node.tagName else { return nil }
      switch tag {
      case "input":
        let type = (node.attribute("type") ?? "text").lowercased()
        if type == "checkbox" || type == "radio" { return Size(width: 16, height: 16) }
        if type == "submit" || type == "button" || type == "reset" {
          let label = node.attribute("value") ?? "Submit"
          let metrics = textMeasurer.measure(
            label, fontSize: style.fontSize, fontWeight: style.fontWeight, maxWidth: nil)
          return Size(
            width: min(availableWidth, max(44, metrics.size.width + 18)),
            height: max(28, metrics.size.height + 10))
        }
        let characters = max(1, Int(node.attribute("size") ?? "20") ?? 20)
        return Size(
          width: min(availableWidth, max(80, Double(characters) * style.fontSize * 0.52 + 12)),
          height: max(28, style.fontSize * 1.55))
      case "button":
        let label = styled.document.textContent(of: id)
        let metrics = textMeasurer.measure(
          label, fontSize: style.fontSize, fontWeight: style.fontWeight, maxWidth: nil)
        return Size(
          width: min(availableWidth, max(44, metrics.size.width + 18)),
          height: max(28, metrics.size.height + 10))
      case "select":
        return Size(width: min(availableWidth, 160), height: max(30, style.fontSize * 1.65))
      case "textarea":
        let columns = max(1, Int(node.attribute("cols") ?? "20") ?? 20)
        let rows = max(1, Int(node.attribute("rows") ?? "2") ?? 2)
        return Size(
          width: min(availableWidth, Double(columns) * style.fontSize * 0.55 + 12),
          height: Double(rows) * style.fontSize * 1.25 + 10)
      case "img":
        let width = Double(node.attribute("width") ?? "")
        let height = Double(node.attribute("height") ?? "")
        if let width, let height { return Size(width: min(availableWidth, width), height: height) }
        if let width { return Size(width: min(availableWidth, width), height: width * 0.5625) }
        if let height {
          return Size(width: min(availableWidth, height * 1.7777777778), height: height)
        }
        return Size(width: min(availableWidth, 300), height: 150)
      default:
        return nil
      }
    }

    func resolve(_ length: CSSLength, reference: Double, fontSize: Double) -> Double? {
      length.resolve(reference: reference, fontSize: fontSize, rootFontSize: 16, viewport: viewport)
    }

    func resolve(_ box: StyleLength, reference: Double, fontSize: Double) -> EdgeInsets {
      EdgeInsets(
        top: resolve(box.top, reference: reference, fontSize: fontSize) ?? 0,
        right: resolve(box.right, reference: reference, fontSize: fontSize) ?? 0,
        bottom: resolve(box.bottom, reference: reference, fontSize: fontSize) ?? 0,
        left: resolve(box.left, reference: reference, fontSize: fontSize) ?? 0
      )
    }

    func clampWidth(_ width: Double, style: ComputedStyle, reference: Double) -> Double {
      var result = width
      if let minWidth = resolve(style.minWidth, reference: reference, fontSize: style.fontSize) {
        result = max(result, minWidth)
      }
      if let maxWidth = resolve(style.maxWidth, reference: reference, fontSize: style.fontSize) {
        result = min(result, maxWidth)
      }
      return max(0, result)
    }
  }
}
