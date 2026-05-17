import AppKit
import SwiftUI

private let sessionDetailBottomID = "session-detail-bottom"
private let approvalNeededMessage = "Hermes requested command approval, but this chat turn cannot collect manual approvals. Retry this turn with Auto-approve enabled, or resume the session in Terminal to review the command yourself."
private let autoApproveHelpText = "Approves command requests for this turn. Without it, approval-required commands may be blocked in chat."

private func sessionMessageScrollID(_ message: SessionMessageDisplay) -> String {
    "session-message-\(message.id)"
}

private func pendingTurnScrollID(_ turn: PendingSessionTurn) -> String {
    "pending-turn-\(turn.id.uuidString)"
}

private enum SessionScrollReason {
    case sessionChanged
    case messagesLoaded
    case pendingTurnChanged
    case messagesChangedWhilePending

    var delay: DispatchTimeInterval {
        switch self {
        case .sessionChanged:
            return .milliseconds(120)
        case .messagesLoaded:
            return .milliseconds(60)
        case .pendingTurnChanged:
            return .milliseconds(40)
        case .messagesChangedWhilePending:
            return .milliseconds(80)
        }
    }

    var followUpDelay: DispatchTimeInterval? {
        switch self {
        case .sessionChanged:
            return .milliseconds(360)
        case .messagesLoaded:
            return .milliseconds(220)
        case .pendingTurnChanged:
            return .milliseconds(140)
        case .messagesChangedWhilePending:
            return nil
        }
    }

    var animated: Bool {
        switch self {
        case .sessionChanged, .messagesLoaded:
            return false
        case .pendingTurnChanged:
            return true
        case .messagesChangedWhilePending:
            return false
        }
    }
}

private struct SessionScrollRequest: Equatable {
    let id = UUID()
    let reason: SessionScrollReason?

    init(reason: SessionScrollReason? = nil) {
        self.reason = reason
    }

    var isPending: Bool {
        reason != nil
    }
}

struct SessionDetailView: View {
    let session: SessionSummary?
    let messages: [SessionMessageDisplay]
    let errorMessage: String?
    let conversationError: String?
    let isSendingMessage: Bool
    let isDeletingSession: Bool
    let pendingTurn: PendingSessionTurn?
    let isActive: Bool
    let savedScrollOffset: CGFloat?
    let onSaveScrollOffset: (String, CGFloat?) -> Void
    let onResumeInTerminal: (SessionSummary) -> Void
    let onDeleteSession: (SessionSummary) async -> Void
    let onStartSession: (String, Bool) async -> Bool
    let onSendMessage: (String, Bool) async -> Bool

    @State private var showDeleteConfirmation = false
    @State private var scrollRequest = SessionScrollRequest()
    @State private var expandedMetadataMessageIDs: Set<String> = []
    @State private var scrollMetrics = SessionScrollMetrics()
    @State private var scrollOffsetRestoreRequestID = UUID()
    @State private var shouldAutoScrollNextMessageLoad = true

