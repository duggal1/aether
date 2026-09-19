import Foundation

public enum FleetPageState: Int, Codable, Sendable, CaseIterable {
    case discarded, frozen, suspended, background, active
}

public struct FleetPage: Sendable, Hashable {
    public let id: String
    public let owner: String
    public var state: FleetPageState
    public var estimatedBytes: Int
    public var importance: Int
    public var lastUsedTick: UInt64
    public var pinned: Bool
    public var pendingWork: Bool

    public init(id: String, owner: String, state: FleetPageState, estimatedBytes: Int, importance: Int = 0, lastUsedTick: UInt64 = 0, pinned: Bool = false, pendingWork: Bool = false) {
        self.id = id
        self.owner = owner
        self.state = state
        self.estimatedBytes = max(0, estimatedBytes)
        self.importance = importance
        self.lastUsedTick = lastUsedTick
        self.pinned = pinned
        self.pendingWork = pendingWork
    }
}

public struct FleetTransition: Sendable, Equatable {
    public let pageID: String
    public let from: FleetPageState
    public let to: FleetPageState
}

public struct FleetPlan: Sendable {
    public let transitions: [FleetTransition]
    public let projectedBytes: Int
    public let unmetBytes: Int
}

public struct FleetPolicy: Sendable {
    public var budgetBytes: Int
    public var suspendedRetention: Double
    public var frozenRetention: Double

    public init(budgetBytes: Int, suspendedRetention: Double = 0.55, frozenRetention: Double = 0.18) {
        self.budgetBytes = max(0, budgetBytes)
        self.suspendedRetention = min(1, max(0, suspendedRetention))
        self.frozenRetention = min(1, max(0, frozenRetention))
    }

    public func plan(_ pages: [FleetPage]) -> FleetPlan {
        let initial = pages.reduce(0) { $0 + max(0, $1.estimatedBytes) }
        var remaining = initial
        var transitions: [FleetTransition] = []
        let candidates = pages.filter { !$0.pinned && !$0.pendingWork }.sorted {
            if $0.importance != $1.importance { return $0.importance < $1.importance }
            if $0.lastUsedTick != $1.lastUsedTick { return $0.lastUsedTick < $1.lastUsedTick }
            return $0.id < $1.id
        }
        for page in candidates where remaining > budgetBytes {
            var state = page.state
            let original = Double(page.estimatedBytes)
            var estimate = original
            while remaining > budgetBytes, state != .discarded {
                let previous = state
                state = nextState(state)
                let revised = state == .discarded ? 0 : estimate * retention(state) / max(0.0001, retention(previous))
                remaining -= Int(estimate.rounded(.down)) - Int(revised.rounded(.down))
                estimate = revised
                transitions.append(FleetTransition(pageID: page.id, from: previous, to: state))
            }
        }
        return FleetPlan(transitions: transitions, projectedBytes: max(0, remaining), unmetBytes: max(0, remaining - budgetBytes))
    }

    private func retention(_ state: FleetPageState) -> Double {
        switch state {
        case .active, .background: 1
        case .suspended: suspendedRetention
        case .frozen: frozenRetention
        case .discarded: 0
        }
    }

    private func nextState(_ state: FleetPageState) -> FleetPageState {
        switch state {
        case .active: .background
        case .background: .suspended
        case .suspended: .frozen
        case .frozen, .discarded: .discarded
        }
    }
}
