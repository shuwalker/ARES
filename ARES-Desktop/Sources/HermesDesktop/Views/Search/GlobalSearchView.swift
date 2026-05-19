import SwiftUI

// MARK: - Result types

private enum GlobalSearchResult: Identifiable {
    case session(SessionSummary)
    case file(WorkspaceFileReference)
    case skill(SkillSummary)

    var id: String {
        switch self {
        case .session(let s): "session:\(s.id)"
        case .file(let f): "file:\(f.id)"
        case .skill(let sk): "skill:\(sk.id)"
        }
    }
}

// MARK: - GlobalSearchView

struct GlobalSearchView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var debouncedQuery = ""
    @FocusState private var isFieldFocused: Bool

    // MARK: Computed results

    private var sessionResults: [SessionSummary] {
        guard !debouncedQuery.isEmpty else { return [] }
        let q = debouncedQuery.lowercased()
        let all = (appState.pinnedSessionSummaries + appState.sessions).uniqued(by: \.id)
        return all.filter { session in
            session.id.lowercased().contains(q) ||
            (session.resolvedTitle.lowercased().contains(q)) ||
            (session.preview?.lowercased().contains(q) == true)
        }
    }

    private var fileResults: [WorkspaceFileReference] {
        guard !debouncedQuery.isEmpty else { return [] }
        let q = debouncedQuery.lowercased()
        return appState.workspaceFileReferences.filter { ref in
            ref.title.lowercased().contains(q) ||
            ref.remotePath.lowercased().contains(q)
        }
    }

    private var skillResults: [SkillSummary] {
        guard !debouncedQuery.isEmpty else { return [] }
        return appState.skills.filter { $0.matchesSearch(debouncedQuery) }
    }

    private var hasAnyResults: Bool {
        !sessionResults.isEmpty || !fileResults.isEmpty || !skillResults.isEmpty
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 560, height: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: query) { _, newValue in
            scheduleDebouncedSearch(query: newValue)
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(L10n.string("Search sessions, files, skills\u{2026}"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFieldFocused)
                .onSubmit { dismissIfEmpty() }

            if !query.isEmpty {
                Button {
                    query = ""
                    debouncedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.string("Clear search"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Results list

    @ViewBuilder
    private var resultsList: some View {
        if query.isEmpty {
            emptyQueryPlaceholder
        } else if debouncedQuery.isEmpty || !hasAnyResults {
            if debouncedQuery.isEmpty {
                // Still waiting for debounce — show nothing yet
                Color.clear
            } else {
                noResultsView
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !sessionResults.isEmpty {
                        sectionHeader(L10n.string("Sessions"))
                        ForEach(sessionResults) { session in
                            sessionResultRow(session)
                        }
                    }

                    if !fileResults.isEmpty {
                        sectionHeader(L10n.string("Files"))
                        ForEach(fileResults) { file in
                            fileResultRow(file)
                        }
                    }

                    if !skillResults.isEmpty {
                        sectionHeader(L10n.string("Skills"))
                        ForEach(skillResults) { skill in
                            skillResultRow(skill)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyQueryPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.string("Type to search sessions, files, and skills"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        ContentUnavailableView(
            L10n.string("No results for \u{201C}%@\u{201D}", debouncedQuery),
            systemImage: "magnifyingglass",
            description: Text(L10n.string("Try a different search term."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: Session result row

    private func sessionResultRow(_ session: SessionSummary) -> some View {
        Button {
            navigateToSession(session)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.resolvedTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(session.id)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if appState.isSessionPinned(session.id) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SearchResultButtonStyle())
    }

    // MARK: File result row

    private func fileResultRow(_ file: WorkspaceFileReference) -> some View {
        Button {
            navigateToFile(file)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(file.remotePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SearchResultButtonStyle())
    }

    // MARK: Skill result row

    private func skillResultRow(_ skill: SkillSummary) -> some View {
        Button {
            navigateToSkill(skill)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.resolvedName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let description = skill.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SearchResultButtonStyle())
    }

    // MARK: Navigation

    private func navigateToSession(_ session: SessionSummary) {
        dismiss()
        appState.requestSectionSelection(.sessions)
        Task {
            await appState.loadSessionDetail(sessionID: session.id)
        }
    }

    private func navigateToFile(_ file: WorkspaceFileReference) {
        dismiss()
        appState.requestSectionSelection(.files)
        appState.selectedWorkspaceFileID = file.id
    }

    private func navigateToSkill(_ skill: SkillSummary) {
        dismiss()
        appState.requestSectionSelection(.skills)
        appState.selectedSkillID = skill.id
        Task {
            await appState.loadSkillDetail(summary: skill)
        }
    }

    private func dismiss() {
        isPresented = false
    }

    private func dismissIfEmpty() {
        if query.isEmpty { dismiss() }
    }

    // MARK: Debounce

    private func scheduleDebouncedSearch(query: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedQuery = query
            }
        }
    }
}

// MARK: - Button style

private struct SearchResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.accentColor.opacity(0.10)
                    : Color.clear
            )
    }
}

// MARK: - Array uniqued helper

private extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
