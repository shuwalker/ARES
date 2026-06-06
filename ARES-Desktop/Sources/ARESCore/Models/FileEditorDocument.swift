import Foundation

public struct FileEditorDocument {
    public let fileID: String
    public var title: String
    public var remotePath: String
    public var content: String = ""
    public var originalContent: String = ""
    public var remoteContentHash: String?
    public var isLoading = false
    public var errorMessage: String?
    public var lastSavedAt: Date?
    public var hasLoaded = false

    public init(
        fileID: String,
        title: String,
        remotePath: String,
        content: String = "",
        originalContent: String = "",
        remoteContentHash: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        lastSavedAt: Date? = nil,
        hasLoaded: Bool = false
    ) {
        self.fileID = fileID
        self.title = title
        self.remotePath = remotePath
        self.content = content
        self.originalContent = originalContent
        self.remoteContentHash = remoteContentHash
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.lastSavedAt = lastSavedAt
        self.hasLoaded = hasLoaded
    }

    public var isDirty: Bool {
        content != originalContent
    }

    public mutating func discardChanges() {
        content = originalContent
    }
}