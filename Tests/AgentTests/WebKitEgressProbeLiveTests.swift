import BrowserEngine
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["AETHER_LIVE"] == "1"))
struct WebKitEgressProbeLiveTests {
    @Test @MainActor func egressProbeExecutesInRealWebKit() async throws {
        let port: UInt16 = 18767
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/webkit", isDirectory: true)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [
            "-m", "http.server", "\(port)", "--bind", "127.0.0.1",
            "--directory", fixtureDir.path,
        ]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        try server.run()
        defer { server.terminate() }
        let deadline = Date().addingTimeInterval(10)
        var ready = false
        while Date() < deadline {
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            probe.arguments = [
                "-s", "-o", "/dev/null", "-w", "%{http_code}",
                "http://127.0.0.1:\(port)/egress.html",
            ]
            let pipe = Pipe()
            probe.standardOutput = pipe
            try? probe.run()
            probe.waitUntilExit()
            let code = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            if code == "200" { ready = true; break }
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(ready, "fixture server never became reachable")

        let profileID = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(profileID)
        let runtime = BrowserRuntime()
        let context = await runtime.createContext(name: "egress-probe")
        try await runtime.openProfile(contextID: context.id, directory: directory)
        let page = try await runtime.createPage(contextID: context.id)
        try await runtime.navigate(
            pageID: page.id, to: URL(string: "http://127.0.0.1:\(port)/egress.html")!,
            settle: .complete)
        var report = ""
        let reportDeadline = Date().addingTimeInterval(30)
        while Date() < reportDeadline {
            report = (try? await runtime.webDocumentText(pageID: page.id)) ?? ""
            if report.contains("\"publicIP\"") && !report.contains("\"status\":\"probing\"") {
                break
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        print("EGRESS-REPORT-BEGIN")
        print(report)
        print("EGRESS-REPORT-END")
        #expect(report.contains("\"publicIP\""), "probe JS never populated the report")
        try await runtime.destroyContext(context.id)
    }
}
