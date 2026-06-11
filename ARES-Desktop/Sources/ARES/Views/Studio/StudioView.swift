import SwiftUI
import ARESCore

struct StudioView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var files: [URL] = []
    @State private var selectedFile: URL? = nil
    @State private var fileContent: String = ""
    @State private var isSaving = false
    
    let baseDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("GitHub/ARES")
    }()

    var body: some View {
        NavigationSplitView {
            List(files, id: \.self, selection: $selectedFile) { url in
                Text(url.lastPathComponent)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(ARESColors.textSecondary)
            }
            .navigationTitle("ARES Modules")
            .onChange(of: selectedFile) { oldSelection, newSelection in
                loadFile()
            }
        } detail: {
            if let file = selectedFile {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent)
                                .font(.headline)
                                .foregroundStyle(ARESColors.textPrimary)
                            Text(file.path)
                                .font(.caption2)
                                .foregroundStyle(ARESColors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button {
                            saveFile()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text(isSaving ? "SAVING..." : "SAVE")
                                    .fontWeight(.bold)
                                    .tracking(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(ARESColors.gold)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    .padding()
                    .background(ARESColors.surface)
                    
                    Divider().background(ARESColors.divider)
                    
                    CodeEditor(text: $fileContent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 48))
                        .foregroundStyle(ARESColors.textTertiary.opacity(0.5))
                    Text("Developer Studio")
                        .font(.headline)
                        .foregroundStyle(ARESColors.textPrimary)
                    Text("Select a module to edit live. Changes take effect on next launch.")
                        .font(.subheadline)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ARESColors.background)
            }
        }
        .background(ARESColors.background)
        .onAppear {
            loadFiles()
        }
    }

    private func loadFiles() {
        guard FileManager.default.fileExists(atPath: baseDirectory.path) else { return }
        let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        var found: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            // Ignore build directories and non-source files
            if url.path.contains(".build") || url.path.contains("DerivedData") {
                continue
            }
            if ["swift", "py", "json", "md", "sh"].contains(url.pathExtension) {
                found.append(url)
            }
        }
        files = found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadFile() {
        guard let url = selectedFile else { return }
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            fileContent = "Error loading file: \(error.localizedDescription)"
        }
    }

    private func saveFile() {
        guard let url = selectedFile else { return }
        isSaving = true
        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save: \(error)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
        }
    }
}
