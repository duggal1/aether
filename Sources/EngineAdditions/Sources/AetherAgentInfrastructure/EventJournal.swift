import Foundation

public struct JournalEvent: Codable, Sendable, Equatable {
    public let sequence: UInt64
    public let session: String
    public let type: String
    public let payload: Data
    public let timestamp: Date
}

public struct JournalBatch: Sendable {
    public let events: [JournalEvent]
    public let oldestAvailable: UInt64
    public let nextCursor: UInt64
    public let hasGap: Bool
}

public actor EventJournal {
    private let capacity: Int
    private var events: [JournalEvent] = []
    private var nextSequence: UInt64 = 1
    private var listeners: [UUID: AsyncStream<JournalEvent>.Continuation] = [:]

    public init(capacity: Int = 2_048) { self.capacity = max(1, capacity) }

    @discardableResult public func append(session: String, type: String, payload: Data = Data()) -> JournalEvent {
        let event = JournalEvent(sequence: nextSequence, session: session, type: type, payload: payload, timestamp: Date())
        nextSequence &+= 1
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        for listener in listeners.values { listener.yield(event) }
        return event
    }

    public func replay(after cursor: UInt64, session: String? = nil, limit: Int = 256) -> JournalBatch {
        let oldest = events.first?.sequence ?? nextSequence
        let selected = events.lazy.filter { $0.sequence > cursor && (session == nil || $0.session == session) }.prefix(max(0, limit))
        let result = Array(selected)
        return JournalBatch(events: result, oldestAvailable: oldest, nextCursor: result.last?.sequence ?? cursor, hasGap: cursor < oldest - 1)
    }

    public func subscribe() -> (UUID, AsyncStream<JournalEvent>) {
        let id = UUID()
        let stream = AsyncStream<JournalEvent>(bufferingPolicy: .bufferingNewest(capacity)) { continuation in
            listeners[id] = continuation
            continuation.onTermination = { @Sendable _ in Task { await self.unsubscribe(id) } }
        }
        return (id, stream)
    }

    public func unsubscribe(_ id: UUID) {
        listeners.removeValue(forKey: id)?.finish()
    }
}
