import SwiftUI

/// Holds per-touch state outside SwiftUI's render cycle so gesture callbacks see writes immediately.
@MainActor
final class WheelTracker {
    var model = WheelGestureModel()
    var touching = false
    var zone: WheelZone?
    var longFired = false
    var atBoundary = false
    var longTask: Task<Void, Never>?
    var repeatTask: Task<Void, Never>?

    func reset() {
        longTask?.cancel()
        repeatTask?.cancel()
        longTask = nil
        repeatTask = nil
        touching = false
        zone = nil
    }
}

struct WheelView: View {
    let diameter: CGFloat

    @Environment(Navigator.self) private var nav
    @Environment(Haptics.self) private var haptics
    @Environment(PlayerService.self) private var player

    @State private var tracker = WheelTracker()
    @State private var pressed: WheelZone?

    var body: some View {
        let d = diameter
        let colors = nav.finish.wheel
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors.center, colors.edge],
                                     center: .center, startRadius: 0, endRadius: d / 2))
                .overlay(Circle().stroke(colors.rim, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)

            labels(d)

            Circle()
                .fill(LinearGradient(colors: [colors.buttonTop, colors.buttonBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(colors.buttonStroke, lineWidth: 1))
                .frame(width: d * Theme.centerButtonRatio, height: d * Theme.centerButtonRatio)
                .brightness(pressed == .center ? -0.04 : 0)
                .scaleEffect(pressed == .center ? 0.97 : 1)
                .animation(.easeOut(duration: 0.08), value: pressed)
        }
        .frame(width: d, height: d)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged(changed)
                .onEnded(ended)
        )
    }

    private func labels(_ d: CGFloat) -> some View {
        let r = d * Theme.labelRadiusRatio
        return ZStack {
            Text("HOME")
                .font(Theme.font(12, .bold))
                .tracking(2.5)
                .offset(y: -r)
                .opacity(pressed == .top ? 0.6 : 1)
            Image(systemName: "backward.end.alt.fill")
                .font(Theme.font(13))
                .offset(x: -r)
                .opacity(pressed == .left ? 0.6 : 1)
            Image(systemName: "forward.end.alt.fill")
                .font(Theme.font(13))
                .offset(x: r)
                .opacity(pressed == .right ? 0.6 : 1)
            Image(systemName: "playpause.fill")
                .font(Theme.font(13))
                .offset(y: r)
                .opacity(pressed == .bottom ? 0.6 : 1)
        }
        .foregroundStyle(nav.finish.wheel.label)
        .allowsHitTesting(false)
    }

    // MARK: Gesture state machine

    private func changed(_ value: DragGesture.Value) {
        let t = tracker
        let time = value.time.timeIntervalSinceReferenceDate

        if !t.touching {
            t.touching = true
            t.model = WheelGestureModel()
            t.longFired = false
            t.atBoundary = false
            t.zone = WheelGestureModel.zone(value.startLocation, size: diameter,
                                            centerRatio: Theme.centerButtonRatio)
            guard let zone = t.zone else { return }
            pressed = zone
            if zone == .center {
                haptics.play(.pressDown)
            } else {
                _ = t.model.move(to: value.location, size: diameter, time: time)
                scheduleLongPress(zone)
            }
            return
        }

        guard let zone = t.zone, zone != .center, !t.longFired else { return }
        let wasScrolling = t.model.isScrolling
        let steps = t.model.move(to: value.location, size: diameter, time: time)
        if t.model.isScrolling, !wasScrolling {
            t.longTask?.cancel()
            pressed = nil
        }
        if steps != 0 { rotate(steps) }
    }

    private func rotate(_ steps: Int) {
        let t = tracker
        let dir = steps > 0 ? 1 : -1
        // The safe dial plays its own haptics, one number per detent.
        if nav.screen == .game {
            for _ in 0..<abs(steps) { nav.game.turn(dir) }
            return
        }
        let scrubbing = nav.screen == .nowPlaying && nav.nowPlayingWheel == .scrub
        let longList = scrubbing || (nav.screen != .nowPlaying && nav.currentCount > 40)
        let mult = longList ? t.model.multiplier : 1
        // Long alphabetical lists: a heavier notch when the index letter changes.
        let lettered = nav.isAlphabetical && nav.currentCount > 25
        for _ in 0..<abs(steps) {
            let before = lettered ? nav.selectionLetter : nil
            if nav.wheel(delta: dir * mult) {
                t.atBoundary = false
                if lettered, nav.selectionLetter != before {
                    haptics.play(.letter)
                } else {
                    haptics.play(t.model.isFast ? .tickSoft : .tick)
                }
                if nav.isAlphabetical, t.model.isFast { nav.flashLetter() }
            } else if !t.atBoundary {
                t.atBoundary = true
                // Setting a sound's level: a firm stop at 100% rather than the list-end thud.
                haptics.play(nav.adjustingSound != nil ? .home : .thud)
            }
        }
    }

    private func ended(_ value: DragGesture.Value) {
        let t = tracker
        let zone = t.zone
        let scrolled = t.model.isScrolling
        let longFired = t.longFired
        t.reset()
        pressed = nil

        if nav.scrubTarget != nil { nav.commitScrub() }
        guard let zone, !scrolled, !longFired else { return }

        switch zone {
        case .center:
            haptics.play(.pressUp)
            if !nav.select() { haptics.play(.thud) }
        case .top:
            haptics.play(.home)
            nav.back()
        case .left:
            haptics.play(.click)
            player.previous()
        case .right:
            haptics.play(.click)
            player.next()
        case .bottom:
            haptics.play(.click)
            // On SOUNDS (or with no song loaded) play/pause runs the sound mix.
            if nav.screen == .sounds || player.current == nil {
                nav.mixer.togglePlay()
            } else {
                player.togglePlayPause()
            }
        }
    }

    private func scheduleLongPress(_ zone: WheelZone) {
        guard zone == .top || zone == .left || zone == .right else { return }
        let t = tracker
        t.longTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, t.touching, !t.model.isScrolling else { return }
            switch zone {
            case .top:
                t.longFired = true
                haptics.play(.double)
                nav.goHome()
            case .left, .right:
                guard player.current != nil else { return }
                t.longFired = true
                haptics.play(.click)
                let delta: Double = zone == .left ? -5 : 5
                t.repeatTask = Task { @MainActor in
                    while !Task.isCancelled {
                        player.seek(by: delta)
                        haptics.play(.tickSoft)
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            default:
                break
            }
        }
    }
}