    private var latestMessageScrollKey: String {
        "\(messages.count):\(messages.last?.id ?? "none")"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        scrollContent

                        Color.clear
                            .frame(height: 1)
                            .id(sessionDetailBottomID)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                }
                .background {
                    SessionScrollOffsetObserver(
                        sessionID: session?.id,
                        savedOffset: savedScrollOffset,
                        restoreRequestID: scrollOffsetRestoreRequestID,
                        onSaveOffset: onSaveScrollOffset,
                        onMetricsChange: { metrics in
                            scrollMetrics = metrics
                        }
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    if shouldShowJumpToLatestButton {
                        Button {
                            requestScrollToLatest(proxy, reason: .pendingTurnChanged)
                        } label: {
                            Label(L10n.string("Jump to Latest"), systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(18)
                        .transition(.opacity)
                        .help(L10n.string("Scroll to the latest message"))
                    }
                }
                .onChange(of: session?.id) { _, _ in
                    expandedMetadataMessageIDs.removeAll()
                    shouldAutoScrollNextMessageLoad = true
                    restoreSavedScrollOffsetOrScrollToLatest(proxy)
                }
                .onChange(of: latestMessageScrollKey) { _, _ in
                    guard session != nil, !messages.isEmpty else { return }
                    handleMessageScrollChange(proxy)
                }
                .onChange(of: pendingTurn?.id) { _, _ in
                    requestScrollToLatest(proxy, reason: .pendingTurnChanged)
                }
                .task(id: session?.id) {
                    restoreSavedScrollOffsetOrScrollToLatest(proxy)
                }
            }

            Divider()
                .opacity(0.6)

            composerDock
        }
        .alert(L10n.string("Delete this session?"), isPresented: $showDeleteConfirmation, presenting: session) { session in
            Button(L10n.string("Delete"), role: .destructive) {
                Task {
                    await onDeleteSession(session)
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { session in
            Text(L10n.string(
                "“%@” will be removed from Hermes Desktop and deleted on the remote Hermes host as well. This action cannot be undone.",
                session.resolvedTitle
            ))
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        if let session {
            SessionSummaryPanel(
                session: session,
                isDeleting: isDeletingSession,
                onDelete: { showDeleteConfirmation = true }
            )

            if let errorMessage {
                HermesSurfacePanel {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            transcriptContent(for: session)
        } else if let pendingTurn, pendingTurn.sessionID == nil {
            HermesSurfacePanel(
                title: "Starting Session"
            ) {
                PendingSessionTurnView(turn: pendingTurn, showPrompt: true)
                    .id(pendingTurnScrollID(pendingTurn))
            }
        } else {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Start or select a session"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(L10n.string("Write below to begin a new Hermes conversation, or choose an existing session from the list."))
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    @ViewBuilder
    private func transcriptContent(for session: SessionSummary) -> some View {
        let matchingPendingTurn = pendingTurn?.sessionID == session.id ? pendingTurn : nil

        if messages.isEmpty && matchingPendingTurn == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No transcript entries"),
                    systemImage: "text.bubble",
                    description: Text(L10n.string("This session has no readable message rows yet."))
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        } else {
            HermesSurfacePanel(
                title: "Transcript",
                subtitle: "Messages are shown in the order Hermes stored them for this session."
            ) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageCard(
                            message: message,
                            isShowingMetadata: metadataExpansionBinding(for: message.id)
                        )
                        .id(sessionMessageScrollID(message))
                    }

                    if let matchingPendingTurn {
                        PendingSessionTurnView(
                            turn: matchingPendingTurn,
                            showPrompt: !messages.containsUserPrompt(matchingPendingTurn.prompt)
                        )
                        .id(pendingTurnScrollID(matchingPendingTurn))
                    }
                }
            }
        }
    }

    private var composerDock: some View {
        SessionComposerPanel(
            title: session == nil ? "New Session" : "Continue Session",
            placeholder: session == nil ? "Start a new Hermes session…" : "Write a reply to continue this session…",
            errorMessage: conversationError,
            isSending: isSendingMessage,
            onResumeInTerminal: session.map { selectedSession in
                { onResumeInTerminal(selectedSession) }
            },
            onSend: session == nil ? onStartSession : onSendMessage
        )
        .id(session?.id ?? "new-session")
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func metadataExpansionBinding(for messageID: String) -> Binding<Bool> {
        Binding {
            expandedMetadataMessageIDs.contains(messageID)
        } set: { isExpanded in
            if isExpanded {
                expandedMetadataMessageIDs.insert(messageID)
            } else {
                expandedMetadataMessageIDs.remove(messageID)
            }
        }
    }

    private var shouldShowJumpToLatestButton: Bool {
        guard session != nil,
              hasLatestTranscriptTarget,
              !scrollRequest.isPending else {
            return false
        }

        return scrollMetrics.distanceToBottom > 96
    }

    private var hasLatestTranscriptTarget: Bool {
        if !messages.isEmpty {
            return true
        }

        guard let pendingTurn else { return false }
        return pendingTurn.sessionID == nil || pendingTurn.sessionID == session?.id
    }

    private var isNearLatest: Bool {
        scrollMetrics.distanceToBottom <= 96
    }

    private func handleMessageScrollChange(_ proxy: ScrollViewProxy) {
        if pendingTurn != nil {
            shouldAutoScrollNextMessageLoad = false
            requestScrollToLatest(proxy, reason: .messagesChangedWhilePending)
            return
        }

        if shouldAutoScrollNextMessageLoad {
            shouldAutoScrollNextMessageLoad = false
            requestScrollToLatest(proxy, reason: .messagesLoaded)
            return
        }

        guard isActive, isNearLatest else { return }
        requestScrollToLatest(proxy, reason: .messagesLoaded)
    }

    private func restoreSavedScrollOffsetOrScrollToLatest(_ proxy: ScrollViewProxy) {
        if savedScrollOffset != nil {
            let request = SessionScrollRequest(reason: .sessionChanged)
            scrollRequest = request
            scrollOffsetRestoreRequestID = UUID()

            let followUpDelay = SessionScrollReason.sessionChanged.followUpDelay ?? .milliseconds(360)
            DispatchQueue.main.asyncAfter(deadline: .now() + followUpDelay) {
                guard scrollRequest == request else { return }
                scrollRequest = SessionScrollRequest()
            }
            return
        }

        requestScrollToLatest(proxy, reason: .sessionChanged)
    }

    private func requestScrollToLatest(_ proxy: ScrollViewProxy, reason: SessionScrollReason) {
        let request = SessionScrollRequest(reason: reason)
        scrollRequest = request

        scheduleScroll(
            proxy,
            request: request,
            target: latestScrollTarget,
            reason: reason,
            delay: reason.delay,
            completesRequest: reason.followUpDelay == nil
        )

        if let followUpDelay = reason.followUpDelay {
            scheduleScroll(
                proxy,
                request: request,
                target: latestScrollTarget,
                reason: reason,
                delay: followUpDelay,
                completesRequest: true
            )
        }
    }

    private func scheduleScroll(
        _ proxy: ScrollViewProxy,
        request: SessionScrollRequest,
        target: (id: String, anchor: UnitPoint),
        reason: SessionScrollReason,
        delay: DispatchTimeInterval,
        completesRequest: Bool
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard scrollRequest == request else { return }

            if reason.animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(target.id, anchor: target.anchor)
                }
            } else {
                proxy.scrollTo(target.id, anchor: target.anchor)
            }

            guard completesRequest else { return }
            scrollRequest = SessionScrollRequest()
        }
    }

    private var latestScrollTarget: (id: String, anchor: UnitPoint) {
        if let pendingTurn,
           pendingTurn.sessionID == nil || pendingTurn.sessionID == session?.id {
            return (pendingTurnScrollID(pendingTurn), .bottom)
        }

        if let lastMessage = messages.last {
            return (sessionMessageScrollID(lastMessage), .top)
        }

        return (sessionDetailBottomID, .bottom)
    }
}

private struct SessionScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0

    var distanceToBottom: CGFloat {
        max(0, maxOffset - offset)
    }
}

private struct SessionScrollOffsetObserver: NSViewRepresentable {
    let sessionID: String?
    let savedOffset: CGFloat?
    let restoreRequestID: UUID
    let onSaveOffset: (String, CGFloat?) -> Void
    let onMetricsChange: (SessionScrollMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SessionScrollOffsetProbeView {
        let view = SessionScrollOffsetProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SessionScrollOffsetProbeView, context: Context) {
        context.coordinator.configure(
            sessionID: sessionID,
            savedOffset: savedOffset,
            restoreRequestID: restoreRequestID,
            onSaveOffset: onSaveOffset,
            onMetricsChange: onMetricsChange
        )
        nsView.attachWhenReady()
    }

    final class Coordinator: NSObject, @unchecked Sendable {
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var sessionID: String?
        private var savedOffset: CGFloat?
        private var restoreRequestID: UUID?
        private var lastAppliedRestoreRequestID: UUID?
        private var isRestoring = false
        private var onSaveOffset: ((String, CGFloat?) -> Void)?
        private var onMetricsChange: ((SessionScrollMetrics) -> Void)?

        @MainActor
        func configure(
            sessionID: String?,
            savedOffset: CGFloat?,
            restoreRequestID: UUID,
            onSaveOffset: @escaping (String, CGFloat?) -> Void,
            onMetricsChange: @escaping (SessionScrollMetrics) -> Void
        ) {
            self.sessionID = sessionID
            self.savedOffset = savedOffset
            self.restoreRequestID = restoreRequestID
            self.onSaveOffset = onSaveOffset
            self.onMetricsChange = onMetricsChange
            restoreIfNeeded()
            reportCurrentOffset(shouldSave: false)
        }

        @MainActor
        func attach(to scrollView: NSScrollView?) {
            guard self.scrollView !== scrollView else {
                restoreIfNeeded()
                reportCurrentOffset(shouldSave: false)
                return
            }

            detach()
            self.scrollView = scrollView

            guard let scrollView else { return }
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reportCurrentOffset(shouldSave: true)
                }
            }

            if let documentView = scrollView.documentView {
                documentView.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.reportCurrentOffset(shouldSave: false)
                    }
                }
            }

