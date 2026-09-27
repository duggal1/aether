import SwiftUI

public struct FindBarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var matches: Int?
    @BrowserState private var message: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle { surface ?? AetherSurfaceResolver.themed(dark: theme.dark) }

    public var body: some View {
        HStack(spacing: 6) {
            AetherField("Find in page", text: Binding(get: { window.findQuery }, set: { window.findQuery = $0 }),
                        icon: .search, onSubmit: { find(true) })
                .frame(width: 232)
            if let matches {
                AetherAnimatedText(text: "\(matches) matches")
                    .font(AetherType.caption(11)).foregroundStyle(skin.secondaryText)
                    .padding(.horizontal, 4)
            }
            if let message {
                Text(message).font(AetherType.caption(11)).foregroundStyle(AetherPalette.error(skin.isDark))
            }
            ChromeButton(.arrowUp, help: "Previous match", size: 28) { find(false) }
            ChromeButton(.arrowDown, help: "Next match", size: 28) { find(true) }
            ChromeButton(.close, help: "Close find", size: 28) { window.showsFind = false }
        }
        .padding(6)
        .background { AetherPopoverBackground() }
        .environment(\.aetherSurfaceStyle, skin)
        .environment(\.aetherTheme, AetherTheme(skin.isDark ? .dark : .light))
        .zIndex(1)
        .aetherGlassShadow(dark: skin.isDark)
    }

    private func find(_ forward: Bool) {
        guard let page = window.selected?.enginePageID,
              let provider = window.workspace.engine as? any BrowserFindProviding else {
            message = "Engine not connected"; return
        }
        Task {
            do { matches = try await provider.find(pageID: page, query: window.findQuery, forward: forward); message = nil }
            catch { message = error.localizedDescription }
        }
    }
}
