import AppKit
import SwiftUI

/// The fill-credentials bubble that hangs off a password field.
///
/// It is a floating surface like any other, so it takes the resolved surface
/// style instead of pinning itself dark: a saved-password bubble on a white
/// login page used to render as a black box for the same reason the cards did.
@MainActor
final class AetherCredentialPopover {
    private var popover: NSPopover?

    func show(
        in view: NSView,
        pageRect: CGRect,
        choices: [BrowserCredentialSummary],
        canGenerate: Bool,
        surface: AetherSurfaceStyle,
        choose: @escaping (BrowserCredentialSummary) -> Void,
        generate: @escaping () -> Void
    ) {
        close()
        guard !choices.isEmpty || canGenerate, view.window != nil else { return }
        let width: CGFloat = 284
        let height = CGFloat(min(choices.count, 5)) * 40 + (canGenerate ? 44 : 0) + 18
        let host = NSHostingController(rootView: AetherCredentialChoices(
            choices: choices,
            canGenerate: canGenerate,
            choose: { [weak self] item in self?.close(); choose(item) },
            generate: { [weak self] in self?.close(); generate() }
        )
        .environment(\.aetherSurfaceStyle, surface)
        .environment(\.aetherTheme, AetherTheme(surface.isDark ? .dark : .light))
        .preferredColorScheme(surface.isDark ? .dark : .light))
        host.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let popover = NSPopover()
        popover.contentViewController = host
        popover.contentSize = NSSize(width: width, height: height)
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: surface.isDark ? .darkAqua : .aqua)
        popover.show(relativeTo: pageRect, of: view, preferredEdge: .maxY)
        self.popover = popover
    }

    func close() {
        popover?.performClose(nil)
        popover = nil
    }
}

private struct AetherCredentialChoices: View {
    let choices: [BrowserCredentialSummary]
    let canGenerate: Bool
    let choose: (BrowserCredentialSummary) -> Void
    let generate: () -> Void
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(choices.prefix(5)) { choice in
                Button { choose(choice) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(skin.secondaryIcon)
                        Text(choice.username.isEmpty ? "Saved password" : choice.username)
                            .foregroundStyle(skin.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 10))
                            .foregroundStyle(skin.secondaryIcon)
                    }
                    .font(AetherType.body(12))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .background(skin.hoverFill, in: RoundedRectangle(cornerRadius: 8))
            }
            if canGenerate {
                Button(action: generate) {
                    Label("Suggest a strong password", systemImage: "key.horizontal")
                        .font(AetherType.body(12))
                        .foregroundStyle(skin.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(AetherPopoverBackground(radius: 12))
        .frame(width: 284)
    }
}
