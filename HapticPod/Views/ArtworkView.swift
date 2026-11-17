import SwiftUI

/// Album art loaded asynchronously from ArtworkCache, with a dark placeholder.
struct ArtworkImage: View {
    let key: String?
    var full = false

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x2C2C2E), Color(hex: 0x161618)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                            .scaleEffect(full ? 2.5 : 1)
                    }
            }
        }
        .task(id: key) {
            guard let key else { image = nil; return }
            if let hit = ArtworkCache.cached(key, full: full) { image = hit; return }
            image = await ArtworkCache.load(key, full: full)
        }
    }
}

struct ArtworkView: View {
    let key: String?
    var full = false
    let size: CGFloat
    var radius: CGFloat = 4

    var body: some View {
        ArtworkImage(key: key, full: full)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
