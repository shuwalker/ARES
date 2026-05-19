import Foundation

// MARK: - Models

struct ConnectionInvite: Codable {
    let host: String
    let port: Int
    let profile: String
    let displayName: String
    let transportMode: String   // "sshTunnel" or "directHTTP"
    let generatedAt: Date
}

// MARK: - Errors

enum ConnectionInviteError: LocalizedError {
    case invalidFormat
    case missingScheme
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return L10n.string("The invite code is not valid. Make sure you copied the full code.")
        case .missingScheme:
            return L10n.string("The invite code must start with ares://")
        case .decodingFailed(let reason):
            return L10n.string("Could not read the invite code: %@", reason)
        }
    }
}

// MARK: - Service

struct ConnectionInviteService {

    static let scheme = "ares://"

    // MARK: - Generate

    /// Builds an invite code string from a saved ConnectionProfile.
    static func generate(from profile: ConnectionProfile) -> String {
        let invite = ConnectionInvite(
            host: profile.sshHost,
            port: profile.dashboardPort ?? 9119,
            profile: profile.hermesProfile ?? "",
            displayName: profile.label,
            transportMode: profile.transportMode.rawValue,
            generatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(invite) else {
            return scheme
        }

        let base64 = base64URLEncode(jsonData)
        return "\(scheme)\(base64)"
    }

    // MARK: - Parse

    /// Parses an invite code into a partially-filled ConnectionProfile.
    /// sshUser and sshAlias are left blank for the user to fill in.
    static func parse(_ code: String) throws -> ConnectionProfile {
        let stripped: String
        if code.hasPrefix(scheme) {
            stripped = String(code.dropFirst(scheme.count))
        } else if code.hasPrefix("ares:") {
            // Handle ares:// where the // may be present or absent
            stripped = code
                .replacingOccurrences(of: "ares://", with: "")
                .replacingOccurrences(of: "ares:", with: "")
        } else {
            // Attempt to decode as raw base64url without scheme
            stripped = code
        }

        guard !stripped.isEmpty else {
            throw ConnectionInviteError.invalidFormat
        }

        guard let data = base64URLDecode(stripped) else {
            throw ConnectionInviteError.invalidFormat
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let invite: ConnectionInvite
        do {
            invite = try decoder.decode(ConnectionInvite.self, from: data)
        } catch {
            throw ConnectionInviteError.decodingFailed(error.localizedDescription)
        }

        let mode = TransportMode(rawValue: invite.transportMode) ?? .sshTunnel
        let port = invite.port != 9119 ? invite.port : nil

        let profile = ConnectionProfile(
            label: invite.displayName,
            sshHost: invite.host,
            hermesProfile: invite.profile.isEmpty ? nil : invite.profile,
            transportMode: mode,
            dashboardPort: port
        )
        // sshUser and sshAlias intentionally left blank — user must supply credentials
        return profile
    }

    // MARK: - Base64URL helpers (no padding, URL-safe alphabet)

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Re-add padding
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}
