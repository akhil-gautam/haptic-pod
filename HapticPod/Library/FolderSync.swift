import Foundation

/// Remembers one folder (e.g. a Google Drive folder picked in Files) and copies any new songs
/// from it into Documents/Music/<FolderName>/ on demand. Additive only: removing a song from the
/// folder doesn't delete the local copy.
enum FolderSync {
    private static let bookmarkKey = "syncFolderBookmark"
    private static let nameKey = "syncFolderName"

    static var folderName: String? { UserDefaults.standard.string(forKey: nameKey) }

    /// Stores a security-scoped bookmark for a folder returned by the document picker.
    @discardableResult
    static func remember(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
        return true
    }

    /// Copies new songs from the remembered folder. Returns the number of new files, or nil when
    /// no folder is set or it can no longer be reached.
    static func sync() async -> Int? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale { remember(url) }
        return await MusicImporter.importItems([url])
    }
}
