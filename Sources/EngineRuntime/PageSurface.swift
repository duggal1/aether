import Diagnostics
import EngineCore
import Foundation
import Graphics

public struct PageSurface: Hashable, Sendable {
  public let pageID: PageID
  let attachmentID: UUID

  init(pageID: PageID, attachmentID: UUID) {
    self.pageID = pageID
    self.attachmentID = attachmentID
  }
}

public struct PageFrame: Sendable {
  public let pageID: PageID
  public let revision: UInt64
  public let mutationVersion: UInt64
  public let viewport: Size
  public let scroll: Point
  public let damage: DirtyRegion
  public let pixels: PixelBuffer
  public let report: FrameReport
}

public enum PageSurfaceError: Error, Equatable, Sendable {
  case alreadyAttached
  case detached
}
