import SwiftUI

/// Windowed list: renders only rows[top ..< top+visible]; the wheel moves the selection.
struct WindowedList<Row: View>: View {
    let frame: NavFrame
    let count: Int
    let rowHeight: CGFloat
    @ViewBuilder let row: (Int, Bool) -> Row

    @Environment(Navigator.self) private var nav
    @Environment(Haptics.self) private var haptics

    var body: some View {
        GeometryReader { geo in
            let vis = max(1, Int(geo.size.height / rowHeight))
            let sel = min(frame.selection, max(count - 1, 0))
            let maxTop = max(count - vis, 0)
            let top = min(max(min(frame.top, sel), sel - vis + 1, 0), maxTop)
            VStack(spacing: 0) {
                ForEach(top..<min(top + vis, count), id: \.self) { i in
                    row(i, i == sel)
                        .frame(height: rowHeight)
                        .onTapGesture {
                            haptics.play(.click)
                            nav.tapRow(i)
                        }
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) {
                if count > vis {
                    scrollbar(height: geo.size.height, vis: vis, top: top)
                        .offset(x: 6)
                }
            }
            .onAppear { nav.visibleRows = vis }
            .onChange(of: vis) { _, v in nav.visibleRows = v }
        }
    }

    private func scrollbar(height: CGFloat, vis: Int, top: Int) -> some View {
        let thumb = max(height * CGFloat(vis) / CGFloat(count), 14)
        let y = (height - thumb) * CGFloat(top) / CGFloat(max(count - vis, 1))
        return ZStack(alignment: .top) {
            Capsule().fill(Theme.divider).frame(width: 2)
            Capsule().fill(Theme.track).frame(width: 2, height: thumb).offset(y: y)
        }
        .frame(width: 2, height: height)
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("NO MUSIC")
                .font(Theme.font(11, .semibold)).tracking(3)
                .foregroundStyle(Theme.primary)
            Text("SETTINGS  ›  IMPORT MUSIC")
                .font(Theme.font(8, .semibold)).tracking(2)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Songs / Playlists / Artists / Albums top-level lists.
struct ListScreenView: View {
    let frame: NavFrame
    @Environment(Navigator.self) private var nav

    var body: some View {
        let content = nav.content(for: frame.screen)
        if content.count == 0 {
            EmptyLibraryView()
        } else {
            WindowedList(frame: frame, count: content.count, rowHeight: Theme.songRowHeight) { i, selected in
                switch content {
                case .tracks(let t): TrackRow(track: t[i], selected: selected)
                case .groups(let g): GroupRow(group: g[i], selected: selected)
                default: EmptyView()
                }
            }
            .padding(.top, 6)
        }
    }
}

/// Playlist / artist / album detail: header + tracks with a round play icon.
struct DetailListView: View {
    let frame: NavFrame
    let title: String

    @Environment(Navigator.self) private var nav
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let content = nav.content(for: frame.screen)
        let tracks: [Track] = if case .tracks(let t) = content { t } else { [] }
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ArtworkView(key: library.artworkKey(for: frame.screen), full: true, size: 64, radius: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Theme.font(19, .semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("\(tracks.count) SONG\(tracks.count == 1 ? "" : "S")")
                        .font(Theme.font(8, .semibold)).tracking(2)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 14)

            if tracks.isEmpty {
                EmptyLibraryView()
            } else {
                WindowedList(frame: frame, count: tracks.count, rowHeight: Theme.songRowHeight - 4) { i, selected in
                    TrackRow(track: tracks[i], selected: selected, showAlbum: false, showPlayIcon: true)
                }
            }
        }
    }
}

struct SettingsView: View {
    let frame: NavFrame
    @Environment(Navigator.self) private var nav

    var body: some View {
        let items = SettingItem.allCases
        WindowedList(frame: frame, count: items.count, rowHeight: Theme.settingRowHeight) { i, selected in
            SettingRow(title: items[i].title, value: nav.settingValue(items[i]), selected: selected)
        }
        .padding(.top, 10)
    }
}
