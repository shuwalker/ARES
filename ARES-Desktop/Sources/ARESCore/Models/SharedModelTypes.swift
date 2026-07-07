import Foundation



public protocol TitleIdentifiable: Identifiable where ID == String {
    var title: String? { get }
}

public extension TitleIdentifiable {
    public var resolvedTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return id
    }
}

public protocol OptionalModelDisplayable {
    var model: String? { get }
}

public extension OptionalModelDisplayable {
    public var displayModel: String? {
        guard let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if model.count <= 34 {
            return model
        }

        let prefix = model.prefix(16)
        let suffix = model.suffix(12)
        return "\(prefix)…\(suffix)"
    }
}

public protocol SkillCatalogItem: Identifiable where ID == String {
    var slug: String { get }
    var category: String? { get }
    var name: String? { get }
    var description: String? { get }
    var version: String? { get }
    var platforms: [String] { get }
    var tags: [String] { get }
    var relatedSkills: [String] { get }
    var hasReferences: Bool { get }
    var hasScripts: Bool { get }
    var hasTemplates: Bool { get }
}

public extension SkillCatalogItem {
    public var resolvedName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return slug
    }

    var trimmedDescription: String? {
        guard let description else { return nil }
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var featureBadges: [SkillFeatureBadge] {
        var badges: [SkillFeatureBadge] = []
        if hasReferences {
            badges.append(.references)
        }
        if hasScripts {
            badges.append(.scripts)
        }
        if hasTemplates {
            badges.append(.templates)
        }
        return badges
    }

    var resolvedCategory: String {
        guard let category,
              !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Root"
        }
        return category
    }
}