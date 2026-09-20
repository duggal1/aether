import SwiftUI

public struct BrowserWindowRoot: View {
    @BrowserState private var window: BrowserWindowModel
    public init(workspace: BrowserWorkspace) {
        _window = State(initialValue: BrowserWindowModel(workspace: workspace))
    }
    public var body: some View {
        AetherThemeScope {
            BrowserWindowView(window: window)
                .aetherTypography()
                .focusedSceneValue(\.aetherWindow, window)
                .task { await window.restoreProfile() }
        }
    }
}
