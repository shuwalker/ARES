import SwiftUI
import WebKit

// MARK: - Render Mode

enum AvatarRenderMode: String, CaseIterable, Identifiable {
    case sprites = "Sprites"
    case liveAvatar = "Avatar"
    case render3D = "3D"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sprites:    return "person.3.sequence.fill"
        case .liveAvatar: return "face.smiling"
        case .render3D:   return "cube"
        }
    }
}

// MARK: - AvatarView

struct AvatarView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("avatarRenderMode") private var renderMode: AvatarRenderMode = .sprites
    @AppStorage("avatarVTuberURL")  private var vtuberURL: String = "http://localhost:12393"
    @AppStorage("avatar3DRenderURL") private var render3DURL: String = "http://localhost:3000"

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            AvatarSettingsView(vtuberURL: $vtuberURL, render3DURL: $render3DURL)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Avatar"))
                .font(.headline)

            Spacer()

            Picker("", selection: $renderMode) {
                ForEach(AvatarRenderMode.allCases) { mode in
                    Label(L10n.string(mode.rawValue), systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Avatar Settings"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    // MARK: Content routing

    @ViewBuilder
    private var content: some View {
        switch renderMode {
        case .sprites:
            AvatarSpritesView()
                .environmentObject(appState)
        case .liveAvatar:
            AvatarWebPanelView(urlString: vtuberURL, serviceName: L10n.string("VTuber avatar service"), defaultPort: 12393)
        case .render3D:
            AvatarWebPanelView(urlString: render3DURL, serviceName: L10n.string("3D render service"), defaultPort: 3000)
        }
    }
}

// MARK: - Sprite Mode

struct AvatarSpritesView: View {
    @EnvironmentObject private var appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if appState.swarmWorkers.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(appState.swarmWorkers, id: \.id) { worker in
                        AgentSpriteCard(worker: worker)
                    }
                }
                .padding(20)
            }
        }
        .task {
            await appState.loadSwarm()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(L10n.string("No agents online"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(L10n.string("Connect to a Hermes instance to see your agent team."))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Agent Sprite Card

private struct AgentSpriteCard: View {
    let worker: SwarmWorker

    @State private var animFrame = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 80, height: 80)

                spriteCanvas
                    .frame(width: 64, height: 64)

                if workerStatus == .active || workerStatus == .running {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(NSColor.controlBackgroundColor), lineWidth: 1.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }

            Text(worker.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(statusLabel)
                .font(.caption2)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
        .onReceive(timer) { _ in
            if workerStatus == .active || workerStatus == .running {
                animFrame = (animFrame + 1) % 4
            } else {
                animFrame = 0
            }
        }
    }

    // MARK: Pixel sprite canvas

    private var spriteCanvas: some View {
        Canvas { ctx, size in
            let scale = size.width / 16
            drawSprite(in: ctx, scale: scale)
        }
        .drawingGroup()
    }

    private func drawSprite(in ctx: GraphicsContext, scale: CGFloat) {
        let s = scale
        let status = workerStatus
        let f = animFrame

        // Body color by status
        let bodyColor: Color = switch status {
        case .active, .running:  .green
        case .error:             .red
        case .offline:           .gray
        default:                 .blue
        }

        // Head (pixels 6-10, rows 1-4)
        fill(ctx, x: 6, y: 1, w: 5, h: 4, color: .yellow, s: s)
        // Eyes
        fill(ctx, x: 7, y: 2, w: 1, h: 1, color: .black, s: s)
        fill(ctx, x: 9, y: 2, w: 1, h: 1, color: .black, s: s)

        // Body (rows 5-10)
        fill(ctx, x: 5, y: 5, w: 7, h: 5, color: bodyColor, s: s)

        // Arms — animate when active
        let armOffset = (status == .active || status == .running) ? (f % 2 == 0 ? 1 : -1) : 0
        fill(ctx, x: 3, y: 5 + armOffset, w: 2, h: 4, color: bodyColor, s: s)
        fill(ctx, x: 12, y: 5 - armOffset, w: 2, h: 4, color: bodyColor, s: s)

        // Legs — bob when active
        let legY = (status == .active || status == .running) && f % 2 == 0 ? 1 : 0
        fill(ctx, x: 5, y: 10 + legY, w: 3, h: 4, color: bodyColor.opacity(0.8), s: s)
        fill(ctx, x: 9, y: 10 - legY, w: 3, h: 4, color: bodyColor.opacity(0.8), s: s)

        // Laptop (idle/working)
        if status != .offline {
            fill(ctx, x: 4, y: 12, w: 9, h: 1, color: .gray.opacity(0.6), s: s)
            fill(ctx, x: 5, y: 11, w: 7, h: 1, color: .cyan.opacity(0.7), s: s)
        }
    }

    private func fill(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color, s: CGFloat) {
        ctx.fill(
            Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)),
            with: .color(color)
        )
    }

    // MARK: Status helpers

    private var workerStatus: WorkerStatus {
        WorkerStatus(rawValue: worker.status.lowercased()) ?? .idle
    }

    private var statusLabel: String {
        switch workerStatus {
        case .active, .running: return L10n.string("Working")
        case .idle:             return L10n.string("Idle")
        case .error:            return L10n.string("Error")
        case .offline:          return L10n.string("Offline")
        }
    }

    private var statusColor: Color {
        switch workerStatus {
        case .active, .running: return .green
        case .idle:             return .blue
        case .error:            return .red
        case .offline:          return .gray
        }
    }
}

