import Foundation

public enum ChannelError: Error, Sendable { case closed, overflow }

public struct TransferMessage: Codable, Sendable, Equatable {
    public let sequence: UInt64
    public let payload: Data
}

public actor MessageChannel {
    private let maximumBytes: Int
    private var queuedBytes = 0
    private var queue: [TransferMessage] = []
    private var sequence: UInt64 = 0
    private var closed = false
    private var listeners: [CheckedContinuation<TransferMessage?, Never>] = []

    public init(maximumBytes: Int = 1_048_576) { self.maximumBytes = max(1, maximumBytes) }

    public func send(_ data: Data) throws {
        guard !closed else { throw ChannelError.closed }
        guard data.count <= maximumBytes - queuedBytes else { throw ChannelError.overflow }
        sequence &+= 1
        let message = TransferMessage(sequence: sequence, payload: data)
        if !listeners.isEmpty { listeners.removeFirst().resume(returning: message) }
        else { queue.append(message); queuedBytes += data.count }
    }

    public func receive() async -> TransferMessage? {
        if !queue.isEmpty {
            let message = queue.removeFirst()
            queuedBytes -= message.payload.count
            return message
        }
        if closed { return nil }
        return await withCheckedContinuation { continuation in listeners.append(continuation) }
    }

    public func finish() {
        closed = true
        for listener in listeners { listener.resume(returning: nil) }
        listeners.removeAll()
    }

    public func bufferedBytes() -> Int { queuedBytes }
}
