import Foundation
import Testing
@testable import AetherHumanUI

@MainActor
struct PrivateRouteTests {
    private func syntheticProtonConfig() -> String {
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        return """
            [Interface]
            PrivateKey = \(key)
            Address = 10.2.0.2/32

            [Peer]
            PublicKey = \(key)
            Endpoint = 127.0.0.1:51820
            AllowedIPs = 0.0.0.0/0
            """
    }

    private func isolatedManager() -> WireProxyManager {
        WireProxyManager(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    @Test func validProtonConfigurationPassesStructuralValidation() throws {
        try WireProxyManager.validateConfiguration(syntheticProtonConfig())
    }

    @Test func garbageConfigurationIsRejected() {
        #expect(throws: PrivateRouteError.self) {
            try WireProxyManager.validateConfiguration("hello garbage")
        }
    }

    @Test func configurationMissingPeerIsRejected() {
        #expect(throws: PrivateRouteError.self) {
            try WireProxyManager.validateConfiguration("[Interface]\nPrivateKey = abc\n")
        }
    }

    @Test func writtenWireProxyConfigurationMatchesDocumentedFormat() throws {
        let manager = isolatedManager()
        #expect(
            manager.wireProxyConfigurationContent()
                == "WGConfig = proton.conf\n\n[Socks5]\nBindAddress = 127.0.0.1:25344")
    }

    @Test func importWritesOwnerOnlyFiles() throws {
        let manager = isolatedManager()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".conf")
        try syntheticProtonConfig().write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }
        #expect(!manager.hasConfiguration)
        try manager.importConfiguration(from: source)
        #expect(manager.hasConfiguration)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: manager.directory.appendingPathComponent("proton.conf").path)[.posixPermissions]
        #expect((permissions as? Int) == 0o600)
    }

    @Test func binaryLookupFindsPlantedExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(WireProxyManager.locateBinary(in: [directory]) == nil)
        let planted = directory.appendingPathComponent("wireproxy")
        try Data([0x7f, 0x45, 0x4c, 0x46]).write(to: planted)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: planted.path)
        #expect(WireProxyManager.locateBinary(in: [planted]) == planted)
        #expect(WireProxyManager.locateBinary(in: [directory, planted]) == planted)
    }

    @Test func probeParsesDocumentedSuccessPayload() throws {
        let payload = """
            {"ip":"203.0.113.10","success":true,"country_code":"US"}
            """.data(using: .utf8)!
        #expect(try PrivateRouteProbe.parse(payload) == .init(ip: "203.0.113.10", country: "US"))
    }

    @Test func probeRejectsFailedOrIncompletePayloads() {
        for payload in [
            #"{"ip":"203.0.113.10","success":false,"country_code":"US"}"#,
            #"{"ip":"","success":true,"country_code":"US"}"#,
            #"{"success":true,"country_code":"US"}"#,
            #"{"ip":"203.0.113.10","success":true}"#,
            "not json",
        ] {
            #expect(throws: PrivateRouteError.self) {
                try PrivateRouteProbe.parse(payload.data(using: .utf8)!)
            }
        }
    }

    @Test func probeAgainstDeadPortFailsInsteadOfConnecting() async {
        await #expect(throws: PrivateRouteError.self) {
            try await PrivateRouteProbe.verifyUS(port: 9)
        }
    }

    @Test @MainActor func startWithoutConfigurationFailsClosed() async {
        let manager = isolatedManager()
        await manager.start()
        guard case .failed = manager.state else {
            Issue.record("expected .failed without an imported configuration")
            return
        }
    }

    @Test @MainActor func verifiedUSProbeReportsConnected() async throws {
        let manager = isolatedManager()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".conf")
        try syntheticProtonConfig().write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }
        try manager.importConfiguration(from: source)
        manager.processLauncher = {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sleep")
            task.arguments = ["30"]
            try task.run()
            return task
        }
        manager.routeVerifier = { _ in .init(ip: "203.0.113.10", country: "US") }
        await manager.start()
        guard case .connected(let ip, let country) = manager.state else {
            Issue.record("expected .connected, got \(manager.state)")
            return
        }
        #expect(ip == "203.0.113.10")
        #expect(country == "US")
        manager.stop()
        #expect(manager.state == .disconnected)
    }

    @Test @MainActor func nonUSProbeNeverReportsConnected() async throws {
        let manager = isolatedManager()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".conf")
        try syntheticProtonConfig().write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }
        try manager.importConfiguration(from: source)
        manager.processLauncher = {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sleep")
            task.arguments = ["30"]
            try task.run()
            return task
        }
        manager.routeVerifier = { _ in .init(ip: "115.97.198.4", country: "IN") }
        await manager.start()
        guard case .failed(let reason) = manager.state else {
            Issue.record("expected .failed for a non-US exit, got \(manager.state)")
            return
        }
        #expect(reason.contains("IN"))
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["AETHER_LIVE"] == "1"))
struct PrivateRouteLiveTests {
    @Test @MainActor func realBinaryAcceptsWellFormedConfiguration() throws {
        guard WireProxyManager.locateBinary(in: WireProxyManager.defaultBinaryCandidates()) != nil
        else {
            Issue.record("wireproxy binary not installed; cannot run live configtest")
            return
        }
        let manager = WireProxyManager(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true))
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let proton = """
            [Interface]
            PrivateKey = \(key)
            Address = 10.2.0.2/32

            [Peer]
            PublicKey = \(key)
            Endpoint = 127.0.0.1:51820
            AllowedIPs = 0.0.0.0/0
            """
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".conf")
        try proton.write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }
        try manager.importConfiguration(from: source)
        try FileManager.default.createDirectory(
            at: manager.directory, withIntermediateDirectories: true)
        try manager.wireProxyConfigurationContent().write(
            to: manager.directory.appendingPathComponent("wireproxy.conf"),
            atomically: true, encoding: .utf8)
        let binary = WireProxyManager.locateBinary(
            in: WireProxyManager.defaultBinaryCandidates())!
        let task = Process()
        task.executableURL = binary
        task.arguments = [
            "-c", manager.directory.appendingPathComponent("wireproxy.conf").path, "-n",
        ]
        task.currentDirectoryURL = manager.directory
        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errOutput = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(task.terminationStatus == 0, "configtest failed: \(output) \(errOutput)")
        #expect(output.contains("Config OK"), "unexpected configtest output: \(output)")
    }
}
