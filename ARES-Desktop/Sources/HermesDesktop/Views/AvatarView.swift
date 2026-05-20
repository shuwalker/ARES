import SwiftUI
import WebKit

// MARK: - ViewModel

@MainActor
final class AvatarPanelViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var hasError = false
    @Published var errorMessage: String?

    func reload(webView: WKWebView) {
        hasError = false
        errorMessage = nil
        isLoading = true
        webView.load(URLRequest(url: AvatarPanelViewModel.vtuberURL))
    }

    private enum Constants {
        static let vtuberURL = URL(string: "http://localhost:12393")!
    }
    static var vtuberURL: URL { Constants.vtuberURL }
}

// MARK: - Coordinator

final class AvatarWebViewCoordinator: NSObject, WKNavigationDelegate {
    @MainActor
    weak var viewModel: AvatarPanelViewModel?

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

struct AvatarWKWebView: NSViewRepresentable {
    @ObservedObject var viewModel: AvatarPanelViewModel
    @Binding var webViewHolder: WKWebView?

    func makeCoordinator() -> AvatarWebViewCoordinator {
        let coordinator = AvatarWebViewCoordinator()
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
        webView.load(URLRequest(url: AvatarPanelViewModel.vtuberURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - View

struct AvatarView: View {
    @StateObject private var viewModel = AvatarPanelViewModel()
    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                AvatarWKWebView(viewModel: viewModel, webViewHolder: $webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isLoading {
                    HermesLoadingState(label: "Loading Avatar…")
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
            Text(L10n.string("Avatar"))
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
            .help(L10n.string("Reload Avatar Panel"))
            .disabled(viewModel.isLoading)
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

            Text(L10n.string("Avatar service not running"))
                .font(.headline)

            Text(L10n.string("Start the VTuber avatar service on localhost:12393 to use this panel."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
