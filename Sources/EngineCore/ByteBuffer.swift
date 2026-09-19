import Foundation

public struct ByteBuffer: Sendable, Hashable {
  private var storage: Data
  private var readIndex: Int

  public init(_ data: Data = Data()) {
    storage = data
    readIndex = 0
  }

  public var readableBytes: Int { storage.count - readIndex }
  public var data: Data { storage.subdata(in: readIndex..<storage.count) }

  public mutating func append(_ data: Data) {
    storage.append(data)
  }

  public mutating func read(count: Int) -> Data? {
    guard count >= 0, readIndex + count <= storage.count else { return nil }
    defer {
      readIndex += count
      compactIfNeeded()
    }
    return storage.subdata(in: readIndex..<(readIndex + count))
  }

  public mutating func readByte() -> UInt8? {
    guard readIndex < storage.count else { return nil }
    defer {
      readIndex += 1
      compactIfNeeded()
    }
    return storage[readIndex]
  }

  private mutating func compactIfNeeded() {
    guard readIndex > 4096, readIndex > storage.count / 2 else { return }
    storage.removeSubrange(0..<readIndex)
    readIndex = 0
  }
}
