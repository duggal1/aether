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
          else if JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
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

  func domScript(_ source: String) -> String {
    WebKitDOMScript.source(generation: generation) + ";\n" + source
  }

  func query(_ selector: String) async throws -> [InspectedNode] {
    let values = try await decode([WebDOMNode].self,
      domScript("JSON.stringify(Array.from(document.querySelectorAll(\(try Self.literal(selector)))).slice(0,10000).map(n => globalThis.__aetherDOM.describe(n)))"))
    return values.map(\.inspected)
  }

  func snapshot(info: BrowserPageInfo, limit: Int = 20000) async throws -> PageSnapshot {
    let capped = max(1, min(limit, 20000))
    let values = try await decode([WebDOMNode].self, domScript("JSON.stringify(globalThis.__aetherDOM.snapshot(\(capped)))"))
    return PageSnapshot(page: info, documentID: DocumentID(rawValue: UInt64(generation)),
      mutationVersion: UInt64(generation), nodes: values.map(\.snapshot))
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

  func fill(_ node: NodeID, value: String, append: Bool) async throws {
    try await nodeAction(node, body: """
    if (n.disabled || n.readOnly) throw new Error('Element is not editable');
    n.focus();
    const text = \(try Self.literal(value));
    if (n.isContentEditable) n.textContent = \(append ? "n.textContent + text" : "text");
    else if (n instanceof HTMLInputElement || n instanceof HTMLTextAreaElement || n instanceof HTMLSelectElement) {
      const prototype = n instanceof HTMLInputElement ? HTMLInputElement.prototype : n instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLSelectElement.prototype;
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
    let config = WKSnapshotConfiguration()
    config.rect = view.bounds
    config.snapshotWidth = NSNumber(value: view.bounds.width)
    let image = try await view.takeSnapshot(configuration: config)
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
