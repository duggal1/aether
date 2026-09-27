import SwiftUI

/// One thing Jev judged about the page, in words.
struct JevSignalRow: Identifiable {
    enum Severity: Int {
        case warning = 3
        case attention = 2
        case note = 1
    }

    let id: String
    /// The system symbol for the row.
    let symbol: String
    let title: String
    let detail: String
    /// 0–1 when the model reported one.
    let confidence: Double?
    let severity: Severity
}

/// What Jev has to say about one page, ordered by what it costs to miss.
///
/// The signals themselves were already being computed, carried across the
/// engine boundary and stored on the tab — and then read by nothing. This is the
/// missing half: the same values, turned into sentences and ordered so the one
/// that matters is first.
@MainActor
struct JevPageVerdict {
    let rows: [JevSignalRow]
    /// How many tabs share this page's semantic group, when it has one.
    let groupSize: Int
    let phishingSuspected: Bool

    var isEmpty: Bool { rows.isEmpty }
    var headline: JevSignalRow? { rows.first }

    init(signals: BrowserSemanticSignals?, window: BrowserWindowModel?) {
        var collected: [JevSignalRow] = []
        var phishing = false

        if let probability = signals?.phishingIdentityMismatchProbability, probability >= 0.25 {
            phishing = true
            collected.append(JevSignalRow(
                id: "phishing", symbol: "exclamationmark.shield",
                title: "This page may not be who it says",
                detail: "The page's identity does not match its address.",
                confidence: probability, severity: .warning))
        }

        switch signals?.sessionState {
        case .sessionExpired:
            collected.append(JevSignalRow(
                id: "session-expired", symbol: "clock.badge.exclamationmark",
                title: "Signed out",
                detail: "You were signed in here and are not any more.",
                confidence: signals?.sessionConfidence, severity: .attention))
        case .loginRequired:
            collected.append(JevSignalRow(
                id: "session-required", symbol: "person.badge.key",
                title: "Sign-in needed",
                detail: "This page is asking for an account.",
                confidence: signals?.sessionConfidence, severity: .note))
        default:
            break
        }

        if let confidence = signals?.accessGateConfidence, confidence >= 0.5 {
            switch signals?.accessGateKind {
            case .authenticationWall:
                collected.append(JevSignalRow(
                    id: "gate-auth", symbol: "lock.rectangle.stack",
                    title: "Behind a sign-in wall",
                    detail: "The content is only shown to signed-in accounts.",
                    confidence: confidence, severity: .attention))
            case .subscriptionPaywall, .softPaywall:
                let soft = signals?.accessGateKind == .softPaywall
                collected.append(JevSignalRow(
                    id: "gate-paywall", symbol: "creditcard",
                    title: soft ? "Soft paywall" : "Subscription paywall",
                    detail: soft
                        ? "The page is readable but reading is being discouraged."
                        : "This page wants a subscription.",
                    confidence: confidence, severity: .note))
            case .permissionWall:
                collected.append(JevSignalRow(
                    id: "gate-permission", symbol: "hand.raised",
                    title: "Asking for permission",
                    detail: "A permission prompt stands in front of the content.",
                    confidence: confidence, severity: .note))
            case .botChallenge:
                collected.append(JevSignalRow(
                    id: "gate-bot", symbol: "shield.lefthalf.filled",
                    title: "Bot challenge",
                    detail: "This page is checking whether you are a person.",
                    confidence: confidence, severity: .note))
            case .brokenContent:
                collected.append(JevSignalRow(
                    id: "gate-broken", symbol: "exclamationmark.triangle",
                    title: "Content looks broken",
                    detail: "The page loaded but its content did not.",
                    confidence: confidence, severity: .attention))
            default:
                break
            }
        }

        if let overlay = signals?.overlayKind, let confidence = signals?.overlayConfidence,
           confidence >= 0.5 {
            let dismissable = signals?.overlaySafeToDismissProbability
            var detail = Self.overlayName(overlay)
            if let dismissable {
                detail += dismissable >= 0.7
                    ? " · safe to dismiss"
                    : dismissable <= 0.4 ? " · leaving it alone is safer" : ""
            }
            collected.append(JevSignalRow(
                id: "overlay", symbol: "rectangle.on.rectangle",
                title: "Something is covering the page",
                detail: detail, confidence: confidence, severity: .note))
        }

        if let intent = signals?.uploadIntent, let confidence = signals?.uploadConfidence,
           confidence >= 0.5 {
            collected.append(JevSignalRow(
                id: "upload", symbol: "arrow.up.doc",
                title: "This page wants a \(Self.uploadName(intent))",
                detail: "Jev expects this kind of file here.",
                confidence: confidence, severity: .note))
        }

        var groupSize = 0
        if let group = signals?.semanticGroupID, let window {
            groupSize = window.tabs.filter { $0.semanticGroupID == group }.count
            if groupSize > 1 {
                collected.append(JevSignalRow(
                    id: "group", symbol: "square.stack.3d.up",
                    title: "\(groupSize) tabs on this subject",
                    detail: "Jev grouped this with the others you have open.",
                    confidence: nil, severity: .note))
            }
        }

        if let related = signals?.relatedPageID, let window,
           let tab = window.tabs.first(where: { $0.enginePageID == related }), tab.id != window.selectedID {
            collected.append(JevSignalRow(
                id: "related", symbol: "link",
                title: "Same page is open elsewhere",
                detail: "Also open as “\(tab.title)”.",
                confidence: signals?.relatedPageConfidence, severity: .note))
        }

        if let score = signals?.tabImportanceScore, score >= 0.5 {
            collected.append(JevSignalRow(
                id: "importance", symbol: "star",
                title: "Worth keeping open",
                detail: "Jev rates this tab's importance at \(Int((min(1, max(0, score)) * 100).rounded()))%.",
                confidence: signals?.tabImportanceConfidence, severity: .note))
        }

        rows = collected.sorted { left, right in
            if left.severity.rawValue != right.severity.rawValue {
                return left.severity.rawValue > right.severity.rawValue
            }
            return (left.confidence ?? 0) > (right.confidence ?? 0)
        }
        self.groupSize = groupSize
        phishingSuspected = phishing
    }

