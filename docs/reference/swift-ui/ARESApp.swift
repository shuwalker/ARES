import SwiftUI
import MetalSplatter
import AVFoundation
import Foundation

// ─── App Entry ─────────────────────────────────────

@main
struct ARESApp: App {
    @StateObject private var world = ARESWorld()
    @StateObject private var voice = VoiceManager()
    
    var body: some Scene {
        WindowGroup {
            ARESRootView()
                .environmentObject(world)
                .environmentObject(voice)
                .frame(minWidth: 900, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(CGSize(width: 1100, height: 750))
        
        MenuBarExtra("ARES", systemImage: "circle.hexagonpath") {
            MenuBarView()
                .environmentObject(world)
        }
    }
}

// ─── HTTP Client ────────────────────────────────────

actor HTTPClient {
    static let shared = HTTPClient()
    private let baseURL = "http://localhost:9876"
    private let session: URLSession
    private(set) var backendReachable = false
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }
    
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "ok" else {
                backendReachable = false
                return false
            }
            backendReachable = true
            return true
        } catch {
            backendReachable = false
            return false
        }
    }
    
    func think(text: String, sessionID: String) async -> (response: String, state: String, expression: String) {
        guard let url = URL(string: "\(baseURL)/think") else {
            return ("Backend URL invalid. Check localhost:9876.", "error", "concerned")
        }
        
        let body: [String: Any] = ["text": text, "session_id": sessionID]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return ("Failed to encode request.", "error", "concerned")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ("Backend returned an unexpected response.", "error", "concerned")
            }
            let reply = json["response"] as? String ?? "No response field in backend reply."
            let state = json["state"] as? String ?? "idle"
            let expression = json["expression"] as? String ?? "neutral"
            backendReachable = true
            return (reply, state, expression)
        } catch {
            backendReachable = false
            return ("Cognition backend unreachable. Running local fallback.", "error", "concerned")
        }
    }
}

// ─── ARES World State ──────────────────────────────

@MainActor
class ARESWorld: ObservableObject {
    @Published var immersionLevel: ImmersionLevel = .light
    @Published var entityType: EntityType = .sphere
    @Published var showLaunchAnimation = true
    @Published var agentState = AgentState.idle
    @Published var messages: [ARESMessage] = []
    @Published var inputText = ""
    @Published var roomModelURL: URL?
    @Published var backendConnected = false
    @Published var avatarExpression = AvatarExpression.neutral
    
    private let sessionID = UUID().uuidString
    
    func onAppear() {
        // Health check backend connectivity at startup
        Task {
            let reachable = await HTTPClient.shared.checkHealth()
            await MainActor.run {
                self.backendConnected = reachable
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 1.2)) {
                self.showLaunchAnimation = false
                self.agentState = .awakened
            }
        }
    }
    
    func cycleImmersion() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            let all = ImmersionLevel.allCases
            let idx = all.firstIndex(of: immersionLevel)!
            immersionLevel = all[(idx + 1) % all.count]
        }
    }
    
    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let clean = text.trimmingCharacters(in: .whitespaces)
        messages.append(ARESMessage(text: clean, isUser: true))
        inputText = ""
        agentState = .thinking
        avatarExpression = .thinking
        
        Task {
            let (response, backendState, backendExpression) = await cognitionQuery(clean)
            await MainActor.run {
                messages.append(ARESMessage(text: response, isUser: false))
                agentState = agentStateFromBackend(backendState)
                avatarExpression = expressionFromBackend(backendExpression)
            }
        }
    }
    
    func handleVoiceInput(_ transcript: String) {
        guard !transcript.isEmpty else { return }
        sendMessage(transcript)
    }
    
    private func cognitionQuery(_ text: String) async -> (response: String, state: String, expression: String) {
        // Try backend first
        let result = await HTTPClient.shared.think(text: text, sessionID: sessionID)
        
        // If backend returned an error, fall back to stub
        if result.state == "error" {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let stub = "I heard you say: \"\(text)\". My deeper reasoning loop is still coming online."
            return (stub, "idle", "concerned")
        }
        
        return result
    }
    
    private func agentStateFromBackend(_ raw: String) -> AgentState {
        switch raw {
        case "idle":       return .idle
        case "thinking":   return .thinking
        case "speaking":   return .speaking
        case "listening":  return .listening
        case "awakened":   return .awakened
        default:           return .idle
        }
    }
    
    private func expressionFromBackend(_ raw: String) -> AvatarExpression {
        AvatarExpression(rawValue: raw) ?? .neutral
    }
}

