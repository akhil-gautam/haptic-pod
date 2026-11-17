import Foundation

enum LibraryScanner {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "flac", "alac", "caf"]

    struct FileInfo: Sendable {
        var url: URL
        var id: String
        var size: Int64
        var modified: Date
        var ext: String
        var folder: String?
    }

    /// Walks Documents, reuses unchanged tracks, reads metadata for new/changed files.
    static func scan(existing: [String: Track]) async -> [Track] {
        let files = enumerateAudio()
        var result: [Track] = []
        var toRead: [FileInfo] = []
        for f in files {
            if let e = existing[f.id], e.fileSize == f.size, e.modified == f.modified {
                result.append(e)
            } else {
                toRead.append(f)
            }
        }

        let now = Date()
        await withTaskGroup(of: Track.self) { group in
            var iterator = toRead.makeIterator()
            var running = 0
            while running < 4, let f = iterator.next() {
                let added = existing[f.id]?.added ?? now
                group.addTask { await makeTrack(f, added: added) }
                running += 1
            }
            while let track = await group.next() {
                result.append(track)
                if let f = iterator.next() {
                    let added = existing[f.id]?.added ?? now
                    group.addTask { await makeTrack(f, added: added) }
                }
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    private static func enumerateAudio() -> [FileInfo] {
        let fm = FileManager.default
        let base = Paths.documents.resolvingSymlinksInPath()
        var basePath = base.path(percentEncoded: false)
        if !basePath.hasSuffix("/") { basePath += "/" }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [FileInfo] = []
        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard audioExtensions.contains(ext),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            let full = url.resolvingSymlinksInPath().path(percentEncoded: false)
            guard full.hasPrefix(basePath) else { continue }
            let rel = String(full.dropFirst(basePath.count))
            let comps = rel.split(separator: "/").map(String.init)
            var folder: String?
            if comps.count >= 3, comps[0] == "Music" {
                folder = comps[1]
            } else if comps.count >= 2, comps[0] != "Music", comps[0] != "Inbox" {
                folder = comps[0]
            }
            files.append(FileInfo(
                url: url,
                id: rel,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast,
                ext: ext,
                folder: folder
            ))
        }
        return files
    }

    private static func makeTrack(_ f: FileInfo, added: Date) async -> Track {
        let meta = await MetadataReader.read(f.url)
        let parsed = parseFilename(f.url.deletingPathExtension().lastPathComponent)
        let title = meta.title ?? parsed.title
        let artist = meta.artist ?? parsed.artist ?? "Unknown Artist"
        let album = meta.album ?? f.folder ?? "Unknown Album"
        var artworkKey: String?
        if let data = meta.artwork {
            let key = ArtworkCache.key(album: album, artist: artist)
            if ArtworkCache.store(data, key: key) { artworkKey = key }
        }
        return Track(
            id: f.id, title: title, artist: artist, album: album,
            duration: meta.duration, folder: f.folder, ext: f.ext,
            fileSize: f.size, modified: f.modified, added: added, artworkKey: artworkKey
        )
    }

    /// "01 - Artist - Title" → (Artist, Title); "03. Title" → (nil, Title)
    static func parseFilename(_ name: String) -> (artist: String?, title: String) {
        var s = name
        if let range = s.range(of: #"^\d{1,3}[\s.\-_]+"#, options: .regularExpression) {
            s.removeSubrange(range)
        }
        let parts = s.components(separatedBy: " - ")
        if parts.count >= 2 {
            let artist = parts[0].trimmingCharacters(in: .whitespaces)
            let title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty { return (artist, title) }
        }
        let title = s.trimmingCharacters(in: .whitespaces)
        return (nil, title.isEmpty ? name : title)
    }
}
