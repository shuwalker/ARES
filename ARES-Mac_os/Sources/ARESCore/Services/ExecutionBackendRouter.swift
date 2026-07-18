import Foundation

/// Pure routing planner for ARES product-layer backend selection.
///
/// It does not decide identity, personality, or presentation. It only answers:
/// which usable backend(s) can satisfy the requested capabilities right now?
public struct ExecutionBackendRouter: Sendable {
    public let backends: [ExecutionBackendDescriptor]

    public init(backends: [ExecutionBackendDescriptor]) {
        self.backends = backends
    }

    public func route(for request: ExecutionBackendRequest) -> ExecutionBackendRoute {
        let allowed = request.allowedBackends
        let usable = backends.filter { backend in
            backend.isUsable && (allowed == nil || allowed!.contains(backend.kind))
        }

        guard !usable.isEmpty else {
            return ExecutionBackendRoute(
                mode: .unavailable,
                selectedBackends: [],
                satisfiedCapabilities: [],
                missingCapabilities: request.requiredCapabilities,
                rationale: ["No allowed backend is currently usable."]
            )
        }

        let required = request.requiredCapabilities
        if required.isEmpty {
            let first = usable[0]
            return ExecutionBackendRoute(
                mode: .single(first.kind),
                selectedBackends: [first.kind],
                satisfiedCapabilities: [],
                missingCapabilities: [],
                rationale: ["No explicit capability constraint; selected first usable backend: \(first.displayName)."]
            )
        }

        // If one backend can satisfy the whole request, use it unless the caller
        // explicitly asked for a hybrid plan and a hybrid plan provides a broader
        // capability spread. Registration order is the product policy; this router
        // does not hardcode Hermes or JROS priority.
        if !request.preferHybrid,
           let single = usable.first(where: { $0.capabilities.isSuperset(of: required) }) {
            return ExecutionBackendRoute(
                mode: .single(single.kind),
                selectedBackends: [single.kind],
                satisfiedCapabilities: required,
                missingCapabilities: [],
                rationale: ["\(single.displayName) satisfies all requested capabilities."]
            )
        }

        var remaining = required
        var selected: [ExecutionBackendDescriptor] = []
        var rationale: [String] = []

        while !remaining.isEmpty {
            let candidates = usable
                .filter { candidate in !selected.contains(where: { $0.kind == candidate.kind }) }
                .map { candidate in (candidate, candidate.capabilities.intersection(remaining)) }
                .filter { !$0.1.isEmpty }
                .sorted { lhs, rhs in
                    if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
                    let lhsIndex = usable.firstIndex(where: { $0.kind == lhs.0.kind }) ?? Int.max
                    let rhsIndex = usable.firstIndex(where: { $0.kind == rhs.0.kind }) ?? Int.max
                    return lhsIndex < rhsIndex
                }

            guard let best = candidates.first else { break }
            selected.append(best.0)
            remaining.subtract(best.1)
            let names = best.1.map(\.rawValue).sorted().joined(separator: ", ")
            rationale.append("\(best.0.displayName) covers: \(names).")
        }

        let satisfied = required.subtracting(remaining)
        let selectedKinds = selected.map(\.kind)
        let mode: ExecutionBackendRouteMode
        if selectedKinds.isEmpty {
            mode = .unavailable
            rationale.append("No usable backend covers the requested capabilities.")
        } else if selectedKinds.count == 1 {
            mode = .single(selectedKinds[0])
        } else {
            mode = .hybrid(selectedKinds)
            rationale.append("Hybrid route composed across peer backends.")
        }

        return ExecutionBackendRoute(
            mode: mode,
            selectedBackends: selectedKinds,
            satisfiedCapabilities: satisfied,
            missingCapabilities: remaining,
            rationale: rationale
        )
    }
}
