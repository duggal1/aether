import AppKit
import BrowserEvents
import EngineCore
import Foundation
import JevSearch
import WebKit

struct WebPageState: Sendable, Equatable {
  let sequence: UInt64
  let documentGeneration: UInt32
  let url: URL?
  let title: String
  let viewport: Size
  let history: [URL]
  let historyIndex: Int
  let loading: Bool
  let loaded: Bool
  let contentReady: Bool
  let painted: Bool
  let progress: Double
  let statusCode: Int
  let error: String?
  let semanticMutationRevision: UInt64
}

enum WebKitNavigationErrorClass {
  case benign
  case genuine

  // WebKit reports policy-driven interruptions under two different domains
  // depending on the framework version. Both mean "this navigation did not
  // proceed", never "the site is broken".
  static let webKitDomains: Set<String> = ["WebKitErrorDomain", "WKErrorDomain"]
  static let frameLoadInterrupted = 102
  static let pluginWillHandleLoad = 204

  static func classify(_ error: Error) -> WebKitNavigationErrorClass {
    if isCancellation(error) { return .benign }
    if isFrameLoadInterrupted(error) { return .benign }
    if isPluginHandledLoad(error) { return .benign }
    return .genuine
  }

  static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
  }

  // Redirects, superseded requests and policy changes surface as WebKit's
  // "Frame load interrupted". This is not a failure to render a website.
  static func isFrameLoadInterrupted(_ error: Error) -> Bool {
    let nsError = error as NSError
    return webKitDomains.contains(nsError.domain) && nsError.code == frameLoadInterrupted
  }

  static func isPluginHandledLoad(_ error: Error) -> Bool {
    let nsError = error as NSError
    return webKitDomains.contains(nsError.domain) && nsError.code == pluginWillHandleLoad
  }

  static func describe(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet: return "The Internet connection appears to be offline."
      case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
        return "The server could not be found."
      case NSURLErrorCannotConnectToHost: return "The server refused the connection."
      case NSURLErrorNetworkConnectionLost: return "The connection to the server was lost."
      case NSURLErrorTimedOut: return "The server took too long to respond."
      case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid:
        return "A secure connection to the server could not be established."
      default: break
      }
    }
    if nsError.domain == "WebKitErrorDomain" {
      switch nsError.code {
      case 101: return "The address cannot be displayed."
      case 103: return "The page could not be reached."
      default: break
      }
    }
    return error.localizedDescription
  }
}

private struct NavigationWaiter {
  let id: UUID
  let scope: UInt64
  let commitOnly: Bool
  let continuation: CheckedContinuation<Void, Error>
}

private final class WebKitPublicationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var pending = false
  private var settleRequested = false

  func begin(settleInterruptedNavigation: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    settleRequested = settleRequested || settleInterruptedNavigation
    guard !pending else { return false }
    pending = true
    return true
  }

  func finish() -> Bool {
    lock.lock()
    let shouldSettle = settleRequested
    pending = false
    settleRequested = false
    lock.unlock()
    return shouldSettle
  }
}

enum WebKitNavigationProbe {
  static var enabled: Bool {
    ProcessInfo.processInfo.environment["AETHER_WEBKIT_DIAG"] != nil
  }

  static func log(_ message: @autoclosure () -> String) {
    guard enabled else { return }
    let line = String(format: "[webkit-nav] epoch=%.0f %@\n", Date().timeIntervalSince1970 * 1000, message())
    FileHandle.standardError.write(Data(line.utf8))
  }
}

@MainActor
final class WebKitContext {
  let store: WKWebsiteDataStore
  let extensionController: WKWebExtensionController?
  let isEphemeral: Bool
  var rules: WKContentRuleList?

  init(identifier: UUID) {
    store = WebKitStoreCache.shared.store(for: identifier)
    extensionController = AetherWebExtensionRegistry.shared.controller(profileID: identifier, store: store)
    isEphemeral = false
  }

  init(ephemeralStore: WKWebsiteDataStore) {
    store = ephemeralStore
    extensionController = nil
    isEphemeral = true
  }

  static func ephemeral() -> WebKitContext {
    WebKitContext(ephemeralStore: WKWebsiteDataStore.nonPersistent())
  }
}

