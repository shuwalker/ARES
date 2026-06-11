import Foundation
import SwiftUI
import ARESCore
import os

private let approvalLog = Logger(subsystem: "com.ares", category: "Approval")

/// A pending tool-execution approval awaiting the user's decision.
struct PendingApproval: Identifiable {
    let id = UUID()
    let providerName: String
    let toolName: String
    let toolDescription: String
    let inputJSON: String
}

/// The approval layer (ARES layer 7): gates high-risk tool executions behind
/// explicit user consent.
///
/// Policy:
/// - Tools flagged `requiresApproval` (or category `.system`) suspend execution
///   until the user responds to a consent sheet.
/// - "Always allow" persists a per-tool allowlist in UserDefaults
///   (`ARES.approval.allowlist`), keyed by "provider/tool".
/// - Everything is audited to the unified log (subsystem com.ares, category Approval).
@MainActor
final class ApprovalBroker: ObservableObject {

    static let shared = ApprovalBroker()

    /// The approval currently displayed to the user (drives the sheet).
    @Published var current: PendingApproval?

    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var queue: [PendingApproval] = []

    private static let allowlistKey = "ARES.approval.allowlist"

    private init() {}

    // MARK: - Allowlist

    private func allowlist() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.allowlistKey) ?? [])
    }

    private func addToAllowlist(_ key: String) {
        var list = allowlist()
        list.insert(key)
        UserDefaults.standard.set(Array(list).sorted(), forKey: Self.allowlistKey)
    }

    func removeFromAllowlist(_ key: String) {
        var list = allowlist()
        list.remove(key)
        UserDefaults.standard.set(Array(list).sorted(), forKey: Self.allowlistKey)
    }

    var allowlistEntries: [String] { Array(allowlist()).sorted() }

    // MARK: - Approval flow

    /// Called by ToolRouter (any isolation) — suspends until the user decides.
    nonisolated func requestApproval(
        providerName: String,
        toolName: String,
        toolDescription: String,
        input: [String: AnyCodable]
    ) async -> Bool {
        let inputJSON: String = {
            let dict = ToolJSON.dictionary(from: input)
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: data, encoding: .utf8) else { return "{}" }
            return str
        }()

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let key = "\(providerName)/\(toolName)"
                if self.allowlist().contains(key) {
                    approvalLog.info("Auto-approved (allowlist): \(key, privacy: .public)")
                    continuation.resume(returning: true)
                    return
                }
                let pending = PendingApproval(
                    providerName: providerName,
                    toolName: toolName,
                    toolDescription: toolDescription,
                    inputJSON: inputJSON
                )
                self.continuations[pending.id] = continuation
                if self.current == nil {
                    self.current = pending
                } else {
                    self.queue.append(pending)
                }
            }
        }
    }

    /// Resolve the currently displayed approval. Called from the sheet UI.
    func resolve(_ approval: PendingApproval, approved: Bool, always: Bool = false) {
        if approved, always {
            addToAllowlist("\(approval.providerName)/\(approval.toolName)")
        }
        approvalLog.notice("User \(approved ? "approved" : "denied", privacy: .public): \(approval.providerName, privacy: .public)/\(approval.toolName, privacy: .public)")
        if let continuation = continuations.removeValue(forKey: approval.id) {
            continuation.resume(returning: approved)
        }
        current = queue.isEmpty ? nil : queue.removeFirst()
    }

    /// Deny everything outstanding (e.g. on chat cancel or app quit).
    func denyAll() {
        if let current { resolve(current, approved: false) }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let continuation = continuations.removeValue(forKey: next.id) {
                continuation.resume(returning: false)
            }
        }
        current = nil
    }
}

// MARK: - Consent sheet

/// Consent dialog for a tool execution. Attach once at root:
/// `.toolApprovalSheet()`
struct ToolApprovalSheet: View {
    @ObservedObject var broker = ApprovalBroker.shared

    var body: some View {
        if let approval = broker.current {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARES wants to run a tool")
                            .font(.headline)
                        Text("\(approval.providerName) · \(approval.toolName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !approval.toolDescription.isEmpty {
                    Text(approval.toolDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Input") {
                    ScrollView {
                        Text(approval.inputJSON)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                }

                HStack {
                    Button(role: .cancel) {
                        broker.resolve(approval, approved: false)
                    } label: {
                        Text("Deny").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.cancelAction)

                    Button {
                        broker.resolve(approval, approved: true, always: true)
                    } label: {
                        Text("Always Allow").frame(maxWidth: .infinity)
                    }

                    Button {
                        broker.resolve(approval, approved: true)
                    } label: {
                        Text("Allow Once").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 440)
        }
    }
}

extension View {
    /// Presents the tool approval consent sheet whenever a tool execution
    /// is awaiting user consent. Attach once, at the app root.
    func toolApprovalSheet() -> some View {
        modifier(ToolApprovalSheetModifier())
    }
}

private struct ToolApprovalSheetModifier: ViewModifier {
    @ObservedObject var broker = ApprovalBroker.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { broker.current != nil },
            set: { isPresented in
                if !isPresented, let current = broker.current {
                    broker.resolve(current, approved: false)
                }
            }
        )) {
            ToolApprovalSheet()
                .interactiveDismissDisabled()
        }
    }
}
