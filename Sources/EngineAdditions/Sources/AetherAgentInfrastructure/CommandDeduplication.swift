import Foundation

public enum DeduplicationDecision: Sendable, Equatable {
    case execute
    case cached(Data)
    case inProgress
    case payloadConflict
}

public actor CommandDeduplication {
    private struct Entry {
        let fingerprint: Data
        var response: Data?
        let issued: Date
    }

    private var entries: [String: Entry] = [:]
    private let capacity: Int
    private let ttl: TimeInterval

    public init(capacity: Int = 2_048, ttl: TimeInterval = 300) {
        self.capacity = max(1, capacity)
        self.ttl = max(0, ttl)
    }

    public func begin(owner: String, request: String, fingerprint: Data, now: Date = Date()) -> DeduplicationDecision {
        evict(now: now)
        let key = owner + "\u{0}" + request
        if let entry = entries[key] {
            if entry.fingerprint != fingerprint { return .payloadConflict }
            return entry.response.map(DeduplicationDecision.cached) ?? .inProgress
        }
        if entries.count >= capacity, let oldest = entries.min(by: { $0.value.issued < $1.value.issued })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = Entry(fingerprint: fingerprint, issued: now)
        return .execute
    }

    public func finish(owner: String, request: String, response: Data) {
        let key = owner + "\u{0}" + request
        guard var existing = entries[key] else { return }
        existing.response = response
        entries[key] = existing
    }

    public func abandon(owner: String, request: String) { entries.removeValue(forKey: owner + "\u{0}" + request) }

    private func evict(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.issued) <= ttl }
    }
}
