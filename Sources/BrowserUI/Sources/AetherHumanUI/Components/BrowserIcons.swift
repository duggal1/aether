import SwiftUI

public enum BrowserIcon: String, CaseIterable, Identifiable, Sendable {
    case sidebar
    case sidebarRight
    case arrowLeft
    case arrowRight
    case arrowUp
    case arrowDown
    case arrowUpRight
    case arrowDownLeft
    case rewind
    case refresh
    case plus
    case minus
    case close
    case search
    case moreHorizontal
    case bookmark
    case doubleBookmark
    case history
    case globe
    case web
    case play
    case music
    case terminalArrowRight
    case terminalArrowLeft
    case download
    case downloads
    case downloadFolder
    case inspect
    case cookie
    case lockPrivacy
    case cursor
    case cursorClick
    case cursorPointer
    case cursorGrabbing
    case resizeHorizontal
    case resizeVertical
    case lock
    case warning
    case checkmark
    case pin
    case folder
    case gear
    case reader
    case mic
    case send
    case chat
    case incognito

    public var id: Self { self }

    public var symbol: AetherSymbol {
        switch self {
        case .sidebar: .sidebarLeft
        case .arrowLeft: .back
        case .sidebarRight: .sidebarRight
        case .arrowRight: .forward
        case .arrowUp: .discloseUp
        case .arrowDown: .discloseDown
        case .arrowUpRight: .openInPage
        case .arrowDownLeft: .arrowDownLeft
        case .rewind, .terminalArrowLeft: .rewind
        case .refresh: .reload
        case .plus: .add
        case .minus: .remove
        case .close: .close
        case .search: .search
        case .moreHorizontal: .more
        case .bookmark: .bookmark
        case .doubleBookmark: .bookmarks
        case .history: .history
        case .globe: .globe
        case .web: .page
        case .play: .play
        case .music: .music
        case .terminalArrowRight: .console
        case .download: .download
        case .downloads: .downloads
        case .downloadFolder: .downloads
        case .inspect: .inspect
        case .cookie: .privacy
        case .lockPrivacy: .lock
        case .cursor: .cursor
        case .cursorClick: .cursorClick
        case .cursorPointer: .cursorPointer
        case .cursorGrabbing: .cursorGrabbing
        case .resizeHorizontal: .resizeHorizontal
        case .resizeVertical: .resizeVertical
        case .lock: .lock
        case .warning: .warning
        case .checkmark: .confirm
        case .pin: .pin
        case .folder: .folder
        case .gear: .settings
        case .reader: .reader
        case .mic: .mic
        case .send: .send
        case .chat: .chat
        case .incognito: .lock
        }
    }

    public var label: String {
        switch self {
        case .cookie: "Cookies"
        default: symbol.label
        }
    }

    public var custom: AetherCustomIcon? {
        switch self {
        case .bookmark: .bookmark
        case .doubleBookmark: .bookmarkSelected
        case .history: .history
        case .gear: .gear
        case .download: .download
        case .downloadFolder: .downloadFolder
        case .reader: .reader
        case .inspect: .inspect
        case .lock: .lock
        case .lockPrivacy: .lockPrivacy
        case .cookie: .cookie
        case .incognito: .incognito
        default: nil
        }
    }
}

public struct BrowserIconView: View {
    @Environment(\.aetherIconSize) private var size
    public let icon: BrowserIcon
    public var tint: Color? = nil

    public init(icon: BrowserIcon, tint: Color? = nil) {
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        if let custom = icon.custom {
            AetherCustomIconView(custom, tint: tint, size: size)
        } else {
            Image(systemName: icon == .doubleBookmark ? "bookmark.fill" : icon.symbol.rawValue)
                .font(AetherType.symbol(size, weight: AetherIconStyle.weight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: AetherIconStyle.canvas,
                       height: AetherIconStyle.canvas,
                       alignment: .center)
                .accessibilityHidden(true)
        }
    }
}

public extension View {
    func iconSize(_ points: CGFloat) -> some View {
        environment(\.aetherIconSize, points)
    }
}

private struct AetherIconSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = AetherIconStyle.chromeSize
}

extension EnvironmentValues {
    public var aetherIconSize: CGFloat {
        get { self[AetherIconSizeKey.self] }
        set { self[AetherIconSizeKey.self] = newValue }
    }
}