            restoreIfNeeded()
            reportCurrentOffset(shouldSave: false)
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
        }

        @MainActor
        private func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            boundsObserver = nil
            frameObserver = nil
        }

        @MainActor
        private func restoreIfNeeded() {
            guard let restoreRequestID,
                  lastAppliedRestoreRequestID != restoreRequestID,
                  savedOffset != nil else {
                return
            }

            lastAppliedRestoreRequestID = restoreRequestID
            restoreSavedOffset(after: .milliseconds(40))
            restoreSavedOffset(after: .milliseconds(220))
        }

        @MainActor
        private func restoreSavedOffset(after delay: DispatchTimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      let scrollView,
                      let savedOffset else {
                    return
                }

                isRestoring = true
                let target = clampedOffset(savedOffset, in: scrollView)
                let clipView = scrollView.contentView
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target))
                scrollView.reflectScrolledClipView(clipView)
                reportCurrentOffset(shouldSave: false)

                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
                    guard let self else { return }
                    isRestoring = false
                    reportCurrentOffset(shouldSave: true)
                }
            }
        }

        @MainActor
        private func reportCurrentOffset(shouldSave: Bool) {
            guard let scrollView else { return }

            let offset = clampedOffset(scrollView.contentView.bounds.origin.y, in: scrollView)
            let metrics = SessionScrollMetrics(
                offset: offset,
                maxOffset: maxOffset(in: scrollView)
            )

            onMetricsChange?(metrics)

            guard shouldSave,
                  !isRestoring,
                  let sessionID else {
                return
            }

            onSaveOffset?(sessionID, offset)
        }

        @MainActor
        private func maxOffset(in scrollView: NSScrollView) -> CGFloat {
            guard let documentView = scrollView.documentView else { return 0 }
            return max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        }

        @MainActor
        private func clampedOffset(_ offset: CGFloat, in scrollView: NSScrollView) -> CGFloat {
            min(max(0, offset), maxOffset(in: scrollView))
        }
    }
}

