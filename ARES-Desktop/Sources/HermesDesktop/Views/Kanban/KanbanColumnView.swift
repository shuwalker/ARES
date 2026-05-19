import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [KanbanTask]
    let selectedTaskID: String?
    let onSelect: (KanbanTask) -> Void
    let onDrop: (String) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            LazyVStack(alignment: .leading, spacing: 8) {
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(tasks) { task in
                        KanbanTaskCard(
                            task: task,
                            isSelected: task.id == selectedTaskID,
                            onSelect: { onSelect(task) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            isDropTarget
                ? KanbanColors.tint(for: status).opacity(0.08)
                : Color.secondary.opacity(0.026),
            in: RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(
                    isDropTarget ? KanbanColors.tint(for: status).opacity(0.6) : HermesTheme.subtleStroke,
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: String.self) { object, _ in
                guard let taskID = object as? String else { return }
                DispatchQueue.main.async { onDrop(taskID) }
            }
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTarget)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(KanbanColors.tint(for: status))
                .frame(width: 7, height: 7)

            Text(L10n.string(status.displayTitle))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("\(tasks.count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(KanbanColors.tint(for: status).opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        Text(L10n.string("No tasks"))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
    }
}

struct KanbanTaskCard: View {
    let task: KanbanTask
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: (() -> Void)?

    init(
        task: KanbanTask,
        isSelected: Bool,
        isChecked: Bool = false,
        onSelect: @escaping () -> Void,
        onToggleCheck: (() -> Void)? = nil
    ) {
        self.task = task
        self.isSelected = isSelected
        self.isChecked = isChecked
        self.onSelect = onSelect
        self.onToggleCheck = onToggleCheck
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if let onToggleCheck {
                        Button(action: onToggleCheck) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .onTapGesture {
                            onToggleCheck()
                        }
                    }

                    Text(task.resolvedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    priorityBadge
                }

                if let body = task.trimmedBody {
                    Text(body.replacingOccurrences(of: "\n", with: " "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                metadataStrip
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? HermesTheme.selectedFill : isHovering ? Color.secondary.opacity(0.07) : HermesTheme.rowFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? HermesTheme.selectedStroke : HermesTheme.subtleStroke, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 9)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onDrag { NSItemProvider(object: task.id as NSString) }
        .contextMenu {
            Button(L10n.string("Copy Task ID")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.id, forType: .string)
            }
        }
    }

    private var priorityBadge: some View {
        Text(task.priorityLabel)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(task.priority == 0 ? Color.secondary : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((task.priority == 0 ? Color.secondary : Color.orange).opacity(0.10), in: Capsule())
    }

    private var metadataStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HermesWrappingFlowLayout(horizontalSpacing: 7, verticalSpacing: 5) {
                KanbanTaskMetadataChip(text: task.shortID, systemImage: "number", isMonospaced: true)

                if let assignee = task.assignee {
                    KanbanTaskMetadataChip(text: "@\(assignee)", systemImage: "person.crop.circle", tint: .accentColor, isMonospaced: true)
                }

                if let tenant = task.tenant {
                    KanbanTaskMetadataChip(text: tenant, systemImage: "building.2")
                }

                if task.commentCount > 0 {
                    KanbanTaskMetadataChip(text: "\(task.commentCount)", systemImage: "text.bubble")
                }

                if let progress = task.progressLabel {
                    KanbanTaskMetadataChip(text: progress, systemImage: "checkmark.circle", tint: .green, isMonospaced: true)
                }

                if !task.parentIDs.isEmpty {
                    KanbanTaskMetadataChip(text: "\(task.parentIDs.count)", systemImage: "link")
                }

                if task.hasActiveWarnings {
                    KanbanTaskMetadataChip(text: "\(task.warnings?.count ?? 0)", systemImage: "exclamationmark.triangle", tint: .orange, isMonospaced: true)
                }
            }

            if let latest = task.latestActivityDate {
                Text(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: latest, relativeTo: .now)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct KanbanTaskMetadataChip: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary
    var isMonospaced = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))

            Text(text)
                .font(isMonospaced ? .system(.caption2, design: .monospaced).weight(.semibold) : .caption2.weight(.medium))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct KanbanEmptyTaskState: View {
    let isFiltering: Bool
    let isSaving: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )

            if !isFiltering {
                Button {
                    onCreate()
                } label: {
                    Label(L10n.string("Create Task"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var title: String {
        isFiltering ? L10n.string("No matching tasks") : L10n.string("No tasks")
    }

    private var systemImage: String {
        isFiltering ? "magnifyingglass" : "checklist"
    }

    private var description: String {
        if isFiltering {
            return L10n.string("Try a different search, status, assignee, tenant, or archive filter.")
        }

        return L10n.string("Choose a task from the selected board, or create a new one.")
    }
}

struct KanbanWarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct KanbanToolbarMenuLabel: View {
    let title: String
    let value: String
    let systemImage: String
    let width: CGFloat

    var body: some View {
        Label {
            HStack(spacing: 5) {
                Text(L10n.string(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
}
