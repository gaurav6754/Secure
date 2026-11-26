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
            UserDefaults.standard.set(zoomLevel, forKey: "secure_ai_browser_zoom_native_v8")
            applyZoom()
        }
    }

    weak var webView: WKWebView?

    // Desktop Chrome/Safari user agent matching iPad Chrome desktop rendering
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    init() {
        let saved = UserDefaults.standard.double(forKey: "secure_ai_browser_zoom_native_v8")
        // Default 100% = Exact Chrome-on-iPad native edge-to-edge layout (zero shrinking or white space)
        self.zoomLevel = (saved >= 0.50 && saved <= 1.25) ? saved : 1.0
    }

    func zoomOut() {
        zoomLevel = max(0.50, (zoomLevel - 0.05).roundedToTwo)
    }

    func zoomIn() {
        zoomLevel = min(1.25, (zoomLevel + 0.05).roundedToTwo)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    /// 100% Chrome-on-iPad Native Rendering:
    /// At 100% (default), leaves the page completely untouched (no CSS transform, no viewport override)
    /// so SECURE v2 fills 100% edge-to-edge identically to Chrome on iPad Pro.
    func applyZoom() {
        guard let wv = webView else { return }
        wv.pageZoom = zoomLevel
        let js = """
        (function() {
          var el = document.documentElement;
          if (!el) return;
          el.style.transform = '';
          el.style.transformOrigin = '';
          el.style.width = '';
          el.style.height = '';
          el.style.zoom = '';
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    func autoFillLogin(userId: String, password: String) async -> String {
        do {
            let raw = try await callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.autoFillSecureLogin(u, p);",
                arguments: ["u": userId, "p": password]
            )
            if let dict = raw as? [String: Any], let msg = dict["message"] as? String {
                return msg
            }
            return "Filled credentials for \(userId)."
        } catch {
            return "Login fill error: \(error.localizedDescription)"
        }
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
        wv.pageZoom = zoomLevel
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
