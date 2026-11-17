@preconcurrency import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// AVAudioPlayer delegate callbacks can arrive on any thread; forward through a Sendable closure.
final class PlayerDelegateProxy: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: @Sendable (Bool) -> Void
    init(onFinish: @escaping @Sendable (Bool) -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish(flag) }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) { onFinish(false) }
}

@MainActor @Observable
final class PlayerService {
    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var shuffle: Bool
    private(set) var repeatAll: Bool

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var proxy: PlayerDelegateProxy?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var currentTime: Double { player?.currentTime ?? 0 }
    var duration: Double {
        if let d = player?.duration, d > 0 { return d }
        return current?.duration ?? 0
    }

    init() {
        shuffle = UserDefaults.standard.bool(forKey: "shuffle")
        repeatAll = UserDefaults.standard.bool(forKey: "repeatAll")
        proxy = PlayerDelegateProxy { [weak self] ok in
            let service = self
            Task { @MainActor in service?.trackFinished(ok) }
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        NowPlayingBridge.register { [weak self] action in self?.handle(action) }
        observeSession()
    }

    // MARK: Transport

    func play(queue newQueue: [Track], at i: Int) {
        guard newQueue.indices.contains(i) else { return }
        if shuffle {
            var rest = newQueue
            let first = rest.remove(at: i)
            rest.shuffle()
            queue = [first] + rest
            index = 0
        } else {
            queue = newQueue
            index = i
        }
        load(autoplay: true)
    }

    /// Returns false when there is nothing to play.
    @discardableResult
    func togglePlayPause() -> Bool {
        guard current != nil else { return false }
        if player == nil { load(autoplay: true); return true }
        isPlaying ? pause() : resume()
        return true
    }

    func resume() {
        guard let player else { if current != nil { load(autoplay: true) }; return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    @discardableResult
    func next() -> Bool {
        guard !queue.isEmpty else { return false }
        if index + 1 < queue.count {
            index += 1
            load(autoplay: isPlaying)
        } else {
            index = 0
            load(autoplay: repeatAll && isPlaying)
        }
        return true
    }

    @discardableResult
    func previous() -> Bool {
        guard !queue.isEmpty else { return false }
        if currentTime > 3 || (index == 0 && !repeatAll) {
            seek(to: 0)
            return true
        }
        index = index == 0 ? queue.count - 1 : index - 1
        load(autoplay: isPlaying)
        return true
    }

    func seek(to t: Double) {
        guard let player else { return }
        player.currentTime = min(max(t, 0), max(player.duration - 0.5, 0))
        updateNowPlaying()
    }

    func seek(by delta: Double) { seek(to: currentTime + delta) }

    /// Current loudness 0...1 for the equalizer (polled by the view each frame).
    func meterLevel() -> Float {
        guard let player, player.isPlaying else { return 0 }
        player.updateMeters()
        var db = player.averagePower(forChannel: 0)
        if player.numberOfChannels > 1 { db = (db + player.averagePower(forChannel: 1)) / 2 }
        let norm = max(0, min(1, (db + 45) / 45))   // -45 dB … 0 dB
        return pow(norm, 1.5)
    }

    func toggleShuffle() {
        shuffle.toggle()
        UserDefaults.standard.set(shuffle, forKey: "shuffle")
    }

    func toggleRepeat() {
        repeatAll.toggle()
        UserDefaults.standard.set(repeatAll, forKey: "repeatAll")
    }

    // MARK: Internals

    private func load(autoplay: Bool) {
        player?.stop()
        player = nil
        var attempts = 0
        while attempts < queue.count, let track = current {
            if let p = try? AVAudioPlayer(contentsOf: track.url) {
                p.delegate = proxy
                p.isMeteringEnabled = true
                p.prepareToPlay()
                player = p
                if autoplay {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    p.play()
                }
                isPlaying = autoplay
                updateNowPlaying()
                return
            }
            // Unplayable or missing file: skip it.
            attempts += 1
            index = (index + 1) % queue.count
        }
        isPlaying = false
        updateNowPlaying()
    }

    private func trackFinished(_ ok: Bool) {
        if index + 1 < queue.count {
            index += 1
            load(autoplay: true)
        } else if repeatAll {
            index = 0
            load(autoplay: true)
        } else {
            index = 0
            load(autoplay: false)
        }
    }

    private func handle(_ action: RemoteAction) {
        switch action {
        case .play: resume()
        case .pause: pause()
        case .toggle: togglePlayPause()
        case .next: next()
        case .previous: previous()
        case .seek(let t): seek(to: t)
        }
    }

    private func updateNowPlaying() {
        guard let t = current else { NowPlayingBridge.update(nil); return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let key = t.artworkKey, let img = ArtworkCache.loadSync(key, full: true) {
            info[MPMediaItemPropertyArtwork] = NowPlayingBridge.artwork(img)
        }
        NowPlayingBridge.update(info)
    }

    private func observeSession() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let service = self
            MainActor.assumeIsolated { service?.interruption(type: type, options: options) }
        })
        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            let service = self
            MainActor.assumeIsolated {
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { service?.pause() }
            }
        })
    }

    private func interruption(type: UInt, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue {
            isPlaying = false
            updateNowPlaying()
        } else if type == AVAudioSession.InterruptionType.ended.rawValue,
                  AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
            resume()
        }
    }
}
