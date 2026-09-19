import Foundation

public struct CaptureRect: Codable, Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public struct CaptureViewport: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let scale: Double

    public init(width: Int, height: Int, scale: Double = 1) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.scale = max(0.1, scale)
    }
}

public struct CaptureStep: Codable, Sendable, Equatable {
    public let index: Int
    public let scrollY: Int
    public let viewportRect: CaptureRect
    public let contentRect: CaptureRect
}

public struct PageCapturePlan: Sendable {
    public let steps: [CaptureStep]
    public let contentHeight: Int
    public let viewport: CaptureViewport

    public init(contentHeight: Int, viewport: CaptureViewport, overlap: Int = 64, maximumSteps: Int = 2_000) {
        self.contentHeight = max(0, contentHeight)
        self.viewport = viewport
        let stride = max(1, viewport.height - max(0, min(overlap, viewport.height - 1)))
        var offsets: [Int] = []
        let finalY = max(0, contentHeight - viewport.height)
        var next = 0
        while next < finalY, offsets.count < max(1, maximumSteps - 1) {
            offsets.append(next)
            next += stride
        }
        if offsets.last != finalY { offsets.append(finalY) }
        var coverage = 0
        steps = offsets.enumerated().map { index, y in
            let start = max(y, coverage)
            let end = min(contentHeight, y + viewport.height)
            let size = max(0, end - start)
            coverage = max(coverage, end)
            return CaptureStep(index: index, scrollY: y,
                viewportRect: CaptureRect(x: 0, y: start - y, width: viewport.width, height: size),
                contentRect: CaptureRect(x: 0, y: start, width: viewport.width, height: size))
        }
    }
}