@MainActor
final class WebKitPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  let view: WKWebView
  /// Reports a `window.open` child view so the runtime can adopt it as a page.
  let popupOpened: @Sendable (WebKitPage) -> Void

  /// Re-points runtime state delivery at this page's final id. A popup is constructed
  /// before the runtime can mint a `PageID` for it, so its sink is bound twice.
  func rebind(changed newChanged: @escaping @Sendable (WebPageState) -> Void) {
    changed = newChanged
  }

  /// Current URL, safe to read from the runtime actor.
  var currentURL: String? { view.url?.absoluteString }
  let context: WebKitContext
  var generation: UInt32 = 1
  /// The snapshot generation the isolated-world DOM extractor is currently installed for.
  /// When it matches `generation`, `domScript` sends only the tiny activation script
  /// instead of re-transmitting the extractor on every operation (directive §10.3.3).
  var domInstalledGeneration: UInt32?
  var loaded = false
  var contentReady = false
  var paintReported = false
  var fcpObserved = false
  var paintGen: UInt64 = 0
  var lastError: String?
  var statusCode = 0
  private var sequence: UInt64 = 0
  private var currentScope: UInt64 = 0
  private var committedScope: UInt64?
  private var interruptedScope: UInt64?
  private var current: WKNavigation?
  private var retired: [WKNavigation] = []
  private var halted = true
  nonisolated private let publicationGate = WebKitPublicationGate()
  private var deferredFeaturesInstalledForGeneration: UInt64?
  private var lastPublished: WebPageState?
  private var observations: [NSKeyValueObservation] = []
  private var waiters: [ObjectIdentifier: NavigationWaiter] = [:]
  private var deadlines: [ObjectIdentifier: Task<Void, Never>] = [:]
  private var scopeStartedAt: [UInt64: Date] = [:]
  private var cachedHistory: [URL] = []
  private var cachedHistoryIndex: Int = -1
  private var historyDirty = true
  private var lastProgressPublishedAt: Date = .distantPast
  private var lastPublishedProgress: Double = 0
  private(set) var committedAt: Date?
  private var submittedCredentialOrigin: String?
  private let fileUploadRequested: @Sendable (SemanticUploadContext) -> Void
  private let emitEvent: @Sendable (BrowserEventKind) -> Void
  private var semanticMutationRevision: UInt64 = 0

  static let paintHandlerName = "aetherPaint"
  static let credentialHandlerName = "aetherCredentials"
  static let semanticMutationHandlerName = "aetherSemanticMutation"
  static let fileUploadHandlerName = "aetherFileUpload"
  static let consoleHandlerName = "aetherConsole"
  static let focusHandlerName = "aetherFocus"
  static let networkHandlerName = "aetherNetwork"

  /// Reports the document as visible/focused regardless of whether the web view is in an
  /// on-screen window. Defines the properties rather than patching them so page code that
  /// feature-detects them behaves the same as in a foreground tab.
  static let visibilityJS = """
    (() => {
      const doc = Document.prototype, win = Window.prototype;
      Object.defineProperty(doc, 'visibilityState', { configurable: true, get: () => 'visible' });
      Object.defineProperty(doc, 'hidden', { configurable: true, get: () => false });
      Object.defineProperty(doc, 'webkitHidden', { configurable: true, get: () => false });
      Object.defineProperty(doc, 'webkitVisibilityState', { configurable: true, get: () => 'visible' });
      Object.defineProperty(doc, 'hasFocus', { configurable: true, value: () => true });
      Object.defineProperty(win, 'documentHidden', { configurable: true, get: () => false });
      Object.defineProperty(win, 'documentVisibilityState', { configurable: true, get: () => 'visible' });
    })();
    """

  static func makeConfiguration(context: WebKitContext) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = context.store
    configuration.webExtensionController = context.extensionController
    // Every page view shares one identity, so no site — Google first among
    // them — can serve a page built for a browser it doesn't recognise. See
    // WebKitUserAgent for why WebKit's own default isn't enough.
    configuration.applicationNameForUserAgent = WebKitUserAgent.safariToken
    configuration.preferences.inactiveSchedulingPolicy = .none
    configuration.preferences.tabFocusesLinks = true
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    configuration.preferences.isElementFullscreenEnabled = true
    configuration.allowsAirPlayForMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = .audio
    // WebKit's "developer extras": Inspect Element in a page's right-click
    // menu. `isInspectable` alone only lets Safari's Develop menu reach the
    // page; without this the menu never carries an inspect item and the only
    // inspection the browser has silently disappears. The name is outside the
    // public framework, so it is asked for first and a WebKit without it is
    // left alone rather than fallen over.
    enableDeveloperExtras(configuration.preferences)
    WebKitAppearance.install(in: configuration)
    if let rules = context.rules { configuration.userContentController.add(rules) }
    return configuration
  }

  /// WebKit's "developer extras": Inspect Element in a page's right-click
  /// menu, and the Web Inspector a View menu opens. `isInspectable` alone
  /// only lets Safari's Develop menu reach the page. The name is outside the
  /// public framework, so it is asked for first.
  static func enableDeveloperExtras(_ preferences: WKPreferences, on: Bool = true) {
    let set = NSSelectorFromString("_setDeveloperExtrasEnabled:")
    guard preferences.responds(to: set) else { return }
    typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, on)
  }

  static let semanticObserverJS = """
  (() => {
    if (window.__aetherSemanticObserver) return;
    const install = () => {
      if (!document.documentElement || window.__aetherSemanticObserver) return;
      let timer = 0;
      let lastMutationAt = 0;
      let revision = 0;
      const reportWhenQuiet = () => {
        const remaining = 650 - (Date.now() - lastMutationAt);
        if (remaining > 0) {
          timer = setTimeout(reportWhenQuiet, remaining);
          return;
        }
        timer = 0;
        try { window.webkit.messageHandlers.aetherSemanticMutation.postMessage({ revision }); } catch (_) {}
      };
      const observer = new MutationObserver(() => {
        revision += 1;
        lastMutationAt = Date.now();
        if (!timer) timer = setTimeout(reportWhenQuiet, 650);
      });
      observer.observe(document.documentElement, {
        childList: true, subtree: true, characterData: true,
        attributes: true, attributeFilter: ['role', 'aria-modal', 'aria-hidden']
      });
      window.__aetherSemanticObserver = observer;
    };
    if (document.documentElement) install();
    else document.addEventListener('DOMContentLoaded', install, { once: true });
  })();
  """

  static let deferredPageFeaturesJS = shortcutObserverJS + "\n" + credentialObserverJS
    + "\n" + fileUploadObserverJS + "\n" + dirtyFormObserverJS
  static let fileUploadObserverJS = """
  (() => {
    if (window.__aetherFileUploadObserver) return;
    const clip = value => String(value || '').replace(/\\s+/g, ' ').trim().slice(0, 240);
    const textFor = element => {
      const root = element || document.querySelector('main') || document.body;
      if (!root) return '';
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      const parts = [];
      let node;
      let count = 0;
      while ((node = walker.nextNode()) && count < 80) {
        count += 1;
        if (node.parentElement?.closest('input,textarea,select,[contenteditable=true]')) continue;
        parts.push(node.textContent || '');
      }
      return clip(parts.join(' '));
    };
    const labelFor = input => {
      const label = input.labels && input.labels[0];
      const parent = input.closest('label');
      const nearby = input.closest('fieldset, form, [role=group], section, div');
      return clip(input.getAttribute('aria-label') || label?.innerText || parent?.innerText ||
        nearby?.innerText || input.name || input.id);
    };
    document.addEventListener('click', event => {
      if (!event.isTrusted) return;
      const target = event.target;
      if (!(target instanceof Element)) return;
      const action = target.closest('button,[role=button],label');
      const actionLabel = clip(action?.getAttribute('aria-label') || action?.textContent || '');
      const uploadAction = /\\b(upload|attach|browse|choose file|select file|add (a )?(file|document))\\b/i.test(actionLabel);
      const scope = action?.closest('form,[role=group],section') || action?.parentElement;
      const label = target.closest('label[for]');
      const associated = label ? document.getElementById(label.htmlFor) : null;
      let input = target.matches('input[type=file]') ? target :
        target.closest('input[type=file]') ||
        (associated instanceof HTMLInputElement && associated.type === 'file' ? associated : null);
      if (!uploadAction && !(input instanceof HTMLInputElement)) return;
      if (input instanceof HTMLInputElement && input.disabled) return;
      if (uploadAction && !input) {
        input = scope?.querySelector('input[type=file]:not(:disabled)') || null;
        if (!input) {
          const candidates = document.querySelectorAll('input[type=file]:not(:disabled)');
          if (candidates.length === 1) input = candidates[0];
        }
      }
      if (!uploadAction && !(input instanceof HTMLInputElement)) return;
      const container = input?.closest('fieldset, form, [role=group], section, div') || scope;
      const text = textFor(container);
      try {
        window.webkit.messageHandlers.aetherFileUpload.postMessage({
          label: actionLabel || (input instanceof HTMLInputElement ? labelFor(input) : ''),
          acceptedTypes: input instanceof HTMLInputElement ? clip(input.accept) : '',
          surroundingText: text
        });
      } catch (_) {}
    }, true);
    window.__aetherFileUploadObserver = true;
  })();
  """
  static let dirtyFormObserverJS = """
  (() => {
    if (window.__aetherDirtyFormObserver) return;
    const original = new WeakMap();
    const dirty = new Set();
    const controls = 'input:not([type=button]):not([type=submit]):not([type=reset]),textarea,select,[contenteditable=true]';
    const valueOf = element => {
      if (element.isContentEditable) return element.innerHTML;
      if (element instanceof HTMLInputElement && ['checkbox', 'radio'].includes(element.type)) {
        return `${element.checked}:${element.value}`;
      }
      return element.value;
    };
    const remember = element => {
      if (!(element instanceof Element) || !element.matches(controls) || original.has(element)) return;
      original.set(element, valueOf(element));
    };
    const update = event => {
      const element = event.target;
      if (!event.isTrusted || !(element instanceof Element) || !element.matches(controls)) return;
      remember(element);
      if (original.get(element) === valueOf(element)) dirty.delete(element);
      else dirty.add(element);
    };
    window.__aetherHasDirtyForm = () => {
      for (const element of dirty) {
        if (!element.isConnected || original.get(element) === valueOf(element)) dirty.delete(element);
      }
      return dirty.size > 0;
    };
    document.addEventListener('focusin', event => {
      if (event.isTrusted) remember(event.target);
    }, true);
    document.addEventListener('beforeinput', event => {
      if (event.isTrusted) remember(event.target);
    }, true);
    document.addEventListener('pointerdown', event => {
      if (event.isTrusted) remember(event.target);
    }, true);
    document.addEventListener('input', update, true);
    document.addEventListener('change', update, true);
    document.addEventListener('reset', event => {
      if (!event.isTrusted || !(event.target instanceof HTMLFormElement)) return;
      setTimeout(() => {
        for (const element of event.target.querySelectorAll(controls)) {
          original.set(element, valueOf(element));
          dirty.delete(element);
        }
      }, 0);
    }, true);
    window.__aetherDirtyFormObserver = true;
  })();
  """
  static let credentialObserverJS = """
  (() => {
    if (window.__aetherCredentialForms) return;
    const visible = element => {
      if (!element || !element.isConnected || element.disabled || element.type === 'hidden') return false;
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };
    const passwordFields = (scope = document) =>
      Array.from(scope.querySelectorAll('input[type="password"]')).filter(visible);
    const likelyUsername = element => {
      const autocomplete = (element.autocomplete || '').toLowerCase();
      const name = `${element.name || ''} ${element.id || ''} ${element.getAttribute('aria-label') || ''}`.toLowerCase();
      return autocomplete === 'username' || /user|email|login|account/.test(name);
    };
    const usernameFor = password => {
      const scope = password ? (password.form || password.closest('form') || document) : document;
      const ranked = Array.from(scope.querySelectorAll('input:not([type="password"])'))
        .filter(element => visible(element) && ['text', 'email', 'tel'].includes((element.type || 'text').toLowerCase()));
      return ranked.find(likelyUsername) || ranked[0] || null;
    };
    const rectFor = element => {
      const rect = element.getBoundingClientRect();
      return { x: rect.x, y: rect.y, w: rect.width, h: rect.height };
    };
    const send = value => {
      try { window.webkit.messageHandlers.aetherCredentials.postMessage(value); } catch (_) {}
    };
    // Framework-bound inputs (Polymer, lit, React) only observe a value once a real
    // `input` event fires. A non-composed `Event` never escapes a shadow root, so the
    // page keeps treating the field as empty and any re-render wipes what we wrote.
    const setValue = (element, value) => {
      if (!element) return;
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
      if (setter && setter.set) setter.set.call(element, value); else element.value = value;
      const fire = type => {
        if (type === 'input' && typeof InputEvent === 'function') {
          element.dispatchEvent(new InputEvent('input', {bubbles: true, composed: true,
            data: value, inputType: 'insertText'}));
        } else {
          element.dispatchEvent(new Event(type, {bubbles: true, composed: true}));
        }
      };
      fire('input');
      fire('change');
    };
    let submitted = false;
    let settleTimer = 0;
    let submittedScope = document;
    let settleAttempts = 0;
    const api = {
      hasPassword: () => passwordFields().length > 0,
      target: () => {
        const password = passwordFields()[0] || null;
        const element = usernameFor(password) || password;
        if (!element) return null;
        const previousX = scrollX, previousY = scrollY;
        element.scrollIntoView({block: 'center', inline: 'center'});
        const rect = element.getBoundingClientRect();
        const x = Math.max(0, Math.min(innerWidth - 1, rect.left + rect.width / 2));
        const y = Math.max(0, Math.min(innerHeight - 1, rect.top + rect.height / 2));
        return JSON.stringify({x, y, viewportWidth: innerWidth, viewportHeight: innerHeight,
          luminance: 1, interactive: true, didScroll: previousX !== scrollX || previousY !== scrollY});
      },
      fill: (fillUser, fillPassword, username, password) => {
        const fields = passwordFields();
        const target = fields[0] || null;
        const user = usernameFor(target);
        if (fillUser) setValue(user, username);
        // Signup and change-password forms pair the entry with a confirm/repeat field
        // (`PasswdAgain`, `confirmPassword`, …). Filling only the first leaves the form
        // unsubmittable, so every visible password field receives the secret.
        if (fillPassword) fields.forEach(element => setValue(element, password));
        if (target && fillPassword) target.focus();
      },
      fillGenerated: password => {
        const fields = passwordFields();
        if (!fields.length) return;
        fields.forEach(element => setValue(element, password));
        fields[0].focus();
      }
    };
    window.__aetherCredentialForms = api;
    const emitFocus = element => {
      if (!(element instanceof HTMLInputElement) || !visible(element)) return;
      const password = element.type === 'password';
      const scope = element.form || document;
      if (!password && (!likelyUsername(element) || !scope.querySelector('input[type="password"]'))) return;
      const fields = passwordFields(scope);
      if (!password && !fields.length) return;
      const user = password ? usernameFor(element) : element;
      const rect = rectFor(element);
      send({ kind: 'focus', origin: location.origin, username: user ? user.value : '',
        rect, passwordField: password,
        passwordCreation: password && (element.autocomplete === 'new-password' || fields.length > 1) });
    };
    const submit = form => {
      const scope = form || document;
      const passwords = Array.from(scope.querySelectorAll('input[type="password"]')).filter(visible);
      const password = passwords.find(element => element.value) || null;
      if (!password) return;
      const username = usernameFor(password);
      submitted = true;
      send({ kind: 'submitted', origin: location.origin,
        username: username ? username.value.trim() : '', password: password.value });
      submittedScope = scope;
      settleAttempts = 0;
      clearTimeout(settleTimer);
      const settle = () => {
        if (!submitted) return;
        if (!passwordFields(submittedScope).length) {
          submitted = false;
          send({ kind: 'settled', origin: location.origin });
          return;
        }
        if (settleAttempts++ < 7) settleTimer = setTimeout(settle, 1600);
        else submitted = false;
      };
      settleTimer = setTimeout(settle, 1600);
    };
    document.addEventListener('focusin', event => emitFocus(event.target), true);
    document.addEventListener('submit', event => submit(event.target), true);
    document.addEventListener('click', event => {
      const target = event.target;
      if (!target || !target.closest) return;
      const button = target.closest('button, input[type="submit"], [role="button"]');
      if (button) setTimeout(() => submit(button.form || button.closest('form')), 0);
    }, true);
  })();
  """
  static let paintObserverJS =
    "(function(){try{var done=false;function report(){if(done)return;done=true;var gen=0;try{gen=window.__aetherPaintGen||0;}catch(_){}try{window.webkit.messageHandlers.aetherPaint.postMessage({gen:gen});}catch(_){}}var po=new PerformanceObserver(function(list){var entries=list.getEntries();for(var i=0;i<entries.length;i++){if(entries[i].name==='first-contentful-paint'){report();po.disconnect();break;}}});po.observe({type:'paint',buffered:true});}catch(_){}})();"
  static let shortcutObserverJS = """
  (() => {
    window.__aetherShortcutHandled = { s: false, f: false };
    document.addEventListener('keydown', event => {
      if (!event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
      const key = event.key.toLowerCase();
      if (key !== 's' && key !== 'f') return;
      window.__aetherShortcutHandled[key] = false;
      setTimeout(() => { window.__aetherShortcutHandled[key] = event.defaultPrevented; }, 0);
    }, false);
  })();
  """

  static let consoleEventBridgeJS = """
  (() => {
    if (window.__aetherConsoleBridge) return;
    window.__aetherConsoleBridge = true;
    const lines = [];
    window.__aetherConsoleLines = lines;
    const clip = value => String(value == null ? String(value) : value).slice(0, 4000);
    const format = args => args.map(value => {
      try {
        if (typeof value === 'string') return value;
        if (value instanceof Error) return value.stack || value.message || String(value);
        return JSON.stringify(value);
      } catch (_) { return String(value); }
    }).join(' ');
    const post = (level, text) => {
      try { window.webkit.messageHandlers.aetherConsole.postMessage({ level: level, text: clip(text) }); } catch (_) {}
    };
    const levels = ['log', 'info', 'warn', 'error', 'debug'];
    for (const level of levels) {
      const original = console[level] ? console[level].bind(console) : null;
      console[level] = (...args) => {
        const text = format(args);
        lines.push(text);
        if (lines.length > 500) lines.splice(0, lines.length - 500);
        post(level, text);
        if (original) original(...args);
      };
    }
    window.addEventListener('error', event => post('error',
      (event.message || 'Error') + (event.filename ? ' @ ' + event.filename + ':' + (event.lineno || 0) : '')));
    window.addEventListener('unhandledrejection', event => post('error',
      'Unhandled rejection: ' + ((event.reason && event.reason.message) ? event.reason.message : String(event.reason))));
  })();
  """
  static let focusEventBridgeJS = """
  (() => {
    if (window.__aetherFocusBridge) return;
    window.__aetherFocusBridge = true;
    const describe = element => {
      if (!element || element === document || element === window) return '';
      const tag = (element.tagName || '').toLowerCase();
      const label = element.getAttribute('aria-label') || element.getAttribute('name') || element.id || '';
      return label ? tag + '#' + label : tag;
    };
    const post = (target, focused) => {
      if (!target) return;
      try { window.webkit.messageHandlers.aetherFocus.postMessage({ target: String(target).slice(0, 240), focused: focused }); } catch (_) {}
    };
    document.addEventListener('focusin', event => post(describe(event.target), true), true);
    document.addEventListener('focusout', event => post(describe(event.target), false), true);
  })();
  """

  /// Layer 1 network observation (directive §7.2). Installed at document start in the page
  /// world, before page script can run, and wraps `fetch` and `XMLHttpRequest` without
  /// changing their contract. Requests, responses, status, timing, sizes, and a bounded
  /// redacted body snippet for JSON/form bodies are reported; everything is capped per
  /// document so a hostile page cannot flood the control plane.
  static let networkObserverJS = """
  (() => {
    if (window.__aetherNetworkBridge) return;
    window.__aetherNetworkBridge = true;
    const limit = 2000;
    let count = 0;
    const numberOrZero = value => {
      const n = parseInt(value || '0', 10);
      return isFinite(n) && n > 0 ? n : 0;
    };
    const post = payload => {
      if (count >= limit) { return; }
      count += 1;
      try { window.webkit.messageHandlers.aetherNetwork.postMessage(payload); } catch (_) {}
      if (count >= limit) {
        try { window.webkit.messageHandlers.aetherNetwork.postMessage({phase:'truncated', limit}); } catch (_) {}
      }
    };
    const snippet = (body, contentType) => {
      if (typeof body !== 'string') { return null; }
      const type = String(contentType || '').toLowerCase();
      if (!(type.indexOf('json') >= 0 || type.indexOf('form-urlencoded') >= 0)) { return null; }
      let text = body.slice(0, 256);
      text = text.replace(/("(?:password|passwd|pwd|token|access_token|refresh_token|id_token|secret|client_secret|api_key|apikey|authorization)"\\s*:\\s*")[^"]*(")/gi, '$1[redacted]$2');
      text = text.replace(/((?:password|passwd|pwd|token|access_token|refresh_token|id_token|secret|client_secret|api_key|apikey)=)[^&]*/gi, '$1[redacted]');
      return text;
    };
    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function(input, init) {
        const started = Date.now();
        const method = ((init && init.method) || (input && input.method) || 'GET');
        const url = typeof input === 'string' ? input : ((input && input.url) || '');
        const headers = (init && init.headers) || {};
        const contentType = headers['Content-Type'] || headers['content-type'] || '';
        post({phase:'request', url, method: String(method).toUpperCase(), bodyBytes: (init && typeof init.body === 'string') ? init.body.length : 0, bodySnippet: snippet(init && init.body, contentType)});
        return originalFetch.apply(this, arguments).then(response => {
          post({phase:'response', url, method: String(method).toUpperCase(), status: response.status, durationMs: Date.now() - started, responseBytes: numberOrZero(response.headers && response.headers.get('content-length'))});
          return response;
        }, error => {
          post({phase:'response', url, method: String(method).toUpperCase(), status: 0, durationMs: Date.now() - started, responseBytes: 0});
          throw error;
        });
      };
    }
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__aetherNetwork = {method: String(method).toUpperCase(), url: String(url), started: 0};
      return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
      const meta = this.__aetherNetwork || {method:'GET', url:'', started: 0};
      meta.started = Date.now();
      post({phase:'request', url: meta.url, method: meta.method, bodyBytes: (typeof body === 'string') ? body.length : 0, bodySnippet: null});
      this.addEventListener('loadend', () => {
        let bytes = 0;
        try {
          if (typeof this.responseText === 'string') { bytes = this.responseText.length; }
          else if (this.response) { bytes = String(this.response).length; }
        } catch (_) {}
        post({phase:'response', url: meta.url, method: meta.method, status: this.status || 0, durationMs: Date.now() - (meta.started || Date.now()), responseBytes: bytes});
      }, {once: true});
      return originalSend.apply(this, arguments);
    };
  })();
  """

  func consoleLines() async -> [String] {
    guard
      let text = try? await script(
        "JSON.stringify(window.__aetherConsoleLines || [])", isolated: false),
      let data = text.data(using: .utf8)
    else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  func userContentController(_ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage)
  {
    guard message.frameInfo.isMainFrame else { return }
    // The Chrome Web Store page's "Add to Aether" was pressed: what gets
    // installed is read from the tab's own address, never from the page.
    if message.name == AetherStoreRelay.name {
      if let body = message.body as? [String: Any], body["add"] != nil,
        let url = view.url?.absoluteString
      {
        NotificationCenter.default.post(
          name: .aetherStoreInstall, object: nil, userInfo: ["url": url])
      }
      return
    }
    if message.name == Self.credentialHandlerName {
      receiveCredentialMessage(message)
      return
    }
    if message.name == Self.semanticMutationHandlerName {
      semanticMutationRevision &+= 1
      emitEvent(.documentMutated(revision: semanticMutationRevision))
      publish()
      return
    }
    if message.name == Self.consoleHandlerName {
      guard let body = message.body as? [String: Any], let level = body["level"] as? String,
        let text = body["text"] as? String else { return }
      emitEvent(.consoleMessage(level: level, text: text))
      return
    }
    if message.name == Self.focusHandlerName {
      guard let body = message.body as? [String: Any], let target = body["target"] as? String else {
        return
      }
      emitEvent(.focusChanged(target: target, focused: body["focused"] as? Bool ?? false))
      return
    }
    if message.name == Self.networkHandlerName {
      receiveNetworkMessage(message)
      return
    }
    if message.name == Self.fileUploadHandlerName {
      receiveFileUploadMessage(message)
      return
    }
    guard message.name == Self.paintHandlerName else { return }
    var gen: UInt64 = 0
    if let dict = message.body as? [String: Any] {
      if let g = dict["gen"] as? UInt64 { gen = g }
      else if let g = dict["gen"] as? Int, g >= 0 { gen = UInt64(g) }
      else if let g = dict["gen"] as? Double, g >= 0 { gen = UInt64(g) }
    }
    let currentGen = gen == paintGen
    // A document can paint before didCommit stamps its generation (fast
    // first paint). The observer is one-shot per document and begin()
    // bumps paintGen, so a gen-0 report while a navigation is in flight
    // can only come from the current document — never a stale one.
    let preCommitGen = gen == 0 && current != nil
    guard currentGen || preCommitGen else {
      probe("paint stale gen=\(gen) paintGen=\(paintGen) scope=\(currentScope)")
      return
    }
    guard !paintReported else { return }
    paintReported = true
    fcpObserved = true
    installDeferredPageFeatures()
    probe("paint observed gen=\(gen) \(elapsed(currentScope))")
    publish()
  }

  /// Turns a layer 1 network message into a typed event (directive §7.2.3). The URL and body
  /// are redacted here, at the producer, so a secret never enters the event pipeline.
  private func receiveNetworkMessage(_ message: WKScriptMessage) {
    guard let body = message.body as? [String: Any], let phase = body["phase"] as? String else {
      return
    }
    func integer(_ key: String) -> Int {
      (body[key] as? NSNumber)?.intValue ?? 0
    }
    switch phase {
    case "request":
      guard let rawURL = body["url"] as? String, let method = body["method"] as? String else {
        return
      }
      let snippet = (body["bodySnippet"] as? String).map(BrowserNetworkRedaction.redactBody)
      emitEvent(.networkRequest(
        url: BrowserNetworkRedaction.redact(url: rawURL), method: method,
        bodyBytes: integer("bodyBytes"), bodySnippet: snippet))
    case "response":
      guard let rawURL = body["url"] as? String, let method = body["method"] as? String else {
        return
      }
      emitEvent(.networkResponse(
        url: BrowserNetworkRedaction.redact(url: rawURL), method: method,
        statusCode: integer("status"), durationMs: integer("durationMs"),
        responseBytes: integer("responseBytes")))
    case "truncated":
      emitEvent(.networkObservationTruncated(limit: integer("limit")))
    default:
      return
    }
  }

  private func receiveFileUploadMessage(_ message: WKScriptMessage) {
    guard let body = message.body as? [String: Any],
      let url = view.url, let host = url.host?.lowercased(),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
    fileUploadRequested(SemanticUploadContext(
      host: String(host.prefix(160)), title: String((view.title ?? "").prefix(180)),
      label: String((body["label"] as? String ?? "").prefix(240)),
      acceptedTypes: String((body["acceptedTypes"] as? String ?? "").prefix(240)),
      surroundingText: String((body["surroundingText"] as? String ?? "").prefix(400))))
  }

  private func receiveCredentialMessage(_ message: WKScriptMessage) {
    guard let body = message.body as? [String: Any],
          let kind = body["kind"] as? String,
          let origin = body["origin"] as? String,
          let current = view.url,
          Self.origin(current) == origin,
          let pageView = view as? AetherPageView else { return }
    switch kind {
    case "focus":
      guard let rect = body["rect"] as? [String: NSNumber],
            let x = rect["x"], let y = rect["y"],
            let width = rect["w"], let height = rect["h"] else { return }
      pageView.onCredentialEvent?(.focus(origin: origin,
        username: body["username"] as? String ?? "",
        rect: CGRect(x: x.doubleValue, y: y.doubleValue, width: width.doubleValue, height: height.doubleValue),
        passwordField: body["passwordField"] as? Bool ?? false,
        passwordCreation: body["passwordCreation"] as? Bool ?? false))
    case "submitted":
      guard let password = body["password"] as? String, !password.isEmpty else { return }
      submittedCredentialOrigin = origin
      pageView.onCredentialEvent?(.submitted(origin: origin,
        username: body["username"] as? String ?? "", password: password))
    case "settled":
      guard submittedCredentialOrigin == origin else { return }
      submittedCredentialOrigin = nil
      pageView.onCredentialEvent?(.settled(origin: origin))
    default:
      break
    }
  }

  private static func origin(_ url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
          let host = url.host?.lowercased() else { return nil }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    if let port = url.port, !(scheme == "https" && port == 443), !(scheme == "http" && port == 80) {
      components.port = port
    }
    return components.string
  }

  private func elapsed(_ scope: UInt64) -> String {
    guard let start = scopeStartedAt[scope] else { return "t=?" }
    return String(format: "t=%.3fs", Date().timeIntervalSince(start))
  }

  private func probe(_ message: @autoclosure () -> String) {
    WebKitNavigationProbe.log("[scope=\(currentScope) \(message())]")
  }
  // `var` so a popup can be re-pointed at its final runtime page id after adoption.
  var changed: @Sendable (WebPageState) -> Void
  var dialogs: WebKitDialogs?

  /// Installs every Aether user script and message handler onto a configuration.
  ///
  /// Shared by the primary initializer and the popup initializer. A popup is built from the
  /// `WKWebViewConfiguration` WebKit hands to `createWebViewWith` — that object is what carries
  /// the `window.opener` relationship Google's GSI `id_token` handshake depends on — so it
  /// cannot go through `makeConfiguration`, and re-registering a handler name on a shared
  /// controller raises `NSInvalidArgumentException`.
  private static func installAetherScripts(
    on configuration: WKWebViewConfiguration, handler: WKScriptMessageHandler
  ) {
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitDOMScript.source(generation: 1), injectionTime: .atDocumentStart,
  forMainFrameOnly: true, in: .defaultClient))
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitPage.paintObserverJS, injectionTime: .atDocumentStart,
  forMainFrameOnly: true, in: .defaultClient))
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitPage.consoleEventBridgeJS, injectionTime: .atDocumentStart,
  forMainFrameOnly: true, in: .page))
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitPage.focusEventBridgeJS, injectionTime: .atDocumentStart,
  forMainFrameOnly: true, in: .page))