// ─── Immersion Levels ──────────────────────────────

enum ImmersionLevel: String, CaseIterable, Codable {
    case light
    case medium
    case full
    
    var label: String {
        switch self {
        case .light:  return "Desktop"
        case .medium: return "Window"
        case .full:   return "Room"
        }
    }
    
    var icon: String {
        switch self {
        case .light:  return "square.stack.3d.up"
        case .medium: return "rectangle.center.inset.filled"
        case .full:   return "cube.transparent"
        }
    }
    
    var description: String {
        switch self {
        case .light:  return "Sits on top of desktop"
        case .medium: return "Focused agent window"
        case .full:   return "Enter the agent's room"
        }
    }
}

enum EntityType: String, CaseIterable, Codable {
    case sphere
    case abstract
    case avatar
}

enum AgentState: String, Codable {
    case idle, awakened, listening, thinking, speaking, sleeping
}

enum AvatarExpression: String, Codable {
    case neutral, happy, curious, thinking, surprised, concerned, excited, sleepy
}

struct ARESMessage: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// ─── Root View ─────────────────────────────────────

struct ARESRootView: View {
    @EnvironmentObject var world: ARESWorld
    @EnvironmentObject var voice: VoiceManager
    
    var body: some View {
        ZStack {
            backgroundLayer
            
            if world.showLaunchAnimation {
                LaunchRipple()
                    .transition(.opacity)
                    .zIndex(1000)
            }
            
            VStack(spacing: 0) {
                ImmersionBar()
                AgentView()
                ChatStream()
                CommandBar()
            }
            .opacity(world.showLaunchAnimation ? 0 : 1)
            .animation(.easeIn(duration: 1.0).delay(1.8), value: world.showLaunchAnimation)
        }
        .task {
            world.onAppear()
        }
        .onChange(of: voice.transcript) { _, text in
            if !text.isEmpty && !voice.isListening {
                world.handleVoiceInput(text)
            }
        }
    }
    
    @ViewBuilder
    var backgroundLayer: some View {
        if world.immersionLevel == .full {
            Color.black.ignoresSafeArea()
        } else {
            VisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

// ─── Launch Ripple Animation ───────────────────────

struct LaunchRipple: View {
    @State private var elapsed: Double = 0
    let duration: Double = 2.5
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince1970
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height)
                
                // Dark water surface
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.black.opacity(0.85)))
                
                // Ripple rings
                for i in 0..<6 {
                    let delay = Double(i) * 0.25
                    let p = ((t - delay) / 2.0).truncatingRemainder(dividingBy: 1.0)
                    let r = p * maxR
                    let alpha = (1 - p) * (0.5 - Double(i) * 0.06)
                    
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                width: r * 2, height: r * 2)),
                        with: .color(.cyan.opacity(max(0, alpha))),
                        lineWidth: 1.5
                    )
                }
                
                // Droplet impact point — fades out
                let dropletAlpha = max(0, 1 - t / 1.5)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)),
                    with: .color(.white.opacity(dropletAlpha))
                )
            }
        }
    }
}

// ─── Immersion Bar ─────────────────────────────────

struct ImmersionBar: View {
    @EnvironmentObject var world: ARESWorld
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(ImmersionLevel.allCases, id: \.self) { level in
                Button {
                    withAnimation(.spring(response: 0.5)) { world.immersionLevel = level }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: level.icon)
                        Text(level.label)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(world.immersionLevel == level
                        ? .white.opacity(0.15) : .clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Text(world.agentState.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
            
            Text(world.avatarExpression.rawValue.capitalized)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.trailing, 4)
            
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }
    
    var stateColor: Color {
        switch world.agentState {
        case .idle:      return .blue
        case .awakened:  return .cyan
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .purple
        case .sleeping:  return .gray
        }
    }
}

// ─── Agent View — Anime Black Fire Entity ──────────

struct AgentView: View {
    @EnvironmentObject var world: ARESWorld
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if world.immersionLevel == .full, let url = world.roomModelURL {
                    SplatRoom(model: url)
                }
                AnimeFireEntity(state: world.agentState, expression: world.avatarExpression)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// ─── Anime Fire Entity ─────────────────────────────

struct AnimeFireEntity: View {
    let state: AgentState
    let expression: AvatarExpression
    
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince1970
                let cx = size.width / 2
                let cy = size.height * 0.5
                let intensity = min(1.0, fireIntensity + expressionBoost)
                let scale = min(size.width, size.height) * 0.45
                