    static func overlayName(_ kind: BrowserOverlayKind) -> String {
        switch kind {
        case .cookieConsent: return "A cookie banner"
        case .newsletterSignup: return "A newsletter prompt"
        case .ageGate: return "An age gate"
        case .paywall: return "A paywall"
        case .promotion: return "A promotion"
        case .requiredDialog: return "A dialog that has to be answered"
        case .authentication: return "A sign-in prompt"
        case .paymentConfirmation: return "A payment confirmation"
        case .destructiveConfirmation: return "A confirmation before something is deleted"
        case .other: return "An overlay"
        }
    }

    static func uploadName(_ intent: BrowserUploadIntent) -> String {
        switch intent {
        case .resume: return "resume"
        case .contract: return "contract"
        case .invoice: return "invoice"
        case .profilePhoto: return "profile photo"
        case .spreadsheet: return "spreadsheet"
        case .identityDocument: return "identity document"
        case .other: return "file"
        }
    }
}

/// The chrome chip. It is absent until Jev has judged something worth saying,
/// so the toolbar never carries a control that is permanently empty.
@MainActor
public struct AetherJevChip: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) { self.window = window }

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }

    private var verdict: JevPageVerdict {
        JevPageVerdict(signals: window.selected?.semanticSignals, window: window)
    }

    public var body: some View {
        if let headline = verdict.headline {
            Button {
                window.showsJevSignals.toggle()
                if window.showsJevSignals {
                    window.showsProfileMenu = false
                    window.showsMoreMenu = false
                    window.showsExtensionsMenu = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: verdict.phishingSuspected ? "exclamationmark.shield" : headline.symbol)
                        .font(.system(size: 11, weight: .medium))
                    Text(short(headline.title))
                        .font(AetherType.caption(10.5))
                        .lineLimit(1)
                }
                .foregroundStyle(tint(hovering || window.showsJevSignals))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background {
                    RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
                        .fill(hovering || window.showsJevSignals
                              ? appearance.hover : appearance.hairline.opacity(0.6))
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AetherPressStyle(reduced: reduced))
            .focusEffectDisabled()
            .animation(AetherMotion.hover(reduced), value: hovering)
            .onHover { hovering = $0 }
            .help("Jev: \(headline.title) — \(headline.detail)")
            .accessibilityLabel("Jev page signals: \(headline.title)")
        }
    }

    private func tint(_ active: Bool) -> Color {
        if verdict.phishingSuspected {
            return AetherPalette.error(appearance.isDark)
        }
        return active ? appearance.text : appearance.secondary
    }

    private func short(_ title: String) -> String {
        title.count <= 22 ? title : String(title.prefix(20)) + "…"
    }
}

