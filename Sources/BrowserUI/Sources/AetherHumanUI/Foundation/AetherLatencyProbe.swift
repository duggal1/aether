import Foundation

public enum AetherLatencyProbe {
    public static let enabled = ProcessInfo.processInfo.environment["AETHER_LATENCY_DIAG"] != nil
    private static let anchor = Date()

    @inline(__always)
    public static func mark(_ label: @autoclosure () -> String) {
        guard enabled else { return }
        let elapsed = Date().timeIntervalSince(anchor) * 1000
        let epoch = Date().timeIntervalSince1970 * 1000
        let line = String(format: "[latency] %9.1fms epoch=%.0f %@\n", elapsed, epoch, label())
        FileHandle.standardError.write(Data(line.utf8))
    }
}
