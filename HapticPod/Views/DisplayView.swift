import SwiftUI

struct DisplayView: View {
    /// Space reserved at the top for the Dynamic Island.
    let topPadding: CGFloat

    @Environment(Navigator.self) private var nav
    @Environment(Haptics.self) private var haptics

    var body: some View {
        let frame = nav.frame
        VStack(spacing: 0) {
            StatusBarView(isRoot: nav.depth == 1) {
                haptics.play(.home)
                nav.back()
            }
            ZStack {
                screen(frame)
                    .id(nav.depth)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 18)),
                        removal: .opacity
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background {
            if frame.screen == .home { HomeBackdrop().padding(.top, topPadding) }
        }
        .animation(.easeOut(duration: 0.18), value: nav.depth)
    }

    @ViewBuilder
    private func screen(_ frame: NavFrame) -> some View {
        switch frame.screen {
        case .home: HomeMenuView(frame: frame)
        case .nowPlaying: NowPlayingView()
        case .settings: SettingsView(frame: frame)
        case .playlist(let n), .artist(let n), .album(let n): DetailListView(frame: frame, title: n)
        case .playlists, .artists, .albums, .songs: ListScreenView(frame: frame)
        }
    }
}
