import Foundation
import AetherResourceControl

public struct AgentInvocation: Sendable {
    public let id: String
    public let owner: String
    public let session: String
    public let generation: UInt64
    public let method: String
    public let parameters: Data
    public let deadline: Date?

    public init(id: String, owner: String, session: String, generation: UInt64, method: String, parameters: Data, deadline: Date? = nil) {
        self.id = id
        self.owner = owner
        self.session = session
        self.generation = generation
        self.method = method
        self.parameters = parameters
        self.deadline = deadline
    }
}

public enum GatewayError: Error, Sendable, Equatable {
    case unsupportedMethod
    case emptyRequest
    case oversizedPayload
    case expired
    case duplicateInProgress
    case duplicateConflict
    case invalidResult
}

public struct CommandAccessPolicy: Sendable {
    private let rules: [String: SessionPermission]

    public init(rules: [String: SessionPermission]) { self.rules = rules }

    public func permission(for method: String) -> SessionPermission? { rules[method] }
}

public actor AgentGateway {
    private let authority: SessionAuthority
    private let journal: EventJournal
    private let deduplication: CommandDeduplication
    private let operations: OperationRegistry
    private let gate: ConcurrencyGate
    private let policy: CommandAccessPolicy
    private let maximumPayloadBytes: Int

    public init(authority: SessionAuthority, journal: EventJournal, deduplication: CommandDeduplication, operations: OperationRegistry, gate: ConcurrencyGate, policy: CommandAccessPolicy, maximumPayloadBytes: Int = 1_048_576) {
        self.authority = authority
        self.journal = journal
        self.deduplication = deduplication
        self.operations = operations
        self.gate = gate
        self.policy = policy
        self.maximumPayloadBytes = max(1, maximumPayloadBytes)
    }

    public func execute(_ request: AgentInvocation, perform: @Sendable (AgentInvocation) async throws -> Data) async throws -> Data {
        guard !request.id.isEmpty, !request.session.isEmpty, !request.owner.isEmpty else { throw GatewayError.emptyRequest }
        guard request.parameters.count <= maximumPayloadBytes else { throw GatewayError.oversizedPayload }
        guard request.deadline.map({ $0 > Date() }) ?? true else { throw GatewayError.expired }
        guard let permission = policy.permission(for: request.method) else { throw GatewayError.unsupportedMethod }
        try await authority.check(session: request.session, owner: request.owner, permission: permission, generation: request.generation)
        let fingerprint = Data(request.method.utf8) + Data([0]) + Data(request.session.utf8) + Data([0]) + request.parameters
        switch await deduplication.begin(owner: request.owner, request: request.id, fingerprint: fingerprint) {
        case .cached(let result): return result
        case .inProgress: throw GatewayError.duplicateInProgress
        case .payloadConflict: throw GatewayError.duplicateConflict
        case .execute: break
        }
        do {
            try await gate.enter()
        } catch {
            await deduplication.abandon(owner: request.owner, request: request.id)
            throw error
        }
        do {
            guard request.deadline.map({ $0 > Date() }) ?? true else { throw GatewayError.expired }
            try await operations.register(id: request.id, owner: request.owner, session: request.session, kind: request.method)
            _ = try await operations.transition(id: request.id, owner: request.owner, to: .running)
            await journal.append(session: request.session, type: "command.started", payload: Data(request.method.utf8))
            let response = try await perform(request)
            _ = try await operations.transition(id: request.id, owner: request.owner, to: .succeeded)
            await journal.append(session: request.session, type: "command.succeeded", payload: Data(request.method.utf8))
            await deduplication.finish(owner: request.owner, request: request.id, response: response)
            await gate.leave()
            return response
        } catch {
            if let record = try? await operations.get(request.id, owner: request.owner), record.state == .running {
                _ = try? await operations.transition(id: request.id, owner: request.owner, to: .failed, error: String(describing: error))
            }
            await journal.append(session: request.session, type: "command.failed", payload: Data(String(describing: error).utf8))
            await deduplication.abandon(owner: request.owner, request: request.id)
            await gate.leave()
            throw error
        }
    }
}