/// Everything Jev judged about the page in front, with the values that produced
/// each row.
public struct JevSignalsPanel: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    private var verdict: JevPageVerdict {
        JevPageVerdict(signals: window.selected?.semanticSignals, window: window)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if verdict.isEmpty {
                empty
            } else {
                ForEach(verdict.rows) { row in
                    signalRow(row)
                }
                actions
            }
        }
        .padding(6)
        .frame(width: 296)
        .background { AetherPopoverBackground() }
        .environment(\.aetherChromeAppearance, skin.isDark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(skin.secondaryIcon)
            Text("What Jev sees")
                .font(AetherType.caption(10.5))
                .foregroundStyle(skin.metadataText)
            Spacer(minLength: 0)
            Text("\(verdict.rows.count)")
                .font(AetherType.caption(10.5))
                .monospacedDigit()
                .foregroundStyle(skin.metadataText)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Nothing unusual here")
                .font(AetherType.body(12))
                .foregroundStyle(skin.primaryText)
            Text("Jev has judged this page and found no sign-in wall, overlay, paywall or identity mismatch worth telling you about.")
                .font(AetherType.caption(10.5))
                .foregroundStyle(skin.metadataText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func signalRow(_ row: JevSignalRow) -> some View {
        AetherMenuRow(radius: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: row.symbol)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(row.severity == .warning
                                     ? AetherPalette.error(skin.isDark) : skin.primaryIcon)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(AetherType.body(12))
                        .foregroundStyle(row.severity == .warning
                                         ? AetherPalette.error(skin.isDark) : skin.primaryText)
                    Text(row.detail)
                        .font(AetherType.caption(10.5))
                        .foregroundStyle(skin.metadataText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let confidence = row.confidence {
                    Text("\(Int((min(1, max(0, confidence)) * 100).rounded()))%")
                        .font(AetherType.caption(10))
                        .monospacedDigit()
                        .foregroundStyle(skin.secondaryIcon)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
    }

    /// The actions the signals actually imply. Only ones that are safe to carry
    /// out are offered: an overlay is described, not clicked away, and nothing
    /// here claims Jev produced text it does not produce.
    @ViewBuilder private var actions: some View {
        let rows = verdict.rows
        if rows.contains(where: { $0.id == "session-expired" }) {
            Divider().overlay(skin.separator).padding(.vertical, 5)
            action(.refresh, "Reload and Sign In Again") {
                window.showsJevSignals = false
                window.perform(.reload)
            }
        }
        if rows.contains(where: { $0.id == "related" }), let related = relatedTab {
            Divider().overlay(skin.separator).padding(.vertical, 5)
            action(.globe, "Switch to “\(related.title)”") {
                window.showsJevSignals = false
                window.switchProfile(related.profileID)
                window.select(related.id)
            }
        }
        if verdict.groupSize > 1, let group = window.selected?.semanticGroupID {
            Divider().overlay(skin.separator).padding(.vertical, 5)
            action(.doubleBookmark, "Select All \(verdict.groupSize) Grouped Tabs") {
                window.showsJevSignals = false
                selectGroup(group)
            }
        }
    }

    private var relatedTab: BrowserTab? {
        guard let related = window.selected?.semanticSignals?.relatedPageID else { return nil }
        return window.tabs.first { $0.enginePageID == related && $0.id != window.selectedID }
    }

    private func selectGroup(_ group: String) {
        let members = window.tabs.filter { $0.semanticGroupID == group }
        guard let first = members.first else { return }
        window.switchProfile(first.profileID)
        window.select(first.id)
    }

    private func action(_ icon: BrowserIcon, _ title: String,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            AetherMenuRow(radius: 8) {
                HStack(spacing: 10) {
                    BrowserIconView(icon: icon, tint: skin.primaryIcon).iconSize(12)
                    Text(title).font(AetherType.body(12)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(skin.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherMenuPressStyle())
        .focusEffectDisabled()
    }
}
