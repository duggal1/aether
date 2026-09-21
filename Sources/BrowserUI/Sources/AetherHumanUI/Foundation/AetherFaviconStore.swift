import AppKit
import CryptoKit
import Foundation

@MainActor
public final class AetherFaviconStore {
    public static let shared = AetherFaviconStore()
    public static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    public static let requestTimeout: TimeInterval = 6

    private var memory: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var unavailable: Set<String> = []
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Aether/Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func cachedImage(for host: String) -> NSImage? { memory[normalized(host)] }

    public func isUnavailable(_ host: String) -> Bool { unavailable.contains(normalized(host)) }

    public func image(for host: String) async -> NSImage? {
        let key = normalized(host)
        guard !key.isEmpty else { return nil }
        if let image = memory[key] { return image }
        if unavailable.contains(key) { return nil }
        if let pending = inFlight[key] { return await pending.value }
        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.load(key)
            self.inFlight[key] = nil
            if let image { self.memory[key] = image } else { self.unavailable.insert(key) }
            return image
        }
        inFlight[key] = task
        return await task.value
    }

    public func prefetch(_ hosts: [String]) {
        for host in hosts { Task { _ = await image(for: host) } }
    }

    private func load(_ host: String) async -> NSImage? {
        if let disk = diskImage(host) { return disk }
        for url in candidates(host) {
            guard let image = await fetch(url) else { continue }
            store(image, host: host)
            return image
        }
        return nil
    }

    private func candidates(_ host: String) -> [URL] {
        [
            URL(string: "https://\(host)/apple-touch-icon.png"),
            URL(string: "https://\(host)/apple-touch-icon-precomposed.png"),
            URL(string: "https://\(host)/favicon.ico"),
            URL(string: "https://\(host)/favicon.png"),
            URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
        ].compactMap { $0 }
    }

    private func fetch(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard data.count >= 64, let image = NSImage(data: data), image.size.width >= 8 else { return nil }
        return image
    }

    private func diskImage(_ host: String) -> NSImage? {
        let file = directory.appendingPathComponent(hostKey(host)).appendingPathExtension("png")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.cacheTTL,
              let image = NSImage(contentsOf: file) else { return nil }
        return image
    }

    private func store(_ image: NSImage, host: String) {
        let key = hostKey(host)
        let file = directory.appendingPathComponent(key).appendingPathExtension("png")
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func hostKey(_ host: String) -> String {
        SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func normalized(_ host: String) -> String {
        host.lowercased().replacingOccurrences(of: "www.", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
