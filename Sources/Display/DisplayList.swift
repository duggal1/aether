import DOM
import EngineCore
import Foundation
import Images

public struct DrawRectCommand: Hashable, Sendable, Codable {
  public var rect: Rect
  public var color: RGBAColor
  public var opacity: Double

  public init(rect: Rect, color: RGBAColor, opacity: Double = 1) {
    self.rect = rect
    self.color = color
    self.opacity = opacity
  }
}

public struct DrawTextCommand: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var text: String
  public var rect: Rect
  public var color: RGBAColor
  public var fontSize: Double
  public var fontWeight: Int
  public var opacity: Double

  public init(
    nodeID: NodeID, text: String, rect: Rect, color: RGBAColor, fontSize: Double, fontWeight: Int,
    opacity: Double = 1
  ) {
    self.nodeID = nodeID
    self.text = text
    self.rect = rect
    self.color = color
    self.fontSize = fontSize
    self.fontWeight = fontWeight
    self.opacity = opacity
  }
}

public struct DrawImageCommand: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var image: DecodedImage
  public var rect: Rect
  public var opacity: Double

  public init(nodeID: NodeID, image: DecodedImage, rect: Rect, opacity: Double = 1) {
    self.nodeID = nodeID
    self.image = image
    self.rect = rect
    self.opacity = opacity
  }
}

public struct ClipCommand: Hashable, Sendable, Codable {
  public var rect: Rect
  public init(rect: Rect) { self.rect = rect }
}

public enum DisplayCommand: Hashable, Sendable, Codable {
  case rect(DrawRectCommand)
  case text(DrawTextCommand)
  case image(DrawImageCommand)
  case pushClip(ClipCommand)
  case popClip
}

public struct DisplayList: Hashable, Sendable, Codable {
  public var commands: [DisplayCommand]
  public var size: Size
  public var dirtyRegion: DirtyRegion

  public init(commands: [DisplayCommand], size: Size, dirtyRegion: DirtyRegion = DirtyRegion()) {
    self.commands = commands
    self.size = size
    self.dirtyRegion = dirtyRegion
  }
}
