import AetherHumanUI
import AppKit
import BrowserEngine
import SwiftUI

@main @MainActor
struct AetherApp: App {
  @NSApplicationDelegateAdaptor(AetherApplicationDelegate.self) private var delegate
  private let adapter: AetherEngineAdapter
  private let verification = WebKitVerification()
  private let workspace: BrowserWorkspace

  init() {
    AetherFontRegistry.install()
    let adapter = AetherEngineAdapter()
    self.adapter = adapter
    workspace = BrowserWorkspace(engine: adapter)
    AetherApplicationDelegate.adapter = adapter
    AetherApplicationDelegate.workspace = workspace
  }

  var body: some Scene {
    WindowGroup("Aether", id: "browser") {
      BrowserWindowRoot(workspace: workspace)
        .task {
          await workspace.loadEngineLibraries()
          for profile in workspace.profiles {
            do { try await adapter.updatePrivacy(profileID: profile.id, policy: workspace.preferences.privacy) }
            catch { workspace.persistenceError = error.localizedDescription }
          }
          if CommandLine.arguments.contains("--verify-webkit") {
            await verification.run(adapter: adapter, workspace: workspace)
          }
          if let index = CommandLine.arguments.firstIndex(of: "--url"),
            CommandLine.arguments.indices.contains(index + 1),
            let window = workspace.windows.last, window.selected?.url == nil {
            window.navigateSelected(CommandLine.arguments[index + 1])
          }
        }
    }
    .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1270, height: 795)
    .commands { BrowserCommands() }
    Settings {
      AetherThemeScope { SettingsWindowView(workspace: workspace) }
    }
  }
}

@MainActor
final class AetherApplicationDelegate: NSObject, NSApplicationDelegate {
  static var adapter: AetherEngineAdapter?
  static var workspace: BrowserWorkspace?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    guard let window = Self.workspace?.windows.first else { return }
    for url in urls where ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
      _ = window.newTab(url: url.absoluteString)
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await Self.adapter?.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
