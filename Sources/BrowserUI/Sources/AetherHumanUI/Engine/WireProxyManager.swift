import Combine
import Foundation

enum PrivateRouteError: LocalizedError, Equatable {
    case invalidConfiguration
    case binaryMissing
    case processExited
    case verificationFailed
    case nonUSExit(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid Proton WireGuard configuration."
        case .binaryMissing:
            return "WireProxy executable not found."
        case .processExited:
            return "WireProxy exited unexpectedly."
        case .verificationFailed:
            return "Unable to verify the VPN connection."
        case .nonUSExit(let country):
            return "Exit is not US: \(country)"
        }
    }
}

@MainActor
final class WireProxyManager: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected(ip: String, country: String)
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected

    static let port: UInt16 = 25344

    var processLauncher: (() throws -> Process)?
    var routeVerifier: ((UInt16) async throws -> PrivateRouteProbe.Result)?

    private let baseDirectory: URL?
    private var process: Process?
    private var logHandle: FileHandle?

    init() {
        baseDirectory = nil
    }

    init(directory: URL) {
        baseDirectory = directory
    }

    var directory: URL {
        if let baseDirectory { return baseDirectory }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aether", isDirectory: true)
            .appendingPathComponent("PrivateRoute", isDirectory: true)
    }

    var hasConfiguration: Bool {
        FileManager.default.fileExists(atPath: protonConfig.path)
    }

    static func validateConfiguration(_ content: String) throws {
        for marker in ["[Interface]", "[Peer]", "PrivateKey", "Endpoint"] {
            guard content.contains(marker) else {
                throw PrivateRouteError.invalidConfiguration
            }
        }
    }

    func importConfiguration(from source: URL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer {
            if access { source.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: source)
        guard let content = String(data: data, encoding: .utf8) else {
            throw PrivateRouteError.invalidConfiguration
        }
        try Self.validateConfiguration(content)
        try prepareDirectory()
        try data.write(to: protonConfig, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: protonConfig.path)
    }

    func start() async {
        guard state != .connecting else { return }
        if case .connected = state, process?.isRunning == true { return }
        guard hasConfiguration else {
            state = .failed(PrivateRouteError.invalidConfiguration.localizedDescription)
            return
        }
        state = .connecting
        do {
            try prepareDirectory()
            try writeWireProxyConfiguration()
            let task = try processLauncher?() ?? launchWireProxy()
            process = task
            let verify = routeVerifier ?? PrivateRouteProbe.verifyUS
            let result = try await verify(Self.port)
            guard result.country == "US" else {
                throw PrivateRouteError.nonUSExit(result.country)
            }
            guard process?.isRunning == true else {
                throw PrivateRouteError.processExited
            }
            state = .connected(ip: result.ip, country: result.country)
        } catch {
            stopProcess()
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func stop() {
        stopProcess()
        state = .disconnected
    }

    func wireProxyConfigurationContent() -> String {
        """
        WGConfig = proton.conf

        [Socks5]
        BindAddress = 127.0.0.1:\(Self.port)
        """
    }

    static func locateBinary(in directories: [URL]) -> URL? {
        directories.first {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: $0.path),
                  (attributes[.type] as? String) == FileAttributeType.typeRegular.rawValue
            else {
                return false
            }
            return FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func defaultBinaryCandidates() -> [URL] {
        [
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("wireproxy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/wireproxy"),
            URL(fileURLWithPath: "/usr/local/bin/wireproxy"),
        ].compactMap { $0 }
    }

    private var protonConfig: URL {
        directory.appendingPathComponent("proton.conf")
    }

    private var wireProxyConfig: URL {
        directory.appendingPathComponent("wireproxy.conf")
    }

    private func stopProcess() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func writeWireProxyConfiguration() throws {
        try wireProxyConfigurationContent().write(
            to: wireProxyConfig, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: wireProxyConfig.path)
    }

    private func binaryURL() throws -> URL {
        guard let binary = Self.locateBinary(in: Self.defaultBinaryCandidates()) else {
            throw PrivateRouteError.binaryMissing
        }
        return binary
    }

    private func launchWireProxy() throws -> Process {
        let binary = try binaryURL()
        let logURL = directory.appendingPathComponent("wireproxy.log")
        FileManager.default.createFile(
            atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: logURL)
        let task = Process()
        task.executableURL = binary
        task.arguments = ["-c", wireProxyConfig.path]
        task.standardOutput = handle
        task.standardError = handle
        task.currentDirectoryURL = directory
        do {
            try task.run()
        } catch {
            try? handle.close()
            throw error
        }
        logHandle = handle
        return task
    }
}
