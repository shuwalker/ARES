import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var folder: String?

    init(title: String = "Untitled", body: String = "", folder: String? = nil) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.folder = folder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
