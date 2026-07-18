import Foundation

public struct SkillListResponse: Codable {
    public let ok: Bool
    public let items: [SkillSummary]
}

public struct SkillDetailResponse: Codable {
    public let ok: Bool
    public let item: SkillDetail
}

public typealias SkillWriteResponse = SkillDetailResponse

public struct SkillLocator: Codable, Hashable, Sendable {
    public let sourceID: String
    public let relativePath: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case relativePath = "relative_path"
    }
}

public enum SkillSourceKind: String, Codable, Hashable {
    case local
    case external
}

public struct SkillSource: Codable, Hashable {
    public let id: String
    public let kind: SkillSourceKind
    public let rootPath: String
    public let isReadOnly: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case rootPath = "root_path"
        case isReadOnly = "is_read_only"
    }
}

public struct SkillSummary: Codable, Identifiable, Hashable, SkillCatalogItem {
    public let id: String
    public let locator: SkillLocator
    public let source: SkillSource
    public let slug: String
    public let category: String?
    public let relativePath: String
    public let name: String?
    public let description: String?
    public let version: String?
    public let platforms: [String]
    public let tags: [String]
    public let relatedSkills: [String]
    public let hasReferences: Bool
    public let hasScripts: Bool
    public let hasTemplates: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case locator
        case source
        case slug
        case category
        case relativePath = "relative_path"
        case name
        case description
        case version
        case platforms
        case tags
        case relatedSkills = "related_skills"
        case hasReferences = "has_references"
        case hasScripts = "has_scripts"
        case hasTemplates = "has_templates"
    }

    public func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let normalizedQuery = trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let haystacks = [
            resolvedName,
            resolvedCategory,
            sourceLabel
        ] + platforms + tags + relatedSkills

        return haystacks.contains { value in
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .localizedStandardContains(normalizedQuery)
        }
    }
}

public struct SkillDetail: Codable, Identifiable, Hashable, SkillCatalogItem {
    public let id: String
    public let locator: SkillLocator
    public let source: SkillSource
    public let slug: String
    public let category: String?
    public let relativePath: String
    public let name: String?
    public let description: String?
    public let version: String?
    public let platforms: [String]
    public let tags: [String]
    public let relatedSkills: [String]
    public let hasReferences: Bool
    public let hasScripts: Bool
    public let hasTemplates: Bool
    public let markdownContent: String
    public let contentHash: String

    enum CodingKeys: String, CodingKey {
        case id
        case locator
        case source
        case slug
        case category
        case relativePath = "relative_path"
        case name
        case description
        case version
        case platforms
        case tags
        case relatedSkills = "related_skills"
        case hasReferences = "has_references"
        case hasScripts = "has_scripts"
        case hasTemplates = "has_templates"
        case markdownContent = "markdown_content"
        case contentHash = "content_hash"
    }

}

public extension SkillSource {
    public var isLocal: Bool {
        kind == .local
    }

    var badgeTitle: String {
        switch kind {
        case .local:
            return "Local"
        case .external:
            return "External"
        }
    }
}

public extension SkillSummary {
    public var sourceLabel: String {
        source.badgeTitle
    }

    public var skillFilePath: String {
        "\(source.rootPath)/\(relativePath)/SKILL.md"
    }
}

public enum SkillEditorMode: Identifiable, Equatable {
    case create
    case edit

    public var id: String {
        switch self {
        case .create:
            return "create"
        case .edit:
            return "edit"
        }
    }

    public var title: String {
        switch self {
        case .create:
            return "New Skill"
        case .edit:
            return "Edit SKILL.md"
        }
    }

    public var actionTitle: String {
        switch self {
        case .create:
            return "Create Skill"
        case .edit:
            return "Save Changes"
        }
    }
}

public struct SkillDraft: Equatable, Hashable, Sendable {
    public var name = ""
    public var description = ""
    public var categoryPath = ""
    public var slug = ""
    public var version = ""
    public var tagsText = ""
    public var relatedSkillsText = ""
    public var instructions = SkillDraft.defaultInstructions
    public var includeReferencesFolder = false
    public var includeScriptsFolder = false
    public var includeTemplatesFolder = false

    public static let defaultInstructions = """
# Overview

Describe when this skill should be used and what it helps ARES do.

## Workflow

- Step 1
- Step 2
- Step 3

## Notes

Add any guardrails, references, or implementation details that matter.
"""

