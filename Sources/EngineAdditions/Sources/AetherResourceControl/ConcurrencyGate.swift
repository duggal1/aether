import Foundation

public enum AdmissionError: Error, Sendable { case closed }

public actor ConcurrencyGate {
    private let capacity: Int
    private var active = 0
    private var closed = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    public init(capacity: Int) { self.capacity = max(1, capacity) }

    public func enter() async throws {
        if closed { throw AdmissionError.closed }
        if active < capacity {
            active += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if closed { continuation.resume(throwing: AdmissionError.closed) }
                else if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if Task.isCancelled {
            leave()
            throw CancellationError()
        }
    }

    public func leave() {
        guard active > 0 else { return }
        while !waiters.isEmpty {
            let (_, next) = waiters.removeFirst()
            next.resume()
            return
        }
        active -= 1
    }

    public func shutdown() {
        closed = true
        let pending = waiters
        waiters.removeAll()
        for (_, continuation) in pending { continuation.resume(throwing: AdmissionError.closed) }
    }

    public func snapshot() -> (active: Int, queued: Int) { (active, waiters.count) }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        let (_, continuation) = waiters.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }
}
