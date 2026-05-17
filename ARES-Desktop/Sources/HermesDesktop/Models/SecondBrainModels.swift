import Foundation

// MARK: - Second Brain Models

struct SecondBrainResult: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let source: String
    let relevanceScore: Double

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case source
        case relevanceScore = "relevance_score"
    }
}

struct SecondBrainSearchResponse: Codable {
    let ok: Bool
    let items: [SecondBrainResult]
    let totalCount: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case items
        case totalCount = "total_count"
        case message
    }
}

struct SecondBrainSearchRequest: Codable {
    let query: String
    let limit: Int
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case query
        case limit
        case hermesHome = "hermes_home"
    }
}

// MARK: - YouTube Pipeline Models

enum YouTubeVideoStatus: String, Codable, Hashable, CaseIterable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case published = "published"

    var displayTitle: String {
        switch self {
        case .pending:
            return "Pending"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        case .published:
            return "Published"
        }
    }

    var tint: YouTubeStatusTint {
        switch self {
        case .pending:
            return .amber
        case .approved:
            return .green
        case .rejected:
            return .red
        case .published:
            return .blue
        }
    }
}

enum YouTubeStatusTint: Hashable {
    case amber
    case green
    case red
    case blue
}

struct YouTubeVideoEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let tags: [String]
    let thumbnailURL: String?
    let status: YouTubeVideoStatus
    let channelName: String
    let uploadDate: String?
    let scheduledPublishAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case tags
        case thumbnailURL = "thumbnail_url"
        case status
        case channelName = "channel_name"
        case uploadDate = "upload_date"
        case scheduledPublishAt = "scheduled_publish_at"
    }
}

struct YouTubePipelineResponse: Codable {
    let ok: Bool
    let items: [YouTubeVideoEntry]
    let message: String?
}

struct YouTubePipelineRequest: Codable {
    let status: String?
    let limit: Int
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case status
        case limit
        case hermesHome = "hermes_home"
    }
}

struct YouTubeVideoApprovalRequest: Codable {
    let videoID: String
    let action: String
    let hermesHome: String
    let title: String?
    let description: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case videoID = "video_id"
        case action
        case hermesHome = "hermes_home"
        case title
        case description
        case tags
    }
}

struct YouTubeApprovalResponse: Codable {
    let ok: Bool
    let message: String?
}
