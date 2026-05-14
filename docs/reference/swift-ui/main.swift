import SwiftUI
import Foundation

// ─── Model ───
struct Msg: Identifiable { let id = UUID(); let me: Bool; let text: String }

// ─── Brain ───
@MainActor final class Brain: ObservableObject {
    @Published var messages: [Msg] = []
    @Published var thinking = false
    @Published var status = "..."

    func check() async {
        guard let u = URL(string: "http://localhost:9876/health") else { return }
        if let (d, _) = try? await URLSession.shared.data(from: u),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String:Any],
           j["status"] as? String == "ok" { status = "connected" }
        else { status = "offline" }
    }

    func ask(_ text: String) {
        messages.append(Msg(me: true, text: text))
        thinking = true
        Task {
            guard let u = URL(string: "http://localhost:9876/think") else { return }
            var r = URLRequest(url: u)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["text":text, "session_id":"app"])
            if let (d, _) = try? await URLSession.shared.data(for: r),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String:Any] {
                let reply = j["text"] as? String ?? j["response"] as? String ?? "..."
                messages.append(Msg(me: false, text: reply))
            } else { messages.append(Msg(me: false, text: "No connection.")) }
            thinking = false
        }
    }
}

// ─── App Entry ───
@main struct ARESApp: App {
    @StateObject private var brain = Brain()
    var body: some Scene {
        WindowGroup { ChatView(brain: brain).frame(minWidth: 360, minHeight: 480) }
    }
}

// ─── Chat ───
struct ChatView: View {
    @ObservedObject var brain: Brain
    @State private var input = ""
    @FocusState private var f: Bool

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(brain: brain)
            Divider()
            MessageList(brain: brain)
            Divider()
            InputBar(input: $input, f: $f, brain: brain) { send() }
        }
        .background(.ultraThinMaterial)
        .task { await brain.check(); f = true }
    }

    func send() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        input = ""; brain.ask(t)
    }
}

// ─── Status Bar ───
struct StatusBar: View {
    @ObservedObject var brain: Brain
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.purple.opacity(brain.thinking ? 0.35 : 0.10))
                    .frame(width: 22, height: 22)
                    .scaleEffect(brain.thinking ? 1.3 : 1.0)
                Circle()
                    .fill(brain.status == "connected" ? .purple.opacity(brain.thinking ? 0.9 : 0.5) : .gray.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("ARES").font(.system(size: 12, weight: .semibold))
                Text(brain.thinking ? "thinking..." : brain.status)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }
}

// ─── Message List ───
struct MessageList: View {
    @ObservedObject var brain: Brain
    var body: some View {
        ScrollViewReader { p in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(brain.messages) { m in Bubble(msg: m) }
                    if brain.thinking { ThinkingLine().id("t") }
                    if brain.messages.isEmpty && !brain.thinking { WelcomeLine() }
                }
                .padding(12)
            }
            .onChange(of: brain.messages.count) { _ in scrollToLast(p) }
            .onChange(of: brain.thinking) { if $0 { p.scrollTo("t") } }
        }
    }
    func scrollToLast(_ p: ScrollViewProxy) {
        if let l = brain.messages.last { p.scrollTo(l.id) }
    }
}

// ─── Bubble ───
struct Bubble: View {
    let msg: Msg

    var bg: AnyShapeStyle {
        msg.me ? AnyShapeStyle(.purple.opacity(0.1)) : AnyShapeStyle(.ultraThinMaterial)
    }

    var body: some View {
        HStack {
            if msg.me { Spacer(minLength: 40) }
            Text(msg.text)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(bg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            if !msg.me { Spacer(minLength: 40) }
        }
    }
}

// ─── Thinking ───
struct ThinkingLine: View {
    var body: some View {
        HStack {
            Circle().fill(.purple.opacity(0.4)).frame(width: 5, height: 5)
            Text("thinking").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// ─── Welcome ───
struct WelcomeLine: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 40)
            Text("✦").font(.largeTitle).foregroundStyle(.purple.opacity(0.5))
            Text("Your twin. Ask anything.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// ─── Input ───
struct InputBar: View {
    @Binding var input: String
    var f: FocusState<Bool>.Binding
    @ObservedObject var brain: Brain
    let send: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("...", text: $input)
                .textFieldStyle(.plain)
                .focused(f)
                .onSubmit { send() }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(input.isEmpty ? .gray : .purple)
            }
            .disabled(input.isEmpty || brain.thinking)
            .buttonStyle(.plain)
        }
        .padding(10)
    }
}
