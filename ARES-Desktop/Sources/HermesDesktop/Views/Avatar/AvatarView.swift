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

// MARK: - Sprite Mode (Pixel Office Scene)

struct AvatarSpritesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            if appState.swarmWorkers.isEmpty {
                emptyState
            } else {
                PixelOfficeView(workers: appState.swarmWorkers)
            }
        }
        .task { await appState.loadSwarm() }
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

// MARK: - Pixel Office View

private struct PixelOfficeView: View {
    let workers: [SwarmWorker]

    // Per-agent animation state: walk position (0…1) and direction
    @State private var walkPos:  [String: CGFloat] = [:]
    @State private var walkDir:  [String: CGFloat] = [:]
    @State private var tick: Int = 0

    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                OfficeRenderer(
                    workers: workers,
                    walkPos: walkPos,
                    walkDir: walkDir,
                    tick: tick
                ).draw(ctx: ctx, size: size)
            }
            .drawingGroup()
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(timer) { _ in
            tick = (tick + 1) % 64
            advanceWalkers()
        }
        .onAppear { seedWalkers() }
        .onChange(of: workers.map(\.id)) { _, _ in seedWalkers() }
    }

    private func seedWalkers() {
        for (i, w) in workers.enumerated() {
            if WorkerKind(w) == .idle && walkPos[w.id] == nil {
                walkPos[w.id] = CGFloat(i % 5) * 0.18 + 0.05
                walkDir[w.id] = i % 2 == 0 ? 1 : -1
            }
        }
    }

    private func advanceWalkers() {
        for w in workers where WorkerKind(w) == .idle {
            let speed: CGFloat = 0.006
            let pos = (walkPos[w.id] ?? 0.1) + speed * (walkDir[w.id] ?? 1)
            if pos > 0.88 {
                walkPos[w.id]  = 0.88
                walkDir[w.id]  = -1
            } else if pos < 0.04 {
                walkPos[w.id]  = 0.04
                walkDir[w.id]  = 1
            } else {
                walkPos[w.id] = pos
            }
        }
    }
}

// MARK: - Status helpers

private enum WorkerKind {
    case working, idle, sleeping

    init(_ w: SwarmWorker) {
        switch w.status.rawValue.lowercased() {
        case "active", "running", "error": self = .working
        case "offline":                    self = .sleeping
        default:                           self = .idle
        }
    }
}

private func agentColor(_ w: SwarmWorker) -> Color {
    switch w.status.rawValue.lowercased() {
    case "active", "running": return Color(hue: Double(abs(w.id.hashValue) % 6) / 6.0, saturation: 0.7, brightness: 0.8)
    case "error":             return .red
    case "offline":           return Color(white: 0.45)
    default:                  return Color(hue: Double(abs(w.id.hashValue) % 8) / 8.0, saturation: 0.5, brightness: 0.75)
    }
}

// MARK: - Office Renderer

private struct OfficeRenderer {
    let workers: [SwarmWorker]
    let walkPos: [String: CGFloat]
    let walkDir: [String: CGFloat]
    let tick: Int

    // Scene proportions
    private let wallFrac:  CGFloat = 0.52  // top fraction = wall
    private let px: CGFloat = 3            // 1 "pixel" in points

    func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let floorY = h * wallFrac