    public var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedCategoryPath: String? {
        let trimmed = categoryPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    public var normalizedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var normalizedVersion: String? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var normalizedInstructions: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var tags: [String] {
        parseCSV(tagsText)
    }

    public var relatedSkills: [String] {
        parseCSV(relatedSkillsText)
    }

    public var relativePath: String {
        if let normalizedCategoryPath {
            return "\(normalizedCategoryPath)/\(normalizedSlug)"
        }

        return normalizedSlug
    }

    public var generatedMarkdown: String {
        var lines = ["---"]
        lines.append("name: \(yamlQuoted(normalizedName))")
        lines.append("description: \(yamlQuoted(normalizedDescription))")

        if let normalizedVersion {
            lines.append("version: \(yamlQuoted(normalizedVersion))")
        }

        if !tags.isEmpty || !relatedSkills.isEmpty {
            lines.append("metadata:")

            if !tags.isEmpty {
                lines.append("  tags:")
                for tag in tags {
                    lines.append("    - \(yamlQuoted(tag))")
                }
            }

            if !relatedSkills.isEmpty {
                lines.append("  related_skills:")
                for skill in relatedSkills {
                    lines.append("    - \(yamlQuoted(skill))")
                }
            }
        }

        lines.append("---")
        lines.append("")
        lines.append(normalizedInstructions)

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public var validationError: String? {
        guard !normalizedName.isEmpty else {
            return "The skill name is required."
        }

        guard !normalizedDescription.isEmpty else {
            return "A short description is required."
        }

        guard !normalizedSlug.isEmpty else {
            return "The skill folder name is required."
        }

        guard isValidPathComponent(normalizedSlug) else {
            return "The skill folder name can only use lowercase letters, numbers, and hyphens."
        }

        if let normalizedCategoryPath {
            let parts = normalizedCategoryPath.split(separator: "/").map(String.init)
            guard parts.allSatisfy(isValidPathComponent) else {
                return "Each category segment must use lowercase letters, numbers, and hyphens."
            }
        }

        guard !normalizedInstructions.isEmpty else {
            return "Add the skill instructions before saving."
        }

        return nil
    }

    public mutating func refreshSuggestedSlug() {
        guard normalizedSlug.isEmpty else { return }
        slug = slugified(normalizedName)
    }

    public init(
        name: String = "",
        description: String = "",
        categoryPath: String = "",
        slug: String = "",
        version: String = "",
        tagsText: String = "",
        relatedSkillsText: String = "",
        instructions: String = SkillDraft.defaultInstructions,
        includeReferencesFolder: Bool = false,
        includeScriptsFolder: Bool = false,
        includeTemplatesFolder: Bool = false
    ) {
        self.name = name
        self.description = description
        self.categoryPath = categoryPath
        self.slug = slug
        self.version = version
        self.tagsText = tagsText
        self.relatedSkillsText = relatedSkillsText
        self.instructions = instructions
        self.includeReferencesFolder = includeReferencesFolder
        self.includeScriptsFolder = includeScriptsFolder
        self.includeTemplatesFolder = includeTemplatesFolder
    }
    public static func from(detail: SkillDetail) -> SkillDraft {
        SkillDraft(
            name: detail.name ?? detail.resolvedName,
            description: detail.description ?? "",
            categoryPath: detail.category ?? "",
            slug: detail.slug,
            version: detail.version ?? "",
            tagsText: detail.tags.joined(separator: ", "),
            relatedSkillsText: detail.relatedSkills.joined(separator: ", "),
            instructions: detail.markdownBodyContent,
            includeReferencesFolder: detail.hasReferences,
            includeScriptsFolder: detail.hasScripts,
            includeTemplatesFolder: detail.hasTemplates
        )
    }

    private func parseCSV(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isValidPathComponent(_ value: String) -> Bool {
        let pattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func slugified(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let replaced = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )

        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public extension SkillDetail {
    public var isReadOnly: Bool {
        source.isReadOnly
    }

    public var sourceLabel: String {
        source.badgeTitle
    }

    public var skillFilePath: String {
        "\(source.rootPath)/\(relativePath)/SKILL.md"
    }

    var markdownBodyContent: String {
        let content = markdownContent
        guard content.hasPrefix("---") else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var closingIndex: Int?
        for index in lines.indices.dropFirst() {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = index
                break
            }
        }

        guard let closingIndex else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let bodyLines = lines.dropFirst(closingIndex + 1)
        return bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SkillFeatureBadge: String, Identifiable {
    case references
    case scripts
    case templates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .references:
            "references"
        case .scripts:
            "scripts"
        case .templates:
            "templates"
        }
    }
}