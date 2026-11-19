import SwiftUI

/// SOUNDS: the ambient mixer. Three control rows, then every built-in sound; a sound in the mix
/// shows its level bar. Centre on a sound adds it; centre again lets the wheel set its level.
struct SoundsView: View {
    let frame: NavFrame
    @Environment(Navigator.self) private var nav

    var body: some View {
        let rows = SoundsRow.all
        VStack(spacing: 0) {
            header
            WindowedList(frame: frame, count: rows.count, rowHeight: Theme.settingRowHeight) { i, selected in
                SoundsRowView(row: rows[i], selected: selected)
            }
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("SOUNDS").foregroundStyle(Theme.primary)
            if let group = nav.selectedSoundGroup {
                Text("· \(group)").foregroundStyle(Theme.secondary)
            }
            Spacer()
            if nav.adjustingSound != nil {
                Text("TURN TO SET LEVEL").foregroundStyle(Theme.secondary)
            } else if nav.mixer.isPlaying {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 6))
                    Text("PLAYING")
                }
                .foregroundStyle(Theme.secondary)
            }
        }
        .font(Theme.font(8, .semibold)).tracking(2)
        .padding(.horizontal, 6)
        .frame(height: 22)
    }
}

private struct SoundsRowView: View {
    let row: SoundsRow
    let selected: Bool
    @Environment(Navigator.self) private var nav

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.font(11, .medium))
                .tracking(2.5)
                .foregroundStyle(selected ? .black : Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            trailing
        }
        .rowChrome(selected: selected)
    }

    private var title: String {
        switch row {
        case .playPause: nav.mixer.isPlaying ? "PAUSE MIX" : "PLAY MIX"
        case .sleepTimer: "SLEEP TIMER"
        case .clear: "CLEAR MIX"
        case .sound(let s): s.title
        }
    }

    @ViewBuilder
    private var trailing: some View {
        let valueColor = selected ? Theme.selectedSecondary : Theme.secondary
        switch row {
        case .sound(let sound):
            if let notice = nav.soundNotice, notice.id == sound.id {
                Text(notice.text)
                    .font(Theme.font(9, .semibold)).tracking(1.5)
                    .foregroundStyle(valueColor)
            } else if let level = nav.mixer.levels[sound.id] {
                let adjusting = nav.adjustingSound == sound.id
                HStack(spacing: 6) {
                    if adjusting {
                        Text("\(Int((level * 100).rounded()))%")
                            .font(Theme.font(9, .semibold).monospacedDigit())
                            .foregroundStyle(.black)
                    }
                    LevelBar(level: level, selected: selected, emphasized: adjusting)
                        .frame(width: adjusting ? 52 : 36, height: adjusting ? 5 : 3)
                }
                .animation(.easeOut(duration: 0.12), value: adjusting)
            }
        default:
            Text(nav.soundsValue(row))
                .font(Theme.font(9, .semibold).monospacedDigit())
                .tracking(1.5)
                .foregroundStyle(valueColor)
        }
    }
}

private struct LevelBar: View {
    let level: Float
    let selected: Bool
    let emphasized: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(selected ? Color.black.opacity(0.18) : Theme.track)
                Capsule()
                    .fill(selected ? Color.black.opacity(emphasized ? 0.9 : 0.6) : Theme.primary.opacity(0.85))
                    .frame(width: max(g.size.width * CGFloat(level), g.size.height))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
