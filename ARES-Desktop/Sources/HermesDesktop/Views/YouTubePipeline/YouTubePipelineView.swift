import SwiftUI

struct YouTubePipelineView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedVideoID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var videos: [YouTubeVideoEntry] = []
    @State private var editingVideo: YouTubeVideoEntry?
    @State private var draftTitle = ""
    @State private var draftDescription = ""
    @State private var draftTags = ""
    @State private var isSaving = false

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 22) {
                HermesPageHeader(
                    title: "YouTube Pipeline",
                    subtitle: "Review, edit metadata and approve staged videos for publishing."
                ) {
                    HermesExpandableSearchField(
                        text: $searchText,
                        prompt: L10n.string("Search videos"),
                        expandedWidth: 220,
                        focusRequestID: appState.searchFocusRequestID
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                pipelineToolbar
                pipelineContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: appState.activeConnectionID) {
            await loadVideos()
        }
    }

    private var pipelineToolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await loadVideos() }
            } label: {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string("Loading…"))
                    }
                } else {
                    Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)

            Spacer()

            if let editingVideo {
                Button {
                    Task { await saveEdits(for: editingVideo) }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Label(L10n.string("Save Metadata"), systemImage: "checkmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isSaving || !hasDraftChanges)

                Button {
                    clearEditor()
                } label: {
                    Label(L10n.string("Cancel"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSaving)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pipelineContent: some View {
        if isLoading && videos.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading pipeline…", minHeight: 300)
            }
        } else if let errorMessage, videos.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load pipeline"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if videos.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No pending videos"),
                    systemImage: "play.rectangle",
                    description: Text(L10n.string("No staged videos found in the YouTube pipeline."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: "Select a video to edit metadata, approve or reject."
            ) {
                if filteredVideos.isEmpty {
                    ContentUnavailableView(
                        L10n.string("No matching videos"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.string("Try searching by title, channel or tag."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredVideos) { video in
                                YouTubeVideoRow(
                                    video: video,
                                    isSelected: selectedVideoID == video.id,
                                    isEditing: editingVideo?.id == video.id,
                                    draftTitle: $draftTitle,
                                    draftDescription: $draftDescription,
                                    draftTags: $draftTags,
                                    onSelect: { selectVideo(video) },
                                    onApprove: { Task { await approve(video) } },
                                    onReject: { Task { await reject(video) } },
                                    onEdit: { startEditing(video) }
                                )
                                .disabled(isSaving)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && !videos.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    private var panelTitle: String {
        let total = videos.count
        let filtered = filteredVideos.count
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Pending Videos (%@)", "\(total)")
        }
        return L10n.string("Pending Videos (%@ of %@)", "\(filtered)", "\(total)")
    }

    private var filteredVideos: [YouTubeVideoEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return videos }
        let query = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return videos.filter { video in
            let haystacks = [video.title, video.channelName, video.description ?? ""]
            return haystacks.contains { value in
                value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .localizedStandardContains(query)
            }
        }
    }

    private var hasDraftChanges: Bool {
        guard let editingVideo else { return false }
        if draftTitle != editingVideo.title { return true }
        if draftDescription != (editingVideo.description ?? "") { return true }
        if draftTags != editingVideo.tags.joined(separator: ",") { return true }
        return false
    }

    private func loadVideos() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        errorMessage = nil
        do {
            let items = try await appState.youtubePipelineService.listPending(connection: connection, limit: 50)
            guard !Task.isCancelled else { return }
            self.videos = items
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func selectVideo(_ video: YouTubeVideoEntry) {
        guard editingVideo?.id != video.id else { return }
        selectedVideoID = video.id
    }

    private func startEditing(_ video: YouTubeVideoEntry) {
        editingVideo = video
        selectedVideoID = video.id
        draftTitle = video.title
        draftDescription = video.description ?? ""
        draftTags = video.tags.joined(separator: ",")
    }

    private func clearEditor() {
        editingVideo = nil
        draftTitle = ""
        draftDescription = ""
        draftTags = ""
    }

    private func saveEdits(for video: YouTubeVideoEntry) async {
        guard let connection = appState.activeConnection else { return }
        isSaving = true
        let tagList = draftTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        do {
            try await appState.youtubePipelineService.approveVideo(
                connection: connection,
                videoID: video.id,
                title: draftTitle,
                description: draftDescription,
                tags: tagList
            )
            clearEditor()
            await loadVideos()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func approve(_ video: YouTubeVideoEntry) async {
        guard let connection = appState.activeConnection else { return }
        isSaving = true
        do {
            try await appState.youtubePipelineService.approveVideo(
                connection: connection,
                videoID: video.id,
                title: nil,
                description: nil,
                tags: nil
            )
            clearEditor()
            await loadVideos()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func reject(_ video: YouTubeVideoEntry) async {
        guard let connection = appState.activeConnection else { return }
        isSaving = true
        do {
            try await appState.youtubePipelineService.rejectVideo(
                connection: connection,
                videoID: video.id
            )
            clearEditor()
            await loadVideos()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct YouTubeVideoRow: View {
    let video: YouTubeVideoEntry
    let isSelected: Bool
    let isEditing: Bool
    @Binding var draftTitle: String
    @Binding var draftDescription: String
    @Binding var draftTags: String
    let onSelect: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnailView

                VStack(alignment: .leading, spacing: 8) {
                    Text(video.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(isEditing ? nil : 1)

                    HStack(spacing: 8) {
                        HermesBadge(
                            text: video.status.displayTitle,
                            tint: tintForStatus(video.status),
                            prominence: .strong
                        )

                        Text(video.channelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let uploadDate = video.uploadDate, !uploadDate.isEmpty {
                            Text(uploadDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if isEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.string("Title"), text: $draftTitle)
                                .textFieldStyle(.roundedBorder)

                            TextEditor(text: $draftDescription)
                                .frame(minHeight: 60, maxHeight: 120)
                                .font(.callout)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )

                            TextField(L10n.string("Tags (comma-separated)"), text: $draftTags)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 4)
                    } else {
                        if let description = video.description, !description.isEmpty {
                            Text(description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !video.tags.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(video.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.10))
                                        )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isEditing {
                    VStack(alignment: .trailing, spacing: 8) {
                        Button {
                            onEdit()
                        } label: {
                            Label(L10n.string("Edit"), systemImage: "pencil")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(L10n.string("Edit metadata"))

                        Button {
                            onApprove()
                        } label: {
                            Label(L10n.string("Approve"), systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(L10n.string("Approve for publishing"))
                        .tint(.green)

                        Button {
                            onReject()
                        } label: {
                            Label(L10n.string("Reject"), systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(L10n.string("Reject video"))
                        .tint(.red)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(isSelected ? HermesTheme.selectedFill : HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? HermesTheme.selectedStroke : HermesTheme.subtleStroke, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = video.thumbnailURL, let url = URL(string: thumbnailURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if phase.error != nil {
                    thumbnailPlaceholder
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: 80, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 28))
            .foregroundStyle(.secondary.opacity(0.4))
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HermesTheme.insetFill)
            )
    }

    private func tintForStatus(_ status: YouTubeVideoStatus) -> Color {
        switch status.tint {
        case .amber: return .orange
        case .green: return .green
        case .red: return .red
        case .blue: return .blue
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    private struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