// MARK: - WorkerStatus

private enum WorkerStatus: String {
    case active, running, idle, error, offline
}

// MARK: - Web Panel (Live2D / 3D)

struct AvatarWebPanelView: View {
    let urlString: String
    let serviceName: String
    let defaultPort: Int

    @StateObject private var viewModel = AvatarWebViewModel()
    @State private var webView: WKWebView?

    var body: some View {
        ZStack {
            AvatarWKWebViewRepresentable(viewModel: viewModel, webViewHolder: $webView, url: resolvedURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.isLoading {
                HermesLoadingState(label: L10n.string("Loading…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
            }

            if viewModel.hasError {
                webErrorOverlay
            }
        }
        .onChange(of: urlString) { _, _ in
            guard let wv = webView, let url = resolvedURL else { return }
            viewModel.reload(webView: wv, url: url)
        }
    }

    private var resolvedURL: URL? {
        URL(string: urlString)
    }

    private var webErrorOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(L10n.string("\(serviceName) not running"))
                .font(.headline)

            Text(L10n.string("Start the service at \(urlString) to use this panel."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let msg = viewModel.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                guard let wv = webView, let url = resolvedURL else { return }
                viewModel.reload(webView: wv, url: url)
            } label: {
                Label(L10n.string("Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Web ViewModel

@MainActor
final class AvatarWebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var hasError = false
    @Published var errorMessage: String?

    func reload(webView: WKWebView, url: URL) {
        hasError = false
        errorMessage = nil
        isLoading = true
        webView.load(URLRequest(url: url))
    }
}

// MARK: - Web Coordinator

final class AvatarWebCoordinator: NSObject, WKNavigationDelegate {
    @MainActor weak var viewModel: AvatarWebViewModel?

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

struct AvatarWKWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: AvatarWebViewModel
    @Binding var webViewHolder: WKWebView?
    let url: URL?

    func makeCoordinator() -> AvatarWebCoordinator {
        let coordinator = AvatarWebCoordinator()
        coordinator.viewModel = viewModel
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        DispatchQueue.main.async { webViewHolder = webView }
        if let url { webView.load(URLRequest(url: url)) }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Settings Sheet

struct AvatarSettingsView: View {
    @Binding var vtuberURL: String
    @Binding var render3DURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("Avatar Settings"))
                .font(.title2.weight(.semibold))

            GroupBox(label: Label(L10n.string("Live2D / VTuber"), systemImage: "face.smiling")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Service URL"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://localhost:12393", text: $vtuberURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(8)
            }

            GroupBox(label: Label(L10n.string("3D Render"), systemImage: "cube")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Render service URL"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://localhost:3000", text: $render3DURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(8)
            }

            Text(L10n.string("Sprites mode requires no external service — it renders directly from your connected agent roster."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L10n.string("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
