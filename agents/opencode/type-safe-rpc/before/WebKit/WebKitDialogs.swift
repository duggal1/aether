import AppKit
import WebKit

@MainActor
final class WebKitDialogs: NSObject, WKUIDelegate, WKDownloadDelegate {
  private var completions: [UUID: () -> Void] = [:]
  private var downloads: [ObjectIdentifier: WKDownload] = [:]

  func close() {
    let remaining = completions.values
    completions.removeAll()
    for completion in remaining { completion() }
    for download in downloads.values { download.cancel { _ in } }
    downloads.removeAll()
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
    let alert = NSAlert()
    alert.messageText = frame.request.url?.host ?? "Website"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    present(alert, in: webView) { _ in completionHandler() }
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
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
    if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
    return nil
  }

  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
    guard let window = webView.window else { completionHandler(nil); return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.beginSheetModal(for: window) { response in
      completionHandler(response == .OK ? panel.urls : nil)
    }
  }

  func track(_ download: WKDownload) {
    downloads[ObjectIdentifier(download)] = download
    download.delegate = self
  }

  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
    suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
    panel.begin { response in completionHandler(response == .OK ? panel.url : nil) }
  }

  func downloadDidFinish(_ download: WKDownload) { downloads[ObjectIdentifier(download)] = nil }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloads[ObjectIdentifier(download)] = nil
  }
}

extension WebKitPage {
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    dialogs?.track(download)
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    dialogs?.track(download)
  }
}
