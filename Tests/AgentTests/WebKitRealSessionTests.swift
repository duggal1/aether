import BrowserEngine
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

struct WebKitRealSessionTests {
    private static let markers = ["cookie-alive", "storage-alive", "idb-alive"]

    private func fixtureDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/webkit", isDirectory: true)
    }

    private func shell(_ path: String, _ arguments: [String]) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return (-1, "") }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func startFixtureServer(port: UInt16) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-m", "http.server", "\(port)", "--bind", "127.0.0.1",
            "--directory", fixtureDirectory().path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if !process.isRunning { throw BrowserRuntimeError.timeout("fixture server exited early") }
            let probe = shell(
                "/usr/bin/curl",
                ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://127.0.0.1:\(port)/session.html"])
            if probe.code == 0, probe.output == "200" { return process }
            Thread.sleep(forTimeInterval: 0.2)
        }
        process.terminate()
        throw BrowserRuntimeError.timeout("fixture server never became reachable")
    }

    private func readMarkers(
        _ runtime: BrowserRuntime, pageID: PageID, deadlineSeconds: Double = 20
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(deadlineSeconds)
        var text = ""
        while Date() < deadline {
            text = (try? await runtime.webDocumentText(pageID: pageID)) ?? ""
            if Self.markers.allSatisfy({ text.contains($0) }) { return text }
            try await Task.sleep(for: .milliseconds(250))
        }
        return text
    }

    @Test @MainActor func realSessionSurvivesQuitAndRelaunch() async throws {
        let server = try startFixtureServer(port: 18765)
        defer { server.terminate() }
        let base = "http://127.0.0.1:18765"
        let profileID = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(profileID)

        let first = BrowserRuntime()
        let firstContext = await first.createContext(name: "real-session")
        try await first.openProfile(contextID: firstContext.id, directory: directory)
        let seedPage = try await first.createPage(contextID: firstContext.id)
        try await first.navigate(
            pageID: seedPage.id, to: URL(string: "\(base)/session.html?seed=1")!,
            settle: .complete)
        let seeded = try await readMarkers(first, pageID: seedPage.id)
        for marker in Self.markers {
            #expect(seeded.contains(marker), "seeding failed: \(marker) missing after real navigation")
        }
        try await first.destroyContext(firstContext.id)

        let second = BrowserRuntime()
        let secondContext = await second.createContext(name: "real-session-relaunch")
        try await second.openProfile(contextID: secondContext.id, directory: directory)
        let returnPage = try await second.createPage(contextID: secondContext.id)
        try await second.navigate(
            pageID: returnPage.id, to: URL(string: "\(base)/session.html")!, settle: .complete)
        let restored = try await readMarkers(second, pageID: returnPage.id)
        for marker in Self.markers {
            #expect(restored.contains(marker), "persistence failed: \(marker) lost across relaunch")
        }
        try await second.destroyContext(secondContext.id)
    }

    @Test @MainActor func realSessionNeverLeaksAcrossProfiles() async throws {
        let server = try startFixtureServer(port: 18766)
        defer { server.terminate() }
        let base = "http://127.0.0.1:18766"
        let runtime = BrowserRuntime()

        let seededProfile = UUID().uuidString
        let seededDir = FileManager.default.temporaryDirectory.appendingPathComponent(seededProfile)
        let seededContext = await runtime.createContext(name: "seeded")
        try await runtime.openProfile(contextID: seededContext.id, directory: seededDir)
        let seedPage = try await runtime.createPage(contextID: seededContext.id)
        try await runtime.navigate(
            pageID: seedPage.id, to: URL(string: "\(base)/session.html?seed=1")!,
            settle: .complete)
        let seeded = try await readMarkers(runtime, pageID: seedPage.id)
        #expect(Self.markers.allSatisfy({ seeded.contains($0) }))

        let otherProfile = UUID().uuidString
        let otherDir = FileManager.default.temporaryDirectory.appendingPathComponent(otherProfile)
        let otherContext = await runtime.createContext(name: "other")
        try await runtime.openProfile(contextID: otherContext.id, directory: otherDir)
        let otherPage = try await runtime.createPage(contextID: otherContext.id)
        try await runtime.navigate(
            pageID: otherPage.id, to: URL(string: "\(base)/session.html")!, settle: .complete)
        try await Task.sleep(for: .seconds(3))
        let other = (try? await runtime.webDocumentText(pageID: otherPage.id)) ?? ""
        for marker in Self.markers {
            #expect(!other.contains(marker), "isolation failed: \(marker) visible in another profile")
        }
        try await runtime.destroyContext(seededContext.id)
        try await runtime.destroyContext(otherContext.id)
    }
}
