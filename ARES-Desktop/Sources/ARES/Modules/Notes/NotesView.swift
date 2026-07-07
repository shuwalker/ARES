import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var selectedNote: Note?
    @State private var searchText = ""

    var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.body.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            // Left pane — note list
            VStack(spacing: 0) {
                HStack {
                    Text("Notes").font(.title2).bold()
                    Spacer()
                    Button(action: addNote) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .padding()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                List(filteredNotes, id: \.id, selection: $selectedNote) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(note.body)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .tag(note)
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            // Right pane — editor
            if let note = selectedNote {
                NoteEditorView(note: note)
            } else {
                Text("Select a note or create a new one.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func addNote() {
        let note = Note()
        context.insert(note)
        selectedNote = note
    }
}

struct NoteEditorView: View {
    @Bindable var note: Note

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $note.title)
                .font(.title3).fontWeight(.semibold)
                .textFieldStyle(.plain)
                .padding([.horizontal, .top])
                .onChange(of: note.title) { _, _ in note.updatedAt = Date() }

            Divider().padding(.top, 8)

            TextEditor(text: $note.body)
                .font(.body)
                .padding(.horizontal, 8)
                .onChange(of: note.body) { _, _ in note.updatedAt = Date() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
