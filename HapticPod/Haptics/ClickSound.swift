@preconcurrency import AVFoundation

/// Synthesised click-wheel sounds played through the app's own audio session.
///
/// System sounds (AudioServicesPlaySystemSound) are muted by the ring/silent switch and the
/// "Keyboard Clicks" setting, so clicks went missing. These play like media instead: they follow
/// the media volume and mix with the music.
@MainActor
final class ClickSound {
    enum Sound: CaseIterable { case tick, tickSoft, press, release, click, home, thud }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var configured = false

    func play(_ sound: Sound) {
        guard ensureRunning(), let buffer = buffers[sound] else { return }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    private func ensureRunning() -> Bool {
        if !configured {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            for sound in Sound.allCases { buffers[sound] = makeBuffer(sound) }
            configured = true
        }
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    // MARK: Synthesis

    /// One mechanical "tick": a very short noise transient plus a damped resonance.
    private struct Strike {
        var at: Double       // seconds
        var gain: Float
        var pitch: Double    // resonance Hz
        var decay: Double    // resonance decay, seconds
    }

    private func strikes(for sound: Sound) -> [Strike] {
        switch sound {
        case .tick:     [Strike(at: 0, gain: 0.55, pitch: 3_400, decay: 0.0018)]
        case .tickSoft: [Strike(at: 0, gain: 0.32, pitch: 3_600, decay: 0.0014)]
        case .press:    [Strike(at: 0, gain: 0.75, pitch: 1_900, decay: 0.0035)]
        case .release:  [Strike(at: 0, gain: 0.35, pitch: 2_600, decay: 0.0020)]
        case .click:    [Strike(at: 0, gain: 0.75, pitch: 1_900, decay: 0.0035),
                         Strike(at: 0.045, gain: 0.32, pitch: 2_600, decay: 0.0020)]
        case .home:     [Strike(at: 0, gain: 0.75, pitch: 1_300, decay: 0.0045),
                         Strike(at: 0.05, gain: 0.28, pitch: 2_200, decay: 0.0020)]
        case .thud:     [Strike(at: 0, gain: 0.6, pitch: 420, decay: 0.012)]
        }
    }

    private func makeBuffer(_ sound: Sound) -> AVAudioPCMBuffer? {
        let parts = strikes(for: sound)
        let sr = format.sampleRate
        let length = (parts.map { $0.at + $0.decay * 8 }.max() ?? 0.02) + 0.005
        let frames = AVAudioFrameCount(length * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        var seed: UInt32 = 0x9E37_79B9
        func noise() -> Float {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Float(seed) / Float(UInt32.max) * 2 - 1
        }

        for i in 0..<Int(frames) { out[i] = 0 }
        for s in parts {
            let start = Int(s.at * sr)
            for i in start..<Int(frames) {
                let t = Double(i - start) / sr
                let body = sin(2 * .pi * s.pitch * t) * exp(-t / s.decay)
                let snap = Double(noise()) * exp(-t / 0.0004)
                out[i] += s.gain * Float(0.7 * body + 0.45 * snap)
            }
        }
        for i in 0..<Int(frames) { out[i] = max(-1, min(1, out[i])) }
        return buffer
    }
}
