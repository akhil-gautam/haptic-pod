import SwiftUI

struct HomeMenuView: View {
    let frame: NavFrame
    @Environment(Navigator.self) private var nav
    @Environment(Haptics.self) private var haptics

    var body: some View {
        let items = MenuItem.allCases
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let selected = i == frame.selection
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 6, height: 6)
                        .opacity(selected ? 1 : 0)
                    Text(item.title)
                        .font(Theme.font(14, .medium))
                        .tracking(3.2)
                        .foregroundStyle(selected ? Theme.primary : Theme.menuIdle)
                }
                .frame(height: Theme.menuRowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    haptics.play(.click)
                    nav.tapRow(i)
                }
            }
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Current (or first) album art bleeding in from the right edge of the home screen.
struct HomeBackdrop: View {
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let key = player.current?.artworkKey ?? library.tracks.first(where: { $0.artworkKey != nil })?.artworkKey
        GeometryReader { geo in
            if let key {
                ArtworkImage(key: key, full: true)
                    .frame(width: geo.size.width * 0.62, height: geo.size.width * 0.62)
                    .clipped()
                    .blur(radius: 3)
                    .opacity(0.75)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.45)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .allowsHitTesting(false)
    }
}
