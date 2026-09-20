import SwiftUI

public enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case tabs = "Tabs"
    case profiles = "Profiles"
    case search = "Search"
    case privacy = "Privacy"
    case passwords = "Passwords & Passkeys"
    case downloads = "Downloads"
    case appearance = "Appearance"
    case shortcuts = "Shortcuts"
    case advanced = "Advanced"
    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .profiles: "person.crop.circle"
        case .search: "magnifyingglass"
        case .privacy: "hand.raised"
        case .passwords: "key.horizontal"
        case .downloads: "arrow.down.circle"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .advanced: "slider.horizontal.3"
        }
    }
}
