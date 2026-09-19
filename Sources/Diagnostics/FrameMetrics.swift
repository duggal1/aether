import EngineCore
import Foundation

public struct FrameReport: Hashable, Sendable, Codable {
  public var layoutMilliseconds: Double
  public var paintMilliseconds: Double
  public var rasterMilliseconds: Double
  public var compositeMilliseconds: Double
  public var gpuSubmitMilliseconds: Double
  public var frameMilliseconds: Double
  public var scrollMilliseconds: Double
  public var gpuBytes: Int
  public var ramBytesEstimate: Int
  public var domNodes: Int
  public var displayCommands: Int
  public var droppedWork: Bool

  public init(
    layoutMilliseconds: Double = 0, paintMilliseconds: Double = 0,
    rasterMilliseconds: Double = 0, compositeMilliseconds: Double = 0,
    gpuSubmitMilliseconds: Double = 0, frameMilliseconds: Double = 0,
    scrollMilliseconds: Double = 0, gpuBytes: Int = 0, ramBytesEstimate: Int = 0,
    domNodes: Int = 0, displayCommands: Int = 0, droppedWork: Bool = false
  ) {
    self.layoutMilliseconds = layoutMilliseconds
    self.paintMilliseconds = paintMilliseconds
    self.rasterMilliseconds = rasterMilliseconds
    self.compositeMilliseconds = compositeMilliseconds
    self.gpuSubmitMilliseconds = gpuSubmitMilliseconds
    self.frameMilliseconds = frameMilliseconds
    self.scrollMilliseconds = scrollMilliseconds
    self.gpuBytes = gpuBytes
    self.ramBytesEstimate = ramBytesEstimate
    self.domNodes = domNodes
    self.displayCommands = displayCommands
    self.droppedWork = droppedWork
  }

  public var pipelineMilliseconds: Double {
    layoutMilliseconds + paintMilliseconds + rasterMilliseconds + compositeMilliseconds
      + gpuSubmitMilliseconds
  }

  public var ramBytesPerNode: Double {
    guard domNodes > 0 else { return 0 }
    return Double(ramBytesEstimate) / Double(domNodes)
  }
}

public struct FrameRecorder: Sendable {
  public var capacity: Int
  public private(set) var droppedFrames: Int
  private var reports: [FrameReport]

  public init(capacity: Int = 240) {
    self.capacity = max(1, capacity)
    self.droppedFrames = 0
    self.reports = []
  }

  public var count: Int { reports.count }

  public mutating func record(_ report: FrameReport) {
    if report.droppedWork { droppedFrames += 1 }
    reports.append(report)
    if reports.count > capacity {
      reports.removeFirst(reports.count - capacity)
    }
  }

  public func percentile(_ path: KeyPath<FrameReport, Double>, _ fraction: Double) -> Double {
    guard !reports.isEmpty else { return 0 }
    let clamped = min(1, max(0, fraction))
    let sorted = reports.map { $0[keyPath: path] }.sorted()
    let rank = clamped * Double(sorted.count - 1)
    let low = Int(floor(rank))
    let high = Int(ceil(rank))
    if low == high { return sorted[low] }
    let mix = rank - Double(low)
    return sorted[low] * (1 - mix) + sorted[high] * mix
  }

  public mutating func reset() {
    reports.removeAll(keepingCapacity: true)
    droppedFrames = 0
  }
}
