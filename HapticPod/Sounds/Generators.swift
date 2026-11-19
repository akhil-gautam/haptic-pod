import Foundation

/// Sounds rendered live in code: no files, no licences, never the same twice.
enum Generator: Sendable, Hashable {
    case white, pink, brown, drone, theta
}

/// Sample-by-sample state for one generator. Plain value type so it can live inside a render block
/// on the audio thread (no locks, no allocation) and be measured offline.
struct GeneratorVoice {
    let kind: Generator
    let sampleRate: Double

    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var pinkL = Pink(), pinkR = Pink()
    private var brownL: Float = 0, brownR: Float = 0
    private var phases = [Double](repeating: 0, count: 6)
    private var t: Double = 0
    /// Drone partials (Hz, amplitude). Held per voice so the audio thread never touches a lazy global.
    private let droneParts: [(Double, Float)] = [(55, 1.0), (110, 0.55), (165, 0.25)]

    init(_ kind: Generator, sampleRate: Double, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.kind = kind
        self.sampleRate = sampleRate
        rng = seed
    }

    /// Output gain per generator, set so each sits near the recordings' level (about -24 LUFS).
    private var gain: Float {
        switch kind {
        case .white: 0.044
        case .pink: 0.244
        case .brown: 0.27
        case .drone: 0.104
        case .theta: 0.063
        }
    }

    mutating func next() -> (Float, Float) {
        let (l, r): (Float, Float)
        switch kind {
        case .white:
            (l, r) = (white(), white())
        case .pink:
            (l, r) = (pinkL.next(white()), pinkR.next(white()))
        case .brown:
            brownL = (brownL + 0.02 * white()) / 1.02
            brownR = (brownR + 0.02 * white()) / 1.02
            (l, r) = (brownL * 3.5, brownR * 3.5)
        case .drone:
            // Three partials of A1, each a touch detuned between ears, breathing every 20 s.
            let swell = Float(0.75 + 0.25 * sin(2 * .pi * 0.05 * t))
            var sl: Float = 0, sr: Float = 0
            for (i, (f, a)) in droneParts.enumerated() {
                sl += a * Float(sin(advance(i, f - 0.3)))
                sr += a * Float(sin(advance(i + 3, f + 0.3)))
            }
            (l, r) = (sl * swell, sr * swell)
        case .theta:
            // 200 Hz left, 206 Hz right: a 6 Hz beat heard inside the head (needs headphones),
            // over a soft pink bed.
            let bed = pinkL.next(white()) * 0.15
            (l, r) = (Float(sin(advance(0, 200))) + bed, Float(sin(advance(1, 206))) + bed)
        }
        t += 1 / sampleRate
        return (l * gain, r * gain)
    }

    private mutating func advance(_ i: Int, _ freq: Double) -> Double {
        phases[i] += 2 * .pi * freq / sampleRate
        if phases[i] > 2 * .pi { phases[i] -= 2 * .pi }
        return phases[i]
    }

    /// Uniform in -1...1 (xorshift64*).
    private mutating func white() -> Float {
        rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27
        let x = rng &* 0x2545_F491_4F6C_DD1D
        return Float(Double(x >> 11) / Double(1 << 53)) * 2 - 1
    }

    /// Paul Kellet's refined pink-noise filter.
    private struct Pink {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        mutating func next(_ w: Float) -> Float {
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
            b6 = w * 0.115926
            return out * 0.11
        }
    }
}
