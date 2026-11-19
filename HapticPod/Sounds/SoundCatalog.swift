import Foundation

/// One built-in ambient sound for the mixer.
struct AmbientSound: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        /// A recording (bundle `Sounds/<file>.m4a`) that loops forever; its ends are crossfaded.
        case loop(String)
        /// A single strike, re-struck at a random interval within `every` seconds.
        case struck(String, every: ClosedRange<Double>)
        /// Rendered live in code.
        case generated(Generator)
    }

    let id: String
    let title: String
    let group: String
    let kind: Kind

    var fileURL: URL? {
        switch kind {
        case .loop(let f), .struck(let f, _):
            Bundle.main.url(forResource: f, withExtension: "m4a", subdirectory: "Sounds")
        case .generated: nil
        }
    }
}

extension AmbientSound {
    private static func loop(_ id: String, _ title: String, _ group: String) -> AmbientSound {
        AmbientSound(id: id, title: title, group: group, kind: .loop(id))
    }

    /// Ordered by group; the SOUNDS list shows them in this order.
    static let all: [AmbientSound] = [
        loop("lightRain", "LIGHT RAIN", "RAIN"),
        loop("heavyRain", "HEAVY RAIN", "RAIN"),
        loop("rainWindow", "RAIN ON WINDOW", "RAIN"),
        loop("thunder", "THUNDERSTORM", "RAIN"),
        loop("ocean", "OCEAN", "WATER"),
        loop("stream", "STREAM", "WATER"),
        loop("waterfall", "WATERFALL", "WATER"),
        loop("birds", "FOREST BIRDS", "NATURE"),
        loop("windTrees", "WIND IN TREES", "NATURE"),
        loop("field", "OPEN FIELD", "NATURE"),
        loop("crickets", "CRICKETS", "NIGHT"),
        loop("frogs", "FROGS", "NIGHT"),
        loop("nightForest", "NIGHT FOREST", "NIGHT"),
        loop("campfire", "CAMPFIRE", "FIRE"),
        AmbientSound(id: "bowl", title: "SINGING BOWL", group: "MEDITATE", kind: .struck("bowl", every: 18...40)),
        AmbientSound(id: "gong", title: "TEMPLE GONG", group: "MEDITATE", kind: .struck("gong", every: 25...55)),
        loop("chimes", "WIND CHIMES", "MEDITATE"),
        loop("fountain", "WATER FOUNTAIN", "MEDITATE"),
        loop("cabin", "AIRPLANE CABIN", "INDOOR"),
        AmbientSound(id: "white", title: "WHITE NOISE", group: "NOISE", kind: .generated(.white)),
        AmbientSound(id: "pink", title: "PINK NOISE", group: "NOISE", kind: .generated(.pink)),
        AmbientSound(id: "brown", title: "BROWN NOISE", group: "NOISE", kind: .generated(.brown)),
        AmbientSound(id: "drone", title: "DEEP DRONE", group: "TONES", kind: .generated(.drone)),
        AmbientSound(id: "theta", title: "THETA BEATS", group: "TONES", kind: .generated(.theta)),
    ]

    static let byID: [String: AmbientSound] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
