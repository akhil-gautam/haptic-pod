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
