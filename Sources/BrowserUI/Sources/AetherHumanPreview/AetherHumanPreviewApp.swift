import AppKit
import SwiftUI
import AetherHumanUI

@main @MainActor
struct AetherHumanPreviewApp: App {
    private let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())

    var body: some Scene {
        WindowGroup("Aether", id: "browser") {
            BrowserWindowRoot(workspace: workspace)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1270, height: 795)
        .commands { BrowserCommands() }

        Settings {
            AetherThemeScope {
                SettingsWindowView(workspace: workspace)
            }
        }
    }
}
