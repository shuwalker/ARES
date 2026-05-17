import SwiftUI

struct SecondBrainView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var results: [SecondBrainResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedResultID: String?

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 22) {
                HermesPageHeader(
                    title: "Second Brain",
                    subtitle: "Search LanceDB embeddings for documents, sessions and skills discovered on the active host."
                )

                searchBar
                resultsContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField(L10n.string("Search Second Brain…"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        results = []
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                    .fill(HermesTheme.insetFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                    .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
            }

            Button {
                performSearch()
            } label: {
                Label(L10n.string("Search"), systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var resultsContent: some View {
        if isLoading {
            HermesSurfacePanel {
                HermesLoadingState(label: "Searching Second Brain…", minHeight: 240)
            }
        } else if let errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Search failed"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        } else if results.isEmpty {
            if searchText.isEmpty {
                HermesSurfacePanel {
                    ContentUnavailableView(
                        L10n.string("Start searching"),
                        systemImage: "brain",
                        description: Text(L10n.string("Enter a query above to search the Second Brain LanceDB."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            } else {
                HermesSurfacePanel {
                    ContentUnavailableView(
                        L10n.string("No results"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.string("No documents matched your query."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        } else {
            HermesSurfacePanel(
                title: "Search Results",
                subtitle: "\(results.count) document(s) matched from LanceDB."
            ) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(results) { result in
                            SecondBrainResultRow(
                                result: result,
                                isExpanded: expandedResultID == result.id
                            ) {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                    if expandedResultID == result.id {
                                        expandedResultID = nil
                                    } else {
                                        expandedResultID = result.id
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let connection = appState.activeConnection else { return }

        isLoading = true
        errorMessage = nil
        results = []
        expandedResultID = nil

        Task {
            do {
                let searchResults = try await appState.secondBrainService.searchSecondBrain(
                    query: trimmed,
                    limit: 20,
                    connection: connection
                )
                guard !Task.isCancelled else { return }
                self.results = searchResults
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}

private struct SecondBrainResultRow: View {
    let result: SecondBrainResult
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(isExpanded ? nil : 1)

                    Text(sourceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HermesBadge(
                    text: scoreText,
                    tint: relevanceColor,
                    systemImage: "chart.bar.fill",
                    prominence: .subtle
                )

                Button(action: action) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Text(result.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(result.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: isExpanded ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }

    private var sourceText: String {
        result.source.isEmpty ? "Unknown source" : result.source
    }

    private var scoreText: String {
        String(format: "%.2f", result.relevanceScore)
    }

    private var relevanceColor: Color {
        if result.relevanceScore >= 0.75 {
            return .green
        } else if result.relevanceScore >= 0.5 {
            return .orange
        }
        return .secondary
    }
}