                drawAnimeFire(&ctx, cx: cx, cy: cy, scale: scale, time: t, intensity: intensity, expression: expression, isSpeaking: state == .speaking)
            }
        }
    }
    
    var fireIntensity: CGFloat {
        switch state {
        case .idle:      return 0.20
        case .awakened:  return 0.40
        case .listening: return 0.45
        case .thinking:  return 0.85
        case .speaking:  return 0.60
        case .sleeping:  return 0.05
        }
    }
    
    var expressionBoost: CGFloat {
        switch expression {
        case .neutral:   return 0.00
        case .happy:     return 0.08
        case .curious:   return 0.05
        case .thinking:  return 0.12
        case .surprised: return 0.18
        case .concerned: return 0.04
        case .excited:   return 0.22
        case .sleepy:    return -0.03
        }
    }
}

func drawAnimeFire(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double, intensity: CGFloat, expression: AvatarExpression, isSpeaking: Bool) {
    guard intensity > 0.01 else { return }
    let tint = expressionTint(expression)
    
    // ─── 3-layer anime fire: core → mid → wisps ───
    // Each layer = multiple flame tongues with Bezier curves
    
    // Core flame — bright violet/white hot center
    if intensity > 0.1 {
        for i in 0..<3 {
            let baseX = cx + sin(time * 1.4 + Double(i) * 2.1) * scale * 0.06
            let height = scale * (0.5 + intensity * 0.4)
            let width = scale * (0.22 + intensity * 0.08)
            let flicker = sin(time * 6.0 + Double(i) * 3.3) * 0.06 + sin(time * 9.0 + Double(i)) * 0.04
            
            var flame = Path()
            let tipX = baseX + sin(time * 3.5 + Double(i)) * width * 0.3
            let tipY = cy - height * (1.0 + flicker)
            
            flame.move(to: CGPoint(x: baseX, y: cy + scale * 0.15))
            flame.addCurve(
                to: CGPoint(x: tipX, y: tipY),
                control1: CGPoint(x: baseX - width * 0.8, y: cy - height * 0.4),
                control2: CGPoint(x: tipX - width * 0.3, y: tipY + height * 0.3)
            )
            flame.addCurve(
                to: CGPoint(x: baseX, y: cy + scale * 0.15),
                control1: CGPoint(x: tipX + width * 0.3, y: tipY + height * 0.3),
                control2: CGPoint(x: baseX + width * 0.8, y: cy - height * 0.4)
            )
            flame.closeSubpath()
            
            // Core: bright violet-white
            ctx.fill(flame, with: .color(.init(red: tint.coreRed, green: tint.coreGreen, blue: tint.coreBlue, opacity: 0.9 * intensity)))
        }
    }
    
    // Mid flame — dark violet/purple body
    if intensity > 0.05 {
        for i in 0..<5 {
            let baseX = cx + sin(time * 1.1 + Double(i) * 1.4) * scale * 0.08
            let height = scale * (0.65 + intensity * 0.5)
            let width = scale * (0.28 + intensity * 0.12)
            let flicker = sin(time * 4.5 + Double(i) * 2.7) * 0.08 + sin(time * 7.0 + Double(i) * 1.3) * 0.05
            let swayX = sin(time * 2.0 + Double(i) * 0.7) * width * 0.25
            
            var flame = Path()
            let tipX = baseX + swayX
            let tipY = cy - height * (1.0 + flicker)
            
            flame.move(to: CGPoint(x: baseX, y: cy + scale * 0.15))
            flame.addCurve(
                to: CGPoint(x: tipX, y: tipY),
                control1: CGPoint(x: baseX - width * 0.9, y: cy - height * 0.35),
                control2: CGPoint(x: tipX - width * 0.4, y: tipY + height * 0.25)
            )
            flame.addCurve(
                to: CGPoint(x: baseX, y: cy + scale * 0.15),
                control1: CGPoint(x: tipX + width * 0.4, y: tipY + height * 0.25),
                control2: CGPoint(x: baseX + width * 0.9, y: cy - height * 0.35)
            )
            flame.closeSubpath()
            
            // Mid: deep violet
            let midAlpha = 0.7 * intensity
            ctx.fill(flame, with: .color(.init(red: tint.midRed, green: tint.midGreen, blue: tint.midBlue, opacity: midAlpha)))
        }
    }
    
    // Outer wisps — black/dark charcoal, wide, slow
    if intensity > 0.03 {
        for i in 0..<7 {
            let baseX = cx + sin(time * 0.8 + Double(i) * 1.0) * scale * 0.1
            let height = scale * (0.8 + intensity * 0.6)
            let width = scale * (0.35 + intensity * 0.18)
            let flicker = sin(time * 3.0 + Double(i) * 2.0) * 0.10 + sin(time * 5.5 + Double(i)) * 0.06
            let swayX = sin(time * 1.5 + Double(i) * 0.55) * width * 0.35
            
            var flame = Path()
            let tipX = baseX + swayX
            let tipY = cy - height * (1.0 + flicker)
            
            flame.move(to: CGPoint(x: baseX, y: cy + scale * 0.15))
            flame.addCurve(
                to: CGPoint(x: tipX, y: tipY),
                control1: CGPoint(x: baseX - width * 1.0, y: cy - height * 0.3),
                control2: CGPoint(x: tipX - width * 0.5, y: tipY + height * 0.2)
            )
            flame.addCurve(
                to: CGPoint(x: baseX, y: cy + scale * 0.15),
                control1: CGPoint(x: tipX + width * 0.5, y: tipY + height * 0.2),
                control2: CGPoint(x: baseX + width * 1.0, y: cy - height * 0.3)
            )
            flame.closeSubpath()
            
            // Outer: near-black with violet edge tint
            let outerAlpha = 0.65 * intensity * (0.7 + abs(sin(time * 2.0 + Double(i))) * 0.3)
            ctx.fill(flame, with: .color(.init(red: 0.06, green: 0.01, blue: 0.18, opacity: outerAlpha)))
            
            // Thin violet outline on outer wisps (anime cell-shade edge)
            if intensity > 0.3 {
                ctx.stroke(flame, with: .color(.init(red: 0.35, green: 0.1, blue: 0.6, opacity: outerAlpha * 0.5)), lineWidth: 1.5)
            }
        }
    }
    
    // ─── Floating ember sparks ──────────────────────
    if intensity > 0.15 {
        let sparkCount = Int(intensity * 20)
        for i in 0..<sparkCount {
            let angle = time * 2.0 + sin(time * 3.0 + Double(i)) * 1.0
            let dist = scale * (0.5 + sin(time * 4.0 + Double(i) * 1.7) * 0.4 + intensity * 0.6)
            let sx = cx + cos(angle) * dist
            let sy = cy - scale * 0.3 + sin(time * 5.0 + Double(i)) * scale * 0.7
            let sparkAlpha = intensity * 0.4 * abs(sin(time * 6.0 + Double(i) * 2.0))
            let sparkSize = 1.5 + intensity * 3.0
            
            ctx.fill(
                Path(ellipseIn: CGRect(x: sx - sparkSize/2, y: sy - sparkSize/2, width: sparkSize, height: sparkSize)),
                with: .color(.init(red: 0.5, green: 0.15, blue: 0.9, opacity: sparkAlpha))
            )
        }
    }
    
    // ─── Eyes in the fire (awakens at medium intensity) ──
    if intensity > 0.2 {
        let eyeY = cy - scale * 0.08
        let eyeSpacing = scale * 0.12
        let eyeW = scale * 0.07
        let eyeH = scale * 0.05
        
        for side: CGFloat in [-1, 1] {
            let ex = cx + side * eyeSpacing
            
            // Sharp angled eye (anime villain style)
            var eyePath = Path()
            eyePath.move(to: CGPoint(x: ex - eyeW, y: eyeY))
            eyePath.addLine(to: CGPoint(x: ex + eyeW, y: eyeY - eyeH * 0.7))
            eyePath.addLine(to: CGPoint(x: ex + eyeW, y: eyeY + eyeH * 0.5))
            eyePath.addLine(to: CGPoint(x: ex - eyeW, y: eyeY + eyeH * 0.9))
            eyePath.closeSubpath()
            
            // Glowing white-hot eye
            let eyeGlow = intensity * 0.9
            ctx.fill(eyePath, with: .color(.init(red: 0.9, green: 0.85, blue: 1.0, opacity: eyeGlow)))
            
            // Pupil — narrow vertical slit
            let pupilX = ex + sin(time * 1.5) * eyeW * 0.2
            ctx.fill(
                Path(ellipseIn: CGRect(x: pupilX - eyeW * 0.12, y: eyeY - eyeH * 0.35,
                                        width: eyeW * 0.4, height: eyeH * 0.8)),
                with: .color(.black.opacity(0.95))
            )
        }
    }
    
    // ─── Mouth — appears when speaking ──────────────
    if isSpeaking {
        let mouthY = cy + scale * 0.08
        let mouthW = scale * 0.1
        let amp = abs(sin(time * 10)) * mouthW * 0.8
        var mouth = Path()
        mouth.move(to: CGPoint(x: cx - mouthW, y: mouthY))
        mouth.addCurve(
            to: CGPoint(x: cx + mouthW, y: mouthY),
            control1: CGPoint(x: cx - mouthW * 0.3, y: mouthY + amp),
            control2: CGPoint(x: cx + mouthW * 0.3, y: mouthY + amp)
        )
        ctx.stroke(mouth, with: .color(.init(red: 0.7, green: 0.6, blue: 1.0, opacity: 0.7)), lineWidth: 2)
    }
}

