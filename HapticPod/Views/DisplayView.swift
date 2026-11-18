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
                if let letter = nav.scrollLetter {
                    Text(letter)
                        .font(Theme.font(54, .bold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 104, height: 104)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1C1C1E).opacity(0.94)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.track, lineWidth: 1))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: nav.scrollLetter)
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
        case .extras: ExtrasView(frame: frame)
        case .game: SafeGameView()
        }
    }
}
