import Foundation

/// Copies picked files/folders (e.g. from Google Drive in the Files app) into Documents/Music.
enum MusicImporter {
    /// Returns how many files were newly copied (files already present are skipped).
    static func importItems(_ urls: [URL]) async -> Int {
        try? FileManager.default.createDirectory(at: Paths.music, withIntermediateDirectories: true)
        var count = 0
        for url in urls { count += importItem(url) }
        return count
    }

    private static func importItem(_ url: URL) -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDir else {
            return copyCoordinated(url, into: Paths.music) ? 1 : 0

        }

        let dest = Paths.music.appending(path: url.lastPathComponent, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var files: [URL] = []
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { dirURL in
            guard let en = FileManager.default.enumerator(
                at: dirURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ) else { return }
            while let f = en.nextObject() as? URL {
                if LibraryScanner.audioExtensions.contains(f.pathExtension.lowercased()) { files.append(f) }
            }
        }
        var count = 0
        for f in files where copyCoordinated(f, into: dest) { count += 1 }
        return count
    }

    /// True when `dir` already holds a file with this name and size. Uses the provider's metadata,
    /// so an already-imported cloud file isn't downloaded again just to compare it.
    private static func alreadyImported(_ src: URL, in dir: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileSizeKey]
        let values = try? src.resourceValues(forKeys: keys)
        guard let srcSize = values?.fileSize ?? values?.totalFileSize else { return false }
        let target = dir.appending(path: src.lastPathComponent)
        let existing = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return existing == srcSize
    }

    /// Coordinated read makes the file provider download the file if it's only a placeholder.
    /// Returns true only when a new file was written.
    private static func copyCoordinated(_ src: URL, into dir: URL) -> Bool {
        if alreadyImported(src, in: dir) { return false }
        var ok = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: src, options: [.withoutChanges], error: &coordError) { readURL in
            let fm = FileManager.default
            let name = src.lastPathComponent
            let srcSize = (try? readURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            var target = dir.appending(path: name)
            if fm.fileExists(atPath: target.path(percentEncoded: false)) {
                let existingSize = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
                if existingSize == srcSize { return }
                let base = src.deletingPathExtension().lastPathComponent
                let ext = src.pathExtension
                var n = 2
                repeat {
                    target = dir.appending(path: "\(base) \(n).\(ext)")
                    n += 1
                } while fm.fileExists(atPath: target.path(percentEncoded: false))
            }
            do {
                try fm.copyItem(at: readURL, to: target)
                ok = true
            } catch {
                ok = false
            }
        }
        return ok
    }
}
