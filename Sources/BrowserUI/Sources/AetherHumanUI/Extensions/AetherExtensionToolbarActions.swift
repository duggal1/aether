import AppKit
import SwiftUI

@MainActor
struct AetherExtensionToolbarActions: View {
    @Environment(\.aetherTheme) private var theme
    @ObservedObject private var extensions: AetherExtensions
    let window: BrowserWindowModel

    init(window: BrowserWindowModel) {
        self.window = window
        _extensions = ObservedObject(wrappedValue: .shared)
    }

    private var enabled: [AetherInstalledExtension] {
        extensions.installed.filter(\.enabled)
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(enabled) { item in
                Button {
                    extensions.press(item.id, profileID: window.activeProfileID)
                } label: {
                    Group {
                        if let icon = extensions.actionIcon(item.id, profileID: window.activeProfileID) {
                            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(theme.muted)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .aetherPointingCursor()
                .focusEffectDisabled()
                .help(item.name)
                .accessibilityLabel(item.name)
                .overlay {
                    AetherExtensionActionAnchor(extensions: extensions, windowID: window.id,
                                                extensionID: item.id)
                        .allowsHitTesting(false)
                }
            }
        }
        .fixedSize()
    }
}

@MainActor
private struct AetherExtensionActionAnchor: NSViewRepresentable {
    let extensions: AetherExtensions
    let windowID: UUID
    let extensionID: String

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        extensions.rememberActionAnchor(view, windowID: windowID, extensionID: extensionID)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        extensions.rememberActionAnchor(view, windowID: windowID, extensionID: extensionID)
    }
}

private final class AnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
