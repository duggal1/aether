import DOM
import EngineCore
import Images

public struct ImageMemoryPolicy: Hashable, Sendable, Codable {
  public var maxTotalBytes: Int
  public var maxSingleImageBytes: Int

  public init(maxTotalBytes: Int = 192_000_000, maxSingleImageBytes: Int = 48_000_000) {
    self.maxTotalBytes = max(1, maxTotalBytes)
    self.maxSingleImageBytes = max(1, maxSingleImageBytes)
  }

  public func bytes(of image: DecodedImage) -> Int {
    guard image.isValid else { return 0 }
    return image.width * image.height * 4
  }

  public func totalBytes(of images: [NodeID: DecodedImage]) -> Int {
    images.values.reduce(0) { $0 + bytes(of: $1) }
  }

  public func evictionCandidates(
    images: [NodeID: DecodedImage], keep: Set<NodeID>, limit: Int? = nil
  ) -> [NodeID] {
    let budget = max(1, limit ?? maxTotalBytes)
    var candidates: [NodeID] = []
    var remaining = totalBytes(of: images)
    guard remaining > budget else { return [] }
    let ranked: [(NodeID, Int)] = images.compactMap { id, image in
      guard !keep.contains(id) else { return nil }
      return (id, bytes(of: image))
    }.sorted { $0.1 > $1.1 }
    for (id, size) in ranked {
      if remaining <= budget { break }
      candidates.append(id)
      remaining -= size
    }
    return candidates
  }
}
