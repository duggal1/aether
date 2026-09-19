import Foundation
import Synchronization

public struct Atom: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public init(_ string: String) {
    self = AtomTable.shared.intern(string)
  }

  public var string: String { AtomTable.shared.resolve(self) }
  public var description: String { string }
}

public final class AtomTable: Sendable {
  public static let shared = AtomTable()

  private struct State: Sendable {
    var strings: [String] = []
    var ids: [String: UInt32] = [:]
  }

  private let state = Mutex(State())

  public init() {}

  public func intern(_ string: String) -> Atom {
    state.withLock { state in
      if let id = state.ids[string] { return Atom(rawValue: id) }
      let id = UInt32(state.strings.count)
      state.strings.append(string)
      state.ids[string] = id
      return Atom(rawValue: id)
    }
  }

  public func resolve(_ atom: Atom) -> String {
    state.withLock { state in
      let index = Int(atom.rawValue)
      guard state.strings.indices.contains(index) else { return "" }
      return state.strings[index]
    }
  }

  public var count: Int {
    state.withLock { $0.strings.count }
  }
}
