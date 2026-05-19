import AppKit
import SwiftUI

struct KanbanTaskLogSheet: View {
    let taskTitle: String
    let log: String?
    let isLoading: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Worker Log"))
                        .font(.title3.weight(.semibold))

                    Text(taskTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            if isLoading && log == nil {
                HermesLoadingState(label: "Loading log…", minHeight: 180)
                    .padding(24)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(log ?? L10n.string("(No log output)"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(log == nil ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(NSColor.textBackgroundColor))

                HStack {
                    Spacer()
                    Button(L10n.string("Close"), action: onDismiss)
                        .buttonStyle(.bordered)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 560, idealWidth: 700, maxWidth: .infinity, minHeight: 400, idealHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
