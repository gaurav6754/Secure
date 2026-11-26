import Foundation
import WebKit

struct QuickBookmark: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let urlString: String

    static let defaults: [QuickBookmark] = [
        .init(title: "SECURE Portal", icon: "building.columns.fill", urlString: "https://secure.dord.gov.in/"),
        .init(title: "Google Search", icon: "magnifyingglass", urlString: "https://www.google.com/"),
        .init(title: "NREGA Bihar", icon: "doc.text.magnifyingglass", urlString: "https://nrega.nic.in/")
    ]
}

@MainActor
final class EmbeddedBrowserStore: ObservableObject {
    @Published var addressText: String = "https://secure.dord.gov.in/"
    @Published var pageTitle: String = "SECURE Portal"
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0.0
    @Published var desktopMode: Bool = true {
        didSet { applyUserAgentAndReload() }
    }
    @Published var zoomLevel: Double {
        didSet {
            UserDefaults.standard.set(zoomLevel, forKey: "secure_ai_browser_zoom_v2")
            applyZoom()
        }
    }

    weak var webView: WKWebView?

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    init() {
        let saved = UserDefaults.standard.double(forKey: "secure_ai_browser_zoom_v2")
        self.zoomLevel = (saved >= 0.45 && saved <= 1.25) ? saved : 0.75
    }

    func zoomOut() {
        zoomLevel = max(0.45, (zoomLevel - 0.05).roundedToTwo)
    }

    func zoomIn() {
        zoomLevel = min(1.25, (zoomLevel + 0.05).roundedToTwo)
    }

    func resetZoom() {
        zoomLevel = 0.75
    }

    /// Uses CSS `document.documentElement.style.zoom` while keeping `webView.pageZoom = 1.0`.
    /// On iPadOS, shrinking `webView.pageZoom` causes `position: fixed` modals (like SECURE Login) to expand in reverse.
    func applyZoom() {
        guard let wv = webView else { return }
        wv.pageZoom = 1.0
        let pct = Int(round(zoomLevel * 100))
        let js = """
        (function() {
          if (document && document.documentElement) {
            window.__SECURE_ZOOM_PCT__ = \(pct); document.documentElement.style.zoom = '\(pct)%';
          }
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    func navigate(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL?
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            targetURL = URL(string: trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://\(trimmed)")
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")
        }

        if let url = targetURL {
            addressText = url.absoluteString
            webView?.load(URLRequest(url: url))
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reloadOrStop() {
        if isLoading { webView?.stopLoading() } else { webView?.reload() }
    }

    func applyUserAgentAndReload() {
        guard let wv = webView else { return }
        wv.customUserAgent = desktopMode ? Self.desktopUserAgent : nil
        wv.configuration.defaultWebpagePreferences.preferredContentMode = desktopMode ? .desktop : .mobile
        wv.pageZoom = 1.0
        wv.reload()
    }

    func callAutomationJS(_ functionBody: String, arguments: [String: Any] = [:]) async throws -> Any? {
        guard let webView else {
            throw NSError(domain: "EmbeddedBrowserStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in browser is not ready yet."])
        }
        _ = try? await webView.evaluateJavaScript(SecureAutomationJS.engineScript)
        return try await webView.callAsyncJavaScript(
            functionBody,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
    }
}

private extension Double {
    var roundedToTwo: Double {
        (self * 100).rounded() / 100
    }
}