        drawBackground(ctx, w: w, h: h, floorY: floorY)
        drawDesks(ctx, w: w, h: h, floorY: floorY)
        drawSleepCorner(ctx, w: w, h: h)
        drawAgents(ctx, w: w, h: h, floorY: floorY)
        drawNameLabels(ctx, w: w, h: h, floorY: floorY)
    }

    // MARK: Background

    private func drawBackground(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, floorY: CGFloat) {
        // Wall
        ctx.fill(rect(0, 0, w, floorY + px * 2),
                 with: .color(Color(red: 0.14, green: 0.17, blue: 0.24)))
        // Wall accent stripe
        ctx.fill(rect(0, floorY - px * 6, w, px * 2),
                 with: .color(Color(red: 0.20, green: 0.24, blue: 0.32)))
        // Baseboard
        ctx.fill(rect(0, floorY, w, px * 4),
                 with: .color(Color(red: 0.55, green: 0.48, blue: 0.38)))
        // Floor
        ctx.fill(rect(0, floorY + px * 4, w, h - floorY - px * 4),
                 with: .color(Color(red: 0.30, green: 0.24, blue: 0.19)))
        // Floor highlight rows (perspective)
        for row in stride(from: 0, to: Int((h - floorY) / (px * 8)), by: 1) {
            let y = floorY + px * 4 + CGFloat(row) * px * 8
            ctx.fill(rect(0, y, w, px),
                     with: .color(Color(white: 1, opacity: 0.04)))
        }
        // Ceiling light strip
        ctx.fill(rect(w * 0.3, 0, w * 0.4, px * 2),
                 with: .color(Color(white: 1, opacity: 0.25)))
    }

    // MARK: Desks

    private func drawDesks(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, floorY: CGFloat) {
        let deskWorkers = workers.filter { WorkerKind($0) == .working }
        guard !deskWorkers.isEmpty else { return }

        let deskW: CGFloat = px * 22
        let spacing = min((w - deskW) / CGFloat(deskWorkers.count), deskW + px * 10)
        let startX = (w - spacing * CGFloat(deskWorkers.count - 1) - deskW) / 2

        for (i, worker) in deskWorkers.enumerated() {
            let x = startX + CGFloat(i) * spacing
            let deskTopY = floorY - px * 14
            drawDesk(ctx, x: x, y: deskTopY, worker: worker)
        }
    }

    private func drawDesk(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, worker: SwarmWorker) {
        let isError = worker.status.rawValue.lowercased() == "error"

        // Desk surface
        ctx.fill(rect(x, y, px * 22, px * 3),
                 with: .color(Color(red: 0.55, green: 0.42, blue: 0.30)))
        ctx.fill(rect(x, y + px * 3, px * 22, px),
                 with: .color(Color(red: 0.35, green: 0.26, blue: 0.18)))
        // Desk legs
        ctx.fill(rect(x + px,       y + px * 4, px * 2, px * 8),
                 with: .color(Color(red: 0.40, green: 0.30, blue: 0.20)))
        ctx.fill(rect(x + px * 19,  y + px * 4, px * 2, px * 8),
                 with: .color(Color(red: 0.40, green: 0.30, blue: 0.20)))

        // Monitor stand
        ctx.fill(rect(x + px * 9, y - px * 2, px * 4, px * 2),
                 with: .color(Color(white: 0.25)))
        // Monitor bezel
        ctx.fill(rect(x + px * 5, y - px * 12, px * 12, px * 10),
                 with: .color(Color(white: 0.15)))
        // Screen glow — cyan when working, red when error
        let screenColor: Color = isError ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 0.2, green: 0.9, blue: 0.8)
        ctx.fill(rect(x + px * 6, y - px * 11, px * 10, px * 8),
                 with: .color(screenColor.opacity(0.85)))
        // Screen "code lines" animation
        if !isError {
            let lineOffset = tick % 4
            for row in 0..<3 {
                let lineW = px * CGFloat([5, 8, 3][row])
                ctx.fill(rect(x + px * 7, y - px * 10 + CGFloat(row + lineOffset % 3) * px * 2, lineW, px),
                         with: .color(Color(white: 1, opacity: 0.5)))
            }
        }

        // Keyboard
        ctx.fill(rect(x + px * 5, y + px * 1, px * 8, px * 2),
                 with: .color(Color(white: 0.30)))

        // Seated agent
        drawSeatedAgent(ctx, deskX: x, deskY: y, worker: worker)
    }

    private func drawSeatedAgent(_ ctx: GraphicsContext, deskX: CGFloat, deskY: CGFloat, worker: SwarmWorker) {
        let color = agentColor(worker)
        let isError = worker.status.rawValue.lowercased() == "error"

        // Agent sits just in front of desk; chair seat at deskY + px*4
        let ax = deskX + px * 8
        let chairY = deskY + px * 4

        // Chair seat
        ctx.fill(rect(ax - px, chairY, px * 6, px * 2),
                 with: .color(Color(white: 0.22)))
        // Chair back
        ctx.fill(rect(ax, chairY - px * 5, px * 4, px * 5),
                 with: .color(Color(white: 0.20)))

        // Body (torso)
        ctx.fill(rect(ax, chairY - px * 9, px * 4, px * 4),
                 with: .color(color))
        // Head
        ctx.fill(rect(ax + px, chairY - px * 13, px * 3, px * 3),
                 with: .color(Color(red: 0.95, green: 0.82, blue: 0.65)))
        // Eyes — blink every ~3s
        let eyeOpen = tick % 22 != 0
        if eyeOpen {
            ctx.fill(rect(ax + px,         chairY - px * 12, px, px),
                     with: .color(.black))
            ctx.fill(rect(ax + px * 3 - px, chairY - px * 12, px, px),
                     with: .color(.black))
        }
        // Error exclamation on head
        if isError {
            ctx.fill(rect(ax + px * 2, chairY - px * 16, px, px * 3),
                     with: .color(.red))
        }

        // Arms — typing animation (alternate up/down)
        let armY = tick % 2 == 0 ? chairY - px * 8 : chairY - px * 7
        ctx.fill(rect(ax - px * 2, armY, px * 2, px * 2), with: .color(color))
        ctx.fill(rect(ax + px * 4, armY, px * 2, px * 2), with: .color(color))

        // Legs folded under chair
        ctx.fill(rect(ax,          chairY, px * 2, px * 3), with: .color(color.opacity(0.8)))
        ctx.fill(rect(ax + px * 2, chairY, px * 2, px * 3), with: .color(color.opacity(0.8)))
    }

    // MARK: Sleep Corner

    private func drawSleepCorner(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let sleepers = workers.filter { WorkerKind($0) == .sleeping }
        guard !sleepers.isEmpty else { return }

        let cornerX: CGFloat = px * 4
        let cornerY = h - px * 18

        // Sleep mat / couch base
        ctx.fill(rect(cornerX, cornerY + px * 6, px * CGFloat(max(sleepers.count, 1)) * 14 + px * 4, px * 4),
                 with: .color(Color(red: 0.28, green: 0.22, blue: 0.45)))
        ctx.fill(rect(cornerX, cornerY + px * 5, px * CGFloat(max(sleepers.count, 1)) * 14 + px * 4, px),
                 with: .color(Color(red: 0.38, green: 0.30, blue: 0.55)))

        for (i, worker) in sleepers.enumerated() {
            drawSleepingAgent(ctx, x: cornerX + px * 2 + CGFloat(i) * px * 14, y: cornerY, worker: worker)
        }
    }

    private func drawSleepingAgent(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, worker: SwarmWorker) {
        let color = agentColor(worker)

        // Body horizontal
        ctx.fill(rect(x, y + px * 6, px * 10, px * 3), with: .color(color))
        // Head
        ctx.fill(rect(x + px * 10, y + px * 5, px * 3, px * 3),
                 with: .color(Color(red: 0.95, green: 0.82, blue: 0.65)))
        // Closed eyes
        ctx.fill(rect(x + px * 11, y + px * 6, px * 2, px),
                 with: .color(Color(white: 0.1)))
        // Pillow
        ctx.fill(rect(x + px * 13, y + px * 5, px * 4, px * 4),
                 with: .color(Color(white: 0.75)))

        // ZZZ floating up (cycles through 3 positions)
        let zzPhase = (tick / 5 + Int(x / 10)) % 9
        let zzOpacity: [Double] = [0.9, 0.8, 0.65, 0.5, 0.35, 0.2, 0.1, 0.05, 0.0]
        let zzYOffsets: [CGFloat] = [0, -px*2, -px*4, -px*6, -px*8, -px*10, -px*12, -px*14, -px*16]
        for j in 0..<3 {
            let phase = (zzPhase + j * 3) % 9
            let zzX = x + px * 12 + CGFloat(j) * px * 2
            let zzY = y + px * 2 + zzYOffsets[phase]
            ctx.fill(rect(zzX, zzY, px * 2, px * 2),
                     with: .color(Color(white: 0.85, opacity: zzOpacity[phase])))
        }
    }

    // MARK: Walking Agents (Idle)

    private func drawAgents(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, floorY: CGFloat) {
        let idleWorkers = workers.filter { WorkerKind($0) == .idle }
        let floorH = h - floorY - px * 4
        let walkY = floorY + floorH * 0.35

        for worker in idleWorkers {
            let xFrac = walkPos[worker.id] ?? 0.5
            let dir = walkDir[worker.id] ?? 1
            let ax = w * xFrac
            drawWalkingAgent(ctx, x: ax, y: walkY, dir: dir, worker: worker)
        }
    }

    private func drawWalkingAgent(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, dir: CGFloat, worker: SwarmWorker) {
        let color = agentColor(worker)
        let walkFrame = tick % 4

        // Head
        ctx.fill(rect(x - px,     y - px * 12, px * 4, px * 3),
                 with: .color(Color(red: 0.95, green: 0.82, blue: 0.65)))
        // Eyes (face direction)
        let eyeX = dir > 0 ? x + px : x - px
        ctx.fill(rect(eyeX, y - px * 11, px, px), with: .color(.black))

        // Body
        ctx.fill(rect(x - px, y - px * 9, px * 4, px * 4), with: .color(color))

        // Arms swing with walk
        let armSwing: CGFloat = walkFrame < 2 ? -px : px
        ctx.fill(rect(x - px * 3, y - px * 9 + armSwing, px * 2, px * 3), with: .color(color))
        ctx.fill(rect(x + px * 3, y - px * 9 - armSwing, px * 2, px * 3), with: .color(color))

        // Legs alternate
        let leg1Y: CGFloat = walkFrame % 2 == 0 ? 0 : px * 2
        let leg2Y: CGFloat = walkFrame % 2 == 0 ? px * 2 : 0
        ctx.fill(rect(x - px,     y - px * 5 + leg1Y, px * 2, px * 4), with: .color(color.opacity(0.85)))
        ctx.fill(rect(x + px,     y - px * 5 + leg2Y, px * 2, px * 4), with: .color(color.opacity(0.85)))

        // Shadow
        ctx.fill(rect(x - px * 2, y + px, px * 6, px),
                 with: .color(Color(white: 0, opacity: 0.25)))
    }

    // MARK: Name Labels (overlay)

    private func drawNameLabels(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, floorY: CGFloat) {
        let deskWorkers = workers.filter { WorkerKind($0) == .working }
        let deskW: CGFloat = px * 22
        let spacing = min((w - deskW) / CGFloat(max(deskWorkers.count, 1)), deskW + px * 10)
        let startX = (w - spacing * CGFloat(max(deskWorkers.count - 1, 0)) - deskW) / 2

        for (i, worker) in deskWorkers.enumerated() {
            let cx = startX + CGFloat(i) * spacing + deskW / 2
            let labelY = floorY - px * 30
            drawLabel(ctx, text: worker.name, cx: cx, y: labelY, color: agentColor(worker))
        }

        let idleWorkers = workers.filter { WorkerKind($0) == .idle }
        let floorH = h - floorY - px * 4
        let walkY = floorY + floorH * 0.35

        for worker in idleWorkers {
            let xFrac = walkPos[worker.id] ?? 0.5
            let cx = w * xFrac + px
            drawLabel(ctx, text: worker.name, cx: cx, y: walkY - px * 16, color: agentColor(worker))
        }

        let sleepers = workers.filter { WorkerKind($0) == .sleeping }
        for (i, worker) in sleepers.enumerated() {
            let cx = px * 4 + px * 2 + CGFloat(i) * px * 14 + px * 7
            let labelY = h - px * 25
            drawLabel(ctx, text: worker.name, cx: cx, y: labelY, color: agentColor(worker))
        }
    }

    private func drawLabel(_ ctx: GraphicsContext, text: String, cx: CGFloat, y: CGFloat, color: Color) {
        let resolved = ctx.resolve(Text(text).font(.system(size: 9, weight: .medium)).foregroundColor(color))
        let size = resolved.measure(in: CGSize(width: 120, height: 20))
        ctx.draw(resolved, at: CGPoint(x: cx - size.width / 2, y: y), anchor: .topLeading)
    }

    // MARK: Helper

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(CGRect(x: x, y: y, width: max(w, 0), height: max(h, 0)))
    }
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
