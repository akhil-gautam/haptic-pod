import Foundation
import Observation

/// Fades out and pauses whatever is playing (music, the sound mix, or both) after a set time.
/// Levels come back to normal for next time.
@MainActor @Observable
final class SleepTimer {
    static let choices = [15, 30, 45, 60, 90]
    static let fadeSeconds: Double = 30

    private(set) var minutes: Int?
    /// Seconds left, updated every second while running.
    private(set) var remaining: TimeInterval?

    @ObservationIgnored private let player: PlayerService
    @ObservationIgnored private let mixer: SoundMixer
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var fading = false

    init(player: PlayerService, mixer: SoundMixer) {
        self.player = player
        self.mixer = mixer
    }

    /// OFF → 15 → 30 → 45 → 60 → 90 → OFF.
    func cycle() {
        let next: Int? = switch minutes {
        case nil: Self.choices.first
        case let m?: Self.choices.first { $0 > m }
        }
        set(next)
    }

    /// "OFF", "30 MIN", or the time left ("23:41") while running.
    var label: String {
        guard let minutes else { return "OFF" }
        guard let remaining else { return "\(minutes) MIN" }
        let s = max(Int(remaining.rounded(.up)), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func set(_ m: Int?) {
        task?.cancel()
        if fading {
            // Changed mid-fade: bring the mix back up (the music restores itself on cancel).
            fading = false
            if mixer.isPlaying { Task { await mixer.fade(to: 1, over: 0.5) } }
        }
        minutes = m
        remaining = nil
        guard let m else { return }
        let end = Date().addingTimeInterval(TimeInterval(m * 60))
        remaining = TimeInterval(m * 60)
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let left = end.timeIntervalSinceNow
                // Overdue: the app was suspended with nothing playing. Don't cut off whatever the
                // user has just started again; the timer simply ran out.
                if left < -2 {
                    self.set(nil)
                    return
                }
                self.remaining = left
                if left <= Self.fadeSeconds {
                    await self.fire(over: max(left, 0))
                    return
                }
            }
        }
    }

    private func fire(over seconds: Double) async {
        fading = true
        defer { fading = false }
        async let music: Void = player.fadeOut(over: seconds)
        async let mix: Void = fadeMix(over: seconds)
        _ = await (music, mix)
        guard !Task.isCancelled else { return }
        minutes = nil
        remaining = nil
    }

    private func fadeMix(over seconds: Double) async {
        guard mixer.isPlaying else { return }
        await mixer.fade(to: 0, over: seconds)
        guard !Task.isCancelled else { return }
        mixer.pause(fade: 0)
    }
}
