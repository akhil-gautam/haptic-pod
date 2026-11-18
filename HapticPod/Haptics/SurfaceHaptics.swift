import CoreHaptics
import QuartzCore

/// Material feel for fingers on the device body.
///
/// A scratch is not a vibration: it is a fast run of tiny, irregular catches whose rate follows how
/// far the finger travels, not a clock. So nothing here hums. Every grain is placed along the
/// finger's actual path, with random spacing and strength, and played at the moment within the
/// frame that the finger passed it.
///
/// - Metal: a dense knock on touch-down. Sliding raises fine grit. Across the grain you also catch
///   on the brushing grooves, placed on the same texture rows that are drawn, so the ridges you
///   feel are the streaks you see.
/// - Wheel rim / display seam: a step as the finger crosses it; the wheel and glass are smooth.
/// - A resting finger feels nothing.
@MainActor
final class SurfaceHaptics {
    enum Material { case metal, wheel, glass }

    private weak var host: Haptics?
    private var engine: CHHapticEngine?
    private var tap: CHHapticPatternPlayer?
    private var edge: CHHapticPatternPlayer?
    /// Recent one-shot grain players, kept alive until they have played.
    private var inFlight: [CHHapticPatternPlayer] = []

    private var last: (point: CGPoint, time: CFTimeInterval)?
    private var material: Material = .metal
    private var speed: CGFloat = 0          // smoothed, pt/s
    private var toNextGrit: CGFloat = 2     // path distance until the next grit grain
    private var seed: UInt32 = 0x2545_F491
    private var seamLast: (y: CGFloat, time: CFTimeInterval)?

    init(host: Haptics) { self.host = host }

    /// Drop players after an engine reset or a level change; they are rebuilt on the next touch.
    func reset() {
        ended()
        engine = nil; tap = nil; edge = nil; inFlight = []
    }

    /// Feed every touch position (in the metal body's coordinates) while the finger is down.
    func track(_ point: CGPoint, on newMaterial: Material) {
        guard let live = host?.liveEngine else { return }
        if engine !== live { build(live) }
        let now = CACurrentMediaTime()

        guard let prev = last else {
            last = (point, now)
            material = newMaterial
            speed = 0
            if newMaterial == .metal { fire(tap) }
            return
        }

        let dx = point.x - prev.point.x, dy = point.y - prev.point.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > 0.2 else { return }
        let dt = now - prev.time
        speed = speed * 0.5 + (dist / max(dt, 1.0 / 240)) * 0.5
        last = (point, now)

        if newMaterial != material {
            // The display seam has its own bump (see `trackSeam`); only the wheel rim fires here.
            if material != .glass && newMaterial != .glass { fire(edge) }
            material = newMaterial
            return
        }
        guard material == .metal else { return }
        // The finger covered this path during the last frame; replay it over one frame.
        scratch(from: prev.point, dx: dx, dy: dy, dist: dist, over: min(max(dt, 1.0 / 240), 1.0 / 60))
    }

    func ended() {
        last = nil
        speed = 0
    }

    // MARK: Display seam

