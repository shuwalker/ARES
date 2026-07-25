import Foundation

/// Errors surfaced when dispatching a routed request to a live backend.
public enum ExecutionDispatchError: Error, Equatable, Sendable {
    /// No usable backend covered the requested capabilities.
    case unroutable(missing: Set<ExecutionCapability>, rationale: [String])
    /// The route selected a backend kind with no registered live instance.
    case backendUnavailable(ExecutionBackendKind)
}

/// Composes the pure `ExecutionBackendRouter` planner with live backend
/// instances and actually dispatches work by calling `execute(_:)`.
///
/// The router decides *which* backend should run; the dispatcher performs the
/// run. Keeping these separate preserves the planner's purity and testability
/// while giving callers a single entry point that plans and executes.
public struct ExecutionBackendDispatcher: Sendable {
    /// Insertion-ordered backends. Order is product policy: the planner breaks
    /// capability ties by registration order, so this must NOT be a dictionary
    /// (whose iteration order is nondeterministic).
    private let orderedBackends: [any AgenticFrameworkBackend]
    private let backends: [ExecutionBackendKind: any AgenticFrameworkBackend]

    public init(backends: [any AgenticFrameworkBackend]) {
        var map: [ExecutionBackendKind: any AgenticFrameworkBackend] = [:]
        var ordered: [any AgenticFrameworkBackend] = []
        for backend in backends {
            // First registration wins for a given kind so callers control
            // priority by ordering.
            if map[backend.kind] == nil {
                map[backend.kind] = backend
                ordered.append(backend)
            }
        }
        self.backends = map
        self.orderedBackends = ordered
    }

    /// Build a descriptor snapshot from the live backends for the planner,
    /// preserving registration order so tie-breaks stay deterministic.
    private func descriptors(healthByKind: [ExecutionBackendKind: ExecutionBackendHealth]) -> [ExecutionBackendDescriptor] {
        orderedBackends.map { backend in
            ExecutionBackendDescriptor(
                kind: backend.kind,
                displayName: backend.displayName,
                capabilities: backend.capabilities,
                health: healthByKind[backend.kind] ?? ExecutionBackendHealth(state: .healthy)
            )
        }
    }

    /// Plan and execute a request end to end.
    ///
    /// Verifies live health first (ARES must not route to an unusable backend),
    /// plans the route, then calls `execute(_:)` on the primary selected
    /// backend. Hybrid routes execute on the first selected backend and record
    /// the full plan in the result metadata; multi-backend fan-out/synthesis is
    /// a higher layer's concern.
    public func dispatch(_ request: ExecutionRequest) async throws -> ExecutionResult {
        // 1. Verify live health for every registered backend before routing.
        var healthByKind: [ExecutionBackendKind: ExecutionBackendHealth] = [:]
        for (kind, backend) in backends {
            healthByKind[kind] = await backend.healthCheck()
        }

        // 2. Plan with the pure router over the freshly-checked descriptors.
        let router = ExecutionBackendRouter(backends: descriptors(healthByKind: healthByKind))
        let route = router.route(
            for: ExecutionBackendRequest(
                userIntent: request.userIntent,
                requiredCapabilities: request.requiredCapabilities
            )
        )

        guard route.isRoutable, let primaryKind = route.selectedBackends.first else {
            throw ExecutionDispatchError.unroutable(
                missing: route.missingCapabilities,
                rationale: route.rationale
            )
        }

        // 3. Dispatch to the live instance for the primary selected backend.
        guard let backend = backends[primaryKind] else {
            throw ExecutionDispatchError.backendUnavailable(primaryKind)
        }

        let result = try await backend.execute(request)

        // Preserve routing provenance on the result (FOUNDATION.md: keep
        // provenance for consequential/composed work).
        var metadata = result.metadata
        metadata["route_mode"] = .string(routeModeLabel(route.mode))
        metadata["route_backends"] = .array(route.selectedBackends.map { .string($0.rawValue) })
        metadata["route_rationale"] = .array(route.rationale.map { .string($0) })
        return ExecutionResult(
            requestId: result.requestId,
            backend: result.backend,
            text: result.text,
            evidence: result.evidence,
            metadata: metadata
        )
    }

    private func routeModeLabel(_ mode: ExecutionBackendRouteMode) -> String {
        switch mode {
        case .single(let kind): return "single:\(kind.rawValue)"
        case .hybrid(let kinds): return "hybrid:\(kinds.map(\.rawValue).sorted().joined(separator: "+"))"
        case .unavailable: return "unavailable"
        }
    }
}
