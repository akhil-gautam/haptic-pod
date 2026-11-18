import Foundation
import Observation

/// SAFECRACKER: turn the wheel like a safe dial and find each number of the combination by feel.
///
/// Every number gives the same click sound and a light tick, except the one you're looking for,
/// which "catches": a heavier, duller notch. Press the centre to try the number under the pointer.
/// Each safe allows three wrong tries. Later levels make the catch fainter and closer to an
/// ordinary tick, add near-miss notches either side of it, and use four-number combinations.
@MainActor @Observable
final class SafeGame {
    enum Phase { case playing, opened, lockedOut }

    static let numbers = 40
    static let maxLives = 3

    /// Cumulative dial position in detents (not wrapped), so the dial can animate smoothly.
    private(set) var position = 0
    private(set) var combination: [Int] = []
    private(set) var solved = 0
    private(set) var level = 1
    private(set) var lives = maxLives
    private(set) var phase: Phase = .playing
    private(set) var best: Int
    /// Bumped on every wrong try so the view can shake.
    private(set) var misses = 0

    @ObservationIgnored private let haptics: Haptics

    init(haptics: Haptics) {
        self.haptics = haptics
        best = UserDefaults.standard.integer(forKey: "safeBest")
    }

    /// Number under the pointer, 0..<40.
    var dial: Int { ((position % Self.numbers) + Self.numbers) % Self.numbers }

    func newGame() {
        level = 1
        startSafe()
    }

    func turn(_ delta: Int) {
        guard phase == .playing else { return }
        position += delta
        feel()
    }

    func press() {
        switch phase {
        case .opened:
            level += 1
            startSafe()
            haptics.play(.click)
        case .lockedOut:
            newGame()
            haptics.play(.click)
        case .playing:
            if dial == combination[solved] {
                solved += 1
                if solved == combination.count {
                    phase = .opened
                    if level > best {
                        best = level
                        UserDefaults.standard.set(best, forKey: "safeBest")
                    }
                    haptics.play(.double)
                } else {
                    // The tumbler drops into place.
                    haptics.play(.home)
                }
            } else {
                lives -= 1
                misses += 1
                haptics.play(.thud)
                if lives == 0 { phase = .lockedOut }
            }
        }
    }

    // MARK: Private

    private func startSafe() {
        let digits = level >= 4 ? 4 : 3
        var combo: [Int] = []
        while combo.count < digits {
            let n = Int.random(in: 0..<Self.numbers)
            // Keep numbers apart so near-miss notches never sit on another number of the combination.
            if combo.allSatisfy({ distance($0, n) > 4 }) { combo.append(n) }
        }
        combination = combo
        solved = 0
        lives = Self.maxLives
        phase = .playing
        position = Int.random(in: 0..<Self.numbers)
    }

    private func distance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % Self.numbers
        return min(d, Self.numbers - d)
    }

    /// The haptic for the number now under the pointer.
    private func feel() {
        let tick: Float = 0.42
        let step = Float(level - 1)
        // The catch: heavy and dull on level 1, closing in on a plain tick as levels rise.
        let catchStrength = max(0.95 - 0.07 * step, tick + 0.12)
        let catchSharpness = min(0.3 + 0.07 * step, 0.75)
        switch distance(dial, combination[solved]) {
        case 0:
            haptics.pulse(catchStrength, sharpness: catchSharpness)
        case 1 where level >= 3:
            // Near miss: a little heavier than a tick, to make you hunt.
            haptics.pulse(tick + (catchStrength - tick) * 0.45, sharpness: 0.8)
        default:
            haptics.pulse(tick, sharpness: 0.95)
        }
    }
}
