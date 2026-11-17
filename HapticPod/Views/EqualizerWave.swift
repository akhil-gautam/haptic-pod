import SwiftUI

/// Smooths raw meter readings: fast attack, slower release.
@MainActor
final class LevelSmoother {
    private var value: Float = 0
    func next(_ x: Float) -> Float {
        value += (x - value) * (x > value ? 0.5 : 0.12)
        return value
    }
}

/// Small audio-reactive waveform shown while music plays.
struct EqualizerWave: View {
    var width: CGFloat = 34
    var height: CGFloat = 12

    @Environment(PlayerService.self) private var player
    @State private var smoother = LevelSmoother()

    private static let waves: [(freq: Double, speed: Double, phase: Double, alpha: Double, line: CGFloat)] = [
        (1.6, 7.0, 0.0, 1.0, 1.3),
        (2.4, -5.0, 1.3, 0.55, 1.0),
        (3.3, 9.0, 2.2, 0.3, 0.8),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !player.isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let level = CGFloat(smoother.next(player.isPlaying ? player.meterLevel() : 0))
            Canvas { gc, size in
                let mid = size.height / 2
                let amp = (size.height / 2 - 0.8) * max(level, 0.08)
                let steps = max(Int(size.width * 1.5), 12)
                for w in Self.waves {
                    var path = Path()
                    for i in 0...steps {
                        let x = Double(i) / Double(steps)
                        let envelope = sin(.pi * x)
                        let y = mid + amp * CGFloat(envelope * sin(2 * .pi * w.freq * x + t * w.speed + w.phase))
                        let p = CGPoint(x: CGFloat(x) * size.width, y: y)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    gc.stroke(path, with: .color(Theme.primary.opacity(w.alpha)),
                              style: StrokeStyle(lineWidth: w.line, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: width, height: height)
        .opacity(player.isPlaying ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: player.isPlaying)
        .accessibilityHidden(true)
    }
}
