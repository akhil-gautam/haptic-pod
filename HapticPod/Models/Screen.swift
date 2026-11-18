import Foundation

enum Screen: Hashable {
    case home
    case playlists, playlist(String)
    case artists, artist(String)
    case albums, album(String)
    case songs
    case settings
    case nowPlaying
}

struct NavFrame: Equatable {
    var screen: Screen
    var selection = 0
    var top = 0
}

enum MenuItem: CaseIterable {
    case playlists, artists, albums, songs, shuffleSongs, settings, nowPlaying

    var title: String {
        switch self {
        case .playlists: "PLAYLISTS"
        case .artists: "ARTISTS"
        case .albums: "ALBUMS"
        case .songs: "SONGS"
        case .shuffleSongs: "SHUFFLE SONGS"
        case .settings: "SETTINGS"
        case .nowPlaying: "NOW PLAYING"
        }
    }
}

enum SettingItem: CaseIterable {
    case haptics, clickSound, shuffle, repeatAll, equalizer, syncFolder, importMusic, rescan, about

    var title: String {
        switch self {
        case .haptics: "HAPTICS"
        case .clickSound: "CLICK SOUND"
        case .shuffle: "SHUFFLE"
        case .repeatAll: "REPEAT"
        case .equalizer: "EQUALIZER"
        case .syncFolder: "SYNC FOLDER"
        case .importMusic: "IMPORT MUSIC"
        case .rescan: "SYNC & RESCAN"
        case .about: "ABOUT"
        }
    }
}

enum GroupKind: Hashable { case playlist, artist, album }

struct GroupInfo: Hashable, Identifiable {
    var kind: GroupKind
    var name: String
    var subtitle: String
    var count: Int
    var artworkKey: String?
    var id: String { name }
}

enum ListContent {
    case menu([MenuItem])
    case groups([GroupInfo])
    case tracks([Track])
    case settings([SettingItem])
    case none

    var count: Int {
        switch self {
        case .menu(let m): m.count
        case .groups(let g): g.count
        case .tracks(let t): t.count
        case .settings(let s): s.count
        case .none: 0
        }
    }
}
