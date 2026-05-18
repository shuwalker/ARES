import SwiftUI
import WebKit

// MARK: - ViewModel

@MainActor
final class DocsViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var hasError = false
    @Published var errorMessage: String?

    func reload(webView: WKWebView) {
        hasError = false
        errorMessage = nil
        isLoading = true
        webView.load(URLRequest(url: DocsViewModel.docsURL))
    }

    static let docsURL = URL(string: "https://hermes-agent.nousresearch.com/docs")!
}

// MARK: - Coordinator

final class DocsWebViewCoordinator: NSObject, WKNavigationDelegate {
    @MainActor
    weak var viewModel: DocsViewModel?

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

struct DocsWKWebView: NSViewRepresentable {
    @ObservedObject var viewModel: DocsViewModel
    @Binding var webViewHolder: WKWebView?

    func makeCoordinator() -> DocsWebViewCoordinator {
        let coordinator = DocsWebViewCoordinator()
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
        webView.load(URLRequest(url: DocsViewModel.docsURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - View

struct DocsView: View {
    @StateObject private var viewModel = DocsViewModel()
    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                DocsWKWebView(viewModel: viewModel, webViewHolder: $webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isLoading {
                    HermesLoadingState(label: "Loading Documentation…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                }

                if viewModel.hasError {
                    errorOverlay
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Documentation"))
                .font(.headline)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Button {
                guard let webView else { return }
                viewModel.reload(webView: webView)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Reload Documentation"))
            .disabled(viewModel.isLoading)

            Button {
                NSWorkspace.shared.open(DocsViewModel.docsURL)
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
            Divider()
                .opacity(0.5)
        }
    }

    private var errorOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(L10n.string("Unable to load Documentation"))
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                guard let webView else { return }
                viewModel.reload(webView: webView)
            } label: {
                Label(L10n.string("Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
