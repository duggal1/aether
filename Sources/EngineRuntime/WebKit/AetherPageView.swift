import AppKit
import WebKit

public enum AetherCredentialEvent {
  case focus(origin: String, username: String, rect: CGRect, passwordField: Bool, passwordCreation: Bool)
  case submitted(origin: String, username: String, password: String)
  case settled(origin: String)
}

// Search/Tab.swift PageView's responder-chain fix, adapted to Aether's WebKitPage.
@MainActor
public final class AetherPageView: WKWebView {
  private var hasBeenPresented = false
  private var handed: NSEvent?
  private var selection: String?
  private enum SwipeAxis { case horizontal, vertical }
  private var swipeAxis: SwipeAxis?
  private var swipeGatheredX: CGFloat = 0
  private var swipeGatheredY: CGFloat = 0
  private var swipeSignedX: CGFloat = 0
  private var swipePoint = NSPoint.zero
  private var swipeStartedAt = Date()
  private var swipeBack = false
  private var swipeFree: Bool?
  private var swipeEnded = false
  private var swipeConsumed = false
  private var swipeGeneration = 0
  public var searchName: (() -> String?)?
  public var onSearch: ((String) -> Void)?
  public var onUnclaimedShortcut: ((String) -> Void)?
  public var onCredentialEvent: ((AetherCredentialEvent) -> Void)?
  /// Asked to fill the page's right-click menu, before WebKit draws it.
  ///
  /// Replaces WebKit's own menu outright. That menu is Safari's, and the parts
  /// of it that look most useful here are the parts with no public hook:
  /// "Download Image" never reaches a download delegate, and "Copy Image"
  /// writes a pasteboard promise a paste does not always resolve. Rather than
  /// patch it, the same facts are read out of it (see
  /// `AetherPageContextReader`) and a menu this browser owns is built in its
  /// place. WebKit's "Inspect Element" is the exception — it is carried over,
  /// because nothing public can ask for WebKit's inspector on an element.
  public var contextMenuBuilder: ((AetherPageContext, NSMenu, WKWebView) -> Void)?

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      hasBeenPresented = true
      configuration.preferences.inactiveSchedulingPolicy = .none
    } else if hasBeenPresented {
      configuration.preferences.inactiveSchedulingPolicy = .suspend
    }
  }

  public func fillCredentials(username: String, password: String?, passwordOnly: Bool = false) {
    guard let user = Self.json(username), let pass = Self.json(password ?? "") else { return }
    let fillUsername = passwordOnly ? "false" : "true"
    let fillPassword = password == nil ? "false" : "true"
    let script = "window.__aetherCredentialForms?.fill(\(fillUsername), \(fillPassword), \(user), \(pass))"
    evaluateJavaScript(script, in: nil, in: .defaultClient) { _ in }
  }

  public func fillGeneratedPassword(_ password: String) {
    guard let value = Self.json(password) else { return }
    evaluateJavaScript("window.__aetherCredentialForms?.fillGenerated(\(value))", in: nil, in: .defaultClient) { _ in }
  }

  private static func json(_ value: String) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public override func keyDown(with event: NSEvent) {
    if let handed, Self.same(handed, event) {
      self.handed = nil
      return
    }
    handed = event
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == [.command, .shift],
       event.charactersIgnoringModifiers?.lowercased() == "v",
       inputContext != nil || event.window?.firstResponder is NSTextView {
      _ = event.window?.firstResponder?.tryToPerform(#selector(NSTextView.pasteAsPlainText(_:)), with: nil)
      return
    }
    super.keyDown(with: event)
    guard modifiers == .command,
          let key = event.charactersIgnoringModifiers?.lowercased(), key == "s" || key == "f" else { return }
    let encodedKey = Self.json(key) ?? "\"\""
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
      self?.evaluateJavaScript("window.__aetherShortcutHandled?.[\(encodedKey)] === true",
                               in: nil, in: .defaultClient) { [weak self] result in
        guard (try? result.get() as? Bool) != true else { return }
        Task { @MainActor [weak self] in self?.onUnclaimedShortcut?(key) }
      }
    }
  }

  public override func scrollWheel(with event: NSEvent) {
    super.scrollWheel(with: event)
    guard event.momentumPhase == [] else { return }
    switch event.phase {
    case .mayBegin, .began:
      resetSwipe()
      swipeStartedAt = Date()
    case .changed:
      guard !swipeConsumed else { return }
      swipePoint = event.locationInWindow
      swipeSignedX += event.scrollingDeltaX
      if swipeAxis == nil {
        swipeGatheredX += abs(event.scrollingDeltaX)
        swipeGatheredY += abs(event.scrollingDeltaY)
        guard swipeGatheredX + swipeGatheredY > 6 else { return }
        guard swipeGatheredX > swipeGatheredY * 1.3 else {
          swipeAxis = .vertical
          swipeConsumed = true
          return
        }
        swipeAxis = .horizontal
        swipeBack = event.scrollingDeltaX > 0
        guard swipeBack ? canGoBack : canGoForward else {
          swipeConsumed = true
          return
        }
        askWhetherPageCanScroll(direction: swipeBack ? 1 : -1)
      }
    case .ended:
      swipeEnded = true
      finishSwipeIfReady()
    case .cancelled:
      resetSwipe()
    default:
      break
    }
  }

  public override func swipe(with event: NSEvent) {
    if event.deltaX > 0, canGoBack { goBack(); return }
    if event.deltaX < 0, canGoForward { goForward(); return }
    super.swipe(with: event)
  }

  private func askWhetherPageCanScroll(direction: CGFloat) {
    let point = convert(swipePoint, from: nil)
    let x = point.x
    let y = isFlipped ? point.y : bounds.height - point.y
    let js = """
    ((x, y, delta) => {
      let node = document.elementFromPoint(x, y);
      while (node) {
        const style = getComputedStyle(node);
        const overflow = style.overflowX;
        const max = node === document.documentElement || node === document.body
          ? document.documentElement.scrollWidth - innerWidth : node.scrollWidth - node.clientWidth;
        const left = node === document.documentElement || node === document.body
          ? scrollX : node.scrollLeft;
        if ((overflow === 'auto' || overflow === 'scroll' || node === document.documentElement || node === document.body) && max > 1) {
          if (delta > 0 ? left < max - 1 : left > 1) return true;
        }
        node = node.parentElement;
      }
      return false;
    })(\(x), \(y), \(direction))
    """
    let generation = swipeGeneration
    evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] result in
      guard let self, self.swipeGeneration == generation, !self.swipeConsumed else { return }
      self.swipeFree = (try? result.get()) as? Bool == false
      self.finishSwipeIfReady()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) { [weak self] in
      guard let self, self.swipeGeneration == generation, self.swipeFree == nil else { return }
      self.swipeFree = true
      self.finishSwipeIfReady()
    }
  }

  private func finishSwipeIfReady() {
    guard swipeEnded, let free = swipeFree else { return }
    defer { resetSwipe() }
    guard free, swipeAxis == .horizontal else { return }
    let travel = max(0, swipeBack ? swipeSignedX : -swipeSignedX)
    let fastFlick = travel >= 30 && Date().timeIntervalSince(swipeStartedAt) <= 0.25
    guard travel >= 70 || fastFlick else { return }
    if swipeBack { goBack() } else { goForward() }
  }

  private func resetSwipe() {
    swipeGeneration &+= 1
    swipeAxis = nil
    swipeGatheredX = 0
    swipeGatheredY = 0
    swipeSignedX = 0
    swipeFree = nil
    swipeEnded = false
    swipeConsumed = false
  }

  public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
    super.willOpenMenu(menu, with: event)
    guard let contextMenuBuilder else { return }
    let context = AetherPageContextReader.read(
      menu, pageURL: url?.absoluteString, canGoBack: canGoBack, canGoForward: canGoForward)
    menu.removeAllItems()
    contextMenuBuilder(context, menu, self)
  }

  /// A "Search with …" item for the words selected where the click was.
  ///
  /// The selection is read when the item is built, not when it is used, because
  /// the click that opened the menu is what is about to clear it. The read is
  /// asynchronous and usually lands while the menu is still open; if it has not,
  /// the action finds nothing and does nothing rather than searching an empty
  /// string.
  public func makeSearchItem(title: String) -> NSMenuItem {
    selection = nil
    evaluateJavaScript(Self.selectedText, in: nil, in: .defaultClient) { [weak self] result in
      let text = (try? result.get()) as? String
      let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
      self?.selection = trimmed?.isEmpty == false ? trimmed : nil
    }
    let item = NSMenuItem(title: title, action: #selector(searchSelection(_:)), keyEquivalent: "")
    item.target = self
    return item
  }

  /// The words selected where the click was, once the read has landed.
  public var selectedWords: String? { selection }

  @objc private func searchSelection(_ item: NSMenuItem) {
    defer { selection = nil }
    guard let text = selection, !text.isEmpty else { return }
    onSearch?(text)
  }

  private static let selectedText = """
  (function read(doc) {
    var el = doc.activeElement;
    if (el && /^(IFRAME|FRAME)$/.test(el.tagName)) {
      try { return el.contentDocument ? read(el.contentDocument) : ''; } catch (_) { return ''; }
    }
    if (el && (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && el.type !== 'password'))) {
      try {
        var start = el.selectionStart, end = el.selectionEnd;
        if (typeof start === 'number' && typeof end === 'number' && end > start) return el.value.slice(start, end);
      } catch (_) {}
    }
    if (el && el.tagName === 'INPUT' && el.type === 'password') return '';
    var selected = doc.getSelection();
    return selected ? selected.toString() : '';
  })(document)
  """

  private static func same(_ one: NSEvent, _ other: NSEvent) -> Bool {
    one === other ||
      (one.timestamp == other.timestamp && one.keyCode == other.keyCode && one.type == other.type)
  }
}
