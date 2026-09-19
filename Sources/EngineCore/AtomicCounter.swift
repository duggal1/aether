import Foundation
import Synchronization

public final class AtomicCounter: Sendable {
  private let value: Mutex<UInt64>

  public init(start: UInt64 = 1) {
    value = Mutex(start)
  }

  public func next() -> UInt64 {
    value.withLock { current in
      let result = current
      current &+= 1
      return result
    }
  }
}
