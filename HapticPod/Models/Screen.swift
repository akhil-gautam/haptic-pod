import Foundation

enum Screen: Hashable {
    case home
    case playlists, playlist(String)
    case artists, artist(String)
    case albums, album(String)
    case songs
    case settings
    case nowPlaying
    case extras, game
}

struct NavFrame: Equatable {
    var screen: Screen
    var selection = 0
    var top = 0
}

enum MenuItem: CaseIterable {
    case playlists, artists, albums, songs, shuffleSongs, extras, settings, nowPlaying

    var title: String {
        switch self {
        case .playlists: "PLAYLISTS"
        case .artists: "ARTISTS"
        case .albums: "ALBUMS"
        case .songs: "SONGS"
        case .shuffleSongs: "SHUFFLE SONGS"
        case .extras: "EXTRAS"
        case .settings: "SETTINGS"
        case .nowPlaying: "NOW PLAYING"
        }
    }
}

enum SettingItem: CaseIterable {
    case haptics, clickSound, shuffle, repeatAll, equalizer, finish, syncFolder, importMusic, rescan, about

    var title: String {
        switch self {
        case .haptics: "HAPTICS"
        case .clickSound: "CLICK SOUND"
        case .shuffle: "SHUFFLE"
        case .repeatAll: "REPEAT"
        case .equalizer: "EQUALIZER"
        case .finish: "BODY"
        case .syncFolder: "SYNC FOLDER"
        case .importMusic: "IMPORT MUSIC"
        case .rescan: "SYNC & RESCAN"
        case .about: "ABOUT"
        }
    }
}

enum ExtraItem: CaseIterable {
    case safecracker

    var title: String {
        switch self {
        case .safecracker: "SAFECRACKER"
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
    case extras([ExtraItem])
    case none

    var count: Int {
        switch self {
        case .menu(let m): m.count
        case .groups(let g): g.count
        case .tracks(let t): t.count
        case .settings(let s): s.count
        case .extras(let e): e.count
        case .none: 0
        }
    }
}
