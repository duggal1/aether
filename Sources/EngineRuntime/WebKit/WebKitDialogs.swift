import AppKit
import BrowserEvents
import WebKit

@MainActor
final class WebKitDialogs: NSObject, WKUIDelegate, WKDownloadDelegate {
  var emit: @Sendable (BrowserEventKind) -> Void = { _ in }
  private var completions: [UUID: () -> Void] = [:]
  private var downloads: [ObjectIdentifier: WKDownload] = [:]
  private var downloadInfo: [ObjectIdentifier: (url: String, path: String?)] = [:]

  func close() {
    let remaining = completions.values
    completions.removeAll()
    for completion in remaining { completion() }
    for download in downloads.values { download.cancel { _ in } }
    downloads.removeAll()
  }

  private func originString(_ origin: WKSecurityOrigin) -> String {
    var value = "\(origin.protocol)://\(origin.host)"
    if origin.port != 0, !(origin.protocol == "https" && origin.port == 443),
      !(origin.protocol == "http" && origin.port == 80) {
      value += ":\(origin.port)"
    }
    return value
  }

  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
    let permission: String
    switch type {
    case .camera: permission = "camera"
    case .microphone: permission = "microphone"
    case .cameraAndMicrophone: permission = "camera+microphone"
    @unknown default: permission = "media"
    }
    emit(.permissionRequested(permission: permission, origin: originString(origin), decision: "prompt"))
    decisionHandler(.prompt)
  }

  func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
    emit(.permissionRequested(permission: "geolocation", origin: originString(origin), decision: "prompt"))
    decisionHandler(.prompt)
  }

  private func present(_ alert: NSAlert, in view: WKWebView,
    completion: @escaping (NSApplication.ModalResponse) -> Void) {
    guard let window = view.window else { completion(.abort); return }
    let token = UUID()
    completions[token] = { completion(.abort) }
    alert.beginSheetModal(for: window) { [weak self] response in
      guard self?.completions.removeValue(forKey: token) != nil else { return }
      completion(response)
    }
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
    emit(.dialogOpened(kind: "alert", message: message))
    let alert = NSAlert()
    alert.messageText = frame.request.url?.host ?? "Website"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    present(alert, in: webView) { _ in completionHandler() }
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
    emit(.dialogOpened(kind: "confirm", message: message))
    let alert = NSAlert()
    alert.messageText = frame.request.url?.host ?? "Website"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    present(alert, in: webView) { completionHandler($0 == .alertFirstButtonReturn) }
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor (String?) -> Void) {
    emit(.dialogOpened(kind: "prompt", message: prompt))
    let alert = NSAlert()
    alert.messageText = frame.request.url?.host ?? "Website"
    alert.informativeText = prompt
    let field = NSTextField(string: defaultText ?? "")
    field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    present(alert, in: webView) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    emit(.popupRequested(url: navigationAction.request.url?.absoluteString ?? ""))
    // Returning nil means WebKit never creates a child window, so anything relying on
    // `window.opener` / a `postMessage` handshake cannot initialise. Google's GSI account
    // chooser is exactly that: it renders blank without a real opener.
    //
    // WebKit hands us the `configuration` for the child. Adopting *that* object (rather
    // than building a fresh one) is what preserves the opener relationship.
    if let makePopup, let child = makePopup(configuration, navigationAction, windowFeatures) {
      return child
    }
    if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
    return nil
  }

  /// Invoked when the popup calls `window.close()`.
  var popupClosed: (@MainActor (WKWebView) -> Void)?
  /// Builds a real child web view. Assigned by `WebKitPage`.
  var makePopup: (@MainActor (WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures) -> WKWebView?)?

  func webViewDidClose(_ webView: WKWebView) {
    popupClosed?(webView)
  }

  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
    emit(.fileChooserRequested(label: nil, allowsMultiple: parameters.allowsMultipleSelection))
    guard let window = webView.window else { completionHandler(nil); return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.beginSheetModal(for: window) { response in
      completionHandler(response == .OK ? panel.urls : nil)
    }
  }

  func track(_ download: WKDownload) {
    let key = ObjectIdentifier(download)
    downloads[key] = download
    download.delegate = self
    let url = download.originalRequest?.url?.absoluteString ?? ""
    downloadInfo[key] = (url, nil)
    emit(.downloadStarted(url: url))
  }

  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
    suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
    let key = ObjectIdentifier(download)
    let panel = NSSavePanel()
    panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
    panel.begin { [weak self] response in
      let destination = response == .OK ? panel.url : nil
      if let destination { self?.downloadInfo[key]?.path = destination.path }
      completionHandler(destination)
    }
  }

  func downloadDidFinish(_ download: WKDownload) {
    let key = ObjectIdentifier(download)
    let info = downloadInfo.removeValue(forKey: key)
    let url = info?.url ?? download.originalRequest?.url?.absoluteString ?? ""
    emit(.downloadFinished(url: url, path: info?.path))
    downloads[key] = nil
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    let key = ObjectIdentifier(download)
    let info = downloadInfo.removeValue(forKey: key)
    let url = info?.url ?? download.originalRequest?.url?.absoluteString ?? ""
    emit(.downloadFailed(url: url, error: error.localizedDescription))
    downloads[key] = nil
  }
}

extension WebKitPage {
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    dialogs?.track(download)
    resolveMainFrameDownload(action: navigationAction)
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    dialogs?.track(download)
    resolveMainFrameDownload(response: navigationResponse)
  }
}
