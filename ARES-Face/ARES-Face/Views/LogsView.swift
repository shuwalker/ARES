import SwiftUI

/// Hermes agent log viewer. Reads from :9119/api/logs.
struct LogsView: View {
    @State private var lines: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lineCount = 100
    @State private var filterText = ""
    
    var filteredLines: [(Int, String)] {
        let all = Array(lines.enumerated())
        guard !filterText.isEmpty else { return all.map { ($0.offset, $0.element) } }
        return all.filter { $0.element.localizedCaseInsensitiveContains(filterText) }
            .map { ($0.offset, $0.element) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Agent Log").font(.headline)
                Spacer()
                Text("\(filteredLines.count) lines").font(.caption).foregroundStyle(.secondary)
                
                Picker("Lines", selection: $lineCount) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("200").tag(200)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: lineCount) { _, _ in loadLogs() }
                
                Button("Refresh") { loadLogs() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            
            // Filter
            HStack {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
            
            // Log lines
            if isLoading {
                Spacer()
                ProgressView("Loading logs...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadLogs() }.buttonStyle(.bordered)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLines, id: \.0) { (idx, line) in
                            LogLineView(line: line, index: idx)
                        }
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
            }
        }
        .onAppear { loadLogs() }
    }
    
    private func loadLogs() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                lines = try await HermesDashboardService.shared.getLogs(lines: lineCount)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct LogLineView: View {
    let line: String
    let index: Int
    
    var levelColor: Color {
        if line.contains(" ERROR ") || line.contains(" CRITICAL ") { return .red }
        if line.contains(" WARNING ") || line.contains(" WARN ") { return .orange }
        if line.contains(" INFO ") || line.contains("info") { return .secondary }
        if line.contains(" DEBUG ") { return .gray.opacity(0.5) }
        return .secondary
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(index)")
                .foregroundStyle(.gray.opacity(0.4))
                .frame(width: 40, alignment: .trailing)
            Text(line)
                .foregroundStyle(levelColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
}