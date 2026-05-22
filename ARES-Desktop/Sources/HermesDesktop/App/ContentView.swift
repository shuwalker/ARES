import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AresAppState()

    var body: some View {
        ZStack {
            if appState.isConnected {
                TabView {
                    // Status Tab
                    StatusView(appState: appState)
                        .tabItem {
                            Image(systemName: "info.circle")
                            Text("Status")
                        }

                    // Chat Tab
                    ChatView(appState: appState)
                        .tabItem {
                            Image(systemName: "message")
                            Text("Chat")
                        }

                    // Memory Tab
                    MemoryView(appState: appState)
                        .tabItem {
                            Image(systemName: "brain")
                            Text("Memory")
                        }
                }
                .onAppear {
                    Task {
                        await appState.refresh()
                    }
                }
            } else {
                ConnectionErrorView(appState: appState)
            }
        }
        .alert("Error", isPresented: .constant(appState.errorMessage != nil), presenting: appState.errorMessage) { msg in
            Button("Dismiss") { appState.errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }
}

// MARK: - Status View

struct StatusView: View {
    @ObservedObject var appState: AresAppState

    var body: some View {
        NavigationStack {
            List {
                if let identity = appState.identity {
                    Section("Identity") {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(identity.name).fontWeight(.bold)
                        }
                        HStack {
                            Text("Role")
                            Spacer()
                            Text(identity.role)
                        }
                    }
                }

                if let status = appState.status {
                    Section("System") {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(status.version)
                        }
                        HStack {
                            Text("Face State")
                            Spacer()
                            Text(status.faceState).fontWeight(.bold)
                        }
                        HStack {
                            Text("Connected Clients")
                            Spacer()
                            Text("\(status.websocketClients)")
                        }
                    }
                }

                if let faceState = appState.faceState {
                    Section("Face") {
                        HStack {
                            Text("Current State")
                            Spacer()
                            Text(faceState.state).fontWeight(.bold)
                        }
                    }
                }
            }
            .navigationTitle("ARES Status")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task {
                            await appState.refresh()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var appState: AresAppState

    var body: some View {
        NavigationStack {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.chatMessages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                        .onChange(of: appState.chatMessages.count) { _, _ in
                            if let lastId = appState.chatMessages.last?.id {
                                proxy.scrollTo(lastId)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("Message...", text: $appState.chatInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task {
                                await appState.sendMessage()
                            }
                        }

                    Button(action: {
                        Task {
                            await appState.sendMessage()
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(appState.chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Chat")
        }
    }
}

struct ChatBubble: View {
    let message: AresAppState.ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .frame(maxWidth: 300, alignment: .trailing)
            } else {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    .frame(maxWidth: 300, alignment: .leading)
                Spacer()
            }
        }
    }
}

// MARK: - Memory View

struct MemoryView: View {
    @ObservedObject var appState: AresAppState

    var body: some View {
        NavigationStack {
            List {
                if appState.memory.isEmpty {
                    Text("No memories yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.memory, id: \.id) { hit in
                        VStack(alignment: .leading) {
                            Text(hit.text)
                                .lineLimit(3)
                            Text("Score: \(String(format: "%.2f", hit.score))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task {
                            await appState.refresh()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Connection Error View

struct ConnectionErrorView: View {
    @ObservedObject var appState: AresAppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("ARES Daemon Not Running")
                .font(.title2)
                .fontWeight(.bold)

            Text("To start ARES, open Terminal and run:")
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text("ares start")
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }

            Button("Try Again", action: {
                Task {
                    await appState.checkConnection()
                }
            })
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
