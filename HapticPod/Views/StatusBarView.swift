import SwiftUI

struct StatusBarView: View {
    let isRoot: Bool
    var onBack: () -> Void

    var body: some View {
        ZStack {
            if isRoot {
                HStack { brand; Spacer() }
            } else {
                brand
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: Theme.statusBarHeight, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            HStack(spacing: 6) {
                Spacer()
                EqualizerWave(width: 30, height: 12)
            }
        }
        .foregroundStyle(Theme.statusText)
        .frame(height: Theme.statusBarHeight)
    }

    private var brand: some View {
        Text("SUDO")
            .font(Theme.font(9, .semibold))
            .tracking(2.5)
    }
}

struct BluetoothGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX, y: r.minY + h * 0.27))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.73))
        p.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + h * 0.27))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.73))
        return p
    }
}

struct BatteryGlyph: View {
    var level: CGFloat = 0.8
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1).opacity(0.5)
                RoundedRectangle(cornerRadius: 1)
                    .padding(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: level, anchor: .leading)
            }
            RoundedRectangle(cornerRadius: 1).frame(width: 1.5, height: 3.5).opacity(0.5)
        }
    }
}
