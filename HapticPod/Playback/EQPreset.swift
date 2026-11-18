@preconcurrency import AVFoundation

/// Sound modes: a five-band EQ curve (60 Hz low shelf, 230 / 910 / 3.6k peaks, 14k high shelf,
/// gains in dB) plus optional room reverb and a short ambience delay for the "space" modes.
enum EQPreset: Int, CaseIterable, Sendable {
    case flat, stereo, surround, cinema, concert, club, bass, vocal, treble, loudness

    static let frequencies: [Float] = [60, 230, 910, 3_600, 14_000]

    var label: String {
        switch self {
        case .flat: "FLAT"
        case .stereo: "STEREO"
        case .surround: "SURROUND"
        case .cinema: "CINEMA"
        case .concert: "CONCERT"
        case .club: "CLUB"
        case .bass: "BASS"
        case .vocal: "VOCAL"
        case .treble: "TREBLE"
        case .loudness: "LOUD"
        }
    }

    var gains: [Float] {
        switch self {
        case .flat: [0, 0, 0, 0, 0]
        // Clean studio stereo: a touch of low end and "air", nothing else.
        case .stereo: [1, 0, -0.5, 0.5, 2]
        // Scooped mids with lifted lows/highs, big room tail and a slap of ambience.
        case .surround: [3, 0.5, -1.5, 1.5, 3.5]
        // Movie-theatre: deep bass, clear dialogue band, medium hall.
        case .cinema: [5, 2, -0.5, 2.5, 4]
        // Open, natural, with a large hall behind it.
        case .concert: [2, 1, 0, 1, 2.5]
        // Heavy kick and bass, tight small room.
        case .club: [7, 4, -1, 0.5, 2]
        case .bass: [6, 3.5, 0, 0, 0]
        case .vocal: [-2, -1, 3, 3.5, 1]
        case .treble: [0, 0, 0, 3.5, 6]
        case .loudness: [5, 2, -1, 2, 5]
        }
    }

    /// Room reverb and its wet mix (0–100), or nil for none.
    var reverb: (preset: AVAudioUnitReverbPreset, wet: Float)? {
        switch self {
        case .surround: (.largeRoom, 22)
        case .cinema: (.mediumHall, 16)
        case .concert: (.largeHall, 28)
        case .club: (.smallRoom, 10)
        default: nil
        }
    }

    /// Short ambience delay (seconds, wet mix 0–100), or nil for none.
    var ambience: (time: TimeInterval, wet: Float)? {
        switch self {
        case .surround: (0.024, 14)
        case .cinema: (0.018, 8)
        default: nil
        }
    }

    /// Pulls the overall level down so boosted bands and added room don't clip.
    var headroom: Float {
        -(gains.max() ?? 0) * 0.6 - (reverb?.wet ?? 0) * 0.04 - (ambience?.wet ?? 0) * 0.04
    }

    var next: EQPreset { EQPreset(rawValue: (rawValue + 1) % Self.allCases.count) ?? .flat }
}