// Layer 1 network observation is installed before page script, so a page cannot dodge
// it (directive §7.2.1). The bridge is bounded and redacted at the producer.
// `forMainFrameOnly: false` — Google's GSI account chooser runs in a frame, so
// main-frame-only observation is exactly what would miss it.
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitPage.networkObserverJS, injectionTime: .atDocumentStart,
  forMainFrameOnly: false, in: .page))
// A `WKWebView` with no on-screen window reports `document.visibilityState ===
// "hidden"`. Content-visibility-gated UIs (YouTube's feed paints on visibility and
// IntersectionObserver) then never render: the DOM is present but permanently empty.
// The offscreen window host is not sufficient by itself — a process without an
// activation policy cannot make a window "visible" to macOS — so the visibility
// primitives a page gates on are corrected here, at document start, ahead of any page
// script. Same class of shim headless browser stacks apply.
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitPage.visibilityJS, injectionTime: .atDocumentStart,
  forMainFrameOnly: false, in: .page))
// The semantic-mutation observer is a first-class event producer
// (`document.mutated`), so it is installed for every page rather than only
// when the optional semantic-signal service is configured. The handler
// `aetherSemanticMutation` is registered in `.defaultClient`, matching this
// script's content world, and the observer itself is debounced to one report
// per quiet period, so the cost is bounded.
configuration.userContentController.addUserScript(WKUserScript(
  source: WebKitPage.semanticObserverJS, injectionTime: .atDocumentStart,
  forMainFrameOnly: true, in: .defaultClient))
