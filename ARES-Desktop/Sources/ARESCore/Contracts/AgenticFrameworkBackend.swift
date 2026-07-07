import Foundation

/// Adapter boundary for full agentic frameworks and ARES-owned services.
///
/// This protocol intentionally treats Hermes and JROS as peer full frameworks.
/// ARES may also use ARES-native services, local model runners, cloud providers,
/// or a hybrid of multiple backends. No backend owns ARES identity or UX.
public protocol AgenticFrameworkBackend: AnyObject, Sendable {
    /// Stable identifier for the backend adapter instance.
    var identifier: String { get }

    /// Backend family. Hermes and JROS are both full agentic frameworks here.
    var kind: ExecutionBackendKind { get }

    /// Human-readable label for UI/status surfaces.
    var displayName: String { get }

    /// Product-level capabilities this backend can currently satisfy.
    var capabilities: Set<ExecutionCapability> { get }

    /// Live health. ARES must verify health before routing important work.
    func healthCheck() async -> ExecutionBackendHealth

    /// Execute a normalized ARES request and return normalized evidence/result.
    func execute(_ request: ExecutionRequest) async throws -> ExecutionResult
}
