import Foundation

/// OwnerModelProvider stores the private learned model of the human owner.
///
/// This is not avatar mimicry and not a character/persona skin. It is the
/// product-level model ARES uses to remember the owner's preferences,
/// accepted/rejected patterns, standards, and corrections.
public protocol OwnerModelProvider: AnyObject, Sendable {
    /// Current owner model snapshot.
    func getOwnerModel() async throws -> OwnerModel

    /// Add or update a durable owner preference.
    func recordPreference(_ preference: OwnerPreference) async throws

    /// Record a correction from the owner.
    func recordCorrection(_ correction: OwnerCorrection) async throws

    /// Replace the project standards ARES should apply when deciding work quality.
    func updateStandards(_ standards: [OwnerStandard]) async throws

    /// Build compact context for the ARES Controller before backend routing.
    func buildContext(for request: String) async throws -> OwnerModelContext
}
