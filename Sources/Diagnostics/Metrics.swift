import Foundation

public struct EngineMetrics: Hashable, Sendable, Codable {
  public var networkMilliseconds: Double
  public var parseMilliseconds: Double
  public var styleMilliseconds: Double
  public var layoutMilliseconds: Double
  public var displayListMilliseconds: Double
  public var renderMilliseconds: Double
  public var totalMilliseconds: Double
  public var domNodes: Int
  public var displayCommands: Int
  public var responseBytes: Int

  public init(
    networkMilliseconds: Double = 0, parseMilliseconds: Double = 0, styleMilliseconds: Double = 0,
    layoutMilliseconds: Double = 0, displayListMilliseconds: Double = 0,
    renderMilliseconds: Double = 0, totalMilliseconds: Double = 0, domNodes: Int = 0,
    displayCommands: Int = 0, responseBytes: Int = 0
  ) {
    self.networkMilliseconds = networkMilliseconds
    self.parseMilliseconds = parseMilliseconds
    self.styleMilliseconds = styleMilliseconds
    self.layoutMilliseconds = layoutMilliseconds
    self.displayListMilliseconds = displayListMilliseconds
    self.renderMilliseconds = renderMilliseconds
    self.totalMilliseconds = totalMilliseconds
    self.domNodes = domNodes
    self.displayCommands = displayCommands
    self.responseBytes = responseBytes
  }
}

public actor MetricsCollector {
  private var latest: [String: EngineMetrics] = [:]

  public init() {}

  public func record(_ metrics: EngineMetrics, key: String) { latest[key] = metrics }
  public func metrics(for key: String) -> EngineMetrics? { latest[key] }
  public func snapshot() -> [String: EngineMetrics] { latest }
}

public enum MetricClock {
  public static func milliseconds<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let clock = ContinuousClock()
    let start = clock.now
    let value = try body()
    let duration = start.duration(to: clock.now)
    return (
      value,
      Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    )
  }

  public static func asyncMilliseconds<T: Sendable>(_ body: () async throws -> T) async rethrows
    -> (
      T, Double
    )
  {
    let clock = ContinuousClock()
    let start = clock.now
    let value = try await body()
    let duration = start.duration(to: clock.now)
    return (
      value,
      Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    )
  }
}
