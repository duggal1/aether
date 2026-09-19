import CSS
import EngineCore
import Foundation

public enum DisplayType: String, Hashable, Sendable, Codable {
  case none
  case block
  case inline
  case inlineBlock
  case flex
  case grid
  case table
}

public enum PositionType: String, Hashable, Sendable, Codable {
  case `static`
  case relative
  case absolute
  case fixed
}

public enum FlexDirection: String, Hashable, Sendable, Codable {
  case row
  case column
}

public enum OverflowMode: String, Hashable, Sendable, Codable {
  case visible
  case hidden
  case scroll
  case auto
}

public enum VisibilityMode: String, Hashable, Sendable, Codable {
  case visible
  case hidden
  case collapse
}

public enum ContentVisibility: String, Hashable, Sendable, Codable {
  case visible
  case auto
  case hidden
}

public struct ContainFlags: Hashable, Sendable, Codable {
  public var layout: Bool
  public var style: Bool
  public var paint: Bool
  public var size: Bool

  public init(layout: Bool = false, style: Bool = false, paint: Bool = false, size: Bool = false) {
    self.layout = layout
    self.style = style
    self.paint = paint
    self.size = size
  }

  public static let none = ContainFlags()

  public static func parse(_ raw: String) -> ContainFlags {
    let tokens = Set(raw.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init))
    if tokens.contains("strict") {
      return ContainFlags(layout: true, style: true, paint: true, size: true)
    }
    if tokens.contains("content") {
      return ContainFlags(layout: true, style: true, paint: true)
    }
    return ContainFlags(
      layout: tokens.contains("layout"), style: tokens.contains("style"),
      paint: tokens.contains("paint"), size: tokens.contains("size"))
  }
}

public struct StyleLength: Hashable, Sendable, Codable {
  public var top: CSSLength
  public var right: CSSLength
  public var bottom: CSSLength
  public var left: CSSLength

  public init(
    top: CSSLength = .px(0), right: CSSLength = .px(0), bottom: CSSLength = .px(0),
    left: CSSLength = .px(0)
  ) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }

  public static let zero = StyleLength()
}

public struct ComputedStyle: Hashable, Sendable, Codable {
  public var display: DisplayType
  public var position: PositionType
  public var color: RGBAColor
  public var backgroundColor: RGBAColor
  public var fontSize: Double
  public var fontWeight: Int
  public var width: CSSLength
  public var height: CSSLength
  public var minWidth: CSSLength
  public var maxWidth: CSSLength
  public var margin: StyleLength
  public var padding: StyleLength
  public var borderWidth: StyleLength
  public var borderColor: RGBAColor
  public var flexDirection: FlexDirection
  public var flexGrow: Double
  public var gap: Double
  public var gridColumns: Int
  public var overflowX: OverflowMode
  public var overflowY: OverflowMode
  public var opacity: Double
  public var left: CSSLength
  public var top: CSSLength
  public var zIndex: Int
  public var fontFamily: String
  public var lineHeight: Double
  public var visibility: VisibilityMode
  public var contain: ContainFlags
  public var contentVisibility: ContentVisibility

  public init(
    display: DisplayType = .inline,
    position: PositionType = .static,
    color: RGBAColor = .black,
    backgroundColor: RGBAColor = .clear,
    fontSize: Double = 16,
    fontWeight: Int = 400,
    width: CSSLength = .auto,
    height: CSSLength = .auto,
    minWidth: CSSLength = .auto,
    maxWidth: CSSLength = .auto,
    margin: StyleLength = .zero,
    padding: StyleLength = .zero,
    borderWidth: StyleLength = .zero,
    borderColor: RGBAColor = .black,
    flexDirection: FlexDirection = .row,
    flexGrow: Double = 0,
    gap: Double = 0,
    gridColumns: Int = 1,
    overflowX: OverflowMode = .visible,
    overflowY: OverflowMode = .visible,
    opacity: Double = 1,
    left: CSSLength = .auto,
    top: CSSLength = .auto,
    zIndex: Int = 0,
    fontFamily: String = "system",
    lineHeight: Double = 1.2,
    visibility: VisibilityMode = .visible,
    contain: ContainFlags = .none,
    contentVisibility: ContentVisibility = .visible
  ) {
    self.display = display
    self.position = position
    self.color = color
    self.backgroundColor = backgroundColor
    self.fontSize = fontSize
    self.fontWeight = fontWeight
    self.width = width
    self.height = height
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.margin = margin
    self.padding = padding
    self.borderWidth = borderWidth
    self.borderColor = borderColor
    self.flexDirection = flexDirection
    self.flexGrow = flexGrow
    self.gap = gap
    self.gridColumns = max(1, gridColumns)
    self.overflowX = overflowX
    self.overflowY = overflowY
    self.opacity = min(1, max(0, opacity))
    self.left = left
    self.top = top
    self.zIndex = zIndex
    self.fontFamily = fontFamily
    self.lineHeight = max(0.5, lineHeight)
    self.visibility = visibility
    self.contain = contain
    self.contentVisibility = contentVisibility
  }
}
