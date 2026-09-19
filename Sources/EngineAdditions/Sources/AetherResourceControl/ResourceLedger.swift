import Foundation

public enum ResourceKind: String, CaseIterable, Codable, Sendable {
    case processMemory, gpuMemory, decodedImages, rasterTiles, glyphs, networkBuffers
}

public struct ResourceLimits: Sendable, Equatable {
    public var bytes: [ResourceKind: Int]

    public init(bytes: [ResourceKind: Int]) {
        self.bytes = bytes.mapValues { max(0, $0) }
    }

    public subscript(_ kind: ResourceKind) -> Int { bytes[kind] ?? 0 }
}

public struct ResourceSnapshot: Sendable, Equatable {
    public let used: [ResourceKind: Int]
    public let limits: ResourceLimits

    public func utilization(_ kind: ResourceKind) -> Double {
        let limit = limits[kind]
        guard limit > 0 else { return used[kind, default: 0] == 0 ? 0 : 1 }
        return Double(used[kind, default: 0]) / Double(limit)
    }
}

public enum ResourceError: Error, Sendable, Equatable {
    case capacityExceeded(ResourceKind)
    case invalidReservation
    case unknownReservation
}

public struct ResourceReservation: Hashable, Sendable {
    public let id: UUID
    public let kind: ResourceKind
    public let bytes: Int
}

public actor ResourceLedger {
    private let limits: ResourceLimits
    private var used: [ResourceKind: Int] = [:]
    private var reservations: [UUID: ResourceReservation] = [:]

    public init(limits: ResourceLimits) { self.limits = limits }

    public func reserve(_ bytes: Int, kind: ResourceKind) throws -> ResourceReservation {
        guard bytes > 0 else { throw ResourceError.invalidReservation }
        let current = used[kind, default: 0]
        guard current <= limits[kind], bytes <= limits[kind] - current else {
            throw ResourceError.capacityExceeded(kind)
        }
        let reservation = ResourceReservation(id: UUID(), kind: kind, bytes: bytes)
        used[kind] = current + bytes
        reservations[reservation.id] = reservation
        return reservation
    }

    public func release(_ reservation: ResourceReservation) throws {
        guard let stored = reservations[reservation.id], stored == reservation else {
            throw ResourceError.unknownReservation
        }
        reservations.removeValue(forKey: reservation.id)
        used[stored.kind, default: 0] -= stored.bytes
    }

    public func snapshot() -> ResourceSnapshot { ResourceSnapshot(used: used, limits: limits) }
}
