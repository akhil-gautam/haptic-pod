import Foundation
import Observation

@MainActor @Observable
final class LibraryStore {
    static let recentlyAdded = "Recently Added"
    static let mostPlayed = "Most Played"

    private(set) var tracks: [Track] = []
    private(set) var isScanning = false
    private(set) var isSyncing = false
    private(set) var syncFolderName: String? = FolderSync.folderName
    /// New songs copied by the last folder sync (nil until one has run).
    private(set) var lastSyncAdded: Int?

    private(set) var allSongs: [Track] = []
    private(set) var artistGroups: [GroupInfo] = []
    private(set) var albumGroups: [GroupInfo] = []
    private(set) var playlistGroups: [GroupInfo] = []
    @ObservationIgnored private var byArtist: [String: [Track]] = [:]
    @ObservationIgnored private var byAlbum: [String: [Track]] = [:]
    @ObservationIgnored private var byPlaylist: [String: [Track]] = [:]
    @ObservationIgnored private var playCounts: [String: Int] =
        (UserDefaults.standard.dictionary(forKey: "playCounts") as? [String: Int]) ?? [:]

    func load() {
        try? FileManager.default.createDirectory(at: Paths.music, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Paths.libraryIndex),
           let saved = try? JSONDecoder().decode([Track].self, from: data) {
            setTracks(saved)
        }
    }

    /// Pulls new songs from the sync folder (if one is set), then rescans the library.
    func refresh() async {
        if syncFolderName != nil, !isSyncing {
            isSyncing = true
            lastSyncAdded = await FolderSync.sync()
            isSyncing = false
        }
        await rescan()
    }

    /// Remembers a newly picked sync folder and syncs it straight away.
    func setSyncFolder(_ url: URL) async {
        guard FolderSync.remember(url) else { return }
        syncFolderName = FolderSync.folderName
        lastSyncAdded = nil
        await refresh()
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let existing = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let scanned = await LibraryScanner.scan(existing: existing)
        if scanned != tracks {
            setTracks(scanned)
            save()
        }
    }

    func artistTracks(_ name: String) -> [Track] { byArtist[name] ?? [] }
    func albumTracks(_ name: String) -> [Track] { byAlbum[name] ?? [] }
    func playlistTracks(_ name: String) -> [Track] { byPlaylist[name] ?? [] }

    func artworkKey(for screen: Screen) -> String? {
        let list: [Track]
        switch screen {
        case .artist(let n): list = artistTracks(n)
        case .album(let n): list = albumTracks(n)
        case .playlist(let n): list = playlistTracks(n)
        default: list = []
        }
        return list.first(where: { $0.artworkKey != nil })?.artworkKey
    }

    private func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: Paths.libraryIndex, options: .atomic)
        }
    }

    private func setTracks(_ new: [Track]) {
        tracks = new
        let lsc: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        let fileOrder: (Track, Track) -> Bool = { lsc($0.id, $1.id) }

        allSongs = new.sorted { lsc($0.title, $1.title) }

        byArtist = Dictionary(grouping: new, by: \.artist).mapValues { list in
            list.sorted { $0.album == $1.album ? fileOrder($0, $1) : lsc($0.album, $1.album) }
        }
        artistGroups = byArtist.keys.sorted(by: lsc).map { name in
            let list = byArtist[name] ?? []
            let albums = Set(list.map(\.album)).count
            return GroupInfo(kind: .artist, name: name,
                             subtitle: "\(albums) ALBUM\(albums == 1 ? "" : "S")",
                             count: list.count, artworkKey: firstArt(list))
        }

        byAlbum = Dictionary(grouping: new, by: \.album).mapValues { $0.sorted(by: fileOrder) }
        albumGroups = byAlbum.keys.sorted(by: lsc).map { name in
            let list = byAlbum[name] ?? []
            return GroupInfo(kind: .album, name: name, subtitle: list.first?.artist ?? "",
                             count: list.count, artworkKey: firstArt(list))
        }

        buildPlaylists()
    }

    /// Counts a listen and refreshes the Most Played playlist.
    func recordPlay(_ id: String) {
        playCounts[id, default: 0] += 1
        UserDefaults.standard.set(playCounts, forKey: "playCounts")
        buildPlaylists()
    }

    /// Recently Added, Most Played, then one playlist per folder.
    private func buildPlaylists() {
        let new = tracks
        let lsc: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        let fileOrder: (Track, Track) -> Bool = { lsc($0.id, $1.id) }
        var playlists: [String: [Track]] = [:]
        let played = new.filter { (playCounts[$0.id] ?? 0) > 0 }
        if !played.isEmpty {
            playlists[Self.mostPlayed] = Array(played.sorted {
                let a = playCounts[$0.id] ?? 0, b = playCounts[$1.id] ?? 0
                return a == b ? lsc($0.title, $1.title) : a > b
            }.prefix(25))
        }
        if !new.isEmpty {
            playlists[Self.recentlyAdded] = Array(
                new.sorted { $0.added == $1.added ? fileOrder($0, $1) : $0.added > $1.added }.prefix(50)
            )
        }
        for (folder, list) in Dictionary(grouping: new.filter { $0.folder != nil }, by: { $0.folder! }) {
            playlists[folder] = list.sorted(by: fileOrder)
        }
        byPlaylist = playlists
        let smart = [Self.recentlyAdded, Self.mostPlayed]
        let folderNames = playlists.keys.filter { !smart.contains($0) }.sorted(by: lsc)
        let names = smart.filter { playlists[$0] != nil } + folderNames
        playlistGroups = names.map { name in
            let list = playlists[name] ?? []
            return GroupInfo(kind: .playlist, name: name, subtitle: "\(list.count) SONGS",
                             count: list.count, artworkKey: firstArt(list))
        }
    }

    private func firstArt(_ list: [Track]) -> String? {
        list.first(where: { $0.artworkKey != nil })?.artworkKey
    }
}
