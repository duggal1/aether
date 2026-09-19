import Style

public struct RenderDirtyFlags: OptionSet, Hashable, Sendable, Codable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let style = RenderDirtyFlags(rawValue: 1 << 0)
  public static let layout = RenderDirtyFlags(rawValue: 1 << 1)
  public static let paint = RenderDirtyFlags(rawValue: 1 << 2)
  public static let composite = RenderDirtyFlags(rawValue: 1 << 3)

  public var needsLayout: Bool { contains(.layout) }
  public var needsPaint: Bool { contains(.paint) || contains(.layout) }
  public var isCompositeOnly: Bool { !needsLayout && !contains(.paint) }
}

public enum PipelineInvalidation {
  public static func dirtyFlags(old: ComputedStyle, new: ComputedStyle) -> RenderDirtyFlags {
    if old == new { return [] }
    var flags: RenderDirtyFlags = [.style, .composite]
    if geometryChanged(old: old, new: new) {
      flags.insert(.layout)
    } else if paintChanged(old: old, new: new) {
      flags.insert(.paint)
    }
    return flags
  }

  static func geometryChanged(old: ComputedStyle, new: ComputedStyle) -> Bool {
    old.display != new.display
      || old.position != new.position
      || old.width != new.width
      || old.height != new.height
      || old.minWidth != new.minWidth
      || old.maxWidth != new.maxWidth
      || old.margin != new.margin
      || old.padding != new.padding
      || old.borderWidth != new.borderWidth
      || old.fontSize != new.fontSize
      || old.fontWeight != new.fontWeight
      || old.flexDirection != new.flexDirection
      || old.flexGrow != new.flexGrow
      || old.gap != new.gap
      || old.gridColumns != new.gridColumns
      || old.left != new.left
      || old.top != new.top
  }

  static func paintChanged(old: ComputedStyle, new: ComputedStyle) -> Bool {
    old.color != new.color
      || old.backgroundColor != new.backgroundColor
      || old.borderColor != new.borderColor
      || old.overflowX != new.overflowX
      || old.overflowY != new.overflowY
  }
}

public struct FramePipelineState: Hashable, Sendable, Codable {
  public private(set) var pending: RenderDirtyFlags = []
  public private(set) var sourceMutationVersion: UInt64 = 0

  public init() {}

  public var isClean: Bool { pending.isEmpty }

  public mutating func markDirty(_ flags: RenderDirtyFlags, mutationVersion: UInt64) {
    pending.formUnion(flags)
    sourceMutationVersion = mutationVersion
  }

  public mutating func takePending() -> RenderDirtyFlags {
    let taken = pending
    pending = []
    return taken
  }
}
