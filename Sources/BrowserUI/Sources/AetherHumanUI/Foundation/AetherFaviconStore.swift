import AppKit
import CryptoKit
import Foundation
import ImageIO

@MainActor
public final class AetherFaviconStore {
    public static let shared = AetherFaviconStore()
    public static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    public static let requestTimeout: TimeInterval = 6
    private static let maxMemoryIcons = 128
    private static let maxIconPixels = 128

    private var memory: [String: NSImage] = [:]
    private var memoryOrder: [String] = []
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
            if let image { self.cache(image, for: key) } else { self.unavailable.insert(key) }
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
            URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
            URL(string: "https://\(host)/apple-touch-icon.png"),
            URL(string: "https://\(host)/apple-touch-icon-precomposed.png"),
            URL(string: "https://\(host)/favicon.ico"),
            URL(string: "https://\(host)/favicon.png")
        ].compactMap { $0 }
    }

    private func fetch(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard (64...2_097_152).contains(data.count) else { return nil }
        return thumbnail(from: data as CFData)
    }

    private func diskImage(_ host: String) -> NSImage? {
        let file = directory.appendingPathComponent(hostKey(host)).appendingPathExtension("png")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.cacheTTL,
              let source = CGImageSourceCreateWithURL(file as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(from: source)
    }

    private func thumbnail(from data: CFData) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(from: source)
    }

    private func thumbnail(from source: CGImageSource) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxIconPixels
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              image.width >= 8, image.height >= 8 else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func cache(_ image: NSImage, for host: String) {
        if memory[host] == nil { memoryOrder.append(host) }
        memory[host] = image
        if memoryOrder.count > Self.maxMemoryIcons {
            let evicted = memoryOrder.removeFirst()
            memory.removeValue(forKey: evicted)
        }
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
        let value = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}
