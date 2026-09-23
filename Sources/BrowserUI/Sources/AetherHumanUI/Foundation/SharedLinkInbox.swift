import Foundation

public struct SharedLinkRecord: Codable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public enum SharedLinkInbox {
    public static let groupIdentifier = "group.dev.aether.browser"

    public static func pending() -> [(SharedLinkRecord, URL)] {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("Incoming", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(SharedLinkRecord.self, from: data)
            else { return nil }
            return (record, file)
        }
    }
}
