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
    case sounds
}

struct NavFrame: Equatable {
    var screen: Screen
    var selection = 0
    var top = 0
}

enum MenuItem: CaseIterable {
    case playlists, artists, albums, songs, shuffleSongs, sounds, extras, settings, nowPlaying

    var title: String {
        switch self {
        case .playlists: "PLAYLISTS"
        case .artists: "ARTISTS"
        case .albums: "ALBUMS"
        case .songs: "SONGS"
        case .shuffleSongs: "SHUFFLE SONGS"
        case .sounds: "SOUNDS"
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
    case sounds([SoundsRow])
    case none

    var count: Int {
        switch self {
        case .menu(let m): m.count
        case .groups(let g): g.count
        case .tracks(let t): t.count
        case .settings(let s): s.count
        case .extras(let e): e.count
        case .sounds(let r): r.count
        case .none: 0
        }
    }
}

/// Rows of the SOUNDS screen: three controls, then every built-in sound.
enum SoundsRow: Hashable {
    case playPause, sleepTimer, clear
    case sound(AmbientSound)

    static let all: [SoundsRow] = [.playPause, .sleepTimer, .clear] + AmbientSound.all.map { .sound($0) }
}
