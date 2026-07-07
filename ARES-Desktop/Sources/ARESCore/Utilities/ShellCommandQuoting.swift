import Foundation

public extension String {
    public var shellQuotedForTerminalCommand: String {
        guard !isEmpty else { return "''" }

        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=@")
        if unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return self
        }

        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}