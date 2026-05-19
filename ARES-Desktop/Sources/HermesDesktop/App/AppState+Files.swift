import Foundation
import SwiftUI

extension AppState {
    // MARK: - Files

    func loadSelectedWorkspaceFile(forceReload: Bool = false) async {
        guard let reference = selectedWorkspaceFileReference else { return }
        selectedWorkspaceFileID = reference.id
        await loadWorkspaceFile(reference, forceReload: forceReload)
    }

    func loadWorkspaceFile(_ reference: WorkspaceFileReference, forceReload: Bool = false) async {
        guard let profile = activeConnection else { return }
        var document = document(for: reference)

        if document.hasLoaded && !forceReload {
            setDocument(document)
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let snapshot = try await fileEditorService.read(
                remotePath: reference.remotePath,
                connection: profile
            )
            guard isActiveWorkspace(profile) else { return }
            document.content = snapshot.content
            document.originalContent = snapshot.content
            document.remoteContentHash = snapshot.contentHash
            document.lastSavedAt = nil
            document.errorMessage = nil
            document.isLoading = false
            document.hasLoaded = true
            setDocument(document)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
        }
    }

    func saveSelectedWorkspaceFile() async {
        await saveWorkspaceFile(fileID: selectedWorkspaceFileID)
    }

    func saveWorkspaceFile(fileID: String) async {
        guard let profile = activeConnection else { return }
        guard let reference = workspaceFileReferences.first(where: { $0.id == fileID }) else { return }
        var document = document(for: reference)
        guard document.hasLoaded, document.remoteContentHash != nil else {
            document.errorMessage = L10n.string("Reload the file before saving.")
            setDocument(document)
            setStatusMessage(document.errorMessage)
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let saveResult = try await fileEditorService.write(
                remotePath: reference.remotePath,
                content: document.content,
                expectedContentHash: document.remoteContentHash,
                connection: profile
            )
            guard isActiveWorkspace(profile) else { return }
            document.originalContent = document.content
            document.remoteContentHash = saveResult.contentHash
            document.lastSavedAt = Date()
            document.hasLoaded = true
            document.isLoading = false
            setDocument(document)
            setStatusMessage(L10n.string("%@ saved", reference.title))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
            setStatusMessage(error.localizedDescription)
        }
    }

    func updateWorkspaceFile(_ fileID: String, content: String) {
        guard let reference = workspaceFileReferences.first(where: { $0.id == fileID }) else { return }
        var document = document(for: reference)
        document.content = content
        setDocument(document)
    }

    func discardWorkspaceFile(_ fileID: String) {
        var document = workspaceFileDocuments[fileID]
        document?.discardChanges()
        workspaceFileDocuments[fileID] = document
    }

    @discardableResult
    func addWorkspaceFileBookmark(
        remotePath: String,
        title: String? = nil,
        selectAfterAdd: Bool = true
    ) -> WorkspaceFileBookmark? {
        guard let activeConnection else { return nil }
        guard let bookmark = connectionStore.upsertWorkspaceFileBookmark(
            remotePath: remotePath,
            title: title,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        ) else {
            return nil
        }

        let reference = WorkspaceFileReference.bookmark(bookmark)
        if selectAfterAdd {
            selectedWorkspaceFileID = reference.id
            workspaceFileDocuments[reference.id] = workspaceFileDocuments[reference.id] ??
                FileEditorDocument(fileID: reference.id, title: reference.title, remotePath: reference.remotePath)
        }
        setStatusMessage(L10n.string("%@ added to Workspace Files", reference.title))
        return bookmark
    }

    func removeWorkspaceFileBookmark(id: UUID) {
        connectionStore.removeWorkspaceFileBookmark(id: id)
        workspaceFileDocuments.removeValue(forKey: "bookmark:\(id.uuidString)")

        if selectedWorkspaceFileID == "bookmark:\(id.uuidString)" {
            selectedWorkspaceFileID = RemoteTrackedFile.memory.workspaceFileID
        }

        setStatusMessage(L10n.string("Bookmark removed"))
    }

    func selectWorkspaceFile(_ fileID: String) {
        guard workspaceFileReferences.contains(where: { $0.id == fileID }) else { return }
        selectedWorkspaceFileID = fileID
    }

    func workspaceFileDocument(for fileID: String) -> FileEditorDocument? {
        workspaceFileDocuments[fileID]
    }

    func browseWorkspaceDirectory(path: String? = nil) async {
        guard let profile = activeConnection else { return }
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let browsePath = trimmedPath?.isEmpty == false ? trimmedPath! : workspaceFileBrowserDefaultPath

        isLoadingWorkspaceFileBrowser = true
        workspaceFileBrowserError = nil

        do {
            let listing = try await fileEditorService.listDirectory(
                remotePath: browsePath,
                hermesHome: overview?.hermesHome ?? profile.remoteHermesHomePath,
                connection: profile
            )
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserListing = listing
            isLoadingWorkspaceFileBrowser = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingWorkspaceFileBrowser = false
            workspaceFileBrowserError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to browse remote files"))
        }
    }

    // MARK: - Internal file helpers

    func document(for reference: WorkspaceFileReference) -> FileEditorDocument {
        var document = workspaceFileDocuments[reference.id] ??
            FileEditorDocument(fileID: reference.id, title: reference.title, remotePath: reference.remotePath)
        document.title = reference.title
        document.remotePath = reference.remotePath
        return document
    }

    func setDocument(_ document: FileEditorDocument) {
        workspaceFileDocuments[document.fileID] = document
    }

    func ensureInitialFileLoads() async {
        await loadSelectedWorkspaceFile()
    }
}
