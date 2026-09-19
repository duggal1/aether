import Foundation

public enum ByteStreamError: Error, Sendable, Equatable {
    case closed
    case chunkTooLarge
    case failed(String)
}

public actor BoundedByteStream {
    private let capacity: Int
    private var buffered: [Data] = []
    private var bytes = 0
    private var closed = false
    private var failure: String?
    private var receivers: [(UUID, CheckedContinuation<Data?, Error>)] = []
    private var senders: [(UUID, Data, CheckedContinuation<Void, Error>)] = []

    public init(capacity: Int = 1_048_576) { self.capacity = max(1, capacity) }

    public func write(_ chunk: Data) async throws {
        guard !chunk.isEmpty else { return }
        guard chunk.count <= capacity else { throw ByteStreamError.chunkTooLarge }
        if let failure { throw ByteStreamError.failed(failure) }
        guard !closed else { throw ByteStreamError.closed }
        if buffered.isEmpty, !receivers.isEmpty {
            receivers.removeFirst().1.resume(returning: chunk)
            return
        }
        if bytes <= capacity - chunk.count {
            buffered.append(chunk)
            bytes += chunk.count
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { senders.append((id, chunk, continuation)) }
            }
        } onCancel: { Task { await self.cancelSender(id) } }
    }

    public func read() async throws -> Data? {
        if !buffered.isEmpty {
            let chunk = buffered.removeFirst()
            bytes -= chunk.count
            drainWriters()
            return chunk
        }
        if let failure { throw ByteStreamError.failed(failure) }
        if closed { return nil }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { receivers.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelReceiver(id) } }
    }

    public func finish() {
        guard !closed else { return }
        closed = true
        for (_, receiver) in receivers { receiver.resume(returning: nil) }
        receivers.removeAll()
        for (_, _, sender) in senders { sender.resume(throwing: ByteStreamError.closed) }
        senders.removeAll()
    }

    public func fail(_ message: String) {
        guard !closed else { return }
        failure = message
        closed = true
        buffered.removeAll()
        bytes = 0
        for (_, receiver) in receivers { receiver.resume(throwing: ByteStreamError.failed(message)) }
        receivers.removeAll()
        for (_, _, sender) in senders { sender.resume(throwing: ByteStreamError.failed(message)) }
        senders.removeAll()
    }

    public func snapshot() -> (bytes: Int, pendingWriters: Int, pendingReaders: Int) {
        (bytes, senders.count, receivers.count)
    }

    private func drainWriters() {
        while !senders.isEmpty {
            let (id, chunk, continuation) = senders[0]
            guard bytes <= capacity - chunk.count else { break }
            senders.removeFirst()
            if buffered.isEmpty, !receivers.isEmpty { receivers.removeFirst().1.resume(returning: chunk) }
            else { buffered.append(chunk); bytes += chunk.count }
            continuation.resume()
            _ = id
        }
    }

    private func cancelReceiver(_ id: UUID) {
        guard let index = receivers.firstIndex(where: { $0.0 == id }) else { return }
        let (_, continuation) = receivers.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }

    private func cancelSender(_ id: UUID) {
        guard let index = senders.firstIndex(where: { $0.0 == id }) else { return }
        let (_, _, continuation) = senders.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }
}
