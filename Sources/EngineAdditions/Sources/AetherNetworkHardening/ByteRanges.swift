import Foundation

public struct HTTPByteRange: Sendable, Equatable {
    public let start: Int64
    public let end: Int64
    public var length: Int64 { end - start + 1 }

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }
}

public enum ByteRangeError: Error, Sendable, Equatable {
    case malformed
    case unsatisfiable
    case tooManyRanges
}

public enum HTTPByteRanges {
    public static func parse(_ value: String, size: Int64, maximum: Int = 16) throws -> [HTTPByteRange] {
        guard size > 0 else { throw ByteRangeError.unsatisfiable }
        guard value.lowercased().hasPrefix("bytes=") else { throw ByteRangeError.malformed }
        let segments = value.dropFirst(6).split(separator: ",", omittingEmptySubsequences: false)
        guard !segments.isEmpty, segments.count <= maximum else { throw ByteRangeError.tooManyRanges }
        var result: [HTTPByteRange] = []
        for segment in segments {
            let parts = segment.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ByteRangeError.malformed }
            if parts[0].isEmpty {
                guard let suffix = Int64(parts[1]), suffix > 0 else { throw ByteRangeError.malformed }
                result.append(HTTPByteRange(start: max(0, size - suffix), end: size - 1))
            } else {
                guard let start = Int64(parts[0]), start >= 0 else { throw ByteRangeError.malformed }
                guard start < size else { continue }
                let end: Int64
                if parts[1].isEmpty { end = size - 1 }
                else {
                    guard let parsed = Int64(parts[1]), parsed >= start else { throw ByteRangeError.malformed }
                    end = min(parsed, size - 1)
                }
                result.append(HTTPByteRange(start: start, end: end))
            }
        }
        guard !result.isEmpty else { throw ByteRangeError.unsatisfiable }
        return result
    }
}
