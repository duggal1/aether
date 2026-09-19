import CSS
import DOM
import EngineCore
import Foundation
import Images
import Layout
import Style

public enum DisplayListBuilder {
  public static func build(
    document: DOMDocument, layout: LayoutTree, images: [NodeID: DecodedImage] = [:]
  ) -> DisplayList {
    var commands: [DisplayCommand] = []
    var dirty = DirtyRegion()
    let order = Dictionary(
      uniqueKeysWithValues: document.depthFirst().enumerated().map { ($0.element, $0.offset) })
    let ordered = document.depthFirst().compactMap { id -> (NodeID, LayoutBox)? in
      guard let box = layout.boxes[id] else { return nil }
      return (id, box)
    }.sorted { lhs, rhs in
      if lhs.1.style.zIndex != rhs.1.style.zIndex { return lhs.1.style.zIndex < rhs.1.style.zIndex }
      return (order[lhs.0] ?? Int.max) < (order[rhs.0] ?? Int.max)
    }

    for (id, box) in ordered {
      guard let node = document.node(id), box.style.display != .none else { continue }
      dirty.add(box.frame)

      if box.style.backgroundColor.alpha > 0 {
        commands.append(
          .rect(
            DrawRectCommand(
              rect: box.frame, color: box.style.backgroundColor, opacity: box.style.opacity)))
      }

      appendBorders(box, to: &commands)

      if let image = images[id], node.tagName == "img", image.isValid {
        commands.append(
          .image(
            DrawImageCommand(
              nodeID: id, image: image, rect: box.contentFrame, opacity: box.style.opacity)))
      }

      if case .text(let text) = node.kind, !text.isEmpty {
        commands.append(
          .text(
            DrawTextCommand(
              nodeID: id,
              text: text,
              rect: box.contentFrame,
              color: box.style.color,
              fontSize: box.style.fontSize,
              fontWeight: box.style.fontWeight,
              opacity: box.style.opacity
            )))
      }
    }

    return DisplayList(commands: commands, size: layout.contentSize, dirtyRegion: dirty)
  }

  private static func appendBorders(_ box: LayoutBox, to commands: inout [DisplayCommand]) {
    let style = box.style
    let frame = box.frame
    let top = resolveBorder(style.borderWidth.top)
    let right = resolveBorder(style.borderWidth.right)
    let bottom = resolveBorder(style.borderWidth.bottom)
    let left = resolveBorder(style.borderWidth.left)
    let color = style.borderColor
    if top > 0 {
      commands.append(
        .rect(
          DrawRectCommand(
            rect: Rect(x: frame.minX, y: frame.minY, width: frame.width, height: top), color: color,
            opacity: style.opacity)))
    }
    if right > 0 {
      commands.append(
        .rect(
          DrawRectCommand(
            rect: Rect(x: frame.maxX - right, y: frame.minY, width: right, height: frame.height),
            color: color, opacity: style.opacity)))
    }
    if bottom > 0 {
      commands.append(
        .rect(
          DrawRectCommand(
            rect: Rect(x: frame.minX, y: frame.maxY - bottom, width: frame.width, height: bottom),
            color: color, opacity: style.opacity)))
    }
    if left > 0 {
      commands.append(
        .rect(
          DrawRectCommand(
            rect: Rect(x: frame.minX, y: frame.minY, width: left, height: frame.height),
            color: color, opacity: style.opacity)))
    }
  }

  private static func resolveBorder(_ length: CSSLength) -> Double {
    if case .px(let value) = length { return max(0, value) }
    return 0
  }
}
