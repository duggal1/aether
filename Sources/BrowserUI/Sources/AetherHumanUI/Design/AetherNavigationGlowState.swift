import Foundation

public enum AetherNavigationPhase: String, Sendable, CaseIterable {
    case idle
    case started
    case awaitingContent
    case contentVisible
    case failed

    public var isActive: Bool { self != .idle }
}

public struct AetherNavigationGlowState: Equatable, Sendable {
    public static let instantThreshold: TimeInterval = 0.18

    public private(set) var phase: AetherNavigationPhase = .idle
    public private(set) var startedAt: Date?
    public private(set) var wasInstant = false

    public init() {}

    public mutating func begin(now: Date = Date()) {
        phase = .started
        startedAt = now
        wasInstant = false
    }

    public mutating func awaitContent() {
        guard phase == .started || phase == .awaitingContent else { return }
        phase = .awaitingContent
    }

    public mutating func contentVisible(now: Date = Date()) {
        guard phase.isActive else { return }
        wasInstant = elapsed(now) < Self.instantThreshold
        phase = .contentVisible
    }

    public mutating func fail(now: Date = Date()) {
        guard phase.isActive else { return }
        wasInstant = elapsed(now) < Self.instantThreshold
        phase = .failed
    }

    public mutating func settle() {
        phase = .idle
        startedAt = nil
    }

    private func elapsed(_ now: Date) -> TimeInterval {
        guard let startedAt else { return .greatestFiniteMagnitude }
        return now.timeIntervalSince(startedAt)
    }
}
