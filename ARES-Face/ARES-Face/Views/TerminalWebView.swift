import SwiftUI
import WebKit

/// A native SwiftUI view that wraps a WKWebView pointing at the Hermes TUI dashboard.
///
/// This gives the user a live terminal view into the Hermes agent session, showing
/// tool calls, streaming output, and the full TUI experience — all embedded in the
/// ARES app drawer.
struct TerminalWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences = WKPreferences()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")  // transparent background
        webView.navigationDelegate = context.coordinator

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op; we only load once
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject dark background to match ARES theme
            let js = """
            document.body.style.backgroundColor = 'transparent';
            document.documentElement.style.backgroundColor = 'transparent';
            """
            webView.evaluateJavaScript(js)
        }
    }
}

/// SwiftUI wrapper for the Hermes terminal TUI embedded in the drawer.
struct HermesTerminalView: View {
    @State private var dashboardURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let url = dashboardURL {
                TerminalWebView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("Connecting to Hermes TUI...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await resolveDashboardURL()
        }
    }

    private func resolveDashboardURL() async {
        // Fetch dashboard HTML to extract session token, then construct TUI URL
        let baseURL = "http://localhost:9119"
        guard let url = URL(string: baseURL) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8),
                  let tokenRange = html.range(of: "__HERMES_SESSION_TOKEN__=\""),
                  let endRange = html[tokenRange.upperBound...].range(of: "\"") else {
                // Fall back to plain URL without token
                dashboardURL = URL(string: baseURL)
                return
            }
            let token = String(html[tokenRange.upperBound..<endRange.lowerBound])
            dashboardURL = URL(string: "\(baseURL)?token=\(token)")
        } catch {
            // If dashboard not reachable, show error
            dashboardURL = URL(string: baseURL)
        }
    }
}