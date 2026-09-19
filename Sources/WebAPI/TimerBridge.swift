import Foundation
import JavaScript

public final class JSTimerBridge: JSTimerHost, JSPumpableTimers {
  private struct Entry {
    var id: Double
    var fireAt: Double
    var interval: Double?
    var callback: JSFunction
  }

  private var entries: [Double: Entry] = [:]
  private var nextID: Double = 1
  private weak var runtime: JSRuntime?
  private let clock: () -> Double

  public init(
    runtime: JSRuntime, now: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }
  ) {
    self.runtime = runtime
    self.clock = now
  }

  public func setTimeout(milliseconds: Double, repeats: Bool, callback: JSFunction) -> Double {
    let id = nextID
    nextID += 1
    let delay = max(0, milliseconds)
    entries[id] = Entry(
      id: id, fireAt: clock() + delay,
      interval: repeats ? delay : nil, callback: callback)
    return id
  }

  public func clearTimeout(id: Double) {
    entries.removeValue(forKey: id)
  }

  public var pendingCount: Int { entries.count }

  public var nextFireAt: Double? { entries.values.map { $0.fireAt }.min() }

  @discardableResult
  public func pump(now: Double) -> Int {
    guard let runtime else { return 0 }
    var fired = 0
    var done = Set<Double>()
    while fired < 10000 {
      let candidate = entries.values
        .filter { $0.fireAt <= now && !done.contains($0.id) }
        .min {
          if $0.fireAt != $1.fireAt { return $0.fireAt < $1.fireAt }
          return $0.id < $1.id
        }
      guard let entry = candidate else { break }
      done.insert(entry.id)
      guard entries[entry.id] != nil else { continue }
      if let interval = entry.interval {
        entries[entry.id]?.fireAt = entry.fireAt + interval
      } else {
        entries.removeValue(forKey: entry.id)
      }
      runtime.invokeTimerCallback(entry.callback)
      fired += 1
    }
    return fired
  }
}
