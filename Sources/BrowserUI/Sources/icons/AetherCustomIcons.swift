import SwiftUI

public enum AetherCustomIcon: String, CaseIterable, Sendable {
    case terminalLeft
    case terminalRight
    case terminalUpLeft
    case terminalDownRight
    case terminalUpRight
    case terminalCornerUpRight
    case bookmark
    case bookmarkSelected
    case gear
    case globe
    case globeNoLogo
    case historyLeft
    case historyRight
    case download
    case file
    case image
    case panorama
    case svgFile
    case search
    case cursor
    case cursorBlocked
    case lock
    case lockPrivacy
    case cookie
    case incognito

    var space: CGFloat {
        switch self {
        case .cursor, .cursorBlocked, .lock, .lockPrivacy, .cookie, .incognito: 24
        default: 256
        }
    }

    var stroked: Bool {
        switch self {
        case .cursor, .cursorBlocked, .lock, .lockPrivacy, .cookie, .incognito: true
        default: false
        }
    }

    var strokeWidth: CGFloat { 1.5 }

    func build(_ p: inout Path) {
        switch self {
        case .terminalLeft: AetherCustomIconPaths.terminalLeft(&p)
        case .terminalRight: AetherCustomIconPaths.terminalRight(&p)
        case .terminalUpLeft: AetherCustomIconPaths.terminalUpLeft(&p)
        case .terminalDownRight: AetherCustomIconPaths.terminalDownRight(&p)
        case .terminalUpRight: AetherCustomIconPaths.terminalUpRight(&p)
        case .terminalCornerUpRight: AetherCustomIconPaths.terminalCornerUpRight(&p)
        case .bookmark: AetherCustomIconPaths.bookmark(&p)
        case .bookmarkSelected: AetherCustomIconPaths.bookmarkSelected(&p)
        case .gear: AetherCustomIconPaths.gear(&p)
        case .globe: AetherCustomIconPaths.globe(&p)
        case .globeNoLogo: AetherCustomIconPaths.globeNoLogo(&p)
        case .historyLeft: AetherCustomIconPaths.historyLeft(&p)
        case .historyRight: AetherCustomIconPaths.historyRight(&p)
        case .download: AetherCustomIconPaths.download(&p)
        case .file: AetherCustomIconPaths.file(&p)
        case .image: AetherCustomIconPaths.image(&p)
        case .panorama: AetherCustomIconPaths.panorama(&p)
        case .svgFile: AetherCustomIconPaths.svgFile(&p)
        case .search: AetherCustomIconPaths.search(&p)
        case .cursor: AetherCustomIconPaths.cursor(&p)
        case .cursorBlocked:
            AetherCustomIconPaths.cursorBlockedA(&p)
            AetherCustomIconPaths.cursorBlockedB(&p)
        case .lock:
            AetherCustomIconPaths.lockShackle(&p)
        case .lockPrivacy:
            AetherCustomIconPaths.lockPrivacyShackle(&p)
        case .cookie:
            AetherCustomIconPaths.cookieChipA(&p)
            AetherCustomIconPaths.cookieChipB(&p)
            AetherCustomIconPaths.cookieBody(&p)
            AetherCustomIconPaths.cookieDotA(&p)
            AetherCustomIconPaths.cookieDotB(&p)
        case .incognito:
            AetherCustomIconPaths.incognitoLensL(&p)
            AetherCustomIconPaths.incognitoLensR(&p)
            AetherCustomIconPaths.incognitoBrim(&p)
            AetherCustomIconPaths.incognitoBridge(&p)
            AetherCustomIconPaths.incognitoBody(&p)
        }
    }

    var extra: AnyShape? {
        switch self {
        case .lock:
            return AnyShape(LockBodyShape())
        case .lockPrivacy:
            return AnyShape(LockPrivacyBodyShape())
        default:
            return nil
        }
    }
}

struct AnyShape: Shape {
    private let build: @Sendable (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        build = { shape.path(in: $0) }
    }
    func path(in rect: CGRect) -> Path { build(rect) }
}

private struct LockBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = rect.width / 24
        let r = CGRect(x: rect.minX + 5.5 * s, y: rect.minY + 10 * s,
                       width: 13 * s, height: 11 * s)
        p.addRoundedRect(in: r, cornerSize: CGSize(width: 0.25 * s, height: 0.25 * s))
        return p
    }
}

private struct LockPrivacyBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = rect.width / 24
        let r = CGRect(x: rect.minX + 4 * s, y: rect.minY + 9 * s,
                       width: 16 * s, height: 13 * s)
        p.addRoundedRect(in: r, cornerSize: CGSize(width: 0.3 * s, height: 0.3 * s))
        for cx in [8, 12, 16] as [CGFloat] {
            p.addEllipse(in: CGRect(x: rect.minX + (cx - 0.25) * s, y: rect.minY + 15.25 * s,
                                    width: 0.5 * s, height: 0.5 * s))
        }
        return p
    }
}

public struct AetherCustomIconShape: Shape {
    let icon: AetherCustomIcon
    public init(_ icon: AetherCustomIcon) { self.icon = icon }
    public func path(in rect: CGRect) -> Path {
        var raw = Path()
        icon.build(&raw)
        if let extra = icon.extra {
            raw.addPath(extra.path(in: CGRect(x: 0, y: 0, width: icon.space, height: icon.space)))
        }
        let space = icon.space
        guard space > 0, rect.width > 0 else { return raw }
        let scale = rect.width / space
        let tx = rect.minX + (rect.width - space * scale) / 2
        let ty = rect.minY + (rect.height - space * scale) / 2
        return raw.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty))
    }
}

public struct AetherCustomIconView: View {
    public let icon: AetherCustomIcon
    public var tint: Color?
    public var size: CGFloat
    public init(_ icon: AetherCustomIcon, tint: Color? = nil, size: CGFloat = 16) {
        self.icon = icon
        self.tint = tint
        self.size = size
    }
    public var body: some View {
        Group {
            if icon.stroked {
                AetherCustomIconShape(icon)
                    .stroke(tint ?? Color.primary,
                            style: StrokeStyle(lineWidth: max(1, icon.strokeWidth / icon.space * size),
                                              lineCap: .round, lineJoin: .round))
            } else {
                AetherCustomIconShape(icon)
                    .fill(tint ?? Color.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public extension AetherCustomIcon {
    static func fileIcon(for fileName: String) -> AetherCustomIcon {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".svg") { return .svgFile }
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "ico"]
            .contains(where: lower.hasSuffix) { return .image }
        return .file
    }
}
