import Foundation
import SwiftData

@Model
public final class SessionModel {
    @Attribute(.unique) public var id: String
    public var title: String
    public var startedAt: Date
    public var updatedAt: Date
    public var model: String
    public var provider: String
    
    @Relationship(deleteRule: .cascade, inverse: \MessageModel.session)
    public var messages: [MessageModel]
    
    public init(id: String = UUID().uuidString, title: String = "New Chat", startedAt: Date = Date(), updatedAt: Date = Date(), model: String = "unknown", provider: String = "unknown", messages: [MessageModel] = []) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.model = model
        self.provider = provider
        self.messages = messages
    }
}

@Model
public final class MessageModel {
    @Attribute(.unique) public var id: String
    public var role: String
    public var content: String
    public var timestamp: Date
    
    public var session: SessionModel?
    
    public init(id: String = UUID().uuidString, role: String, content: String, timestamp: Date = Date(), session: SessionModel? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.session = session
    }
}
