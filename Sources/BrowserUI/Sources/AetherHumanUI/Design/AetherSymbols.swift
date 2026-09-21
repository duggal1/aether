import SwiftUI

public enum AetherIconStyle {
    public static let weight: Font.Weight = .medium
    public static let chromeSize: CGFloat = 16
    public static let menuSize: CGFloat = 16
    public static let canvas: CGFloat = 20
}

public enum AetherSymbol: String, CaseIterable, Sendable {
    case sidebarLeft = "sidebar.left"
    case sidebarRight = "sidebar.right"
    case sidebarRow = "rectangle.split.2x1"
    case back = "chevron.left"
    case forward = "chevron.right"
    case discloseUp = "chevron.up"
    case discloseDown = "chevron.down"
    case openInPage = "arrow.up.right"
    case arrowDownLeft = "arrow.down.left"
    case rewind = "arrow.uturn.backward"
    case reload = "arrow.clockwise"
    case add = "plus"
    case remove = "minus"
    case close = "xmark"
    case search = "magnifyingglass"
    case more = "ellipsis"
    case bookmark = "bookmark"
    case bookmarkCollection = "bookmark.circle"
    case bookmarks = "bookmark.square"
    case history = "clock"
    case recentlyClosed = "clock.arrow.circlepath"
    case globe = "globe"
    case page = "doc.text"
    case play = "play.fill"
    case music = "music.note"
    case console = "chevron.right.square"
    case download = "arrow.down.circle"
    case downloads = "arrow.down.to.line"
    case cursor = "cursorarrow"
    case cursorClick = "cursorarrow.click"
    case cursorPointer = "cursorarrow.rays"
    case cursorGrabbing = "cursorarrow.motionlines"
    case resizeHorizontal = "arrow.left.and.right"
    case resizeVertical = "arrow.up.and.down"
    case lock = "lock"
    case unlock = "lock.open"
    case warning = "exclamationmark.triangle"
    case confirm = "checkmark"
    case selected = "checkmark.circle.fill"
    case unselected = "circle"
    case pin = "pin"
    case unpin = "pin.slash"
    case folder = "folder"
    case settings = "gearshape"
    case profiles = "person.crop.circle"
    case addProfile = "person.crop.circle.badge.plus"
    case reader = "text.alignleft"
    case inspect = "magnifyingglass.circle"
    case automation = "wand.and.stars"
    case privacy = "hand.raised"
    case passwords = "key.horizontal"
    case appearance = "paintbrush"
    case shortcuts = "keyboard"
    case advanced = "slider.horizontal.3"
    case tabLayout = "square.on.square"
    case tiles = "square.grid.2x2"
    case addTile = "plus.square.dashed"
    case external = "arrow.up.forward.square"
    case mic = "mic"
    case send = "arrow.up"
    case chat = "bubble.left.fill"

    public var label: String {
        switch self {
        case .sidebarLeft, .sidebarRow: "Sidebar"
        case .sidebarRight: "Right sidebar"
        case .back: "Back"
        case .forward: "Forward"
        case .discloseUp: "Show"
        case .discloseDown: "More"
        case .openInPage, .arrowDownLeft: "Open"
        case .rewind: "Reopen"
        case .reload: "Reload"
        case .add: "Add"
        case .remove: "Remove"
        case .close: "Close"
        case .search: "Search"
        case .more: "More actions"
        case .bookmark: "Bookmark"
        case .bookmarkCollection: "Bookmark this page"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .recentlyClosed: "Recently closed"
        case .globe: "Website"
        case .page: "Page"
        case .play: "Play"
        case .music: "Audio"
        case .console: "Console"
        case .download: "Download"
        case .downloads: "Downloads"
        case .cursor, .cursorClick, .cursorPointer, .cursorGrabbing: "Pointer"
        case .resizeHorizontal, .resizeVertical: "Resize"
        case .lock: "Secure connection"
        case .unlock: "Not secure"
        case .warning: "Warning"
        case .confirm: "Done"
        case .selected: "Selected"
        case .unselected: "Not selected"
        case .pin: "Pinned"
        case .unpin: "Unpinned"
        case .folder: "Reveal in Finder"
        case .settings: "Settings"
        case .profiles: "Profile"
        case .addProfile: "New profile"
        case .reader: "Reader"
        case .inspect: "Inspect"
        case .automation: "Automation"
        case .privacy: "Privacy"
        case .passwords: "Passwords & Passkeys"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .tabLayout: "Tab layout"
        case .tiles: "Shortcuts"
        case .addTile: "Add shortcut"
        case .external: "Open externally"
        case .mic: "Voice"
        case .send: "Send"
        case .chat: "Chat"
        }
    }

}

public struct AetherSymbolView: View {
    public let symbol: AetherSymbol
    public var tint: Color?
    public var size: CGFloat

    public init(_ symbol: AetherSymbol, tint: Color? = nil, size: CGFloat = AetherIconStyle.chromeSize) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol.rawValue)
            .font(AetherType.symbol(size, weight: AetherIconStyle.weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint ?? Color.primary)
        .frame(width: AetherIconStyle.canvas, height: AetherIconStyle.canvas, alignment: .center)
        .accessibilityHidden(true)
    }
}
