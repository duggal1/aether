import AppKit
import DOM
import EngineCore
import Foundation
import WebKit

extension WebKitPage {
  static func literal(_ value: String) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }

  func script(_ source: String, isolated: Bool = true) async throws -> String {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      view.evaluateJavaScript(source, in: nil, in: isolated ? .defaultClient : .page) { result in
        switch result {
        case .success(let value):
          if let text = value as? String { continuation.resume(returning: text) }
          else if value is NSNull { continuation.resume(returning: "null") }
          else if let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) {
            continuation.resume(returning: String(decoding: data, as: UTF8.self))
          } else { continuation.resume(returning: String(describing: value)) }
        case .failure(let error): continuation.resume(throwing: BrowserRuntimeError.javascript(error.localizedDescription))
        }
      }
    }
  }

  func decode<T: Decodable>(_ type: T.Type, _ source: String) async throws -> T {
    let result = try await script(source)
    return try JSONDecoder().decode(type, from: Data(result.utf8))
  }

  func evaluate(_ source: String) async throws -> JavaScriptResult {
    JavaScriptResult(value: try await script(source, isolated: false), console: [])
  }

  /// Fills the page's generic login form. Runs in the isolated client world
  /// where `__aetherCredentialForms` is installed — the generic `evaluate`
  /// path runs in the page world and cannot see it.
  func fillCredentials(username: String, password: String, fillUsername: Bool = true) async throws {
    let user = try Self.literal(username)
    let pass = try Self.literal(password)
    _ = try await script(
      "window.__aetherCredentialForms?.fill(\(fillUsername), true, \(user), \(pass))", isolated: true)
  }

  func credentialInteractionTarget() async throws -> WebKitInteractionTarget? {
    let result = try await script("window.__aetherCredentialForms?.target() ?? null", isolated: true)
    return try JSONDecoder().decode(WebKitInteractionTarget?.self, from: Data(result.utf8))
  }

  func domScript(_ source: String) -> String {
    // The extractor is installed once per document (document-start user script, with this
    // as the lazy fallback). Once installed for the current generation, only the tiny
    // activation script crosses the bridge, so a per-operation read no longer pays for a
    // 3.5 KiB source re-transmission (directive §10.3.3, §10.4.6).
    let installed = domInstalledGeneration == generation
    let prefix = installed
      ? WebKitDOMScript.activation(generation: generation)
      : WebKitDOMScript.source(generation: generation)
    domInstalledGeneration = generation
    return prefix + ";\n" + source
  }

  func query(_ selector: String) async throws -> [InspectedNode] {
    let values = try await decode([WebDOMNode].self,
      domScript("JSON.stringify(Array.from(document.querySelectorAll(\(try Self.literal(selector)))).slice(0,10000).map(n => globalThis.__aetherDOM.describe(n)))"))
    return values.map(\.inspected)
  }

  func inspectedNode(_ node: NodeID) async throws -> InspectedNode? {
    guard node.version == generation else { throw BrowserRuntimeError.nodeNotFound(node) }
    let result = try await decode(WebDOMNode?.self, domScript("""
    (() => {
      const n = globalThis.__aetherDOM.get(\(node.index));
      return JSON.stringify(n && n.isConnected ? globalThis.__aetherDOM.describe(n) : null);
    })()
    """))
    return result?.inspected
  }

  func focusedNode() async throws -> InspectedNode? {
    let result = try await decode(WebDOMNode?.self, domScript("""
    (() => {
      const node = document.activeElement;
      return JSON.stringify(node && node !== document.body && node !== document.documentElement
        ? globalThis.__aetherDOM.describe(node) : null);
    })()
    """))
    return result?.inspected
  }

  func nodeAtPoint(x: Double, y: Double) async throws -> InspectedNode? {
    let result = try await decode(WebDOMNode?.self, domScript("""
    (() => {
      const node = document.elementFromPoint(\(x), \(y));
      return JSON.stringify(node ? globalThis.__aetherDOM.describe(node) : null);
    })()
    """))
    return result?.inspected
  }

  func pressKey(_ key: String) async throws -> String {
    let escapedKey = try Self.literal(key)
    return try await decode(String.self, domScript("""
    (() => {
      const target = document.activeElement;
      if (!target || target === document.body || target === document.documentElement) {
        throw new Error('No focused node for keyboard input');
      }
      const key = \(escapedKey);
      const dispatch = type => target.dispatchEvent(new KeyboardEvent(type, {
        key, bubbles: true, cancelable: true
      }));
      const down = new KeyboardEvent('keydown', {key, bubbles: true, cancelable: true});
      target.dispatchEvent(down);
      if (key === 'Escape') {
        target.blur();
        target.dispatchEvent(new KeyboardEvent('keyup', {key, bubbles: true}));
        return JSON.stringify('');
      }
      if (key === 'Tab') {
        const focusable = Array.from(document.querySelectorAll(
          'a[href],button,input,select,textarea,[tabindex]:not([tabindex="-1"])'))
          .filter(node => !node.disabled && node.getAttribute('aria-hidden') !== 'true');
        const index = focusable.indexOf(target);
        const next = focusable[(index + (down.shiftKey ? -1 : 1) + focusable.length) % focusable.length];
        if (next) next.focus(); else target.blur();
        dispatch('keyup');
        return JSON.stringify('');
      }
      const editable = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement
        || target.isContentEditable;
      if (!editable || target.disabled || target.readOnly) {
        throw new Error('Focused node is not editable');
      }
      const input = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement;
      let value = input ? target.value : target.textContent || '';
      if (input && (key.length === 1 || key === 'Backspace' || key === 'Delete'
        || key === 'Enter' && target instanceof HTMLTextAreaElement)) {
        let start = value.length, end = value.length;
        try { start = target.selectionStart ?? value.length; end = target.selectionEnd ?? value.length; }
        catch {}
        if (key === 'Backspace' && start === end && start > 0) start--;
        if (key === 'Delete' && start === end && end < value.length) end++;
        const inserted = key.length === 1 ? key
          : key === 'Enter' && target instanceof HTMLTextAreaElement ? '\\n' : '';
        if (key.length === 1 || key === 'Enter' && target instanceof HTMLTextAreaElement
          || key === 'Backspace' || key === 'Delete') {
          const next = value.slice(0, start) + inserted + value.slice(end);
          const prototype = target instanceof HTMLInputElement
            ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
          Object.getOwnPropertyDescriptor(prototype, 'value').set.call(target, next);
          const caret = start + inserted.length;
          try { target.setSelectionRange(caret, caret); } catch {}
          target.dispatchEvent(new Event('input', {bubbles: true}));
          value = next;
        }
      } else if (target.isContentEditable && key.length === 1) {
        document.execCommand('insertText', false, key);
        value = target.textContent || '';
      } else if (key === 'Enter' && target instanceof HTMLInputElement && target.form) {
        target.form.requestSubmit();
      }
      dispatch('keyup');
      return JSON.stringify(value);
    })()
    """))
  }

  /// Byte budget for one snapshot payload. Bounds the allocation a hostile or very large
  /// page can force on a single read (directive §4.1.4, §9.6).
  static let snapshotByteBudget = 1 * 1024 * 1024

  func snapshot(info: BrowserPageInfo, limit: Int = 20000, since: UInt64? = nil) async throws
    -> PageSnapshot
  {
    let capped = max(1, min(limit, 20000))
    // Change check first: if the caller's generation matches this document and nothing has
    // mutated, return a flagged no-op instead of re-serializing the tree (directive §4.1.3).
    if let since, (since >> 32) == UInt64(generation) {
      let revision = try await decode(
        UInt64.self, domScript("JSON.stringify(globalThis.__aetherDOM.mutationVersion())"))
      let current = (UInt64(generation) << 32) | (revision & 0xffff_ffff)
      if current == since {
        return PageSnapshot(
          page: info, documentID: DocumentID(rawValue: UInt64(generation)),
          mutationVersion: current, nodes: [], truncated: false, omittedNodes: 0,
          unchanged: true)
      }
    }
    let values = try await decode([WebDOMNode].self, domScript("JSON.stringify(globalThis.__aetherDOM.snapshot(\(capped)))"))
    let mutationRevision = try await decode(UInt64.self,
      domScript("JSON.stringify(globalThis.__aetherDOM.mutationVersion())"))
    let mutationVersion = (UInt64(generation) << 32) | (mutationRevision & 0xffff_ffff)
    // Deterministic truncation: keep nodes until the byte budget is reached, then stop and
    // report the count. The document node is always kept so the driver sees the root.
    var totalBytes = 0
    var kept: [WebDOMNode] = []
    for value in values {
      let cost = (value.text?.utf8.count ?? 0) + value.name.utf8.count + 64
      if !kept.isEmpty && totalBytes + cost > Self.snapshotByteBudget { break }
      totalBytes += cost
      kept.append(value)
    }
    let omittedByBytes = values.count - kept.count
    let omittedByCap = values.count >= capped ? 1 : 0
    let omitted = max(omittedByBytes, omittedByCap)
    return PageSnapshot(
      page: info, documentID: DocumentID(rawValue: UInt64(generation)),
      mutationVersion: mutationVersion, nodes: kept.map(\.snapshot),
      truncated: omitted > 0, omittedNodes: omitted)
  }

  func nodeAction(_ node: NodeID, body: String) async throws {
    guard node.version == generation else { throw BrowserRuntimeError.nodeNotFound(node) }
    _ = try await script(domScript("""
    (() => { const n = globalThis.__aetherDOM.get(\(node.index));
    if (!n || !n.isConnected) throw new Error('Node is no longer attached');
    \(body)
    })()
    """))
  }

  func interactionTarget(_ node: NodeID) async throws -> WebKitInteractionTarget {
    guard node.version == generation else { throw BrowserRuntimeError.nodeNotFound(node) }
    return try await decode(WebKitInteractionTarget.self, domScript("""
    (() => {
      const n = globalThis.__aetherDOM.get(\(node.index));
      if (!n || !n.isConnected) throw new Error('Node is no longer attached');
      const previousX = scrollX, previousY = scrollY;
      n.scrollIntoView({block:'center', inline:'center'});
      const rect = n.getBoundingClientRect();
      const x = Math.max(0, Math.min(innerWidth, rect.left + rect.width / 2));
      const y = Math.max(0, Math.min(innerHeight, rect.top + rect.height / 2));
      let backgrounds = [];
      for (let element = n; element; element = element.parentElement) {
        const color = getComputedStyle(element).backgroundColor;
        const match = color.match(/rgba?[(]([^)]+)[)]/);
        if (!match) continue;
        const channels = match[1].split(',').map(Number);
        const alpha = channels.length > 3 ? channels[3] : 1;
        if (alpha <= 0.05) continue;
        const linear = channels.slice(0, 3).map(value => {
          const c = Math.max(0, Math.min(1, value / 255));
          return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        });
        backgrounds.push({value: 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2], alpha});
      }
      let luminance = 1;
      for (const background of backgrounds.reverse()) {
        luminance = background.value * background.alpha + luminance * (1 - background.alpha);
      }
      let interactive = false;
      for (let element = n; element; element = element.parentElement) {
        const role = element.getAttribute('role') || '';
        const style = getComputedStyle(element);
        if (/^(a|button|input|select|textarea|summary)$/.test(element.localName)
          || /^(button|link|checkbox|radio|menuitem|option|tab|switch)$/.test(role)
          || style.cursor === 'pointer') {
          interactive = true;
          break;
        }
      }
      return JSON.stringify({x, y, viewportWidth: innerWidth, viewportHeight: innerHeight,
        luminance, interactive, didScroll: previousX !== scrollX || previousY !== scrollY});
    })()
    """))
  }

  func click(_ node: NodeID) async throws {
    try await nodeAction(node, body: "n.scrollIntoView({block:'center', inline:'center'}); n.focus(); n.click();")
  }

  func sampleLuminance(at target: WebKitInteractionTarget) async -> Double? {
    guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
    let xScale = view.bounds.width / CGFloat(max(1, target.viewportWidth))
    let yScale = view.bounds.height / CGFloat(max(1, target.viewportHeight))
    let x = min(view.bounds.maxX - 1, max(view.bounds.minX, view.bounds.minX + CGFloat(target.x) * xScale))
    let y = view.isFlipped
      ? min(view.bounds.maxY - 1, max(view.bounds.minY, view.bounds.minY + CGFloat(target.y) * yScale))
      : min(view.bounds.maxY - 1, max(view.bounds.minY, view.bounds.maxY - CGFloat(target.y + 1) * yScale))
    let configuration = WKSnapshotConfiguration()
    configuration.rect = CGRect(x: x, y: y, width: 1, height: 1)
    configuration.snapshotWidth = 1
    guard let image = try? await view.takeSnapshot(configuration: configuration),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    var rgba = [UInt8](repeating: 0, count: 4)
    let sampled = rgba.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return true
    }
    guard sampled else { return nil }
    let alpha = Double(rgba[3]) / 255
    func linear(_ channel: UInt8) -> Double {
      let value = alpha > 0 ? min(1, Double(channel) / 255 / alpha) : 1
      return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let red = linear(rgba[0]), green = linear(rgba[1]), blue = linear(rgba[2])
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  @discardableResult
  func moveNativePointer(to target: WebKitInteractionTarget) -> Bool {
    sendMouseEvent(.mouseMoved, target: target, clickCount: 0)
  }

  @discardableResult
  func clickNativePointer(at target: WebKitInteractionTarget) -> Bool {
    guard sendMouseEvent(.leftMouseDown, target: target, clickCount: 1) else { return false }
    _ = sendMouseEvent(.leftMouseUp, target: target, clickCount: 1)
    return true
  }

  func beginNativeDrag(at target: WebKitInteractionTarget) -> Bool {
    sendMouseEvent(.leftMouseDown, target: target, clickCount: 1)
  }

  func dragNativePointer(to target: WebKitInteractionTarget) -> Bool {
    sendMouseEvent(.leftMouseDragged, target: target, clickCount: 1)
  }

  func endNativeDrag(at target: WebKitInteractionTarget) {
    _ = sendMouseEvent(.leftMouseUp, target: target, clickCount: 1)
  }

  func viewportSize() async throws -> Size {
    try await decode(Size.self, "JSON.stringify({width:innerWidth,height:innerHeight})")
  }

  func dragTarget(_ point: Point, viewport: Size) -> WebKitInteractionTarget {
    WebKitInteractionTarget(x: point.x, y: point.y, viewportWidth: viewport.width,
      viewportHeight: viewport.height, luminance: 1, interactive: true, didScroll: false)
  }

  func canSendNativePointer() -> Bool { view.window != nil }

  private func sendMouseEvent(_ type: NSEvent.EventType, target: WebKitInteractionTarget,
                              clickCount: Int) -> Bool {
    guard let window = view.window else { return false }
    let xScale = view.bounds.width / CGFloat(max(1, target.viewportWidth))
    let yScale = view.bounds.height / CGFloat(max(1, target.viewportHeight))
    let x = view.bounds.minX + CGFloat(target.x) * xScale
    let y = view.isFlipped
      ? view.bounds.minY + CGFloat(target.y) * yScale
      : view.bounds.maxY - CGFloat(target.y) * yScale
    let location = view.convert(CGPoint(x: x, y: y), to: nil)
    guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 0, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1)
    else { return false }
    window.sendEvent(event)
    return true
  }

  func fill(_ node: NodeID, value: String, append: Bool) async throws {
    try await nodeAction(node, body: """
    if (n.disabled || n.readOnly) throw new Error('Element is not editable');
    n.focus();
    const text = \(try Self.literal(value));
    if (n.isContentEditable) n.textContent = \(append ? "n.textContent + text" : "text");
    else if (n instanceof HTMLSelectElement) {
      const option = Array.from(n.options).find(option => option.value === text);
      if (!option) throw new Error('Select option was not found');
      Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(n, text);
    } else if (n instanceof HTMLInputElement || n instanceof HTMLTextAreaElement) {
      const prototype = n instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(n, \(append ? "n.value + text" : "text"));
    } else throw new Error('Element is not editable');
    n.dispatchEvent(new Event('input', {bubbles:true}));
    n.dispatchEvent(new Event('change', {bubbles:true}));
    """)
  }

  func scroll(x: Double, y: Double) async throws -> Point {
    guard x.isFinite, y.isFinite else { throw BrowserRuntimeError.invalidState("Invalid scroll coordinates") }
    return try await decode(Point.self, "window.scrollTo(\(x),\(y)); JSON.stringify({x:scrollX,y:scrollY})")
  }

  func scrollPosition() async throws -> Point {
    try await decode(Point.self, "JSON.stringify({x:scrollX,y:scrollY})")
  }

  func pixels() async throws -> PixelBuffer {
    final class Once: @unchecked Sendable {
      private let lock = NSLock()
      private var done = false
      func run(_ body: @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
      }
    }
    let once = Once()
    let image: NSImage = try await withCheckedThrowingContinuation { continuation in
      Task { @MainActor [weak self] in
        guard let self else {
          once.run {
            continuation.resume(throwing: BrowserRuntimeError.invalidState("The page was closed."))
          }
          return
        }
        do {
          let config = WKSnapshotConfiguration()
          config.rect = self.view.bounds
          // Native backing-store pixels (up to 4K wide), not CSS points: a
          // 1x snapshot is what made every capture look soft. Offscreen pages
          // have no window, so they render at 2x rather than 1x.
          let scale = self.view.window?.backingScaleFactor ?? 2
          let nativeWidth = min(3840, max(1, (self.view.bounds.width * scale).rounded()))
          config.snapshotWidth = NSNumber(value: Double(nativeWidth))
          let captured = try await self.view.takeSnapshot(configuration: config)
          once.run { continuation.resume(returning: captured) }
        } catch {
          once.run { continuation.resume(throwing: error) }
        }
      }
      Task {
        try? await Task.sleep(for: .seconds(30))
        if !Task.isCancelled {
          once.run {
            continuation.resume(
              throwing: BrowserRuntimeError.timeout("The page snapshot took too long."))
          }
        }
      }
    }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw RendererError.renderingFailed
    }
    var buffer = PixelBuffer(width: cgImage.width, height: cgImage.height)
    let width = buffer.width
    let height = buffer.height
    let success = buffer.bytes.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard success else { throw RendererError.renderingFailed }
    return buffer
  }

  func find(_ query: String, forward: Bool) async throws -> Int {
    let configuration = WKFindConfiguration()
    configuration.backwards = !forward
    configuration.wraps = true
    let result = try await view.find(query, configuration: configuration)
    guard result.matchFound else { return 0 }
    let count = try await script("document.body.innerText.toLocaleLowerCase().split(\(try Self.literal(query.lowercased()))).length - 1")
    return max(1, Int(count) ?? 1)
  }
}

struct WebKitInteractionTarget: Decodable, Sendable {
  let x: Double
  let y: Double
  let viewportWidth: Double
  let viewportHeight: Double
  let luminance: Double
  let interactive: Bool
  let didScroll: Bool
}
