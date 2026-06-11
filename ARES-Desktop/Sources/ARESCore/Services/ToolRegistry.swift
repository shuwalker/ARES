import Foundation

/// Manages dynamic registration and discovery of tools for ARES.
public final class ToolRegistry: @unchecked Sendable {
    public static let shared = ToolRegistry()
    
    private var providers: [String: any ToolProvider] = [:]
    
    private init() {}
    
    /// Register a new ToolProvider
    public func register(provider: any ToolProvider) {
        providers[provider.identifier] = provider
        print("✅ [ToolRegistry] Registered tool provider: \(provider.displayName)")
    }
    
    /// Unregister a ToolProvider
    public func unregister(identifier: String) {
        providers.removeValue(forKey: identifier)
    }
    
    /// Get all registered tool providers
    public func allProviders() -> [any ToolProvider] {
        return Array(providers.values)
    }
    
    /// Get a specific provider by its identifier
    public func getProvider(for identifier: String) -> (any ToolProvider)? {
        return providers[identifier]
    }
}
