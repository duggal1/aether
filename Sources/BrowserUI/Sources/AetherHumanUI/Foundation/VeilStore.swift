import Foundation

// Ported from Search/Sources/Search/Curtain.swift (Veil/Curtain).
// Per-site element hiding: selectors remembered by host, applied as a
// `display:none` stylesheet. Persisted to Application Support + UserDefaults fallback.
public struct Veil: Codable, Identifiable, Equatable, Sendable {
    public var selector: String
    public var label: String
    public var note: String?
    public var date: Date
    public var id: String { selector }
    public init(selector: String, label: String, note: String? = nil, date: Date = Date()) {
        self.selector = selector; self.label = label; self.note = note; self.date = date
    }
}

@MainActor
public final class VeilStore {
    public static let shared = VeilStore()
    private var byHost: [String: [Veil]] = [:]
    private var saveWork: Task<Void, Never>?

    private init() { load() }

    public func host(of url: URL?) -> String? {
        guard let h = url?.host?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    public func host(of raw: String?) -> String? {
        guard let raw, let url = URL(string: raw) else { return nil }
        return host(of: url)
    }

    public func veils(on host: String?) -> [Veil] {
        guard let host else { return [] }
        return byHost[host] ?? []
    }

    public func hide(_ selector: String, label: String, note: String, on host: String) {
        let sel = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sel.isEmpty, sel.count <= 500 else { return }
        var list = byHost[host] ?? []
        guard !list.contains(where: { $0.selector == sel }) else { return }
        list.append(Veil(selector: sel, label: label.isEmpty ? sel : label, note: note.isEmpty ? nil : note))
        byHost[host] = list
        saveSoon()
    }

    public func restore(_ veil: Veil, on host: String) {
        byHost[host] = (byHost[host] ?? []).filter { $0.selector != veil.selector }
        if byHost[host]?.isEmpty == true { byHost[host] = nil }
        saveSoon()
    }

    @discardableResult
    public func undo(on host: String) -> Veil? {
        guard var list = byHost[host], let last = list.popLast() else { return nil }
        byHost[host] = list.isEmpty ? nil : list
        saveSoon()
        return last
    }

    public func restoreAll(on host: String) {
        byHost.removeValue(forKey: host)
        saveSoon()
    }

    /// Stylesheet for a site. Each selector stands alone so one bad selector
    /// cannot take the whole list down (Search Curtain.css equivalent).
    public func css(on host: String?, without spared: String? = nil) -> String {
        veils(on: host)
            .filter { $0.selector != spared }
            .map { "\($0.selector) { display: none !important; }" }
            .joined(separator: "\n")
    }

    // MARK: - persistence (file + UserDefaults mirror)
    private static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Aether/veils.json")
    }

    private func load() {
        if let data = try? Data(contentsOf: Self.file),
           let stored = try? JSONDecoder().decode([String: [Veil]].self, from: data) {
            byHost = stored
            return
        }
        if let data = UserDefaults.standard.data(forKey: "aether.veils"),
           let stored = try? JSONDecoder().decode([String: [Veil]].self, from: data) {
            byHost = stored
        }
    }

    private func saveSoon() {
        saveWork?.cancel()
        let snapshot = byHost
        saveWork = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: "aether.veils")
                let url = Self.file
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
