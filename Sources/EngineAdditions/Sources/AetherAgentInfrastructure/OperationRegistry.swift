import Foundation

public enum OperationState: String, Codable, Sendable {
    case pending, running, succeeded, failed, cancelled
}

public struct OperationRecord: Codable, Sendable {
    public let id: String
    public let owner: String
    public let session: String
    public let kind: String
    public var state: OperationState
    public let startedAt: Date
    public var finishedAt: Date?
    public var error: String?
}

public enum OperationError: Error, Sendable { case duplicate, missing, invalidTransition, unauthorized }

public actor OperationRegistry {
    private var records: [String: OperationRecord] = [:]
    private let completedLimit: Int

    public init(completedLimit: Int = 500) { self.completedLimit = max(0, completedLimit) }

    public func register(id: String, owner: String, session: String, kind: String) throws {
        guard records[id] == nil else { throw OperationError.duplicate }
        records[id] = OperationRecord(id: id, owner: owner, session: session, kind: kind, state: .pending, startedAt: Date())
    }

    @discardableResult public func transition(id: String, owner: String, to state: OperationState, error: String? = nil) throws -> OperationRecord {
        guard var record = records[id] else { throw OperationError.missing }
        guard record.owner == owner else { throw OperationError.unauthorized }
        let legal: Bool
        switch (record.state, state) {
        case (.pending, .running), (.pending, .cancelled), (.running, .succeeded), (.running, .failed), (.running, .cancelled): legal = true
        default: legal = false
        }
        guard legal else { throw OperationError.invalidTransition }
        record.state = state
        record.error = error
        if state != .running { record.finishedAt = Date() }
        records[id] = record
        prune()
        return record
    }

    public func get(_ id: String, owner: String) throws -> OperationRecord {
        guard let record = records[id] else { throw OperationError.missing }
        guard record.owner == owner else { throw OperationError.unauthorized }
        return record
    }

    private func prune() {
        let completed = records.values.filter { $0.finishedAt != nil }.sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
        for record in completed.prefix(max(0, completed.count - completedLimit)) { records.removeValue(forKey: record.id) }
    }
}
