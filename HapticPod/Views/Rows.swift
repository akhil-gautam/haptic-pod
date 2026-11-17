import SwiftUI

/// Inverted highlight used by all list rows.
private struct RowChrome: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.primary)
                }
            }
            .overlay(alignment: .bottom) {
                if !selected { Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.horizontal, 6) }
            }
            .contentShape(Rectangle())
    }
}

extension View {
    func rowChrome(selected: Bool) -> some View { modifier(RowChrome(selected: selected)) }
}

struct TrackRow: View {
    let track: Track
    let selected: Bool
    var showAlbum = true
    var showPlayIcon = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(key: track.artworkKey, size: 32, radius: 3)
            if showPlayIcon {
                ZStack {
                    Circle().stroke(selected ? Color.black.opacity(0.35) : Color(hex: 0x48484A), lineWidth: 1)
                    Image(systemName: "play.fill").font(.system(size: 7))
                        .foregroundStyle(selected ? .black : Theme.primary)
                        .offset(x: 0.5)
                }
                .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(selected ? .black : Theme.primary)
                Text(track.artist)
                    .font(Theme.font(9, .medium))
                    .foregroundStyle(selected ? Theme.selectedSecondary : Theme.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if showAlbum {
                Text(track.album.uppercased())
                    .font(Theme.font(8, .semibold))
                    .tracking(1.2)
                    .lineLimit(1)
                    .frame(maxWidth: 90, alignment: .trailing)
                    .foregroundStyle(selected ? Theme.selectedSecondary : Theme.secondary)
            }
            Text(formatTime(track.duration))
                .font(Theme.font(9, .semibold).monospacedDigit())
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(selected ? Theme.selectedSecondary : Theme.secondary)
        }
        .rowChrome(selected: selected)
    }
}

struct GroupRow: View {
    let group: GroupInfo
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(key: group.artworkKey, size: 32, radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(selected ? .black : Theme.primary)
                Text(group.subtitle)
                    .font(Theme.font(9, .medium))
                    .foregroundStyle(selected ? Theme.selectedSecondary : Theme.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(group.count)")
                .font(Theme.font(9, .semibold).monospacedDigit())
                .foregroundStyle(selected ? Theme.selectedSecondary : Theme.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(selected ? Theme.selectedSecondary : Theme.tertiary)
        }
        .rowChrome(selected: selected)
    }
}

struct SettingRow: View {
    let title: String
    let value: String
    let selected: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.font(11, .medium))
                .tracking(2.5)
                .foregroundStyle(selected ? .black : Theme.primary)
            Spacer()
            Text(value)
                .font(Theme.font(9, .semibold))
                .tracking(1.5)
                .foregroundStyle(selected ? Theme.selectedSecondary : Theme.secondary)
        }
        .rowChrome(selected: selected)
    }
}
