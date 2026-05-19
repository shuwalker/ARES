import SwiftUI
import WebKit

// MARK: - ViewModel

@MainActor
final class OfficeViewModel: ObservableObject {
    static let defaultURL = URL(string: "http://localhost:9321")!

    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage: String?
    @Published var urlText = "http://localhost:9321"

    var resolvedURL: URL {
        URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Self.defaultURL
    }

    func load(webView: WKWebView) {
        hasError = false
        errorMessage = nil
        isLoading = true
        webView.load(URLRequest(url: resolvedURL))
    }

    func reload(webView: WKWebView) {
        load(webView: webView)
    }
}

// MARK: - Coordinator

final class OfficeWebViewCoordinator: NSObject, WKNavigationDelegate {
    @MainActor
    weak var viewModel: OfficeViewModel?

    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        viewModel?.isLoading = false
        viewModel?.hasError = false
        viewModel?.errorMessage = nil
    }

    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewModel?.isLoading = false
        viewModel?.hasError = true
        viewModel?.errorMessage = error.localizedDescription
    }

    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewModel?.isLoading = false
        viewModel?.hasError = true
        viewModel?.errorMessage = error.localizedDescription
    }
}

// MARK: - NSViewRepresentable

struct OfficeWKWebView: NSViewRepresentable {
    @ObservedObject var viewModel: OfficeViewModel
    @Binding var webViewHolder: WKWebView?

    func makeCoordinator() -> OfficeWebViewCoordinator {
        let coordinator = OfficeWebViewCoordinator()
        coordinator.viewModel = viewModel
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        DispatchQueue.main.async {
            webViewHolder = webView
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - View

struct OfficeView: View {
    @StateObject private var viewModel = OfficeViewModel()
    @State private var webView: WKWebView?
    @State private var hasAttemptedLoad = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                OfficeWKWebView(viewModel: viewModel, webViewHolder: $webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !hasAttemptedLoad {
                    placeholderState
                } else if viewModel.isLoading {
                    HermesLoadingState(label: "Loading Office…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                } else if viewModel.hasError {
                    errorOverlay
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(L10n.string("Office"))
                .font(.headline)

            Spacer()

            TextField(L10n.string("URL"), text: $viewModel.urlText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 200, maxWidth: 340)
                .onSubmit {
                    loadPage()
                }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Button {
                loadPage()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Reload Office"))
            .disabled(viewModel.isLoading)

            Button {
                NSWorkspace.shared.open(viewModel.resolvedURL)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Open in Browser"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    // MARK: - Placeholder

    private var placeholderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text(L10n.string("Office"))
                .font(.title3.weight(.semibold))

            Text(L10n.string("Start the Office server on your host to connect."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                loadPage()
            } label: {
                Label(L10n.string("Connect"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Error overlay

    private var errorOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(L10n.string("Unable to connect to Office"))
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Text(L10n.string("Start the Office server on your host to connect."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                loadPage()
            } label: {
                Label(L10n.string("Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                NSWorkspace.shared.open(viewModel.resolvedURL)
            } label: {
                Label(L10n.string("Open in Browser"), systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func loadPage() {
        guard let webView else { return }
        hasAttemptedLoad = true
        viewModel.load(webView: webView)
    }
}