func expressionTint(_ expression: AvatarExpression) -> (coreRed: Double, coreGreen: Double, coreBlue: Double, midRed: Double, midGreen: Double, midBlue: Double) {
    switch expression {
    case .happy:
        return (0.65, 0.55, 1.0, 0.26, 0.12, 0.52)
    case .curious:
        return (0.45, 0.75, 1.0, 0.10, 0.25, 0.52)
    case .thinking:
        return (0.85, 0.45, 0.85, 0.35, 0.08, 0.45)
    case .surprised:
        return (0.85, 0.85, 1.0, 0.25, 0.20, 0.55)
    case .concerned:
        return (0.45, 0.45, 0.85, 0.08, 0.08, 0.32)
    case .excited:
        return (0.85, 0.35, 1.0, 0.38, 0.05, 0.55)
    case .sleepy:
        return (0.40, 0.35, 0.70, 0.06, 0.04, 0.22)
    case .neutral:
        return (0.65, 0.30, 1.0, 0.25, 0.08, 0.50)
    }
}

// ─── Splat Room ────────────────────────────────────

struct SplatRoom: View {
    let model: URL
    
    var body: some View {
        Color.clear.overlay(
            VStack(spacing: 12) {
                Image(systemName: "cube.transparent").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Room View").font(.headline).foregroundStyle(.secondary)
                Text(model.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
            }
        )
    }
}

// ─── Chat Stream ───────────────────────────────────

struct ChatStream: View {
    @EnvironmentObject var world: ARESWorld
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(world.messages) { msg in
                        ChatBubble(msg: msg)
                    }
                }
                .padding(12)
            }
            .onChange(of: world.messages.count) { _, _ in
                if let last = world.messages.last {
                    withAnimation { proxy.scrollTo(last.id) }
                }
            }
        }
        .frame(height: 140)
        .background(.ultraThinMaterial.opacity(0.4))
    }
}

