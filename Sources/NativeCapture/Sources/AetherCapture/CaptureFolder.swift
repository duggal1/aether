import Foundation

/// Write to a sibling staging directory, then atomically publish on success.
/// Never overwrite another capture; never allow a path traversal from URLs.
struct CaptureFolder {
    let destination: URL
    let staging: URL
    init(destination: URL) {
        self.destination = destination
        self.staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".aether-\(UUID().uuidString)-staging")
    }

    func prepare() throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path),
              !manager.fileExists(atPath: staging.path) else {
            throw CaptureFailure.pathNotWritable(destination.path)
        }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    }

    func write(_ data: Data, relative path: String) throws {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\\") else {
            throw CaptureFailure.pathNotWritable(path)
        }
        let file = staging.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    func writeJSON<T: Encodable>(_ value: T, relative path: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try write(encoder.encode(value), relative: path)
    }

    func finish() throws {
        try FileManager.default.moveItem(at: staging, to: destination)
    }
    func discard() {
        try? FileManager.default.removeItem(at: staging)
    }
}
