import AppKit
import SwiftUI

struct KanbanFormField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct KanbanActionDisclosureRow<Content: View>: View {
    let title: String
    let summary: String
    let systemImage: String
    let isExpanded: Bool
    let isDisabled: Bool
    let onToggle: () -> Void
    let content: Content

    init(
        title: String,
        summary: String,
        systemImage: String,
        isExpanded: Bool,
        isDisabled: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.isDisabled = isDisabled
        self.onToggle = onToggle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 11) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string(title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(L10n.string(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            if isExpanded {
                content
                    .padding(.leading, 29)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
}

struct KanbanActionDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 29)
            .opacity(0.55)
    }
}

struct KanbanTextEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 68)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.string(placeholder))
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct ComboBoxTextField: View {
    @Binding var text: String
    let suggestions: [String]
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(L10n.string(placeholder), text: $text)
                .textFieldStyle(.roundedBorder)
                .layoutPriority(1)

            if !suggestions.isEmpty {
                Menu {
                    Button(L10n.string("Unassigned")) {
                        text = ""
                    }

                    Divider()

                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            text = suggestion
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help(L10n.string("Pick a discovered assignee"))
            }
        }
    }
}

struct KanbanIDGroup: View {
    let title: String
    let ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)

            if ids.isEmpty {
                Text(L10n.string("None"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HermesWrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(ids, id: \.self) { id in
                        HermesBadge(text: id, tint: .secondary, isMonospaced: true)
                    }
                }
            }
        }
    }
}

struct KanbanCommentRow: View {
    let comment: KanbanComment

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))

                    Text(DateFormatters.relativeFormatter().localizedString(for: comment.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(comment.body)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}

struct KanbanRunRow: View {
    let run: KanbanRun

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HermesBadge(text: "#\(run.id)", tint: .secondary, isMonospaced: true)
                    HermesBadge(text: run.resolvedOutcome, tint: run.endedAt == nil ? .orange : .secondary)

                    if let profile = run.profile {
                        HermesBadge(text: "@\(profile)", tint: .accentColor, isMonospaced: true)
                    }
                }

                Text(DateFormatters.shortDateTimeFormatter().string(from: run.startedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summary = run.summary {
                    Text(summary)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }

                if let error = run.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct KanbanEventRow: View {
    let event: KanbanEvent

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HermesBadge(text: event.kind, tint: .secondary)

                    if let runID = event.runID {
                        HermesBadge(text: "run \(runID)", tint: .secondary, isMonospaced: true)
                    }

                    Spacer(minLength: 8)

                    Text(DateFormatters.relativeFormatter().localizedString(for: event.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let payload = event.displayPayload {
                    Text(payload)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct KanbanHomeChannelRow: View {
    let homeChannel: KanbanHomeChannel
    let isDisabled: Bool
    let onToggle: () async -> Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: homeChannel.subscribed ? "bell.badge.fill" : "bell")
                .foregroundStyle(homeChannel.subscribed ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(homeChannel.displayPlatform)
                    .font(.subheadline.weight(.semibold))

                Text("\(homeChannel.resolvedName) · \(homeChannel.destinationLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            toggleButton
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var toggleButton: some View {
        if homeChannel.subscribed {
            Button(L10n.string("Subscribed")) {
                Task { _ = await onToggle() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isDisabled)
        } else {
            Button(L10n.string("Subscribe")) {
                Task { _ = await onToggle() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
        }
    }
}

struct KanbanRecoveryWarningSummary: View {
    let warnings: KanbanTaskWarnings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(warnings.displayMessage))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    HermesBadge(text: L10n.string("%@ warning events", "\(warnings.count)"), tint: .orange)

                    if let latestDate = warnings.latestDate {
                        Text(DateFormatters.relativeFormatter().localizedString(for: latestDate, relativeTo: .now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }
}
