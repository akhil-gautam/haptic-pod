import SwiftUI

struct NowPlayingView: View {
    @Environment(Navigator.self) private var nav
    @Environment(PlayerService.self) private var player
    @Environment(Haptics.self) private var haptics

    var body: some View {
        if let track = player.current {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                content(track)
            }
        } else {
            VStack(spacing: 8) {
                Text("NOTHING PLAYING")
                    .font(Theme.font(11, .semibold)).tracking(3)
                    .foregroundStyle(Theme.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ track: Track) -> some View {
        let duration = player.duration
        let elapsed = nav.scrubTarget ?? player.currentTime
        let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ArtworkView(key: track.artworkKey, full: true, size: 136, radius: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOW PLAYING")
                        .font(Theme.font(7, .semibold)).tracking(2.2)
                        .foregroundStyle(Theme.secondary)
                    Text(track.title)
                        .font(Theme.font(18, .semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(track.artist)
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(Color(hex: 0xC7C7CC))
                        .lineLimit(1)
                    Text(track.album.uppercased())
                        .font(Theme.font(7, .semibold)).tracking(1.6)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)

            Spacer(minLength: 14).frame(maxHeight: 30)

            // Progress
            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.primary).frame(width: g.size.width * progress)
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text("-" + formatTime(max(duration - elapsed, 0)))
                }
                .font(Theme.font(9, .medium).monospacedDigit())
                .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 10).frame(maxHeight: 26)

            // Transport
            HStack(spacing: 22) {
                transportButton("backward.end.fill", size: 30) { player.previous() }
                Button {
                    haptics.play(.click)
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle().fill(Theme.primary)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: player.isPlaying ? 0 : 1.5)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                transportButton("forward.end.fill", size: 30) { player.next() }
            }

            Spacer(minLength: 10)

            HStack {
                Label {
                    Text("SUDO AUDIO")
                } icon: {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 8))
                }
                .labelStyle(.titleAndIcon)
                Spacer()
                Text(track.formatLabel)
            }
            .font(Theme.font(7, .semibold))
            .tracking(1.8)
            .foregroundStyle(Theme.secondary)
            .padding(.bottom, 4)
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            haptics.play(.click)
            action()
        } label: {
            ZStack {
                Circle().fill(Color(hex: 0x1C1C1E))
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}
