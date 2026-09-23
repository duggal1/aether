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
    let silent = CommandLine.arguments.contains("--silent-verification")
    let profileDirectory = silent
      ? FileManager.default.temporaryDirectory
        .appendingPathComponent("aether-verification-\(ProcessInfo.processInfo.processIdentifier)/Profiles")
      : nil
    let adapter = AetherEngineAdapter(profileDirectory: profileDirectory)
    self.adapter = adapter
    workspace = BrowserWorkspace(engine: adapter, systemIntegrationsEnabled: !silent)
    AetherApplicationDelegate.adapter = adapter
    AetherApplicationDelegate.workspace = workspace
    adapter.startAutomation(workspace: workspace)
    Task { [adapter] in await adapter.engine.runtime.warmWebProcess() }
    Task { [adapter, workspace] in try? await adapter.warmDefaultProfile(workspace.defaultProfileID) }
  }

  var body: some Scene {
    WindowGroup("Aether", id: "browser") {
      BrowserWindowRoot(workspace: workspace)
        .task {
          // Navigation first: library loads and blocker compilation must never
          // sit serially ahead of the user's first paint.
          if let index = CommandLine.arguments.firstIndex(of: "--url"),
            CommandLine.arguments.indices.contains(index + 1),
            let window = workspace.windows.last, window.selected?.url == nil {
            window.navigateSelected(CommandLine.arguments[index + 1])
          }
          await workspace.loadEngineLibraries()
          await workspace.importSharedLinks()
          for profile in workspace.profiles {
            do { try await adapter.updatePrivacy(profileID: profile.id, policy: workspace.preferences.privacy) }
            catch { workspace.persistenceError = error.localizedDescription }
          }
          if CommandLine.arguments.contains("--verify-webkit") {
            await verification.run(adapter: adapter, workspace: workspace)
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
    if !CommandLine.arguments.contains("--silent-verification") {
      NSApp.activate(ignoringOtherApps: true)
    }
  }
  func applicationDidBecomeActive(_ notification: Notification) {
    if let workspace = Self.workspace {
      Task { await workspace.importSharedLinks() }
    }
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    guard let window = Self.workspace?.windows.first else { return }
    for url in urls where ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
      _ = window.newTab(url: url.absoluteString)
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      Self.workspace?.flushSession()
      await Self.adapter?.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
