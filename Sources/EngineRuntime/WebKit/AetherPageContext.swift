import AppKit
import WebKit

/// What a right-click landed on, and the one WebKit item worth keeping.
///
/// Read from the menu WebKit has already built for this click, rather than from
/// a JavaScript round trip. `willOpenMenu` is synchronous and runs *before* the
/// menu is drawn, so anything read here can still shape what the person sees;
/// an `evaluateJavaScript` probe resolves a runloop turn later, after the menu
/// has already been placed on screen. That timing is the whole reason the menu
/// could only ever be WebKit's own Safari menu with one item renamed.
///
/// WebKit publishes the address of the thing under the pointer in each item's
/// `representedObject`, and each item's `identifier` says what kind of thing it
/// was. Those two together are the complete context, with no page cooperation
/// and no script a site can shadow.
public struct AetherPageContext {
  public enum Target: String, Sendable {
    /// Empty page area, or text — the click was not on something actionable.
    case page
    case link
    /// A link whose content is an image: both actions are worth offering.
    case imageLink
    case image
    case media
    /// A text field, textarea or contenteditable the caret was placed in.
    case editable
  }

  public var target: Target = .page
  /// The `href` under the pointer, when there was one.
  public var linkURL: String?
  /// The `src` under the pointer, when it was an image.
  public var imageURL: String?
  /// The poster or source of a video/audio element, when there was one.
  public var mediaURL: String?
  /// Whether anything was selected. The text itself is not read here — see
  /// `AetherPageView.makeSearchItem`, which resolves it when the item is used.
  public var hasSelection: Bool = false
  public var canGoBack: Bool = false
  public var canGoForward: Bool = false
  /// The page's own address, so a menu can copy it without asking the window.
  public var pageURL: String?
  /// WebKit's own "Inspect Element", carried over untouched.
  ///
  /// There is no public API to put WebKit's inspector on a particular element,
  /// so this item is preserved rather than reimplemented: dropping it would
  /// remove the only inspection the browser has.
  public var inspectItem: NSMenuItem?

  /// Items neither WebKit's own nor ours: an extension's `chrome.contextMenus`
  /// entries, which WebKit added to this same menu a moment ago. Rebuilt menus
  /// have to put them back, or every extension's context menu silently stops
  /// existing the day this browser takes its menu over.
  public var extensionItems: [NSMenuItem] = []

  public init() {}
}

/// Reads an `NSMenu`, so nothing else in the tree has to know WebKit's
/// identifier strings.
public enum AetherPageContextReader {
  // Spelled out rather than referenced as constants: the symbols are only
  // declared from macOS 13.3, and a string is what WebKit actually puts in the
  // identifier either way.
  private static let openLink = "WKMenuItemIdentifierOpenLink"
  private static let openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
  private static let copyLink = "WKMenuItemIdentifierCopyLink"
  private static let openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
  private static let copyImage = "WKMenuItemIdentifierCopyImage"
  private static let downloadImage = "WKMenuItemIdentifierDownloadImage"
  private static let openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
  private static let copyMediaLink = "WKMenuItemIdentifierCopyMediaLink"
  private static let searchWeb = "WKMenuItemIdentifierSearchWeb"
  private static let lookUp = "WKMenuItemIdentifierLookUp"
  private static let paste = "WKMenuItemIdentifierPaste"
  private static let inspectElement = "WKMenuItemIdentifierInspectElement"
  private static let goBack = "WKMenuItemIdentifierGoBack"
  private static let goForward = "WKMenuItemIdentifierGoForward"

  public static func read(_ menu: NSMenu, pageURL: String?, canGoBack: Bool, canGoForward: Bool)
    -> AetherPageContext
  {
    var context = AetherPageContext()
    context.pageURL = pageURL
    context.canGoBack = canGoBack
    context.canGoForward = canGoForward

    for item in menu.items {
      guard let identifier = item.identifier?.rawValue else { continue }
      switch identifier {
      case openLink, copyLink:
        context.linkURL = context.linkURL ?? address(of: item)
      case openLinkInNewWindow:
        context.linkURL = context.linkURL ?? address(of: item)
      case openImageInNewWindow, copyImage, downloadImage:
        context.imageURL = context.imageURL ?? address(of: item)
      case openMediaInNewWindow, copyMediaLink:
        context.mediaURL = context.mediaURL ?? address(of: item)
      case searchWeb, lookUp:
        // Both appear only when there is a selection to act on.
        context.hasSelection = true
      case paste:
        // WebKit offers Paste for a field the caret is in, and never otherwise.
        context.target = .editable
      case inspectElement:
        context.inspectItem = item
      case goBack:
        context.canGoBack = true
      case goForward:
        context.canGoForward = true
      default:
        // Anything without WebKit's own identifier prefix was put here by
        // something else — in practice an extension — and is theirs to keep.
        if !identifier.hasPrefix("WKMenuItemIdentifier") {
          context.extensionItems.append(item)
        }
      }
    }
    // An item with no identifier at all cannot be attributed, so it is kept
    // rather than dropped: losing an extension's menu entry is silent, and
    // carrying over a stray separator is not.
    for item in menu.items where item.identifier == nil && !item.isSeparatorItem {
      context.extensionItems.append(item)
    }

    if context.imageURL != nil {
      context.target = context.linkURL != nil ? .imageLink : .image
    } else if context.linkURL != nil {
      context.target = .link
    } else if context.mediaURL != nil {
      context.target = .media
    }
    // `.editable` set above stands only when nothing actionable was under the
    // pointer: right-clicking a link inside a rich text editor should still
    // offer the link, not the pasteboard.
    return context
  }

  /// WebKit hands over a `URL`, an `NSURL` or occasionally a `String`, depending
  /// on the item and the macOS version, so all three are accepted rather than
  /// assuming one and losing the address on the others.
  private static func address(of item: NSMenuItem) -> String? {
    let value: Any? = item.representedObject ?? item.toolTip
    if let url = value as? URL { return url.absoluteString }
    if let url = value as? NSURL, let value = url as URL? { return value.absoluteString }
    if let text = value as? String, !text.isEmpty { return text }
    return nil
  }
}
