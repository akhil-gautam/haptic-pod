import Foundation

struct Track: Codable, Sendable, Hashable, Identifiable {
    /// Path relative to Documents, e.g. "Music/Night Drive/01 Song.flac"
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var folder: String?
    var ext: String
    var fileSize: Int64
    var modified: Date
    var added: Date
    var artworkKey: String?

    var url: URL { Paths.documents.appending(path: id) }
    var isLossless: Bool { ["flac", "wav", "aif", "aiff", "alac", "caf"].contains(ext) }
    var formatLabel: String { isLossless ? "LOSSLESS" : ext.uppercased() }
}

enum Paths {
    static let documents = URL.documentsDirectory
    static let music = URL.documentsDirectory.appending(path: "Music", directoryHint: .isDirectory)
    static let artwork = URL.cachesDirectory.appending(path: "Artwork", directoryHint: .isDirectory)
    static let libraryIndex = URL.applicationSupportDirectory.appending(path: "library.json")
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let t = Int(seconds.rounded(.down))
    if t >= 3600 {
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
    return String(format: "%d:%02d", t / 60, t % 60)
}
