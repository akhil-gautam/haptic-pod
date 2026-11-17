@preconcurrency import AVFoundation

struct TrackMeta: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double
    var artwork: Data?
}

enum MetadataReader {
    static func read(_ url: URL) async -> TrackMeta {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        var items = (try? await asset.load(.commonMetadata)) ?? []
        if items.isEmpty {
            // FLAC / Vorbis comments often only show up in the full metadata list.
            items = (try? await asset.load(.metadata)) ?? []
        }

        var meta = TrackMeta(duration: seconds.isFinite ? seconds : 0)
        meta.title = await string(in: items, key: .commonKeyTitle, needle: "title")
        meta.artist = await string(in: items, key: .commonKeyArtist, needle: "artist")
        meta.album = await string(in: items, key: .commonKeyAlbumName, needle: "album")
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) {
                meta.artwork = data
                break
            }
        }
        return meta
    }

    private static func string(in items: [AVMetadataItem], key: AVMetadataKey, needle: String) async -> String? {
        for item in items {
            let matches = item.commonKey == key
                || (item.identifier?.rawValue.lowercased().hasSuffix(needle) ?? false)
            guard matches else { continue }
            if let s = try? await item.load(.stringValue) {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
