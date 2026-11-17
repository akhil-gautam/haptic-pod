import SwiftUI
import UIKit

/// Procedural brushed-aluminium grain: horizontal fibres + fine per-pixel noise, neutral at 50% grey
/// so it can be laid over a gradient with `.overlay` blending.
enum MetalTexture {
    static let image: UIImage = make(width: 900, height: 520, scale: 2)

    static func make(width: Int, height: Int, scale: CGFloat) -> UIImage {
        var pixels = [UInt8](repeating: 128, count: width * height)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        @inline(__always) func rand() -> Float {   // xorshift, -1...1
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(state & 0xFFFF) / 32767.5 - 1
        }
        for y in 0..<height {
            let row = rand() * 0.6 + rand() * 0.4      // per-row brushing streak
            var fibre = rand() * 0.3
            let base = y * width
            for x in 0..<width {
                fibre = fibre * 0.96 + rand() * 0.07    // long horizontal fibres
                let grain = rand()                      // fine sparkle
                let v = 0.5 + row * 0.06 + fibre * 0.55 + grain * 0.07
                pixels[base + x] = UInt8(max(0, min(255, v * 255)))
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return UIImage() }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

struct MetalSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Theme.bodyTop, location: 0),
                                   .init(color: Theme.bodyMid, location: 0.5),
                                   .init(color: Theme.bodyBottom, location: 1)],
                           startPoint: .top, endPoint: .bottom)

            Image(uiImage: MetalTexture.image)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(0.75)

            // Soft diagonal sheen, like light catching anodised aluminium.
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.15),
                                   .init(color: .white.opacity(0.45), location: 0.42),
                                   .init(color: .white.opacity(0), location: 0.7)],
                           startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1))
                .blendMode(.softLight)

            // Shadow cast by the display edge.
            VStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.55)).frame(height: 0.5)
                LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 10)
                Spacer(minLength: 0)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}
