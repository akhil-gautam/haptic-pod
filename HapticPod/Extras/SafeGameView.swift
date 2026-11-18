import SwiftUI

struct ExtrasView: View {
    let frame: NavFrame
    @Environment(Navigator.self) private var nav

    var body: some View {
        let items = ExtraItem.allCases
        WindowedList(frame: frame, count: items.count, rowHeight: Theme.settingRowHeight) { i, selected in
            SettingRow(title: items[i].title, value: value(items[i]), selected: selected)
        }
        .padding(.top, 10)
    }

    private func value(_ item: ExtraItem) -> String {
        switch item {
        case .safecracker: nav.game.best > 0 ? "BEST LV \(nav.game.best)" : "NEW"
        }
    }
}

struct SafeGameView: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        let game = nav.game
        VStack(spacing: 0) {
            header(game)
            Spacer(minLength: 6)
            DialView(position: game.position, number: game.dial, opened: game.phase == .opened)
                .frame(width: 156, height: 156)
                .modifier(Shake(amount: CGFloat(game.misses)))
                .animation(.linear(duration: 0.32), value: game.misses)
            Spacer(minLength: 10)
            slots(game)
            Spacer(minLength: 8)
            Text(hint(game))
                .font(Theme.font(7, .semibold)).tracking(2)
                .foregroundStyle(Theme.secondary)
                .padding(.bottom, 4)
        }
        .padding(.top, 8)
    }

    private func header(_ game: SafeGame) -> some View {
        HStack(spacing: 10) {
            Text("LEVEL \(game.level)")
                .foregroundStyle(Theme.primary)
            if game.best > 0 {
                Text("BEST \(game.best)").foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<SafeGame.maxLives, id: \.self) { i in
                    Circle()
                        .fill(i < game.lives ? Theme.primary : Theme.track)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .font(Theme.font(8, .semibold)).tracking(2.2)
    }

    private func slots(_ game: SafeGame) -> some View {
        HStack(spacing: 14) {
            ForEach(game.combination.indices, id: \.self) { i in
                let known = i < game.solved
                let current = i == game.solved && game.phase == .playing
                VStack(spacing: 4) {
                    Text(known ? String(format: "%02d", game.combination[i]) : "··")
                        .font(Theme.font(17, .semibold).monospacedDigit())
                        .foregroundStyle(known ? Theme.primary : current ? Theme.secondary : Theme.tertiary)
                    Capsule()
                        .fill(current ? Theme.primary : Theme.track)
                        .frame(width: 22, height: 2)
                }
            }
        }
    }

    private func hint(_ game: SafeGame) -> String {
        switch game.phase {
        case .playing: "FEEL FOR THE CATCH  ·  PRESS TO TRY"
        case .opened: "OPENED  ·  PRESS FOR LEVEL \(game.level + 1)"
        case .lockedOut: "LOCKED OUT  ·  PRESS TO START AGAIN"
        }
    }
}

/// A safe dial: 40 numbers on a ring that turns under a fixed pointer.
private struct DialView: View {
    let position: Int
    let number: Int
    let opened: Bool

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let r = size / 2
            ZStack {
                Circle().fill(Color(hex: 0x0E0E10))
                Circle().stroke(Theme.track, lineWidth: 1.5)

                ZStack {
                    ForEach(0..<SafeGame.numbers, id: \.self) { i in
                        let major = i % 5 == 0
                        Capsule()
                            .fill(major ? Theme.primary : Theme.tertiary)
                            .frame(width: major ? 1.6 : 1, height: major ? 9 : 5)
                            .offset(y: -(r - 8))
                            .rotationEffect(.degrees(Double(i) * 360 / Double(SafeGame.numbers)))
                        if i % 10 == 0 {
                            Text("\(i)")
                                .font(Theme.font(8, .semibold).monospacedDigit())
                                .foregroundStyle(Theme.secondary)
                                .offset(y: -(r - 24))
                                .rotationEffect(.degrees(Double(i) * 360 / Double(SafeGame.numbers)))
                        }
                    }
                }
                .rotationEffect(.degrees(-Double(position) * 360 / Double(SafeGame.numbers)))
                .animation(.easeOut(duration: 0.09), value: position)

                // Pointer
                Triangle()
                    .fill(Theme.primary)
                    .frame(width: 9, height: 7)
                    .offset(y: -r - 6)

                Circle()
                    .fill(Color(hex: 0x1C1C1E))
                    .frame(width: size * 0.46, height: size * 0.46)
                Text(opened ? "OPEN" : String(format: "%02d", number))
                    .font(Theme.font(opened ? 15 : 28, .semibold).monospacedDigit())
                    .tracking(opened ? 2.5 : 0)
                    .foregroundStyle(Theme.primary)
            }
            .frame(width: size, height: size)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// Side-to-side shake, one burst per increment of `amount`.
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(amount * .pi * 4), y: 0))
    }
}
