import SwiftUI
import WebKit

/// High-performance WKWebView wrapper decoupled from SwiftUI's progress-bar re-renders.
/// Uses `let store` instead of `@ObservedObject` so loading-progress ticks never trigger view re-layouts.
struct WebViewRepresentable: UIViewRepresentable {
    let store: EmbeddedBrowserStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.preferredContentMode = store.desktopMode ? .desktop : .mobile

        let userContent = WKUserContentController()
        let script = WKUserScript(
            source: SecureAutomationJS.engineScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(script)

                config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = store.desktopMode ? EmbeddedBrowserStore.desktopUserAgent : nil
        webView.pageZoom = 1.0
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear

        context.coordinator.bindObservers(to: webView)
        store.webView = webView

        if let initialURL = URL(string: store.addressText) {
            webView.load(URLRequest(url: initialURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Deliberately empty: mutations happen directly through EmbeddedBrowserStore for 120Hz smoothness
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let store: EmbeddedBrowserStore
        private var observers: [NSKeyValueObservation] = []

        init(store: EmbeddedBrowserStore) {
            self.store = store
        }

        func bindObservers(to webView: WKWebView) {
            observers = [
                webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.estimatedProgress = wv.estimatedProgress }
                },
                webView.observe(\.isLoading, options: .new) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.isLoading = wv.isLoading }
                },
                webView.observe(\.canGoBack, options: .new) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward, options: .new) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.canGoForward = wv.canGoForward }
                },
                webView.observe(\.title, options: .new) { [weak self] wv, _ in
                    Task { @MainActor in
                        if let t = wv.title, !t.isEmpty { self?.store.pageTitle = t }
                    }
                },
                webView.observe(\.url, options: .new) { [weak self] wv, _ in
                    Task { @MainActor in
                        if let u = wv.url?.absoluteString { self?.store.addressText = u }
                    }
                }
            ]
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                store.applyZoom()
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
    }
}
