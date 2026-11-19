@preconcurrency import AVFoundation
import Foundation
import Observation

/// The ambient mixer: layers built-in sounds, each at its own level, on an engine of its own, so
/// the music's EQ and reverb never touch it and a problem here can't stop the music.
///
/// Recordings are decoded into memory once and looped sample-accurately; bells are re-struck at
/// random intervals; noise and tones are generated live. Every level change is ramped, so nothing
/// clicks or zips.
@MainActor @Observable
final class SoundMixer {
    static let maxActive = 6
    static let startLevel: Float = 0.5

    /// Level (0...1) of every sound in the mix, keyed by sound id.
    private(set) var levels: [String: Float]
    private(set) var isPlaying = false

    /// Active sounds in list order.
    var active: [AmbientSound] { AmbientSound.all.filter { levels[$0.id] != nil } }
    var activeTitles: [String] { active.map(\.title) }

    /// Lets the player refresh lock-screen info when the mix changes.
    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored weak var player: PlayerService?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var channels: [String: Channel] = [:]
    @ObservationIgnored private var master = Ramp(current: 1, target: 1, step: 1)
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var nextToken = 0

    private static let tick = 0.01
    private static let stereo = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: "soundMix") as? [String: Double] ?? [:]
        levels = saved.reduce(into: [:]) { result, pair in
            if AmbientSound.byID[pair.key] != nil, pair.value > 0 { result[pair.key] = Float(min(pair.value, 1)) }
        }
        #if DEBUG
        for sound in AmbientSound.all where sound.fileURL == nil {
            if case .generated = sound.kind { continue }
            assertionFailure("Missing bundled sound \(sound.id).m4a")
        }
        #endif
        _ = engine.mainMixerNode
        observe()
    }

    // MARK: Mix

    /// Adds a sound at the starting level and starts the mix. False when the mix is full.
    @discardableResult
    func turnOn(_ id: String) -> Bool {
        guard let sound = AmbientSound.byID[id] else { return false }
        if levels[id] != nil { return true }
        guard levels.count < Self.maxActive else { return false }
        levels[id] = Self.startLevel
        save()
        if isPlaying {
            open(sound, fadeIn: 1.5)
            changed()
        } else {
            play()
        }
        return true
    }

    /// 0 takes the sound out of the mix (fading out over a second).
    func setLevel(_ id: String, _ level: Float) {
        guard levels[id] != nil else { return }
        let level = min(max(level, 0), 1)
        if level <= 0.001 {
            turnOff(id)
            return
        }
        levels[id] = level
        save()
        channels[id]?.gain.move(to: Self.gain(level), over: 0.05, tick: Self.tick)
        runTicker()
    }

    func turnOff(_ id: String) {
        guard levels.removeValue(forKey: id) != nil else { return }
        save()
        if let ch = channels[id] {
            ch.removing = true
            ch.gain.move(to: 0, over: 1, tick: Self.tick)
            runTicker()
        }
        if levels.isEmpty, isPlaying { pause(fade: 1) } else { changed() }
    }

    func clear() {
        for id in levels.keys { turnOff(id) }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !levels.isEmpty else { return }
        activateSession()
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return }
        }
        let wasPlaying = isPlaying
        isPlaying = true
        player?.owner = .mix
        if !wasPlaying {
            master = Ramp(current: 0, target: 1, step: 0)
            master.move(to: 1, over: 0.6, tick: Self.tick)
            engine.mainMixerNode.outputVolume = 0
        } else if master.target < 1 {
            // Already playing but fading (a pause in progress): come back up.
            master.move(to: 1, over: 0.3, tick: Self.tick)
        }
        for sound in active {
            if let ch = channels[sound.id] {
                ch.removing = false
                ch.gain.move(to: Self.gain(levels[sound.id] ?? Self.startLevel), over: 0.05, tick: Self.tick)
                ch.resume()
            } else {
                open(sound, fadeIn: 0.05)
            }
        }
        runTicker()
        changed()
    }

    /// Fades out, then stops the engine. Levels and the mix stay for next time.
    func pause(fade: Double = 0.3) {
        guard isPlaying else { return }
        isPlaying = false
        changed()
        Task { [weak self] in
            await self?.fade(to: 0, over: fade)
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
            for ch in self.channels.values { ch.suspend() }
        }
    }

    /// Ramps the whole mix (for the sleep timer); returns when done or superseded.
    func fade(to gain: Float, over seconds: Double) async {
        master.move(to: gain, over: seconds, tick: Self.tick)
        let target = master.target
        runTicker()
        while master.current != master.target, master.target == target {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Channels

    /// One sound's node in the engine. Its level is its node's mixing volume.
    private final class Channel {
        let sound: AmbientSound
        let token: Int
        var node: AVAudioNode?
        var buffer: AVAudioPCMBuffer?
        var gain: Ramp
        var removing = false
        var strikes: Task<Void, Never>?

        init(sound: AmbientSound, token: Int, gain: Ramp) {
            self.sound = sound
            self.token = token
            self.gain = gain
        }

        var player: AVAudioPlayerNode? { node as? AVAudioPlayerNode }

        func apply() { (node as? AVAudioMixing)?.volume = gain.current }

        /// (Re)starts playback from a stopped player (first start, or after the engine restarted).
        func schedule() {
            guard let player, let buffer else { return }
            player.stop()
            switch sound.kind {
            case .loop:
                player.scheduleBuffer(buffer, at: nil, options: .loops)
            case .struck(_, let every):
                player.scheduleBuffer(buffer, at: nil)
                strikes?.cancel()
                strikes = Task { @MainActor [weak player] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(Double.random(in: every)))
                        guard !Task.isCancelled, let player else { return }
                        player.scheduleBuffer(buffer, at: nil, completionHandler: nil)
                    }
                }
            case .generated:
                break
            }
            // play() on a node whose engine isn't running raises; the restart path reschedules it.
            if player.engine?.isRunning == true { player.play() }
        }

        /// Starts a paused or stopped player again from the top: loops are seamless anyway, and a
        /// bell gets a fresh strike. A player still decoding starts once its buffer arrives.
        func resume() {
            guard let player, !player.isPlaying else { return }
            schedule()
        }

        func suspend() {
            strikes?.cancel()
            strikes = nil
            player?.stop()
        }

        func close() {
            strikes?.cancel()
            strikes = nil
            player?.stop()
        }
    }

    private func open(_ sound: AmbientSound, fadeIn: Double) {
        if let ch = channels[sound.id] {
            // Still fading out: bring it back.
            ch.removing = false
            ch.gain.move(to: Self.gain(levels[sound.id] ?? Self.startLevel), over: fadeIn, tick: Self.tick)
            ch.resume()
            runTicker()
            return
        }
        nextToken += 1
        let ch = Channel(sound: sound, token: nextToken, gain: Ramp(current: 0, target: 0, step: 0))
        ch.gain.move(to: Self.gain(levels[sound.id] ?? Self.startLevel), over: fadeIn, tick: Self.tick)
        channels[sound.id] = ch

        switch sound.kind {
        case .generated(let g):
            let node = Self.makeSourceNode(g, format: Self.stereo)
            attach(node, to: ch, format: Self.stereo)
        case .loop, .struck:
            guard let url = sound.fileURL else { channels[sound.id] = nil; return }
            let token = ch.token
            Task {
                guard let decoded = await Self.decode(url) else { return }
                // Turned off (or replaced) while decoding: drop it.
                guard let ch = self.channels[sound.id], ch.token == token else { return }
                ch.buffer = decoded.buffer
                let player = AVAudioPlayerNode()
                self.attach(player, to: ch, format: decoded.buffer.format)
                if self.isPlaying { ch.schedule() }
            }
        }
        runTicker()
    }

    private func attach(_ node: AVAudioNode, to ch: Channel, format: AVAudioFormat) {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        ch.node = node
        ch.apply()
    }

    private func close(_ id: String) {
        guard let ch = channels.removeValue(forKey: id) else { return }
        ch.close()
        if let node = ch.node { engine.detach(node) }
    }

    // MARK: Ramps

    /// A value moving linearly toward a target, one tick at a time.
    private struct Ramp {
        var current: Float
        var target: Float
        var step: Float

        mutating func move(to value: Float, over seconds: Double, tick: Double) {
            target = value
            step = abs(value - current) / Float(max(seconds / tick, 1))
        }

        /// Returns whether it moved.
        mutating func advance() -> Bool {
            guard current != target else { return false }
            current = current < target ? min(current + step, target) : max(current - step, target)
            return true
        }
    }

    /// Perceptual level → node gain: 50% sits about 7 dB down, 100% a little above unity.
    private static func gain(_ level: Float) -> Float { pow(level, 1.5) * 1.25 }

    private func runTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(Self.tick * 1000)))
                guard let self else { return }
                if !self.step() { self.ticker = nil; return }
            }
        }
    }

    /// Advances every ramp one tick; false once everything has settled.
    private func step() -> Bool {
        var moving = false
        if master.advance() {
            engine.mainMixerNode.outputVolume = master.current
            moving = true
        }
        for (id, ch) in channels {
            if ch.gain.advance() {
                ch.apply()
                moving = true
            } else if ch.removing, ch.gain.current == 0 {
                close(id)
            }
        }
        return moving || channels.values.contains { $0.removing }
    }

    // MARK: Engine and session

    /// Mix under other apps' audio (a podcast) if one is playing and our music isn't; otherwise take
    /// the session like our music does, so the mix owns the lock screen.
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if session.isOtherAudioPlaying, player?.isPlaying != true {
            if !session.categoryOptions.contains(.mixWithOthers) {
                try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
        } else if session.category != .playback || !session.categoryOptions.isEmpty {
            try? session.setCategory(.playback, mode: .default, options: [])
        }
        try? session.setActive(true)
    }

    /// The engine stopped under us (route change, AirPods, a session category switch by the music):
    /// start it again and restart every player, which lose their schedules when the engine stops.
    private func restartIfNeeded() {
        guard isPlaying else { return }
        let restarted = !engine.isRunning
        if restarted {
            engine.prepare()
            guard (try? engine.start()) != nil else {
                isPlaying = false
                changed()
                return
            }
        }
        // After a restart, players may report playing yet have lost their schedules: redo them all.
        for ch in channels.values where ch.player != nil && (restarted || ch.player?.isPlaying != true) {
            ch.schedule()
        }
    }

    private func observe() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            let mixer = self
            MainActor.assumeIsolated { mixer?.restartIfNeeded() }
        })
        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let mixer = self
            MainActor.assumeIsolated {
                guard let mixer else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    guard mixer.isPlaying else { return }
                    mixer.isPlaying = false
                    for ch in mixer.channels.values { ch.suspend() }
                    mixer.resumeAfterInterruption = true
                    mixer.changed()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    defer { mixer.resumeAfterInterruption = false }
                    if mixer.resumeAfterInterruption,
                       AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        mixer.play()
                    }
                }
            }
        })
        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            let mixer = self
            MainActor.assumeIsolated {
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    mixer?.pause()
                } else {
                    mixer?.restartIfNeeded()
                }
            }
        })
    }

    @ObservationIgnored private var resumeAfterInterruption = false

    private func changed() {
        onStateChange?()
    }

    private func save() {
        UserDefaults.standard.set(levels.mapValues { Double($0) }, forKey: "soundMix")
    }

    // MARK: Off the main actor

    private struct Decoded: @unchecked Sendable { let buffer: AVAudioPCMBuffer }

    nonisolated private static func decode(_ url: URL) async -> Decoded? {
        await Task.detached(priority: .userInitiated) {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { return nil }
            return Decoded(buffer: buffer)
        }.value
    }

    /// Built nonisolated so the render block never inherits the main actor: it runs on the audio
    /// thread and owns its generator state outright.
    nonisolated private static func makeSourceNode(_ g: Generator, format: AVAudioFormat) -> AVAudioSourceNode {
        final class VoiceBox: @unchecked Sendable { var voice: GeneratorVoice; init(_ v: GeneratorVoice) { voice = v } }
        let box = VoiceBox(GeneratorVoice(g, sampleRate: format.sampleRate))
        return AVAudioSourceNode(format: format) { _, _, frameCount, data in
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frameCount) {
                let (a, b) = box.voice.next()
                l[i] = a
                r[i] = b
            }
            return noErr
        }
    }
}