    /// Feed every touch's y (device coordinates) anywhere on screen; `seamY` is where the display
    /// meets the metal. Crossing it rolls the finger over a rounded ridge: a swell that builds,
    /// a firm crest, then a fall-off, stretched to how long the finger takes to cross (~6 pt).
    /// Climbing onto the glass has a crisper leading edge; dropping onto the metal a heavier landing.
    func trackSeam(y: CGFloat, seamY: CGFloat) {
        let now = CACurrentMediaTime()
        defer { seamLast = (y, now) }
        guard let prev = seamLast, (prev.y - seamY) * (y - seamY) < 0 || (y == seamY && prev.y != seamY),
              let live = host?.liveEngine else { return }
        if engine !== live { build(live) }
        let speed = abs(y - prev.y) / max(now - prev.time, 1.0 / 240)
        let d = min(max(Double(6 / max(speed, 1)), 0.035), 0.09)
        let crest = d * 0.45
        let up = y < seamY
        let scale = host?.level.scale ?? 0
        func transient(_ i: Float, _ sh: Float, _ t: TimeInterval) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, i * scale)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sh),
            ], relativeTime: t)
        }
        let swell = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: scale),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22),
        ], relativeTime: 0, duration: d)
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.3),
            .init(relativeTime: crest, value: 1.0),
            .init(relativeTime: d, value: 0.0),
        ], relativeTime: 0)
        let events = [
            swell,
            transient(up ? 0.6 : 0.35, up ? 0.6 : 0.3, 0),   // finger meets the lip
            transient(1.0, 0.4, crest),                      // over the top
            transient(up ? 0.35 : 0.7, up ? 0.7 : 0.3, d),   // lands on the other side
        ]
        guard let engine, let pattern = try? CHHapticPattern(events: events, parameterCurves: [curve]),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
        inFlight.append(player)
    }

    func endSeam() { seamLast = nil }

    // MARK: Scratch

    private struct Grain { var t: TimeInterval; var intensity: Float; var sharpness: Float }

    private func scratch(from start: CGPoint, dx: CGFloat, dy: CGFloat, dist: CGFloat, over span: TimeInterval) {
        let pace = Float(min(speed / 700, 1))
        let across = Float(abs(dy) / dist)
        var grains: [Grain] = []

        // Grit: irregular fine catches every 1–4 pt of travel, a little harder across the grain.
        var walked: CGFloat = 0
        while toNextGrit <= dist - walked {
            walked += toNextGrit
            toNextGrit = 1 + rand() * 3
            let catchHard = rand() < 0.07          // the odd stick-slip snag
            let base: Float = catchHard ? 0.9 : 0.32 + Float(rand()) * 0.33
            let intensity = base * (0.55 + 0.45 * pace) * (0.78 + 0.22 * across)
            grains.append(Grain(t: Double(walked / dist) * span, intensity: intensity,
                                sharpness: 0.72 + Float(rand()) * 0.28))
        }
        toNextGrit -= dist - walked

        // Grooves: each brushing streak crossed vertically is a distinct, duller ridge.
        let y0 = start.y, y1 = start.y + dy
        let lo = Int(floor(min(y0, y1))) + 1, hi = Int(floor(max(y0, y1)))
        if lo <= hi, hi - lo < 400, dy != 0 {
            let map = Self.grooveMap
            for y in lo...hi {
                let strength = map[((y % map.count) + map.count) % map.count]
                guard strength > 0 else { continue }
                let frac = (CGFloat(y) - y0) / dy
                grains.append(Grain(t: Double(frac) * span,
                                    intensity: (0.6 + 0.4 * strength) * (0.75 + 0.25 * pace),
                                    sharpness: 0.5))
            }
        }
        play(grains)
    }

    /// Plays grains as one pattern. Grains closer than the actuator can separate are merged,
    /// keeping the stronger one.
    private func play(_ grains: [Grain]) {
        guard let engine, !grains.isEmpty else { return }
        let scale = host?.level.scale ?? 0
        var kept: [Grain] = []
        for g in grains.sorted(by: { $0.t < $1.t }) {
            if let lastKept = kept.last, g.t - lastKept.t < 0.005 {
                if g.intensity > lastKept.intensity { kept[kept.count - 1] = g }
            } else {
                kept.append(g)
            }
        }
        let events = kept.map { g in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, g.intensity * scale)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: g.sharpness),
            ], relativeTime: g.t)
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
        inFlight.append(player)
        if inFlight.count > 12 { inFlight.removeFirst(inFlight.count - 12) }
    }

    /// Groove strength (0...1) for each point of one texture tile; zero between grooves.
    private static let grooveMap: [Float] = {
        let rows = MetalTexture.rows
        let per = MetalTexture.rowsPerPoint
        let count = rows.count / per
        let raw = (0..<count).map { y in (0..<per).map { abs(rows[y * per + $0]) }.max() ?? 0 }
        // Strongest ~1 in 5 points: distinct ridges that stand out from the grit.
        let threshold = raw.sorted()[Int(Double(count) * 0.8)]
        return raw.map { $0 > threshold ? min(1, ($0 - threshold) / max(0.001, 1 - threshold) * 1.4 + 0.3) : 0 }
    }()

    private func rand() -> CGFloat {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return CGFloat(seed % 10_000) / 10_000
    }

    // MARK: Players

    private func fire(_ player: CHHapticPatternPlayer?) {
        try? player?.start(atTime: CHHapticTimeImmediate)
    }

    private func build(_ engine: CHHapticEngine) {
        let scale = host?.level.scale ?? 1
        func transient(_ intensity: Float, _ sharpness: Float, at t: TimeInterval = 0) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity * scale)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: t)
        }
        func player(_ events: [CHHapticEvent]) -> CHHapticPatternPlayer? {
            guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return nil }
            return try? engine.makePlayer(with: pattern)
        }
        // Fingertip on solid aluminium: one dense knock with a faint stiff after-ring.
        tap = player([transient(1.0, 0.85), transient(0.35, 1.0, at: 0.011)])
        // Lip of the wheel rim / display seam: a firm, rounder step.
        edge = player([transient(0.95, 0.5)])
        self.engine = engine
    }
}
