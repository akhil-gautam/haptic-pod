import Foundation
import Observation

@MainActor @Observable
final class Navigator {
    private(set) var stack: [NavFrame] = [NavFrame(screen: .home)]
    enum ImporterMode { case music, syncFolder }
    var showImporter = false
    private(set) var importerMode: ImporterMode = .music
    private(set) var scrubTarget: Double?
    private(set) var importStatus: String?
    @ObservationIgnored var visibleRows = 7

    /// What the wheel does on Now Playing: system volume by default; a centre press switches to
    /// scrubbing, which falls back to volume after a few idle seconds.
    enum NowPlayingWheel { case volume, scrub }
    private(set) var nowPlayingWheel: NowPlayingWheel = .volume
    /// True briefly after the wheel changes volume, so Now Playing shows the volume bar.
    private(set) var showingVolume = false
    @ObservationIgnored private var scrubIdleTask: Task<Void, Never>?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?

    /// Big index letter shown while spinning fast through an alphabetical list.
    private(set) var scrollLetter: String?
    @ObservationIgnored private var letterTask: Task<Void, Never>?

    private(set) var finish: BodyFinish
    let game: SafeGame

    /// SOUNDS: the sound whose level the wheel is setting, if any.
    private(set) var adjustingSound: String?
    /// SOUNDS: a brief note on one row ("MAX 6").
    private(set) var soundNotice: (id: String, text: String)?
    @ObservationIgnored private var adjustIdleTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    let mixer: SoundMixer
    let sleepTimer: SleepTimer

    let library: LibraryStore
    let player: PlayerService
    let haptics: Haptics

    init(library: LibraryStore, player: PlayerService, haptics: Haptics, mixer: SoundMixer, sleepTimer: SleepTimer) {
        self.library = library
        self.player = player
        self.haptics = haptics
        self.mixer = mixer
        self.sleepTimer = sleepTimer
        finish = BodyFinish(rawValue: UserDefaults.standard.integer(forKey: "bodyFinish")) ?? .silver
        game = SafeGame(haptics: haptics)
        #if DEBUG
        // Launch with `-screen songs|playlists|artists|albums|settings|nowPlaying|extras|game`.
        if let s = UserDefaults.standard.string(forKey: "screen") {
            let map: [String: Screen] = ["songs": .songs, "playlists": .playlists, "artists": .artists,
                                         "albums": .albums, "settings": .settings, "nowPlaying": .nowPlaying,
                                         "extras": .extras, "game": .game, "sounds": .sounds]
            if let screen = map[s] {
                stack.append(NavFrame(screen: screen))
                if screen == .game { game.newGame() }
            }
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
        case .extras: .extras(ExtraItem.allCases)
        case .sounds: .sounds(SoundsRow.all)
        case .nowPlaying, .game: .none
        }
    }

    // MARK: Index letters

    var isAlphabetical: Bool {
        switch screen {
        case .songs, .artists, .albums: true
        default: false
        }
    }

    /// Index letter of the selected row on Songs / Artists / Albums.
    var selectionLetter: String? {
        guard isAlphabetical else { return nil }
        let name: String? = switch content(for: screen) {
        case .tracks(let t): t.indices.contains(frame.selection) ? t[frame.selection].title : nil
        case .groups(let g): g.indices.contains(frame.selection) ? g[frame.selection].name : nil
        default: nil
        }
        return name.map(Self.indexLetter)
    }

    static func indexLetter(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        guard let c = folded.first(where: { !$0.isWhitespace }), c.isLetter else { return "#" }
        return String(c)
    }

