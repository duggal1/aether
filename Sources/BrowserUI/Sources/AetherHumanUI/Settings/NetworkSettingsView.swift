import SwiftUI
import UniformTypeIdentifiers

public struct NetworkSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var status: NetworkRouteStatus = .unknown
    @BrowserState private var probing = false
    @BrowserState private var endpointHost = ""
    @BrowserState private var endpointPort = "1080"
    @BrowserState private var endpointExpectedIP = ""
    @BrowserState private var credentialUser = ""
    @BrowserState private var credentialPassword = ""
    @BrowserState private var hasStoredCredential = false
    @BrowserState private var message: String?
    @BrowserState private var importingRelayConfig = false
    @StateObject private var relay = WireProxyManager()
    @State private var relayEndpointIDBeforeRelay: String?
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var routing: (any BrowserNetworkRouting)? { workspace.engine as? any BrowserNetworkRouting }

    public var body: some View {
        AetherSection("Remote exit") {
            AetherRow("Hide my IP address", symbol: "eye.slash") {
                Toggle("Hide my IP address", isOn: Binding(
                    get: { workspace.preferences.networkRoute.enabled },
                    set: { enabled in
                        var route = workspace.preferences.networkRoute
                        route.enabled = enabled
                        if enabled, route.region == .direct { route.region = .sanFrancisco }
                        workspace.preferences.networkRoute = route
                        applyRoute()
                    }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsDivider()
            AetherRow("Exit region", symbol: "network") {
                Picker("Exit region", selection: Binding(
                    get: { workspace.preferences.networkRoute.region },
                    set: { region in
                        var route = workspace.preferences.networkRoute
                        route.region = region
                        workspace.preferences.networkRoute = route
                        loadEndpointFields()
                        applyRoute()
                    })) {
                    ForEach(AetherExitRegion.allCases) { region in
                        Text(region.rawValue).tag(region)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 170)
                .disabled(!workspace.preferences.networkRoute.enabled)
            }
            SettingsDivider()
            AetherRow("Fail closed", customIcon: .lockPrivacy) {
                Toggle("Fail closed", isOn: Binding(
                    get: { workspace.preferences.networkRoute.failClosed },
                    set: { value in
                        workspace.preferences.networkRoute.failClosed = value
                        applyRoute()
                    }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(!workspace.preferences.networkRoute.enabled)
            }
            SettingsDivider()
            AetherRow("Status", subtitle: statusDetail, customIcon: statusIcon) {
                statusBadge
            }
        }
        AetherSection("Exit server") {
            AetherRow("Host", customIcon: .server) {
                settingsField($endpointHost, placeholder: "exit.example.com", width: 200)
            }
            SettingsDivider()
            AetherRow("Port", customIcon: .server) {
                settingsField($endpointPort, placeholder: "1080", width: 72)
            }
            SettingsDivider()
            AetherRow("Expected exit IP", symbol: "checkmark.shield") {
                settingsField($endpointExpectedIP, placeholder: "203.0.113.10", width: 200)
            }
            SettingsDivider()
            AetherRow("Credentials", subtitle: hasStoredCredential ? "Stored in Keychain." : "Empty for no authentication.", symbol: "person.crop.circle") {
                HStack(spacing: 6) {
                    settingsField($credentialUser, placeholder: "Username", width: 140)
                    SecureField("Password", text: $credentialPassword)
                        .textFieldStyle(.plain)
                        .font(AetherType.body(12))
                        .foregroundStyle(theme.ink)
                        .frame(width: 140)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(theme.input, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Save Server") { saveEndpoint() }
                    .aetherProminentButton()
                    .frame(minHeight: 28)
                Button("Verify Route") { applyRoute() }
                    .aetherButton()
                    .frame(minHeight: 28)
                    .disabled(workspace.preferences.networkRoute.region == .direct)
                if workspace.preferences.routeEndpoints.contains(where: {
                    $0.region == workspace.preferences.networkRoute.region
                }) {
                    Button("Remove Server", role: .destructive) {
                        removeEndpoint()
                    }
                    .aetherButton()
                    .frame(minHeight: 28)
                }
                Spacer()
                if probing {
                    Text("Verifying…")
                        .font(AetherType.caption(12)).foregroundStyle(theme.muted)
                }
            }
            if let message {
                AetherAnimatedText(text: message)
                    .font(AetherType.caption(12))
                    .foregroundStyle(status == .connected ? theme.active : theme.error)
            }
        }
        .padding(.vertical, 4)
        AetherSection("Private Relay (Proton)",
                      footer: "Free Proton WireGuard account required: download a US configuration at account.protonvpn.com, then import it. The exit city is whichever server your configuration holds; free plans assign servers, so exact-city choice is not guaranteed. The relay carries TCP only, so WebRTC can still reveal the direct IP.") {
            AetherRow("WireProxy relay", subtitle: relaySubtitle, symbol: "network.badge.shield.half.filled") {
                HStack(spacing: 6) {
                    if relayHasConnected {
                        Button("Stop Relay") { stopRelay() }
                            .aetherButton()
                            .frame(minHeight: 28)
                    } else {
                        Button("Start Relay") { startRelay() }
                            .aetherProminentButton()
                            .frame(minHeight: 28)
                            .disabled(!relay.hasConfiguration)
                    }
                }
            }
            SettingsDivider()
            AetherRow("Proton configuration", subtitle: relay.hasConfiguration ? "Imported. The private key stays in a 0600 file, never in SQLite or logs." : "Download a US WireGuard .conf from your Proton account, then import it.", symbol: "doc.badge.gearshape") {
                Button("Import .conf") { importingRelayConfig = true }
                    .aetherButton()
                    .frame(minHeight: 28)
            }
        }
        .fileImporter(
            isPresented: $importingRelayConfig,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                do {
                    let urls = try result.get()
                    guard let url = urls.first,
                          url.pathExtension.lowercased() == "conf" else {
                        throw PrivateRouteError.invalidConfiguration
                    }
                    relay.stop()
                    try relay.importConfiguration(from: url)
                    message = "Proton configuration imported. Start the relay to verify the exit."
                } catch {
                    message = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
        .onAppear {
            loadEndpointFields()
            status = routing?.currentRouteStatus(profileID: workspace.defaultProfileID) ?? .unknown
            hasStoredCredential = storedCredentialExists()
        }
    }

    private var subtitle: String {
        workspace.preferences.networkRoute.region.subtitle
    }

    private var statusDetail: String {
        guard workspace.preferences.networkRoute.enabled else { return "Remote exit is off." }
        guard let ip = routing?.observedExitIP(profileID: workspace.defaultProfileID) else {
            return status.label + (status == .connected ? "" : ". No exit IP has been verified.")
        }
        return status.label + " · observed exit IP " + ip
    }

    private var statusIcon: AetherCustomIcon {
        switch status {
        case .connected: .server
        case .connecting: .zap
        case .blocked: .serverCrash
        case .unavailable: .serverOffline
        case .direct, .unknown: .server
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(AetherType.body(12))
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(theme.input, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel(status.label)
    }

    private var statusColor: Color {
        switch status {
        case .connected: theme.active
        case .blocked, .unavailable: theme.error
        case .connecting: AetherProgressColor.neutral.color
        case .direct, .unknown: theme.muted
        }
    }

    private func applyRoute() {
        guard let routing else {
            status = .unknown
            message = "Connect the browser engine to configure routing."
            return
        }
        let route = workspace.preferences.networkRoute
        let endpoint = workspace.preferences.endpoint(for: route.region)
        status = route.enabled && route.region != .direct ? .connecting : .direct
        probing = status == .connecting
        message = nil
        Task {
            var report: NetworkRouteStatus = .unknown
            for profile in workspace.profiles {
                do {
                    report = try await routing.applyNetworkRoute(
                        profileID: profile.id, route: route, endpoint: endpoint)
                } catch {
                    report = .unknown
                    message = error.localizedDescription
                    break
                }
            }
            status = report
            probing = false
            if report == .blocked {
                message = endpoint == nil
                    ? "No exit server saved for this region. Traffic is blocked, not leaked."
                    : "The exit server is unreachable. Traffic is blocked, not leaked."
            } else if report == .unavailable {
                message = "The exit server did not answer, or its observed IP did not match the expected IP."
            } else if report == .connected {
                message = nil
            }
        }
    }

    private func settingsField(_ text: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(AetherType.body(12))
            .foregroundStyle(theme.ink)
            .frame(width: width)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func loadEndpointFields() {        if let endpoint = workspace.preferences.endpoint(for: workspace.preferences.networkRoute.region) {
            endpointHost = endpoint.host
            endpointPort = String(endpoint.port)
            endpointExpectedIP = endpoint.expectedExitIP ?? ""
        } else {
            endpointHost = ""
            endpointPort = "1080"
            endpointExpectedIP = ""
        }
        credentialUser = ""
        credentialPassword = ""
        hasStoredCredential = storedCredentialExists()
    }

    private func saveEndpoint() {
        let region = workspace.preferences.networkRoute.region
        guard region != .direct else {
            message = "Select a remote region before saving a server."
            return
        }
        let host = endpointHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = UInt16(endpointPort.trimmingCharacters(in: .whitespaces)),
              port > 0 else {
            message = "Enter a server host and a port between 1 and 65535."
            return
        }
        let existingID = workspace.preferences.endpoint(for: region)?.id
        let expected = endpointExpectedIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = RouteEndpoint(
            id: existingID ?? UUID().uuidString, host: host, port: port, region: region,
            expectedExitIP: expected.isEmpty ? nil : expected)
        workspace.preferences.setEndpoint(endpoint)
        if let store = workspace.engine as? any BrowserProxyCredentialStoring {
            do {
                try store.saveProxyCredential(
                    endpointID: endpoint.id, username: credentialUser,
                    password: credentialPassword)
            } catch {
                message = "The credential could not be stored in the Keychain."
                return
            }
        }
        credentialPassword = ""
        hasStoredCredential = storedCredentialExists()
        message = "Server saved for \(region.rawValue)."
        applyRoute()
    }

    private func removeEndpoint() {
        let region = workspace.preferences.networkRoute.region
        if let endpoint = workspace.preferences.endpoint(for: region),
            let store = workspace.engine as? any BrowserProxyCredentialStoring
        {
            try? store.saveProxyCredential(endpointID: endpoint.id, username: "", password: "")
        }
        workspace.preferences.forgetEndpoint(region: region)
        loadEndpointFields()
        message = "Server removed for \(region.rawValue)."
        applyRoute()
    }

    private func storedCredentialExists() -> Bool {
        guard let endpoint = workspace.preferences.endpoint(for: workspace.preferences.networkRoute.region)
        else { return false }
        return (try? AetherKeychain().contains(
            account: AetherKeychain.proxyCredentialAccount(endpointID: endpoint.id))) == true
    }

    private var relayHasConnected: Bool {
        if case .connected = relay.state { return true }
        return false
    }

    private var relaySubtitle: String {
        switch relay.state {
        case .disconnected:
            return "Relay is off."
        case .connecting:
            return "Connecting to Proton…"
        case .connected(let ip, let country):
            return "Verified exit \(ip) · \(country)."
        case .failed(let reason):
            return reason
        }
    }

    private var relayEndpoint: RouteEndpoint {
        RouteEndpoint(
            id: "proton-wireproxy-relay", host: "127.0.0.1",
            port: WireProxyManager.port,
            region: workspace.preferences.networkRoute.region)
    }

    private func startRelay() {
        guard let routing else {
            message = "Connect the browser engine to configure routing."
            return
        }
        relayEndpointIDBeforeRelay = workspace.preferences.networkRoute.endpointID
        status = .connecting
        probing = true
        message = nil
        Task {
            await relay.start()
            guard relayHasConnected else {
                status = .unavailable
                probing = false
                message = relaySubtitle
                return
            }
            var report: NetworkRouteStatus = .unknown
            let route = workspace.preferences.networkRoute
            for profile in workspace.profiles {
                do {
                    report = try await routing.applyNetworkRoute(
                        profileID: profile.id, route: route, endpoint: relayEndpoint)
                } catch {
                    report = .unknown
                    message = error.localizedDescription
                    break
                }
            }
            status = report
            probing = false
            if report == .connected {
                message = "Private relay verified: \(relaySubtitle)"
            } else if report != .unknown {
                relay.stop()
                message = "Relay verified but the route did not apply. Relay stopped."
            }
        }
    }

    private func stopRelay() {
        relay.stop()
        var route = workspace.preferences.networkRoute
        route.endpointID = relayEndpointIDBeforeRelay
        workspace.preferences.networkRoute = route
        relayEndpointIDBeforeRelay = nil
        applyRoute()
    }
}
