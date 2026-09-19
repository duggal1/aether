import CryptoKit
import Foundation

public enum DiskCacheError: Error, Sendable, CustomStringConvertible {
  case invalidHash(String)
  case io(String)

  public var description: String {
    switch self {
    case .invalidHash(let value): return "Invalid cache hash: \(value)"
    case .io(let value): return "Disk cache I/O failed: \(value)"
    }
  }
}

public struct DiskCache: Hashable, Sendable, Codable {
  public var root: URL
  public var maxBytes: Int

  public init(root: URL, maxBytes: Int = 256 * 1024 * 1024) {
    self.root = root
    self.maxBytes = max(0, maxBytes)
  }

  public static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func isValidHash(_ hash: String) -> Bool {
    guard hash.count >= 4 else { return false }
    return hash.allSatisfy { $0.isHexDigit }
  }

  public func path(for hash: String) throws -> URL {
    guard Self.isValidHash(hash) else { throw DiskCacheError.invalidHash(hash) }
    let prefix = hash.prefix(2)
    let middle = hash.dropFirst(2).prefix(2)
    let rest = hash.dropFirst(4)
    return root.appendingPathComponent(String(prefix))
      .appendingPathComponent(String(middle))
      .appendingPathComponent(String(rest))
  }

  public func contains(_ hash: String) -> Bool {
    guard let url = try? path(for: hash) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  public func write(hash: String, data: Data) throws {
    let destination = try path(for: hash)
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      let staging = root.appendingPathComponent(".tmp-\(UUID().uuidString)")
      try data.write(to: staging, options: .atomic)
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: staging, to: destination)
    } catch let error as DiskCacheError {
      throw error
    } catch {
      throw DiskCacheError.io(error.localizedDescription)
    }
  }

  public func read(hash: String) -> Data? {
    guard let url = try? path(for: hash) else { return nil }
    guard let data = try? Data(contentsOf: url) else { return nil }
    try? FileManager.default.setAttributes(
      [.modificationDate: Date()], ofItemAtPath: url.path)
    return data
  }

  public func remove(hash: String) throws {
    let url = try path(for: hash)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      throw DiskCacheError.io(error.localizedDescription)
    }
  }

  public func totalBytes() -> Int {
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return 0 }
    var total = 0
    for case let name as String in enumerator {
      if name.hasPrefix(".tmp-") { continue }
      let url = root.appendingPathComponent(name)
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
        values.isRegularFile == true
      else { continue }
      total += values.fileSize ?? 0
    }
    return total
  }

  @discardableResult
  public func evict(maxBytes: Int, keeping: Set<String> = []) throws -> Int {
    guard let enumerator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
    else { return totalBytes() }
    var files: [(url: URL, size: Int, modified: Date)] = []
    for case let url as URL in enumerator {
      if url.lastPathComponent.hasPrefix(".tmp-") { continue }
      guard let values = try? url.resourceValues(
        forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
        values.isRegularFile == true
      else { continue }
      files.append((
        url: url, size: values.fileSize ?? 0,
        modified: values.contentModificationDate ?? .distantPast
      ))
    }
    var total = files.reduce(0) { $0 + $1.size }
    files.sort { $0.modified < $1.modified }
    for file in files {
      if total <= maxBytes { break }
      guard let hash = hash(for: file.url), !keeping.contains(hash) else { continue }
      do {
        try FileManager.default.removeItem(at: file.url)
        total -= file.size
      } catch {
        throw DiskCacheError.io(error.localizedDescription)
      }
    }
    return total
  }

  private func hash(for url: URL) -> String? {
    let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
    let parts = relative.split(separator: "/")
    guard parts.count == 3 else { return nil }
    let hash = parts.joined()
    return Self.isValidHash(hash) ? hash : nil
  }
}