    func flashLetter() {
        scrollLetter = selectionLetter
        letterTask?.cancel()
        letterTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.scrollLetter = nil
        }
    }

    var currentCount: Int { content(for: screen).count }

    // MARK: Wheel

    /// Rotates the selection (or scrubs on Now Playing). Returns whether anything moved.
    @discardableResult
    func wheel(delta: Int) -> Bool {
        if screen == .sounds, let id = adjustingSound {
            return adjustLevel(id, by: delta)
        }
        if screen == .nowPlaying, nowPlayingWheel == .volume {
            guard VolumeControl.shared.change(by: Float(delta) / 32) else { return false }
            showingVolume = true
            volumeTask?.cancel()
            volumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled else { return }
                self?.showingVolume = false
            }
            return true
        }
        if screen == .nowPlaying {
            scheduleScrubIdle()
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
        if nowPlayingWheel == .scrub { scheduleScrubIdle() }
    }

    /// Centre press on Now Playing: switch the wheel between volume and scrubbing.
    private func toggleNowPlayingWheel() -> Bool {
        guard player.current != nil else { return false }
        showingVolume = false
        nowPlayingWheel = nowPlayingWheel == .volume ? .scrub : .volume
        if nowPlayingWheel == .scrub { scheduleScrubIdle() } else { scrubIdleTask?.cancel() }
        return true
    }

    private func scheduleScrubIdle() {
        scrubIdleTask?.cancel()
        scrubIdleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.scrubTarget == nil else { return }
            self.nowPlayingWheel = .volume
        }
    }

    private func leaveNowPlaying() {
        scrubTarget = nil
        scrubIdleTask?.cancel()
        nowPlayingWheel = .volume
        showingVolume = false
    }

    // MARK: Actions

    /// Activates the selected row. Returns false when there was nothing to do.
    @discardableResult
    func select() -> Bool {
        let content = content(for: screen)
        if case .none = content {
            switch screen {
            case .nowPlaying: return toggleNowPlayingWheel()
            case .game: game.press(); return true
            default: return false
            }
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
            case .shuffleSongs:
                guard !library.allSongs.isEmpty else { return false }
                player.shuffleAll(library.allSongs)
                push(.nowPlaying)
            case .sounds: push(.sounds)
            case .extras: push(.extras)
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
        case .extras(let items):
            switch items[sel] {
            case .safecracker:
                game.newGame()
                push(.game)
            }
        case .sounds(let rows):
            return selectSoundsRow(rows[sel])
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
        if adjustingSound != nil {
            endAdjust()
            return true
        }
        leaveNowPlaying()
        guard stack.count > 1 else { return false }
        stack.removeLast()
        return true
    }

    func goHome() {
        endAdjust()
        leaveNowPlaying()
        stack = [stack[0]]
    }

    func settingValue(_ item: SettingItem) -> String {
        switch item {
        case .haptics: haptics.level.label
        case .clickSound: haptics.clickSound ? "ON" : "OFF"
        case .shuffle: player.shuffle ? "ON" : "OFF"
        case .repeatAll: player.repeatAll ? "ALL" : "OFF"
        case .equalizer: player.eqPreset.label
        case .finish: finish.label
        case .syncFolder:
            if library.isSyncing { "SYNCING" }
            else if let name = library.syncFolderName {
                (library.lastSyncAdded.map { $0 > 0 ? "+\($0) · " : "" } ?? "") + Self.short(name.uppercased())
            } else { "CHOOSE" }
        case .importMusic: importStatus ?? "FILES"
        case .rescan: library.isSyncing || library.isScanning ? "WORKING" : ""
        case .about: "\(library.tracks.count) SONGS"
        }
    }

    func importFinished(count: Int) {
        importStatus = "+\(count)"
    }

    private static func short(_ s: String, max: Int = 14) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private func push(_ s: Screen) {
        if s == .nowPlaying, screen == .nowPlaying { return }
        endAdjust()
        leaveNowPlaying()
        stack.append(NavFrame(screen: s))
    }

    private func perform(_ item: SettingItem) {
        switch item {
        case .haptics: haptics.cycleLevel()
        case .clickSound: haptics.toggleClickSound()
        case .shuffle: player.toggleShuffle()
        case .repeatAll: player.toggleRepeat()
        case .equalizer: player.cycleEQ()
        case .finish:
            finish = finish.next
            UserDefaults.standard.set(finish.rawValue, forKey: "bodyFinish")
        case .syncFolder: importerMode = .syncFolder; showImporter = true
        case .importMusic: importStatus = nil; importerMode = .music; showImporter = true
        case .rescan: Task { await library.refresh() }
        case .about: break
        }
    }

    // MARK: Sounds

    /// Group of the selected sound (for the SOUNDS header), nil on the control rows.
    var selectedSoundGroup: String? {
        guard screen == .sounds, SoundsRow.all.indices.contains(frame.selection),
              case .sound(let sound) = SoundsRow.all[frame.selection] else { return nil }
        return sound.group
    }

    func soundsValue(_ row: SoundsRow) -> String {
        switch row {
        case .playPause: mixer.levels.isEmpty ? "EMPTY" : "\(mixer.levels.count) ON"
        case .sleepTimer: sleepTimer.label
        case .clear: ""
        case .sound: ""
        }
    }

    private func selectSoundsRow(_ row: SoundsRow) -> Bool {
        switch row {
        case .playPause:
            guard !mixer.levels.isEmpty else { return false }
            mixer.togglePlay()
        case .sleepTimer:
            sleepTimer.cycle()
        case .clear:
            guard !mixer.levels.isEmpty else { return false }
            endAdjust()
            mixer.clear()
        case .sound(let sound):
            if adjustingSound == sound.id {
                endAdjust()
            } else if mixer.levels[sound.id] != nil {
                adjustingSound = sound.id
                scheduleAdjustIdle()
            } else if mixer.turnOn(sound.id) {
                endAdjust()
            } else {
                flashNotice(sound.id, "MAX \(SoundMixer.maxActive)")
                return false
            }
        }
        return true
    }

    /// Wheel while adjusting: one detent is 1/32. Reaching zero takes the sound out of the mix.
    private func adjustLevel(_ id: String, by delta: Int) -> Bool {
        scheduleAdjustIdle()
        guard let level = mixer.levels[id] else { endAdjust(); return false }
        let next = min(max(level + Float(delta) / 32, 0), 1)
        guard abs(next - level) > 0.0001 else { return false }
        mixer.setLevel(id, next)
        if mixer.levels[id] == nil { endAdjust() }
        return true
    }

    private func endAdjust() {
        adjustIdleTask?.cancel()
        adjustingSound = nil
    }

    private func scheduleAdjustIdle() {
        adjustIdleTask?.cancel()
        adjustIdleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.adjustingSound = nil
        }
    }

    private func flashNotice(_ id: String, _ text: String) {
        soundNotice = (id, text)
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            self?.soundNotice = nil
        }
    }
}
