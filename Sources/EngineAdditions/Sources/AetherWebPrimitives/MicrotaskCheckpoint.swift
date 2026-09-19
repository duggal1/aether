import Foundation

@MainActor public final class MicrotaskCheckpoint {
    private var tasks: [() -> Void] = []
    private var draining = false
    public var maximumJobsPerCheckpoint: Int

    public init(maximumJobsPerCheckpoint: Int = 10_000) {
        self.maximumJobsPerCheckpoint = max(1, maximumJobsPerCheckpoint)
    }

    public func enqueue(_ job: @escaping () -> Void) { tasks.append(job) }

    @discardableResult public func run() -> Int {
        guard !draining else { return 0 }
        draining = true
        defer { draining = false }
        var cursor = 0
        while cursor < tasks.count, cursor < maximumJobsPerCheckpoint {
            let job = tasks[cursor]
            cursor += 1
            job()
        }
        if cursor > 0 { tasks.removeFirst(cursor) }
        return cursor
    }

    public var pending: Int { tasks.count }
}