private final class SessionScrollOffsetProbeView: NSView {
    weak var coordinator: SessionScrollOffsetObserver.Coordinator?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachWhenReady()
    }

    func attachWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            coordinator?.attach(to: enclosingScrollView)
        }
    }
}

private struct SessionSummaryPanel: View {
    let session: SessionSummary
    let isDeleting: Bool
    let onDelete: () -> Void

    var body: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.resolvedTitle)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(session.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .contextMenu {
                                Button(L10n.string("Copy Session ID")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.id, forType: .string)
                                }
                            }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        if let model = session.displayModel {
                            HermesBadge(text: model, tint: .orange)
                        }

                        if let count = session.messageCount {
                            HermesBadge(text: L10n.string("%@ messages", "\(count)"), tint: .accentColor)
                        }

                        Menu {
                            Button(L10n.string("Delete session"), role: .destructive, action: onDelete)
                        } label: {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(L10n.string("More"), systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(L10n.string("More session actions"))
                        .accessibilityLabel(L10n.string("More session actions"))
                        .disabled(isDeleting)
                    }
                }

                if !sessionMetadataFields.isEmpty {
                    HermesInspectorFieldList(fields: sessionMetadataFields)
                }
            }
        }
    }

    private var sessionMetadataFields: [HermesInspectorField] {
        var fields: [HermesInspectorField] = []

        if let startedAt = session.startedAt?.dateValue {
            fields.append(HermesInspectorField(
                id: "started",
                label: "Started",
                value: DateFormatters.shortDateTimeFormatter().string(from: startedAt)
            ))
        }

        if let lastActive = session.lastActive?.dateValue {
            fields.append(HermesInspectorField(
                id: "last-active",
                label: "Last active",
                value: DateFormatters.shortDateTimeFormatter().string(from: lastActive)
            ))
        }

        return fields
    }
}

private struct SessionComposerPanel: View {
    let title: String
    let placeholder: String
    let errorMessage: String?
    let isSending: Bool
    let onResumeInTerminal: (() -> Void)?
    let onSend: (String, Bool) async -> Bool

    @State private var draft = ""
    @State private var autoApproveCommands = false
    @State private var isExpanded = false
    @FocusState private var isEditorFocused: Bool

