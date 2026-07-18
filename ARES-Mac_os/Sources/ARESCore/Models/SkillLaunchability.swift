import Foundation

public struct LaunchableSkillRecord: Equatable, Hashable, Sendable {
    public let name: String
    public let category: String?
    public let source: String
    public let status: String

    public var launchIdentifier: String {
        guard let category,
              !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return name
        }

        return "\(category)/\(name)"
    }
}

public enum LaunchableSkillInventoryParser {
    public static func parse(_ output: String) -> [LaunchableSkillRecord] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseRecord)
    }

    public static func filterDiscoveredSkills(
        _ discovered: [SkillSummary],
        using launchableRecords: [LaunchableSkillRecord]
    ) -> [SkillSummary] {
        let allowedIdentifiers = Set(launchableRecords.map(\.launchIdentifier))
        return discovered.filter { allowedIdentifiers.contains($0.relativePath) }
    }

    private static func parseRecord(_ rawLine: Substring) -> LaunchableSkillRecord? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("│"), line.hasSuffix("│") else { return nil }

        let columns = line
            .split(separator: "│", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard columns.count == 5 else { return nil }
        guard columns[0] != "Name" else { return nil }
        guard columns[4] == "enabled" else { return nil }
        guard !columns[0].isEmpty else { return nil }

        let category = columns[1].isEmpty ? nil : columns[1]

        return LaunchableSkillRecord(
            name: columns[0],
            category: category,
            source: columns[2],
            status: columns[4]
        )
    }
}