// The Chrome Web Store's "Add to Aether" button (see AetherStoreRelay).
configuration.userContentController.addUserScript(WKUserScript(
  source: AetherStoreRelay.script, injectionTime: .atDocumentEnd,
  forMainFrameOnly: true, in: .defaultClient))
configuration.userContentController.add(handler, contentWorld: .defaultClient,
  name: WebKitPage.paintHandlerName)
configuration.userContentController.add(handler, contentWorld: .defaultClient,
  name: WebKitPage.credentialHandlerName)
configuration.userContentController.add(handler, contentWorld: .defaultClient,
  name: WebKitPage.semanticMutationHandlerName)
configuration.userContentController.add(handler, contentWorld: .defaultClient,
  name: WebKitPage.fileUploadHandlerName)
configuration.userContentController.add(handler, contentWorld: .page,
  name: WebKitPage.consoleHandlerName)
configuration.userContentController.add(handler, contentWorld: .page,
  name: WebKitPage.focusHandlerName)
configuration.userContentController.add(handler, contentWorld: .page,
  name: WebKitPage.networkHandlerName)
configuration.userContentController.add(handler, contentWorld: .defaultClient,
  name: AetherStoreRelay.name)
  }

  /// Adopts a view WebKit created for `window.open` as a driveable Aether page.
  ///
  /// The view must be adopted as-is: it carries the `window.opener` relationship that
  /// Google's GSI flow needs to complete its `id_token` `postMessage` back to the origin.
  /// Rebuilding an equivalent view silently breaks the handshake, which is why this takes a
  /// `WKWebView` rather than a `WKWebViewConfiguration`.
  init(
    adopting child: WKWebView, context: WebKitContext, viewport: Size,
    emitEvent: @escaping @Sendable (BrowserEventKind) -> Void = { _ in },
    changed: @escaping @Sendable (WebPageState) -> Void
  ) {
    self.context = context
    self.changed = changed
    self.fileUploadRequested = { _ in }
    self.emitEvent = emitEvent
    self.popupOpened = { _ in }
    view = child
    super.init()
    child.navigationDelegate = self
    // A private script controller: the popup's configuration may share the opener's, and
    // re-registering an existing handler name raises NSInvalidArgumentException.
    let scripts = WKUserContentController()
    Self.installAetherScripts(on: child.configuration, handler: self)
    child.allowsBackForwardNavigationGestures = false
    child.isInspectable = true
    dialogs = WebKitDialogs()
    dialogs?.emit = emitEvent
    child.uiDelegate = dialogs
    _ = scripts
  }

  init(
    context: WebKitContext, viewport: Size,
    fileUploadRequested: @escaping @Sendable (SemanticUploadContext) -> Void = { _ in },
    emitEvent: @escaping @Sendable (BrowserEventKind) -> Void = { _ in },
    // A popup view created for `window.open`, handed to the runtime so it can be adopted as
    // a first-class page. OAuth popups (Google's GSI chooser) live in the child window, so
    // without this an agent cannot reach them at all.
    popupOpened: @escaping @Sendable (WebKitPage) -> Void = { _ in },
    changed: @escaping @Sendable (WebPageState) -> Void
  ) {
    self.context = context
    self.popupOpened = popupOpened
    self.changed = changed
    self.fileUploadRequested = fileUploadRequested
    self.emitEvent = emitEvent
    let viewStart = WebKitNavigationProbe.enabled ? Date() : nil
    let configuration = Self.makeConfiguration(context: context)
    // The Tier 1 structured-state extractor exists before page script can run, in the
    // isolated client world the page cannot see or tamper with (directive §4.1.7).
    view = AetherPageView(frame: NSRect(x: 0, y: 0, width: viewport.width, height: viewport.height),
      configuration: configuration)
    if let viewStart {
      let ms = Date().timeIntervalSince(viewStart) * 1000
      WebKitNavigationProbe.log(String(format: "view-alloc %.1fms", ms))
    }
    super.init()
    view.navigationDelegate = self
    Self.installAetherScripts(on: configuration, handler: self)
    view.allowsBackForwardNavigationGestures = false
    view.isInspectable = true
    dialogs = WebKitDialogs()
    dialogs?.emit = emitEvent
    view.uiDelegate = dialogs
    // A real child view, built from the `configuration` WebKit supplies. Adopting that
    // object rather than a fresh one is what preserves `window.opener`, which anything
    // using a `postMessage` handshake (Google's GSI chooser) needs in order to render.
    dialogs?.makePopup = { [weak self] configuration, action, features in
      guard let self else { return nil }
      let width = features.width?.doubleValue ?? Double(self.view.bounds.width)
      let height = features.height?.doubleValue ?? Double(self.view.bounds.height)
      let size = width > 0 && height > 0 ? CGSize(width: width, height: height) : self.view.bounds.size
      // A private script controller: the supplied configuration may share the parent's,
      // and re-registering a handler name raises NSInvalidArgumentException.
      configuration.userContentController = WKUserContentController()
      if let rules = self.context.rules {
        configuration.userContentController.add(rules)
      }
      let child = WKWebView(
        frame: NSRect(origin: .zero, size: size), configuration: configuration)
      child.allowsBackForwardNavigationGestures = false
      child.isInspectable = true
      // Offscreen, for the same reason the main view is: no window means
      // `visibilityState === "hidden"`, and a hidden popup paints nothing.
      OffscreenPageHost.attach(child, pageID: PageID(rawValue: 1 << 20))
      // WebKit performs the initial load itself once this returns a view, so do not
      // call `child.load` here.
      // Build the page HERE, on the main actor, while the popup has not started loading.
      // Its document-start scripts (notably the isolated-world DOM extractor) must be
      // installed before the first byte arrives; installing them after the async hop to
      // the runtime leaves the popup un-evaluable and the OAuth flow unstoppable.
      let popup = WebKitPage(
        adopting: child, context: self.context,
        viewport: Size(width: size.width, height: size.height),
        emitEvent: self.emitEvent, changed: { _ in })
      self.emitEvent(.popupOpened(url: action.request.url?.absoluteString ?? ""))
      popupOpened(popup)
      return child
    }
    dialogs?.popupClosed = { [weak self] closed in
      OffscreenPageHost.detach(closed)
      self?.emitEvent(.popupClosed(url: closed.url?.absoluteString ?? ""))
    }
    observations = [
      view.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.title, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
        self?.scheduleChange(settleInterruptedNavigation: true)
      },
      view.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.scheduleChange() }
    ]
  }

  nonisolated private func scheduleChange(settleInterruptedNavigation: Bool = false) {
    guard publicationGate.begin(settleInterruptedNavigation: settleInterruptedNavigation) else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      MainActor.assumeIsolated {
        let shouldSettle = self.publicationGate.finish()
        if shouldSettle, let scope = self.interruptedScope {
          self.settleInterruptedNavigation(scope)
        }
        self.publish()
      }
    }
  }

  private func installDeferredPageFeatures() {
    guard deferredFeaturesInstalledForGeneration != paintGen else { return }
    deferredFeaturesInstalledForGeneration = paintGen
    view.evaluateJavaScript(Self.deferredPageFeaturesJS, in: nil, in: .defaultClient) { result in
      switch result {
      case .success:
        WebKitNavigationProbe.log("post-paint features installed")
      case .failure(let error):
        WebKitNavigationProbe.log("post-paint feature install failed: \(error.localizedDescription)")
      }
    }
  }

  func startSemanticObservation() async throws {
    _ = try await script(Self.semanticObserverJS)
  }

  func state() -> WebPageState {
    sequence += 1
    if historyDirty {
      historyDirty = false
      refreshHistoryCache()
    }
    return WebPageState(sequence: sequence, documentGeneration: generation,
      url: view.url, title: view.title ?? "",
      viewport: Size(width: view.bounds.width, height: view.bounds.height),
      history: cachedHistory, historyIndex: cachedHistoryIndex,
      loading: isLoading, loaded: loaded, contentReady: contentReady,
      painted: fcpObserved,
      progress: view.estimatedProgress,
      statusCode: statusCode, error: lastError,
      semanticMutationRevision: semanticMutationRevision)
  }

  private func refreshHistoryCache() {
    let list = view.backForwardList
    cachedHistory =
      list.backList.map(\.url) + (list.currentItem.map { [$0.url] } ?? []) + list.forwardList.map(\.url)
    cachedHistoryIndex = list.currentItem == nil ? -1 : list.backList.count
  }

  private var isLoading: Bool {
    guard !halted else { return false }
    return view.isLoading || current != nil
  }

  func publish() {
    let value = state()
    if lastPublished?.url != value.url {
      emitEvent(.urlChanged(url: value.url?.absoluteString))
    }
    if (lastPublished?.title ?? "") != value.title {
      emitEvent(.titleChanged(title: value.title))
    }
    if let previous = lastPublished,
      previous.url == value.url, previous.title == value.title,
      previous.viewport == value.viewport, previous.history == value.history,
      previous.historyIndex == value.historyIndex,       previous.loading == value.loading,
      previous.loaded == value.loaded, previous.contentReady == value.contentReady,
      previous.painted == value.painted, previous.statusCode == value.statusCode,
      previous.error == value.error,
      previous.semanticMutationRevision == value.semanticMutationRevision {
      let delta = abs(value.progress - lastPublishedProgress)
      let now = Date()
      if value.progress < 1.0, delta < 0.02, now.timeIntervalSince(lastProgressPublishedAt) < 0.1 { return }
      if value.progress == previous.progress { return }
      lastPublishedProgress = value.progress
      lastProgressPublishedAt = now
      lastPublished = value
      changed(value)
      return
    }
    lastPublishedProgress = value.progress
    lastProgressPublishedAt = Date()
    lastPublished = value
    changed(value)
  }

  // A fresh navigation identity never means "cancel the caller". Our own
  // navigate/back/forward/reload already cancel through begin() -> stop(), and
  // WebKit hands us a new identity for server redirects and for navigations it
  // starts itself. Pending waiters are therefore transferred, not cancelled, so
  // one waiter follows one logical navigation and a redirect resolves normally
  // instead of throwing a bogus CancellationError (which surfaced as a false
  // error over an already rendered page).
  @discardableResult
  private func track(_ navigation: WKNavigation) -> UInt64 {
    if let current, current === navigation { return currentScope }
    let nextScope = currentScope &+ 1
    let key = ObjectIdentifier(navigation)
    let pending = waiters.filter { $0.value.scope == currentScope }
    probe("track new-identity transferred=\(pending.count) url=\(view.url?.absoluteString ?? "nil") loading=\(view.isLoading)")
    for (index, entry) in pending.enumerated() {
      waiters.removeValue(forKey: entry.key)
      deadlines.removeValue(forKey: entry.key)?.cancel()
      guard index == 0 else {
        entry.value.continuation.resume(throwing: CancellationError())
        continue
      }
      waiters[key] = NavigationWaiter(
        id: entry.value.id, scope: nextScope, commitOnly: entry.value.commitOnly,
        continuation: entry.value.continuation)
      armDeadline(for: key)
    }
    current = navigation
    currentScope = nextScope
    scopeStartedAt[nextScope] = Date()
    committedScope = nil
    committedAt = nil
    interruptedScope = nil
    halted = false
    historyDirty = true
    contentReady = false
    paintReported = false
    fcpObserved = false
    statusCode = 0
    lastError = nil
    return currentScope
  }

  private func armDeadline(for key: ObjectIdentifier) {
    deadlines[key] = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(60)) } catch { return }
      self?.expire(key)
    }
  }

  private func isTracked(_ navigation: WKNavigation?) -> Bool {
    guard let navigation, let current else { return false }
    return current === navigation
  }

  private func endTracking(contentUsable: Bool) {
    current = nil
    halted = true
    contentReady = contentUsable
    interruptedScope = nil
  }

  private func begin(_ start: () -> WKNavigation?) -> WKNavigation? {
    if current != nil || !waiters.isEmpty || view.isLoading { stop() }
    guard let navigation = start() else {
      probe("begin no-navigation-object")
      publish()
      return nil
    }
    current = navigation
    currentScope &+= 1
    paintGen &+= 1
    scopeStartedAt[currentScope] = Date()
    committedScope = nil
    committedAt = nil
    interruptedScope = nil
    halted = false
    historyDirty = true
    contentReady = false
    paintReported = false
    fcpObserved = false
    statusCode = 0
    lastError = nil
    probe("begin url=\(view.url?.absoluteString ?? "nil")")
    publish()
    return navigation
  }

  func navigate(_ request: URLRequest, settle: PageReadiness = .complete) async throws {
    guard let scheme = request.url?.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) else {
      throw BrowserRuntimeError.invalidNavigation("Only HTTP and HTTPS navigation is supported")
    }
    if settle == .commit, isPlainGet(request), let url = request.url {
      guard let navigation = begin({ view.load(url) }) else { return }
      try await wait(for: navigation, settle: settle)
      return
    }
    guard let navigation = begin({ view.load(request) }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  private func isPlainGet(_ request: URLRequest) -> Bool {
    guard let url = request.url, url.host != nil else { return false }
    let method = request.httpMethod?.uppercased() ?? "GET"
    guard method == "GET" else { return false }
    guard request.httpBody == nil, request.httpBodyStream == nil else { return false }
    guard request.allHTTPHeaderFields?.isEmpty ?? true else { return false }
    return request.cachePolicy == .useProtocolCachePolicy
  }

  func loadHTML(_ html: String, url: URL) async throws {
    guard let navigation = begin({ view.loadHTMLString(html, baseURL: url) }) else { return }
    try await wait(for: navigation, settle: .complete)
  }

  func back(settle: PageReadiness = .complete) async throws {
    guard let navigation = begin({ view.goBack() }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  func forward(settle: PageReadiness = .complete) async throws {
    guard let navigation = begin({ view.goForward() }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  func reload(bypassCache: Bool, settle: PageReadiness = .complete) async throws {
    guard let navigation = begin({ bypassCache ? view.reloadFromOrigin() : view.reload() }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  private func wait(for navigation: WKNavigation?, settle: PageReadiness = .complete) async throws {
    guard let navigation else { return }
    let key = ObjectIdentifier(navigation)
    let scope = currentScope
    let waiterID = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { continuation in
        waiters[key] = NavigationWaiter(
          id: waiterID, scope: scope, commitOnly: settle == .commit, continuation: continuation)
        armDeadline(for: key)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelWaiting(waiterID) }
    }
  }

  private func expire(_ key: ObjectIdentifier) {
    guard let waiter = waiters[key] else { return }
    probe("expire waiterScope=\(waiter.scope) committed=\(committedScope.map(String.init) ?? "nil") \(elapsed(waiter.scope))")
    // Usable content is already on screen: release the caller rather than
    // inventing a timeout failure over a page the user can read.
    if committedScope != nil || committedScope == waiter.scope {
      resolve(key)
      endTracking(contentUsable: true)
      publish()
      return
    }
    view.stopLoading()
    lastError = "The page took too long to load."
    resolve(key, error: BrowserRuntimeError.timeout(lastError ?? ""))
    endTracking(contentUsable: false)
    publish()
  }

  // Cancelling a waiter must only stop the load it belongs to. Abandoning a
  // superseded navigation previously called stopLoading() on the navigation
  // that had already replaced it, which is how a healthy page load ended up
  // interrupted.
  private func cancelWaiting(_ id: UUID) {
    guard let (key, waiter) = waiters.first(where: { $0.value.id == id }) else { return }
    probe("cancelWaiting waiterScope=\(waiter.scope)")
    let isTrackedScope = waiter.scope == currentScope
    resolve(key, error: CancellationError())
    if isTrackedScope {
      view.stopLoading()
      endTracking(contentUsable: loaded)
      publish()
    }
  }

  private func settleInterruptedNavigation(_ scope: UInt64) {
    Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, self.interruptedScope == scope, self.currentScope == scope,
        !self.view.isLoading else { return }
      if let current = self.current {
        self.resolve(ObjectIdentifier(current), error: CancellationError())
      }
      self.lastError = nil
      self.endTracking(contentUsable: self.loaded)
      self.publish()
    }
  }

  private func resolve(_ key: ObjectIdentifier, error: Error? = nil) {
    deadlines.removeValue(forKey: key)?.cancel()
    guard let waiter = waiters.removeValue(forKey: key) else { return }
    if let error { waiter.continuation.resume(throwing: error) }
    else { waiter.continuation.resume() }
  }

  private func resolveCommitWaiters(_ navigation: WKNavigation) {
    let key = ObjectIdentifier(navigation)
    guard current === navigation, let waiter = waiters[key], waiter.commitOnly else { return }
    resolve(key)
  }

  func stop() {
    if current != nil || !waiters.isEmpty {
      probe("stop waiters=\(waiters.count)")
    }
    if let current {
      retired.append(current)
      if retired.count > 32 { retired.removeFirst(retired.count - 32) }
    }
    view.stopLoading()
    for key in Array(waiters.keys) { resolve(key, error: CancellationError()) }
    endTracking(contentUsable: loaded)
    publish()
  }

  func close() {
    stop()
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.paintHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.credentialHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.semanticMutationHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.fileUploadHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.consoleHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.focusHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: Self.networkHandlerName)
    view.configuration.userContentController.removeScriptMessageHandler(forName: AetherStoreRelay.name)
    view.navigationDelegate = nil
    view.uiDelegate = nil
    dialogs?.close()
    observations.removeAll()
    view.removeFromSuperview()
  }

  func prepareForPresentation() {
    view.configuration.preferences.inactiveSchedulingPolicy = .none
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    guard let navigation else {
      publish()
      return
    }
    probe("didStartProvisional tracked=\(isTracked(navigation)) retired=\(retired.contains(where: { $0 === navigation })) url=\(webView.url?.absoluteString ?? "nil")")
    guard !retired.contains(where: { $0 === navigation }) else { return }
    track(navigation)
    emitEvent(.navigationStarted(url: webView.url?.absoluteString ?? ""))
    publish()
  }

  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    probe("serverRedirect tracked=\(isTracked(navigation)) url=\(webView.url?.absoluteString ?? "nil")")
    emitEvent(.navigationRedirected(url: webView.url?.absoluteString ?? ""))
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    guard let navigation else { return }
    probe("didCommit tracked=\(isTracked(navigation)) url=\(webView.url?.absoluteString ?? "nil") \(elapsed(currentScope))")
    guard isTracked(navigation) else { return }
    generation &+= 1
    loaded = true
    contentReady = true
    committedScope = currentScope
    committedAt = Date()
    historyDirty = true
    lastError = nil
    emitEvent(.navigationCommitted(url: webView.url?.absoluteString ?? "", statusCode: statusCode))
    let gen = paintGen
    view.evaluateJavaScript("window.__aetherPaintGen=\(gen);", in: nil, in: .defaultClient) { _ in }
    publish()
    resolveCommitWaiters(navigation)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let navigation else { return }
    probe("didFinish tracked=\(isTracked(navigation)) url=\(webView.url?.absoluteString ?? "nil") \(elapsed(currentScope))")
    guard isTracked(navigation) else {
      publish()
      return
    }
    loaded = true
    lastError = nil
    if let origin = submittedCredentialOrigin, let pageView = view as? AetherPageView {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak pageView] in
        guard let self, let pageView, self.submittedCredentialOrigin == origin else { return }
        pageView.evaluateJavaScript("window.__aetherCredentialForms?.hasPassword() ?? false", in: nil, in: .defaultClient) { result in
          guard self.submittedCredentialOrigin == origin,
                (try? result.get() as? Bool) != true else { return }
          self.submittedCredentialOrigin = nil
          pageView.onCredentialEvent?(.settled(origin: origin))
        }
      }
    }
    if !paintReported {
      paintReported = true
      probe("paint fallback no-observed-fcp \(elapsed(currentScope))")
      installDeferredPageFeatures()
    }
    resolve(ObjectIdentifier(navigation))
    endTracking(contentUsable: true)
    publish()
    emitEvent(.navigationFinished(url: webView.url?.absoluteString ?? "", title: webView.title ?? ""))
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failed(navigation, error: error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failed(navigation, error: error)
  }

  private func failed(_ navigation: WKNavigation?, error: Error) {
    guard let navigation else {
      publish()
      return
    }
    let nsError = error as NSError
    probe("didFail tracked=\(isTracked(navigation)) domain=\(nsError.domain) code=\(nsError.code) class=\(WebKitNavigationErrorClass.classify(error)) committed=\(committedScope.map(String.init) ?? "nil") \(elapsed(currentScope))")
    let key = ObjectIdentifier(navigation)
    guard isTracked(navigation) else {
      // A superseded navigation must never touch the current page's state, but
      // its own waiter still has to be released so no caller hangs.
      if waiters[key] != nil {
        resolve(key, error: WebKitNavigationErrorClass.isCancellation(error)
          ? CancellationError() : error)
      }
      publish()
      return
    }
    // A navigation that already committed is on screen. Its document is the
    // user's page; a later interruption of that same navigation must never
    // replace rendered content with an error overlay.
    let documentOnScreen = committedScope == currentScope
    emitEvent(.navigationFailed(
      url: view.url?.absoluteString, error: WebKitNavigationErrorClass.describe(error),
      benign: WebKitNavigationErrorClass.classify(error) != .genuine))
    switch WebKitNavigationErrorClass.classify(error) {
    case .benign where !WebKitNavigationErrorClass.isCancellation(error):
      lastError = nil
      interruptedScope = currentScope
      settleInterruptedNavigation(currentScope)
      publish()
    case .benign:
      if documentOnScreen {
        resolve(key)
      } else {
        resolve(key, error: CancellationError())
      }
      lastError = nil
      endTracking(contentUsable: documentOnScreen || contentReady)
      publish()
    case .genuine where documentOnScreen:
      lastError = nil
      loaded = true
      resolve(key)
      endTracking(contentUsable: true)
      publish()
    case .genuine:
      lastError = WebKitNavigationErrorClass.describe(error)
      resolve(key, error: error)
      endTracking(contentUsable: false)
      publish()
    }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    probe("processTerminated url=\(webView.url?.absoluteString ?? "nil")")
    let message = "The webpage process stopped. Reload the page to continue."
    emitEvent(.navigationFailed(url: webView.url?.absoluteString, error: message, benign: false))
    lastError = message
    loaded = false
    contentReady = false
    paintReported = false
    fcpObserved = false
    committedScope = nil
    committedAt = nil
    for key in Array(waiters.keys) {
      resolve(key, error: BrowserRuntimeError.invalidState(message))
    }
    endTracking(contentUsable: false)
    publish()
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
    let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
    probe("decideAction scheme=\(scheme) mainFrame=\(mainFrame) type=\(navigationAction.navigationType.rawValue) mainNavTracked=\(mainNavTracked(navigationAction.mainFrameNavigation)) url=\(navigationAction.request.url?.absoluteString ?? "nil")")
    guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
    let authoritativeMain = isAuthoritativeMain(response: navigationResponse)
    if navigationResponse.isForMainFrame, authoritativeMain {
      statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
    }
    let policy: WKNavigationResponsePolicy
    if let response = navigationResponse.response as? HTTPURLResponse,
       (300...399).contains(response.statusCode) {
      policy = .allow
    } else if let response = navigationResponse.response as? HTTPURLResponse,
              response.value(forHTTPHeaderField: "Content-Disposition")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().hasPrefix("attachment") == true {
      policy = .download
    } else {
      policy = navigationResponse.canShowMIMEType ? .allow : .download
    }
    probe("decideResponse mainFrame=\(navigationResponse.isForMainFrame) authoritative=\(authoritativeMain) mime=\(navigationResponse.response.mimeType ?? "nil") policy=\(policy == .allow ? "allow" : "download")")
    if navigationResponse.isForMainFrame, authoritativeMain,
      let url = navigationResponse.response.url?.absoluteString {
      emitEvent(.networkNavigationResponse(
        url: url, statusCode: statusCode, mimeType: navigationResponse.response.mimeType))
    }
    decisionHandler(policy)
  }

  private func mainNavTracked(_ navigation: WKNavigation?) -> String {
    guard let navigation else { return "nil" }
    return isTracked(navigation) ? "tracked" : "stale"
  }

  private func isAuthoritativeMain(response: WKNavigationResponse) -> Bool {
    guard response.isForMainFrame else { return false }
    guard let mainNavigation = response.mainFrameNavigation else { return true }
    return isTracked(mainNavigation)
  }

  func resolveMainFrameDownload(action: WKNavigationAction) {
    guard action.targetFrame?.isMainFrame ?? false else { return }
    let documentOnScreen = committedScope == currentScope
    probe("downloadTerminal(action) committed=\(documentOnScreen) waiters=\(waiters.count)")
    for key in Array(waiters.keys) where waiters[key]?.scope == currentScope {
      if documentOnScreen { resolve(key) } else { resolve(key, error: CancellationError()) }
    }
    lastError = nil
    endTracking(contentUsable: documentOnScreen || contentReady)
    publish()
  }

  func resolveMainFrameDownload(response: WKNavigationResponse) {
    guard isAuthoritativeMain(response: response) else { return }
    let documentOnScreen = committedScope == currentScope
    probe("downloadTerminal committed=\(documentOnScreen) waiters=\(waiters.count)")
    for key in Array(waiters.keys) where waiters[key]?.scope == currentScope {
      if documentOnScreen { resolve(key) } else { resolve(key, error: CancellationError()) }
    }
    lastError = nil
    endTracking(contentUsable: documentOnScreen || contentReady)
    publish()
  }
}

extension WebKitPage {
  func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let space = challenge.protectionSpace
    emitEvent(.authenticationChallenge(host: space.host, method: space.authenticationMethod))
    completionHandler(.performDefaultHandling, nil)
  }
}
