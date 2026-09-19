import Foundation

public struct FrameDamage: Sendable, Codable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public struct RenderFrame: Sendable, Codable, Equatable {
    public let revision: UInt64
    public let viewport: CaptureViewport
    public let damage: [FrameDamage]
    public let layoutNanoseconds: UInt64
    public let paintNanoseconds: UInt64
    public let compositeNanoseconds: UInt64
}

public actor RenderFrameJournal {
    private let capacity: Int
    private var frames: [RenderFrame] = []
    private var nextRevision: UInt64 = 1

    public init(capacity: Int = 240) { self.capacity = max(1, capacity) }

    @discardableResult public func commit(viewport: CaptureViewport, damage: [FrameDamage], layoutNanoseconds: UInt64, paintNanoseconds: UInt64, compositeNanoseconds: UInt64) -> RenderFrame {
        let frame = RenderFrame(revision: nextRevision, viewport: viewport, damage: damage,
            layoutNanoseconds: layoutNanoseconds, paintNanoseconds: paintNanoseconds, compositeNanoseconds: compositeNanoseconds)
        nextRevision &+= 1
        frames.append(frame)
        if frames.count > capacity { frames.removeFirst(frames.count - capacity) }
        return frame
    }

    public func since(_ revision: UInt64) -> [RenderFrame] { frames.filter { $0.revision > revision } }
    public func latest() -> RenderFrame? { frames.last }
}