struct ChatBubble: View {
    let msg: ARESMessage
    
    var body: some View {
        HStack {
            if msg.isUser { Spacer() }
            Text(msg.text)
                .font(.callout)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(msg.isUser ? .blue.opacity(0.5) : .white.opacity(0.08))
                .cornerRadius(10)
                .foregroundColor(msg.isUser ? .white : .primary)
                .frame(maxWidth: 420, alignment: msg.isUser ? .trailing : .leading)
            if !msg.isUser { Spacer() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// ─── Command Bar ────────────────────────────────────

struct CommandBar: View {
    @EnvironmentObject var world: ARESWorld
    @EnvironmentObject var voice: VoiceManager
    @FocusState private var focused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Divider().background(.white.opacity(0.08))
            HStack(spacing: 10) {
                TextField("Talk to ARES...", text: $world.inputText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .cornerRadius(9)
                    .onSubmit { world.sendMessage(world.inputText) }
                
                Button {
                    if voice.isListening {
                        voice.stopListening()
                        world.handleVoiceInput(voice.transcript)
                    } else {
                        voice.startListening()
                    }
                } label: {
                    Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundColor(voice.isListening ? .green : .secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    world.sendMessage(world.inputText)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(world.inputText.isEmpty ? .secondary.opacity(0.4) : .blue)
                }
                .buttonStyle(.plain)
                .disabled(world.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}

// ─── Menu Bar ──────────────────────────────────────

struct MenuBarView: View {
    @EnvironmentObject var world: ARESWorld
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ARES").font(.headline)
            Text(world.agentState.rawValue.capitalized).font(.caption).foregroundColor(.secondary)
            Divider()
            Button("Show ARES") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            ForEach(ImmersionLevel.allCases, id: \.self) { lvl in
                Button(lvl.label) { world.immersionLevel = lvl }
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 200)
    }
}

// ─── Helpers ───────────────────────────────────────

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
