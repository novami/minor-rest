import SwiftUI
import WebKit

/// Náhled HTML odpovědi: `WKWebView` bez JavaScriptu, bez úložiště a bez navigace (síť blokuje CSP v textu).
struct HTMLPreviewView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Povolí jen načtení vlastního textu (`about:blank`), odkazy a přesměrování zahodí.
        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            action.request.url?.scheme == "about" && action.navigationType == .other ? .allow : .cancel
        }
    }
}
