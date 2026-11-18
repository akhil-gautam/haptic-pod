import CoreHaptics
import Observation
import QuartzCore
import UIKit

@MainActor @Observable
final class Haptics {
    /// tick/tickSoft: wheel detents. pressDown/pressUp: centre button travel.
    /// click: a full press+release for the ring buttons. home: back. thud: end stop / no-op.
    enum Kind: CaseIterable { case tick, tickSoft, pressDown, pressUp, click, home, thud, double }

    enum Level: Int, CaseIterable {
        case off, low, medium, high
        var label: String { ["OFF", "LOW", "MED", "HIGH"][rawValue] }
        var scale: Float { [0, 0.5, 0.75, 1][rawValue] }
    }

    private(set) var level: Level
    private(set) var clickSound: Bool

    @ObservationIgnored private var engine: CHHapticEngine?
    /// Texture feel for touches on the device body (metal, wheel rim, display glass).
    @ObservationIgnored private(set) var surface: SurfaceHaptics!
    @ObservationIgnored private let sound = ClickSound()
    @ObservationIgnored private var players: [Kind: CHHapticPatternPlayer] = [:]
    @ObservationIgnored private var needsStart = true
    @ObservationIgnored private var lastTick: CFTimeInterval = 0
    @ObservationIgnored private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    @ObservationIgnored private let selectionGen = UISelectionFeedbackGenerator()
    @ObservationIgnored private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let heavyGen = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        let stored = UserDefaults.standard.object(forKey: "hapticLevel") as? Int
        level = Level(rawValue: stored ?? Level.high.rawValue) ?? .high
        clickSound = UserDefaults.standard.bool(forKey: "clickSound")
        surface = SurfaceHaptics(host: self)
    }

    /// The running engine, or nil when haptics are off or unsupported.
    var liveEngine: CHHapticEngine? {
        guard level != .off, supportsHaptics, let engine else { return nil }
        if needsStart { start() }
        return engine
    }

    func prepare() {
        selectionGen.prepare()
        rigidGen.prepare()
        heavyGen.prepare()
        guard supportsHaptics, engine == nil, let e = try? CHHapticEngine() else { return }
        e.playsHapticsOnly = true          // stay out of the music audio session
        e.isAutoShutdownEnabled = false    // no wake-up latency on the first tick
        Self.installHandlers(on: e, owner: self)
        engine = e
        rebuildPlayers()
        start()
    }

    func start() {
        guard let engine else { return }
        do { try engine.start(); needsStart = false } catch { needsStart = true }
    }

    func stop() {
        surface.ended()
        engine?.stop()
        needsStart = true
    }

    func cycleLevel() {
        level = Level(rawValue: (level.rawValue + 1) % Level.allCases.count) ?? .high
        UserDefaults.standard.set(level.rawValue, forKey: "hapticLevel")
        rebuildPlayers()
        surface.reset()
    }

    func toggleClickSound() {
        clickSound.toggle()
        UserDefaults.standard.set(clickSound, forKey: "clickSound")
    }

    func play(_ kind: Kind) {
        let isTick = kind == .tick || kind == .tickSoft
        if isTick {
            let now = CACurrentMediaTime()
            if now - lastTick < 0.012 { return }
            lastTick = now
        }
        if clickSound {
            switch kind {
            case .tick: sound.play(.tick)
            case .tickSoft: sound.play(.tickSoft)
            case .pressDown: sound.play(.press)
            case .pressUp: sound.play(.release)
            case .click, .double: sound.play(.click)
            case .home: sound.play(.home)
            case .thud: sound.play(.thud)
            }
        }
        guard level != .off else { return }
        guard supportsHaptics, let player = players[kind] else { fallback(kind); return }
        if needsStart { start() }
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            needsStart = true
            fallback(kind)
        }
    }

    // MARK: Private

    private func markStopped() { needsStart = true }

    private func handleReset() {
        needsStart = true
        surface.reset()
        rebuildPlayers()
        start()
    }

    /// Built in a nonisolated context so the closures don't inherit @MainActor
    /// (Core Haptics calls them on its own queue).
    nonisolated private static func installHandlers(on engine: CHHapticEngine, owner: Haptics) {
        engine.stoppedHandler = { [weak owner] _ in
            let o = owner
            Task { @MainActor in o?.markStopped() }
        }
        engine.resetHandler = { [weak owner] in
            let o = owner
            Task { @MainActor in o?.handleReset() }
        }
    }

    private func rebuildPlayers() {
        guard let engine else { return }
        players = [:]
        for kind in Kind.allCases {
            if let pattern = try? pattern(for: kind), let p = try? engine.makePlayer(with: pattern) {
                players[kind] = p
            }
        }
    }

    private func pattern(for kind: Kind) throws -> CHHapticPattern {
        let s = level.scale
        func event(_ intensity: Float, _ sharpness: Float, at t: TimeInterval = 0) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity * s)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: t
            )
        }
        let events: [CHHapticEvent]
        switch kind {
        // Detents: tiny, glassy, maximum sharpness so fast scrolling reads as a ratchet.
        case .tick: events = [event(0.62, 1.0)]
        case .tickSoft: events = [event(0.42, 1.0)]
        // Centre button: firm bottom-out on press, faint snap on release.
        case .pressDown: events = [event(1.0, 0.72)]
        case .pressUp: events = [event(0.36, 0.9)]
        // Ring buttons fire on lift, so play the whole press + release travel at once.
        case .click: events = [event(0.95, 0.72), event(0.34, 0.9, at: 0.045)]
        // Back: deeper, rounder click than the ring buttons so it reads differently.
        case .home: events = [event(0.9, 0.42), event(0.3, 0.8, at: 0.05)]
        // End of list / nothing to select: dull, soft knock.
        case .thud: events = [event(0.8, 0.12), event(0.35, 0.05, at: 0.03)]
        // Long-press home: two quick firm clicks.
        case .double: events = [event(0.75, 0.65), event(1.0, 0.6, at: 0.085)]
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private func fallback(_ kind: Kind) {
        let s = CGFloat(level.scale)
        switch kind {
        case .tick, .tickSoft: selectionGen.selectionChanged()
        case .pressDown, .pressUp, .click, .double: rigidGen.impactOccurred(intensity: s)
        case .home, .thud: heavyGen.impactOccurred(intensity: s)
        }
    }
}
