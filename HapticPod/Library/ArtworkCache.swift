import CryptoKit
import ImageIO
import UIKit

enum ArtworkCache {
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func key(album: String, artist: String) -> String {
        let digest = SHA256.hash(data: Data("\(album.lowercased())|\(artist.lowercased())".utf8))
        return digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func url(_ key: String, full: Bool) -> URL {
        Paths.artwork.appending(path: "\(key)\(full ? "_f" : "_t").jpg")
    }

    /// Writes a thumbnail and a full-size JPEG for the key. Returns false if the data isn't an image.
    static func store(_ data: Data, key: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url(key, full: true).path(percentEncoded: false)) { return true }
        try? fm.createDirectory(at: Paths.artwork, withIntermediateDirectories: true)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        for (full, px) in [(false, 180), (true, 720)] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: px,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
            else { return false }
            try? jpg.write(to: url(key, full: full), options: .atomic)
        }
        return true
    }

    static func cached(_ key: String, full: Bool) -> UIImage? {
        memory.object(forKey: cacheKey(key, full))
    }

    static func loadSync(_ key: String, full: Bool) -> UIImage? {
        if let img = cached(key, full: full) { return img }
        guard let data = try? Data(contentsOf: url(key, full: full)),
              let img = UIImage(data: data) else { return nil }
        let decoded = img.preparingForDisplay() ?? img
        memory.setObject(decoded, forKey: cacheKey(key, full))
        return decoded
    }

    /// Runs off the main actor (nonisolated async).
    static func load(_ key: String, full: Bool) async -> UIImage? {
        loadSync(key, full: full)
    }

    private static func cacheKey(_ key: String, _ full: Bool) -> NSString {
        "\(key)\(full ? "f" : "t")" as NSString
    }
}
