import Foundation
import Observation

@MainActor @Observable
final class Navigator {
    private(set) var stack: [NavFrame] = [NavFrame(screen: .home)]
    var showImporter = false
    private(set) var scrubTarget: Double?
    private(set) var importStatus: String?
    @ObservationIgnored var visibleRows = 7

    let library: LibraryStore
    let player: PlayerService
    let haptics: Haptics

    init(library: LibraryStore, player: PlayerService, haptics: Haptics) {
        self.library = library
        self.player = player
        self.haptics = haptics
        #if DEBUG
        // Launch with `-screen songs|playlists|artists|albums|settings|nowPlaying` to jump straight in.
        if let s = UserDefaults.standard.string(forKey: "screen") {
            let map: [String: Screen] = ["songs": .songs, "playlists": .playlists, "artists": .artists,
                                         "albums": .albums, "settings": .settings, "nowPlaying": .nowPlaying]
            if let screen = map[s] { stack.append(NavFrame(screen: screen)) }
        }
        #endif
    }

    var frame: NavFrame { stack[stack.count - 1] }
    var screen: Screen { frame.screen }
    var depth: Int { stack.count }

    func content(for screen: Screen) -> ListContent {
        switch screen {
        case .home: .menu(MenuItem.allCases)
        case .playlists: .groups(library.playlistGroups)
        case .artists: .groups(library.artistGroups)
        case .albums: .groups(library.albumGroups)
        case .songs: .tracks(library.allSongs)
        case .playlist(let n): .tracks(library.playlistTracks(n))
        case .artist(let n): .tracks(library.artistTracks(n))
        case .album(let n): .tracks(library.albumTracks(n))
        case .settings: .settings(SettingItem.allCases)
        case .nowPlaying: .none
        }
    }

    var currentCount: Int { content(for: screen).count }

    // MARK: Wheel

    /// Rotates the selection (or scrubs on Now Playing). Returns whether anything moved.
    @discardableResult
    func wheel(delta: Int) -> Bool {
        if screen == .nowPlaying {
            guard player.current != nil else { return false }
            let duration = player.duration
            guard duration > 0 else { return false }
            let base = scrubTarget ?? player.currentTime
            let next = min(max(base + Double(delta) * 2, 0), duration)
            guard next != base else { return false }
            scrubTarget = next
            return true
        }
        let count = currentCount
        guard count > 0 else { return false }
        var f = frame
        let old = min(f.selection, count - 1)
        let new = min(max(old + delta, 0), count - 1)
        guard new != old else { return false }
        f.selection = new
        let vis = max(visibleRows, 1)
        if new < f.top { f.top = new } else if new >= f.top + vis { f.top = new - vis + 1 }
        stack[stack.count - 1] = f
        return true
    }

    func commitScrub() {
        if let t = scrubTarget { player.seek(to: t) }
        scrubTarget = nil
    }

    // MARK: Actions

    /// Activates the selected row. Returns false when there was nothing to do.
    @discardableResult
    func select() -> Bool {
        let content = content(for: screen)
        if case .none = content {
            return screen == .nowPlaying ? player.togglePlayPause() : false
        }
        guard content.count > 0 else { return false }
        let sel = min(frame.selection, content.count - 1)
        switch content {
        case .menu(let items):
            switch items[sel] {
            case .playlists: push(.playlists)
            case .artists: push(.artists)
            case .albums: push(.albums)
            case .songs: push(.songs)
            case .settings: push(.settings)
            case .nowPlaying:
                guard player.current != nil else { return false }
                push(.nowPlaying)
            }
        case .groups(let groups):
            let g = groups[sel]
            switch g.kind {
            case .playlist: push(.playlist(g.name))
            case .artist: push(.artist(g.name))
            case .album: push(.album(g.name))
            }
        case .tracks(let tracks):
            player.play(queue: tracks, at: sel)
            push(.nowPlaying)
        case .settings(let items):
            perform(items[sel])
        case .none:
            return false
        }
        return true
    }

    func tapRow(_ i: Int) {
        var f = frame
        f.selection = i
        stack[stack.count - 1] = f
        if !select() { haptics.play(.thud) }
    }

    @discardableResult
    func back() -> Bool {
        scrubTarget = nil
        guard stack.count > 1 else { return false }
        stack.removeLast()
        return true
    }

    func goHome() {
        scrubTarget = nil
        stack = [stack[0]]
    }

    func settingValue(_ item: SettingItem) -> String {
        switch item {
        case .haptics: haptics.level.label
        case .clickSound: haptics.clickSound ? "ON" : "OFF"
        case .shuffle: player.shuffle ? "ON" : "OFF"
        case .repeatAll: player.repeatAll ? "ALL" : "OFF"
        case .importMusic: importStatus ?? "FILES"
        case .rescan: library.isScanning ? "SCANNING" : ""
        case .about: "\(library.tracks.count) SONGS"
        }
    }

    func importFinished(count: Int) {
        importStatus = "+\(count)"
    }

    private func push(_ s: Screen) {
        if s == .nowPlaying, screen == .nowPlaying { return }
        stack.append(NavFrame(screen: s))
    }

    private func perform(_ item: SettingItem) {
        switch item {
        case .haptics: haptics.cycleLevel()
        case .clickSound: haptics.toggleClickSound()
        case .shuffle: player.toggleShuffle()
        case .repeatAll: player.toggleRepeat()
        case .importMusic: importStatus = nil; showImporter = true
        case .rescan: Task { await library.rescan() }
        case .about: break
        }
    }
}
