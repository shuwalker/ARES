import CryptoKit
import Foundation

/// Produces a short, stable identifier scoped to a (host, profile) pair.
///
/// The fingerprint is the first 8 hex characters of SHA-256(host ":" profile),
/// suitable for use as a namespace key in local caches and stores.
struct WorkspaceFingerprint {
    /// Returns the first 8 hex characters of SHA-256(`host` + ":" + `profile`).
    static func compute(host: String, profile: String) -> String {
        let input = "\(host):\(profile)"
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }
}