    private let compactPromptHeight: CGFloat = 28
    private let compactPromptLeadingInset: CGFloat = 8
    private let compactPromptTopInset: CGFloat = 3
    private let expandedPromptHeight: CGFloat = 96
    private let expandedPromptHorizontalInset: CGFloat = 12
    private let expandedPromptTopInset: CGFloat = 10
    private let expandedEditorCharacterThreshold = 140
    private let expandedEditorLongTokenThreshold = 52

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isSending && !trimmedDraft.isEmpty
    }

    private var shouldUseExpandedEditor: Bool {
        isExpanded || shouldExpandEditor(for: draft)
    }

    private var compactPlaceholder: String {
        title == "New Session" ? L10n.string("Start…") : L10n.string("Reply…")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)

                Text(L10n.string(title))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if let onResumeInTerminal {
                    Button(action: onResumeInTerminal) {
                        Label(L10n.string("Resume in Terminal"), systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSending)
                    .help(L10n.string("Open this Hermes session in a fresh Terminal tab"))
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                HermesInsetSurface {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            if isApprovalNeededError(errorMessage) {
                                Text(L10n.string("Approval needed"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            composerInput
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.84))
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var composerInput: some View {
        let usesExpandedEditor = shouldUseExpandedEditor

        VStack(alignment: .leading, spacing: usesExpandedEditor ? 10 : 0) {
            HStack(alignment: .center, spacing: 10) {
                promptEditor(
                    placeholderText: usesExpandedEditor ? L10n.string(placeholder) : compactPlaceholder,
                    height: usesExpandedEditor ? expandedPromptHeight : compactPromptHeight,
                    contentPadding: usesExpandedEditor
                        ? EdgeInsets(
                            top: expandedPromptTopInset,
                            leading: expandedPromptHorizontalInset,
                            bottom: 0,
                            trailing: expandedPromptHorizontalInset
                        )
                        : EdgeInsets(
                            top: compactPromptTopInset,
                            leading: compactPromptLeadingInset,
                            bottom: 0,
                            trailing: 0
                        ),
                    showsEditorBackground: usesExpandedEditor
                )
                .frame(minWidth: 80)
                .frame(height: usesExpandedEditor ? 108 : compactPromptHeight)

                if !usesExpandedEditor {
                    controlCluster
                }
            }
            .padding(.leading, usesExpandedEditor ? 0 : 12)
            .padding(.trailing, usesExpandedEditor ? 0 : 8)
            .frame(height: usesExpandedEditor ? nil : 46)
            .background {
                if !usesExpandedEditor {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(HermesTheme.insetFill)
                }
            }
            .overlay {
                if !usesExpandedEditor {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !usesExpandedEditor {
                    expandEditor()
                }
            }

            if usesExpandedEditor {
                HStack {
                    Spacer(minLength: 8)
                    controlCluster
                }
            }
        }
        .onChange(of: shouldUseExpandedEditor) { _, _ in
            preserveEditorFocusAfterLayoutChange()
        }
    }

    private func promptEditor(
        placeholderText: String,
        height: CGFloat,
        contentPadding: EdgeInsets,
        showsEditorBackground: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if showsEditorBackground {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HermesTheme.insetFill)
            }

            SessionPromptTextView(
                text: $draft,
                placeholder: placeholderText,
                isFocused: $isEditorFocused,
                isDisabled: isSending,
                onCommandReturn: submit
            )
                .padding(contentPadding)
                .frame(height: height)
        }
        .overlay {
            if showsEditorBackground {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
            }
        }
    }

    private var controlCluster: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                autoApproveToggle
                compactAutoApproveToggle
            }

            Button {
                submit()
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")

                        Text("⌘↩")
                            .font(.caption2.monospaced().weight(.semibold))
                    }
                    .frame(minWidth: 48)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(L10n.string("Send with Command-Return"))
            .accessibilityLabel(L10n.string("Send"))
        }
    }

    private var autoApproveToggle: some View {
        Toggle(isOn: $autoApproveCommands) {
            Label(L10n.string("Auto-approve commands"), systemImage: "checkmark.shield")
        }
        .toggleStyle(.checkbox)
        .disabled(isSending)
        .help(L10n.string(autoApproveHelpText))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactAutoApproveToggle: some View {
        Toggle(isOn: $autoApproveCommands) {
            Label(L10n.string("Auto-approve commands"), systemImage: "checkmark.shield")
                .labelStyle(.iconOnly)
        }
        .toggleStyle(.checkbox)
        .disabled(isSending)
        .help(L10n.string(autoApproveHelpText))
        .accessibilityLabel(L10n.string("Auto-approve commands"))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func submit() {
        let prompt = trimmedDraft
        guard !isSending, !prompt.isEmpty else { return }
        let shouldAutoApprove = autoApproveCommands
        autoApproveCommands = false
        isExpanded = false
        isEditorFocused = false
        draft = ""

        Task {
            let didSend = await onSend(prompt, shouldAutoApprove)
            if !didSend && draft.isEmpty {
                draft = prompt
                isExpanded = shouldExpandEditor(for: prompt)
            }
        }
    }

    private func expandEditor() {
        guard !isSending else { return }
        isExpanded = true
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }

    private func preserveEditorFocusAfterLayoutChange() {
        guard isEditorFocused, !isSending else { return }
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }

    private func shouldExpandEditor(for text: String) -> Bool {
        text.contains("\n") ||
            text.count > expandedEditorCharacterThreshold ||
            longestTokenLength(in: text) > expandedEditorLongTokenThreshold
    }

    private func longestTokenLength(in text: String) -> Int {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(\.count)
            .max() ?? 0
    }

    private func isApprovalNeededError(_ message: String) -> Bool {
        message.contains(approvalNeededMessage)
    }
}

private struct SessionPromptTextView: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isFocused: FocusState<Bool>.Binding
    let isDisabled: Bool
    let onCommandReturn: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = PlaceholderCommandTextView()
        textView.placeholder = placeholder
        textView.commandReturnAction = onCommandReturn
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        configure(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? PlaceholderCommandTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.placeholder = placeholder
        textView.commandReturnAction = onCommandReturn
        configure(textView)
        updateFocus(for: textView)
        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func configure(_ textView: PlaceholderCommandTextView) {
        textView.isEditable = !isDisabled
        textView.isSelectable = !isDisabled
        textView.alphaValue = isDisabled ? 0.62 : 1
    }

    private func updateFocus(for textView: NSTextView) {
        guard let window = textView.window else { return }

        if isFocused.wrappedValue {
            if window.firstResponder !== textView {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SessionPromptTextView
        weak var textView: PlaceholderCommandTextView?

        init(parent: SessionPromptTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlaceholderCommandTextView else { return }
            parent.isFocused.wrappedValue = textView.window?.firstResponder === textView
            parent.text = textView.string
            textView.needsDisplay = true
        }
    }
}

private final class PlaceholderCommandTextView: NSTextView {
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }

    var commandReturnAction: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(at: textContainerOrigin)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "\r" {
            commandReturnAction?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct PendingSessionTurnView: View {
    let turn: PendingSessionTurn
    let showPrompt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showPrompt {
                PendingBubble(
                    title: "You",
                    icon: "person.crop.circle.fill",
                    content: turn.prompt,
                    tint: .green
                )
            }

            HermesInsetSurface {
                HStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L10n.string("Agent is working"))
                                .font(.subheadline.weight(.semibold))

                            if turn.autoApproveCommands {
                                HermesBadge(text: "Auto-approve", tint: .orange)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PendingBubble: View {
    let title: String
    let icon: String
    let content: String
    let tint: Color

    var body: some View {
        TranscriptMessageSurface(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)

                    Text(L10n.string(title))
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }

                Text(content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct TranscriptMessageSurface<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .fill(HermesTheme.rowFill)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint.opacity(0.62))
                    .frame(width: 2)
                    .padding(.vertical, 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
            }
    }
}

private struct MessageCard: View {
    let message: SessionMessageDisplay
    @Binding var isShowingMetadata: Bool

    var body: some View {
        if message.isToolMessage {
            ToolMessageCard(
                message: message,
                isShowingMetadata: $isShowingMetadata
            )
        } else {
            ConversationMessageCard(
                message: message,
                isShowingMetadata: $isShowingMetadata
            )
        }
    }
}

private struct ConversationMessageCard: View {
    let message: SessionMessageDisplay
    @Binding var isShowingMetadata: Bool

    var body: some View {
        TranscriptMessageSurface(tint: roleTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    HermesBadge(
                        text: displayRole,
                        tint: roleTint,
                        systemImage: roleSystemImage,
                        isMonospaced: false
                    )

                    Spacer()

                    if let timestampText = message.timestampText {
                        Text(timestampText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(L10n.string("No text payload"))
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if !message.metadataItems.isEmpty {
                    MetadataDisclosureView(
                        items: message.metadataItems,
                        isShowingMetadata: $isShowingMetadata
                    )
                }
            }
        }
    }

    private var displayRole: String {
        message.role.displayTitle
    }

    private var roleTint: Color {
        switch message.role {
        case .assistant:
            return .blue
        case .user:
            return .cyan
        case .system:
            return .orange
        case .event, .custom:
            return .secondary
        }
    }

    private var roleSystemImage: String? {
        switch message.role {
        case .assistant:
            return "sparkles"
        case .user:
            return "person.fill"
        case .system:
            return "gearshape.fill"
        case .event, .custom:
            return nil
        }
    }
}

private struct ToolMessageCard: View {
    let message: SessionMessageDisplay
    @Binding var isShowingMetadata: Bool
    @State private var isExpanded = false

    private var summary: SessionToolMessageSummary? {
        message.toolSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolHeader

            if isExpanded {
                ToolOutputView(content: message.content, summary: summary)

                if !message.metadataItems.isEmpty {
                    MetadataDisclosureView(
                        items: message.metadataItems,
                        isShowingMetadata: $isShowingMetadata
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(statusTint.opacity(0.72))
                .frame(width: 2)
                .padding(.vertical, 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.13), lineWidth: 1)
        }
    }

    private var toolHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                HermesBadge(
                    text: L10n.string("Tool"),
                    tint: .secondary,
                    systemImage: "wrench.and.screwdriver.fill",
                    isMonospaced: false
                )

                if let summary,
                   let statusText = summary.statusText {
                    HermesBadge(
                        text: statusText,
                        tint: statusTint,
                        systemImage: statusSystemImage,
                        prominence: statusProminence,
                        isMonospaced: false
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary?.title ?? L10n.string("Tool output"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(summaryPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                if let sizeText = summary?.sizeText {
                    Text(sizeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(L10n.string(isExpanded ? "Hide details" : "Details"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryPreview: String {
        if let preview = summary?.preview, !preview.isEmpty {
            return preview
        }

        return L10n.string("No output preview")
    }

    private var statusTint: Color {
        switch summary?.statusKind {
        case .success:
            return Color(red: 0.0, green: 0.58, blue: 0.22)
        case .failure:
            return .red
        case .neutral, .none:
            return .secondary
        }
    }

    private var statusSystemImage: String? {
        switch summary?.statusKind {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .neutral, .none:
            return nil
        }
    }

    private var statusProminence: HermesBadge.BadgeProminence {
        switch summary?.statusKind {
        case .success, .failure:
            return .strong
        case .neutral, .none:
            return .subtle
        }
    }
}

private struct ToolOutputView: View {
    let content: String?
    let summary: SessionToolMessageSummary?
    @State private var isShowingFullOutput = false

    private var visibleContent: String? {
        guard isShowingFullOutput else {
            return SessionToolMessageSummary.detailPreview(from: content)
        }

        return content
    }

    private var isTruncated: Bool {
        summary?.isDetailPreviewTruncated == true && !isShowingFullOutput
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let visibleContent, !visibleContent.isEmpty {
                ScrollView {
                    Text(visibleContent)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: isShowingFullOutput ? 280 : 180)
                .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                        .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
                }
            } else {
                Text(L10n.string("No text payload"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if isTruncated {
                Button {
                    isShowingFullOutput = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(L10n.string("Show full output"))
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(L10n.string("Render the full tool output on demand"))
            }
        }
    }
}

private struct MetadataDisclosureView: View {
    let items: [SessionMetadataDisplayItem]
    @Binding var isShowingMetadata: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isShowingMetadata.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShowingMetadata ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Text(L10n.string("Metadata"))
                        .font(.caption.weight(.semibold))

                    Text("(\(items.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if isShowingMetadata {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        MetadataItemView(item: item)
                    }
                }
            }
        }
    }
}

private struct MetadataItemView: View {
    let item: SessionMetadataDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(item.displayValue)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

private extension Array where Element == SessionMessageDisplay {
    func containsUserPrompt(_ prompt: String) -> Bool {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else { return false }

        return contains { message in
            guard message.role == .user,
                  let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return content == normalizedPrompt
        }
    }
}
