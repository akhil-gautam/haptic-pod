@preconcurrency import AVFoundation
import MediaPlayer
import Observation
import os
import UIKit

/// Latest output loudness, written on the audio render thread and read by the UI.
final class MeterBox: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Float(0))
    func set(_ v: Float) { value.withLock { $0 = v } }
    func get() -> Float { value.withLock { $0 } }
}

/// Playback on AVAudioEngine: player node → 5-band EQ → reverb → ambience delay → mixer.
///
/// Gapless: while a track plays, the next one is already scheduled on the same player node, so it
/// starts on the very next sample. That needs both files to share a sample rate and channel count;
/// otherwise the node is reconnected for the new format, which costs a few milliseconds.
@MainActor @Observable
final class PlayerService {
    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var shuffle: Bool
    private(set) var repeatAll: Bool
    private(set) var eqPreset: EQPreset

    /// Called once per listen (30 s or half the track, whichever comes first).
    @ObservationIgnored var onPlayCounted: ((String) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private let eq = AVAudioUnitEQ(numberOfBands: EQPreset.frequencies.count)
    @ObservationIgnored private let reverb = AVAudioUnitReverb()
    @ObservationIgnored private let ambience = AVAudioUnitDelay()
    @ObservationIgnored private let meter = MeterBox()
    @ObservationIgnored private var connectedFormat: AVAudioFormat?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// A file region scheduled on the node. `nodeStart` is the node sample time where it begins.
    private struct Segment {
        let index: Int
        let file: AVAudioFile
        let startFrame: AVAudioFramePosition
        let nodeStart: AVAudioFramePosition
        let frames: AVAudioFramePosition
        var sampleRate: Double { file.processingFormat.sampleRate }
    }

    @ObservationIgnored private var currentSeg: Segment?
    @ObservationIgnored private var nextSeg: Segment?
    /// Bumped on every reschedule so completion callbacks from stopped segments are ignored.
    @ObservationIgnored private var generation = 0
    /// Last known position, used while paused or when the engine has stopped.
    @ObservationIgnored private var lastTime: Double = 0
    @ObservationIgnored private var countedCurrent = false

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    var duration: Double {
        if let seg = currentSeg { return Double(seg.file.length) / seg.sampleRate }
        return current?.duration ?? 0
    }

    var currentTime: Double { liveTime() ?? lastTime }

    init() {
        shuffle = UserDefaults.standard.bool(forKey: "shuffle")
        repeatAll = UserDefaults.standard.bool(forKey: "repeatAll")
        eqPreset = EQPreset(rawValue: UserDefaults.standard.integer(forKey: "eqPreset")) ?? .flat
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        setUpEngine()
        NowPlayingBridge.register { [weak self] action in self?.handle(action) }
        observeSession()
        Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                tick += 1
                self.heartbeat(saving: tick % 5 == 0)
            }
        }
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
        countedCurrent = false
        start(at: 0, autoplay: true)
    }

    /// Plays every track in random order, regardless of the shuffle setting.
    func shuffleAll(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        queue = tracks.shuffled()
        index = 0
        countedCurrent = false
        start(at: 0, autoplay: true)
    }

    /// Returns false when there is nothing to play.
    @discardableResult
    func togglePlayPause() -> Bool {
        guard current != nil else { return false }
        isPlaying ? pause() : resume()
        return true
    }

    func resume() {
        guard current != nil else { return }
        guard currentSeg != nil else { start(at: lastTime, autoplay: true); return }
        Self.activateForPlayback()
        guard startEngine() else { return }
        node.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        lastTime = currentTime
        node.pause()
        engine.pause()
        isPlaying = false
        updateNowPlaying()
        saveState()
    }

    @discardableResult
    func next() -> Bool {
        guard !queue.isEmpty else { return false }
        countedCurrent = false
        if index + 1 < queue.count {
            index += 1
            start(at: 0, autoplay: isPlaying)
        } else {
            index = 0
            start(at: 0, autoplay: repeatAll && isPlaying)
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
        countedCurrent = false
        index = index == 0 ? queue.count - 1 : index - 1
        start(at: 0, autoplay: isPlaying)
        return true
    }

    func seek(to t: Double) {
        guard current != nil else { return }
        start(at: min(max(t, 0), max(duration - 0.5, 0)), autoplay: isPlaying)
    }

    func seek(by delta: Double) { seek(to: currentTime + delta) }

    /// Current loudness 0...1 for the equalizer (polled by the view each frame).
    func meterLevel() -> Float {
        guard isPlaying else { return 0 }
        let rms = meter.get()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
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
        // Line up the wrap-around to the first track if we're on the last one.
        if repeatAll { scheduleNextIfGapless() }
    }

    func cycleEQ() {
        eqPreset = eqPreset.next
        UserDefaults.standard.set(eqPreset.rawValue, forKey: "eqPreset")
        applyEQ()
    }

    // MARK: Resume

    private struct SavedState: Codable {
        var ids: [String]
        var index: Int
        var time: Double
    }

    private static let stateKey = "resumeState"

    /// Persists the queue, current track and position so a relaunch picks up where we left off.
    func saveState() {
        guard current != nil else { UserDefaults.standard.removeObject(forKey: Self.stateKey); return }
        let state = SavedState(ids: queue.map(\.id), index: index, time: currentTime)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    /// Rebuilds the last session's queue (paused) from the library. Missing files are dropped.
    func restoreState(library tracks: [Track]) {
        guard queue.isEmpty,
              let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(SavedState.self, from: data),
              state.ids.indices.contains(state.index) else { return }
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let restored = state.ids.compactMap { byID[$0] }
        guard !restored.isEmpty else { return }
        let currentID = state.ids[state.index]
        let newIndex = restored.firstIndex { $0.id == currentID }
        queue = restored
        index = newIndex ?? 0
        let time = newIndex != nil ? state.time : 0
        countedCurrent = time >= 30
        start(at: time, autoplay: false)
    }

    // MARK: Engine

    private func setUpEngine() {
        engine.attach(node)
        engine.attach(eq)
        engine.attach(reverb)
        engine.attach(ambience)
        ambience.feedback = 0
        ambience.lowPassCutoff = 7_000
        for (i, band) in eq.bands.enumerated() {
            band.frequency = EQPreset.frequencies[i]
            band.filterType = i == 0 ? .lowShelf : (i == eq.bands.count - 1 ? .highShelf : .parametric)
            band.bandwidth = 1.0
            band.bypass = false
        }
        applyEQ()
        connect(format: AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.meterTap(meter))
    }

    private func applyEQ() {
        let p = eqPreset
        for (i, band) in eq.bands.enumerated() { band.gain = p.gains[i] }
        eq.globalGain = p.headroom
        if let r = p.reverb {
            reverb.loadFactoryPreset(r.preset)
            reverb.wetDryMix = r.wet
            reverb.bypass = false
        } else {
            reverb.wetDryMix = 0
            reverb.bypass = true
        }
        if let a = p.ambience {
            ambience.delayTime = a.time
            ambience.wetDryMix = a.wet
            ambience.bypass = false
        } else {
            ambience.wetDryMix = 0
            ambience.bypass = true
        }
    }

    private func connect(format: AVAudioFormat) {
        if let f = connectedFormat, f.sampleRate == format.sampleRate, f.channelCount == format.channelCount { return }
        if engine.isRunning { engine.stop() }
        let chain: [AVAudioNode] = [node, eq, reverb, ambience]
        for n in chain { engine.disconnectNodeOutput(n) }
        for (a, b) in zip(chain, chain.dropFirst()) { engine.connect(a, to: b, format: format) }
        engine.connect(ambience, to: engine.mainMixerNode, format: format)
        connectedFormat = format
    }

    @discardableResult
    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        engine.prepare()
        do { try engine.start(); return true } catch { return false }
    }

    /// (Re)schedules the current track from `time`, plus the next one for gapless playback.
    private func start(at time: Double, autoplay: Bool) {
        generation += 1
        node.stop()
        currentSeg = nil
        nextSeg = nil
        var time = time
        var attempts = 0
        while attempts < queue.count, let track = current {
            if let file = try? AVAudioFile(forReading: track.url), file.length > 0 {
                connect(format: file.processingFormat)
                let sr = file.processingFormat.sampleRate
                let startFrame = min(AVAudioFramePosition(max(time, 0) * sr), file.length - 1)
                let seg = Segment(index: index, file: file, startFrame: startFrame, nodeStart: 0,
                                  frames: file.length - startFrame)
                schedule(seg)
                currentSeg = seg
                lastTime = Double(startFrame) / sr
                scheduleNextIfGapless()
                if autoplay {
                    Self.activateForPlayback()
                    if startEngine() { node.play() }
                }
                isPlaying = autoplay && engine.isRunning
                updateNowPlaying()
                saveState()
                return
            }
            // Unplayable or missing file: skip it.
            attempts += 1
            index = (index + 1) % queue.count
            time = 0
        }
        isPlaying = false
        updateNowPlaying()
    }

    private func nextIndex(after i: Int) -> Int? {
        if i + 1 < queue.count { return i + 1 }
        return repeatAll ? 0 : nil
    }

    private func scheduleNextIfGapless() {
        guard let seg = currentSeg, nextSeg == nil, let ni = nextIndex(after: seg.index),
              queue.indices.contains(ni),
              let file = try? AVAudioFile(forReading: queue[ni].url), file.length > 0,
              let format = connectedFormat,
              file.processingFormat.sampleRate == format.sampleRate,
              file.processingFormat.channelCount == format.channelCount else { return }
        let next = Segment(index: ni, file: file, startFrame: 0,
                           nodeStart: seg.nodeStart + seg.frames, frames: file.length)
        schedule(next)
        nextSeg = next
    }

    private func schedule(_ seg: Segment) {
        let gen = generation
        node.scheduleSegment(
            seg.file, startingFrame: seg.startFrame, frameCount: AVAudioFrameCount(seg.frames),
            at: nil, completionCallbackType: .dataPlayedBack,
            completionHandler: Self.completion { [weak self] in self?.segmentFinished(generation: gen) }
        )
    }

    private func segmentFinished(generation gen: Int) {
        guard gen == generation, let seg = currentSeg else { return }
        countedCurrent = false
        if let next = nextSeg {
            // Already playing, sample-accurately. Just move the bookkeeping along.
            currentSeg = next
            nextSeg = nil
            index = next.index
            updateNowPlaying()
            saveState()
            scheduleNextIfGapless()
        } else if let ni = nextIndex(after: seg.index) {
            index = ni
            start(at: 0, autoplay: true)
        } else {
            index = 0
            start(at: 0, autoplay: false)
        }
    }

    /// Position from the node's clock, or nil while it isn't rendering.
    private func liveTime() -> Double? {
        guard isPlaying, let seg = currentSeg,
              let renderTime = node.lastRenderTime, renderTime.isSampleTimeValid,
              let playerTime = node.playerTime(forNodeTime: renderTime) else { return nil }
        let into = min(max(playerTime.sampleTime - seg.nodeStart, 0), seg.frames)
        return Double(seg.startFrame + into) / seg.sampleRate
    }

    /// Once a second: remember the position, count listens, save every few seconds.
    private func heartbeat(saving: Bool) {
        guard isPlaying, let live = liveTime() else { return }
        lastTime = live
        if !countedCurrent, let track = current, live >= min(30, duration * 0.5) {
            countedCurrent = true
            onPlayCounted?(track.id)
        }
        if saving { saveState() }
    }

    /// Our music takes over the session (no mixing) so it owns the lock screen and remote controls.
    /// Click sounds may have switched the session to mix with another app's audio while idle.
    private static func activateForPlayback() {
        let session = AVAudioSession.sharedInstance()
        if !session.categoryOptions.isEmpty || session.category != .playback {
            try? session.setCategory(.playback, mode: .default, options: [])
        }
        try? session.setActive(true)
    }

    // MARK: Callbacks (built nonisolated: AVFoundation calls them on its own threads)

    nonisolated private static func completion(
        _ body: @escaping @MainActor @Sendable () -> Void
    ) -> AVAudioPlayerNodeCompletionHandler {
        { _ in Task { @MainActor in body() } }
    }

    nonisolated private static func meterTap(_ box: MeterBox) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let count = Int(buffer.format.channelCount)
            guard frames > 0, count > 0 else { return }
            var sum: Float = 0
            for c in 0..<count {
                let p = channels[c]
                for i in 0..<frames { sum += p[i] * p[i] }
            }
            box.set(sqrt(sum / Float(frames * count)))
        }
    }

    // MARK: System

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
        // Route/format changes (e.g. AirPods connecting) stop the engine; pick up where we were.
        observers.append(nc.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            let service = self
            MainActor.assumeIsolated { service?.engineConfigurationChanged() }
        })
    }

    private func engineConfigurationChanged() {
        guard isPlaying else { return }
        start(at: lastTime, autoplay: true)
    }

    private func interruption(type: UInt, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue {
            guard isPlaying else { return }
            lastTime = liveTime() ?? lastTime
            node.pause()
            isPlaying = false
            updateNowPlaying()
            saveState()
        } else if type == AVAudioSession.InterruptionType.ended.rawValue,
                  AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
            start(at: lastTime, autoplay: true)
        }
    }
}
