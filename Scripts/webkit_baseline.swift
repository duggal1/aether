import AppKit
import Foundation
import WebKit

final class Probe: NSObject, WKNavigationDelegate {
    var done = false
    var t0 = Date()
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        JSON.stringify({fcp:(performance.getEntriesByType('paint').find(e=>e.name==='first-contentful-paint')||{}).startTime??null,
        n:performance.getEntriesByType('resource').length,
        dcl:(performance.getEntriesByType('navigation')[0]||{}).domContentLoadedEventEnd??null})
        """
        webView.evaluateJavaScript(js) { [self] value, _ in
            print("RESULT fcp_probe \((value as? String) ?? "nil")")
            self.done = true
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("RESULT navigation_failed \(error.localizedDescription)")
        done = true
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("RESULT content_process_terminated")
        done = true
    }
}

let url = CommandLine.arguments[1]
let probe = Probe()
let config = WKWebViewConfiguration()
let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
view.navigationDelegate = probe
let t0 = Date()
probe.t0 = t0
view.load(URLRequest(url: URL(string: url)!))
while !probe.done && Date().timeIntervalSince(t0) < 60 {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
}
print("RESULT wall_ms \(Int(Date().timeIntervalSince(t0) * 1000))")
