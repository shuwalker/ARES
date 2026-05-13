import SwiftUI

struct ChatStream: View {
    @EnvironmentObject var brain: BrainConnection
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(brain.messages) { msg in
                        ChatBubble(msg: msg)
                    }
                }
                .padding(12)
            }
            .onChange(of: brain.messages.count) { _, _ in
                if let last = brain.messages.last {
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