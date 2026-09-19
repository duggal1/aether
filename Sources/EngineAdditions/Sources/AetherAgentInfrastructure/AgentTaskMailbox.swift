import Foundation

public struct AgentTask: Sendable, Equatable {
    public let id: String
    public let owner: String
    public let session: String
    public let action: String
    public let payload: Data
    public let deadline: Date?

    public init(id: String, owner: String, session: String, action: String, payload: Data = Data(), deadline: Date? = nil) {
        self.id = id; self.owner = owner; self.session = session; self.action = action; self.payload = payload; self.deadline = deadline
    }
}

public enum MailboxError: Error, Sendable { case closed, capacityExceeded, duplicate, wrongOwner }

public actor AgentTaskMailbox {
    private let capacity: Int
    private var pending: [AgentTask] = []
    private var active: [String: AgentTask] = [:]
    private var closed = false

    public init(capacity: Int = 1_024) { self.capacity = max(1, capacity) }

    public func enqueue(_ task: AgentTask) throws {
        guard !closed else { throw MailboxError.closed }
        guard pending.count + active.count < capacity else { throw MailboxError.capacityExceeded }
        guard !pending.contains(where: { $0.id == task.id }), active[task.id] == nil else { throw MailboxError.duplicate }
        pending.append(task)
    }

    public func take(owner: String, now: Date = Date()) -> AgentTask? {
        pending.removeAll { $0.deadline.map { $0 <= now } ?? false }
        guard let index = pending.firstIndex(where: { $0.owner == owner }) else { return nil }
        let item = pending.remove(at: index)
        active[item.id] = item
        return item
    }

    public func complete(id: String, owner: String) throws {
        guard let item = active[id], item.owner == owner else { throw MailboxError.wrongOwner }
        active.removeValue(forKey: id)
    }

    public func cancel(id: String, owner: String) throws {
        if let item = active[id] {
            guard item.owner == owner else { throw MailboxError.wrongOwner }
            active.removeValue(forKey: id)
            return
        }
        guard let index = pending.firstIndex(where: { $0.id == id && $0.owner == owner }) else { throw MailboxError.wrongOwner }
        pending.remove(at: index)
    }

    public func shutdown() { closed = true; pending.removeAll() }
    public func snapshot() -> (pending: Int, active: Int) { (pending.count, active.count) }
}
