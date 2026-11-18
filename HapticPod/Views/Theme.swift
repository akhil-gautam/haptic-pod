import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    // Body
    static let background = Color(hex: 0xE9E9EB)
    static let bodyTop = Color(hex: 0xD9DADD)
    static let bodyMid = Color(hex: 0xC4C5C9)
    static let bodyBottom = Color(hex: 0xA6A7AB)
    static let bodyStroke = Color(hex: 0x9C9DA1)

    // Display
    static let screen = Color.black
    static let screenStroke = Color(hex: 0x1C1C1E)
    static let statusText = Color(hex: 0xE5E5EA)
    static let primary = Color(hex: 0xF5F5F7)
    static let secondary = Color(hex: 0x8E8E93)
    static let tertiary = Color(hex: 0x636366)
    static let menuIdle = Color(hex: 0xB0B0B5)
    static let selectedSecondary = Color(hex: 0x3A3A3C)
    static let divider = Color(hex: 0x1C1C1E)
    static let track = Color(hex: 0x3A3A3C)

    // Wheel
    static let wheelCenter = Color(hex: 0x151517)
    static let wheelEdge = Color(hex: 0x0A0A0B)
    static let buttonTop = Color(hex: 0x252528)
    static let buttonBottom = Color(hex: 0x131315)
    static let buttonStroke = Color(hex: 0x2C2C2F)
    static let wheelLabel = Color(hex: 0xEDEDF0)

    // Metrics
    static let displayHeightRatio: CGFloat = 0.47
    static let statusBarHeight: CGFloat = 22
    static let menuRowHeight: CGFloat = 34
    static let songRowHeight: CGFloat = 44
    static let settingRowHeight: CGFloat = 36
    static let wheelWidthRatio: CGFloat = 0.70
    static let wheelMax: CGFloat = 300
    static let centerButtonRatio: CGFloat = 0.40
    static let labelRadiusRatio: CGFloat = 0.39

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Colours of the click wheel and its centre button.
struct WheelColors {
    var center, edge, buttonTop, buttonBottom, buttonStroke, label, rim: Color
}

/// Body editions. Each one recolours the body, retunes how strongly the brushed grain and the sheen
/// show on that colour, and picks a matching wheel.
enum BodyFinish: Int, CaseIterable {
    case silver, graphite, gold, blue, red

    var label: String { ["SILVER", "GRAPHITE", "GOLD", "BLUE", "RED"][rawValue] }
    var next: BodyFinish { BodyFinish(rawValue: (rawValue + 1) % Self.allCases.count) ?? .silver }

    /// Top, middle and bottom of the body gradient.
    var body: (top: Color, mid: Color, bottom: Color) {
        switch self {
        case .silver: (Theme.bodyTop, Theme.bodyMid, Theme.bodyBottom)
        case .graphite: (Color(hex: 0x5A5B5F), Color(hex: 0x3E3F43), Color(hex: 0x29292C))
        case .gold: (Color(hex: 0xE9DABF), Color(hex: 0xD3BD99), Color(hex: 0xB39B75))
        case .blue: (Color(hex: 0x74A4DA), Color(hex: 0x4C7FBF), Color(hex: 0x33609C))
        case .red: (Color(hex: 0xDA5860), Color(hex: 0xB8323C), Color(hex: 0x8C222B))
        }
    }

    /// Opacity of the brushed-grain overlay; dark anodising needs more to show the brushing.
    var grain: Double {
        switch self {
        case .silver: 0.75
        case .graphite: 0.95
        case .gold: 0.65
        case .blue, .red: 0.8
        }
    }

    var sheen: Double {
        switch self {
        case .silver, .gold: 0.45
        case .graphite: 0.22
        case .blue, .red: 0.35
        }
    }

    var wheel: WheelColors {
        switch self {
        case .silver:
            WheelColors(center: Theme.wheelCenter, edge: Theme.wheelEdge, buttonTop: Theme.buttonTop,
                        buttonBottom: Theme.buttonBottom, buttonStroke: Theme.buttonStroke,
                        label: Theme.wheelLabel, rim: .black)
        case .graphite:
            WheelColors(center: Color(hex: 0x1B1B1D), edge: Color(hex: 0x0B0B0C), buttonTop: Color(hex: 0x2B2B2E),
                        buttonBottom: Color(hex: 0x161618), buttonStroke: Color(hex: 0x37373A),
                        label: Color(hex: 0x9C9CA1), rim: .black)
        case .gold, .blue, .red:
            WheelColors(center: Color(hex: 0xFAFAF8), edge: Color(hex: 0xE2E2DE), buttonTop: Color(hex: 0xFFFFFF),
                        buttonBottom: Color(hex: 0xE8E8E4), buttonStroke: Color(hex: 0xD0D0CB),
                        label: Color(hex: 0x8A8A8F), rim: Color.black.opacity(0.28))
        }
    }
}
