import Foundation

public enum SessionPermission: String, CaseIterable, Codable, Sendable, Hashable {
    case inspect, navigate, interact, evaluate, storage, downloads, permissions, lifecycle
}

public enum AuthorityError: Error, Sendable, Equatable {
    case noSession
    case forbidden
    case duplicateSession
    case invalidOwner
}

public struct SessionGrant: Sendable, Equatable {
    public let session: String
    public let owner: String
    public let allowed: Set<SessionPermission>
    public let generation: UInt64
}

public actor SessionAuthority {
    private var grants: [String: SessionGrant] = [:]
    private var sequence: UInt64 = 0

    public init() {}

    @discardableResult public func create(session: String, owner: String, allowed: Set<SessionPermission> = [.inspect]) throws -> SessionGrant {
        guard !owner.isEmpty, !session.isEmpty else { throw AuthorityError.invalidOwner }
        guard grants[session] == nil else { throw AuthorityError.duplicateSession }
        sequence &+= 1
        let grant = SessionGrant(session: session, owner: owner, allowed: allowed, generation: sequence)
        grants[session] = grant
        return grant
    }

    public func check(session: String, owner: String, permission: SessionPermission, generation: UInt64? = nil) throws {
        guard let grant = grants[session] else { throw AuthorityError.noSession }
        guard grant.owner == owner, grant.allowed.contains(permission), generation.map({ $0 == grant.generation }) ?? true else {
            throw AuthorityError.forbidden
        }
    }

    @discardableResult public func rotate(session: String, owner: String) throws -> SessionGrant {
        guard let old = grants[session] else { throw AuthorityError.noSession }
        guard old.owner == owner else { throw AuthorityError.forbidden }
        sequence &+= 1
        let new = SessionGrant(session: session, owner: owner, allowed: old.allowed, generation: sequence)
        grants[session] = new
        return new
    }

    public func revoke(session: String, owner: String) throws {
        guard let existing = grants[session] else { throw AuthorityError.noSession }
        guard existing.owner == owner else { throw AuthorityError.forbidden }
        grants.removeValue(forKey: session)
    }

    public func list(owner: String) -> [SessionGrant] {
        grants.values.filter { $0.owner == owner }.sorted { $0.session < $1.session }
    }
}
