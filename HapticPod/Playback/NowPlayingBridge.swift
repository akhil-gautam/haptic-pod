@preconcurrency import MediaPlayer
import UIKit

enum RemoteAction: Sendable {
    case play, pause, toggle, next, previous
    case seek(Double)
}

/// MediaPlayer invokes these closures off the main thread, so they are built in a
/// nonisolated context (never inheriting @MainActor) and hop explicitly.
enum NowPlayingBridge {
    static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    static func register(_ handle: @escaping @MainActor @Sendable (RemoteAction) -> Void) {
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ action: RemoteAction) {
            command.isEnabled = true
            command.addTarget { @Sendable _ in
                Task { @MainActor in handle(action) }
                return .success
            }
        }
        add(center.playCommand, .play)
        add(center.pauseCommand, .pause)
        add(center.togglePlayPauseCommand, .toggle)
        add(center.nextTrackCommand, .next)
        add(center.previousTrackCommand, .previous)
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            let t = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            Task { @MainActor in handle(.seek(t)) }
            return .success
        }
    }

    /// Next/previous/seek only make sense for music; the sound mix has no tracks.
    static func setTrackCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        guard center.nextTrackCommand.isEnabled != enabled else { return }
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled
        center.changePlaybackPositionCommand.isEnabled = enabled
    }

    static func update(_ info: [String: Any]?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
