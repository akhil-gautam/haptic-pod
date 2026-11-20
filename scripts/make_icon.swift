// Draws Haptic Pod's Detents icon and logo.
//
//     swift scripts/make_icon.swift
//
// Writes the app icon PNGs (light, dark and tinted, every iOS size) and Contents.json into
// HapticPod/Assets.xcassets/AppIcon.appiconset, and docs/logo.svg / docs/logo-dark.svg.
// The mark: a ring of short ticks, one every 15°, with a long tick at 12 o'clock in place of the
// 24th. At 87 px and below it has 12 ticks (every 30°) with heavier strokes, so the ticks don't
// blur into a grey ring. Geometry is on a 1024 canvas; see
// docs/superpowers/specs/2026-11-20-app-icon-design.md.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconDir = root.appendingPathComponent("HapticPod/Assets.xcassets/AppIcon.appiconset")
let docsDir = root.appendingPathComponent("docs")

struct Tick { let angle: Double; let r0, r1, width: Double }

/// The ticks for an icon `px` pixels wide, in 1024-canvas units. Angle 0 is 12 o'clock, clockwise.
func ticks(px: Int) -> [Tick] {
    let small = px <= 87
    let step = small ? 30.0 : 15.0
    let weight = small ? 1.4 : 1.0
    var t = stride(from: step, to: 360, by: step).map {
        Tick(angle: $0, r0: 205, r1: 248, width: 21 * weight)
    }
    t.append(Tick(angle: 0, r0: 150, r1: 325, width: 34 * weight))
    return t
}

func endpoints(_ t: Tick) -> (Double, Double, Double, Double) {
    let a = t.angle * .pi / 180
    let (dx, dy) = (sin(a), -cos(a)) // y down, as in SVG
    return (512 + dx * t.r0, 512 + dy * t.r0, 512 + dx * t.r1, 512 + dy * t.r1)
}

enum Variant: String, CaseIterable { case any, dark, tinted }

func png(px: Int, variant: Variant) -> URL {
    let opaque = variant == .any
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info)!
    let s = Double(px) / 1024
    if opaque {
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    }
    // Flip to y-down so the geometry matches the SVG.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: CGFloat(s), y: -CGFloat(s))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round)
    for t in ticks(px: px) {
        let (x0, y0, x1, y1) = endpoints(t)
        ctx.setLineWidth(t.width)
        ctx.move(to: CGPoint(x: x0, y: y0))
        ctx.addLine(to: CGPoint(x: x1, y: y1))
        ctx.strokePath()
    }
    let name = "icon-\(px)\(variant == .any ? "" : "-" + variant.rawValue).png"
    let url = iconDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(name)")
    return url
}

// Every slot of an iOS "All Sizes" app icon: (points, scale).
let slots: [(String, Int)] = [
    ("20", 2), ("20", 3), ("29", 2), ("29", 3), ("38", 2), ("38", 3), ("40", 2), ("40", 3),
    ("60", 2), ("60", 3), ("64", 2), ("64", 3), ("68", 2), ("76", 2), ("83.5", 2), ("1024", 1),
]

try? FileManager.default.removeItem(at: iconDir)
try FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
var images: [[String: Any]] = []
var written = Set<String>()
for (pt, scale) in slots {
    let px = Int((Double(pt)! * Double(scale)).rounded())
    for v in Variant.allCases {
        let file = png(px: px, variant: v).lastPathComponent
        written.insert(file)
        var entry: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios",
                                    "size": "\(pt)x\(pt)"]
        if pt != "1024" { entry["scale"] = "\(scale)x" }
        if v != .any { entry["appearances"] = [["appearance": "luminosity", "value": v.rawValue]] }
        images.append(entry)
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconDir.appendingPathComponent("Contents.json"))
let catalog = iconDir.deletingLastPathComponent()
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(
    to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

func svg(color: String) -> String {
    let lines = ticks(px: 1024).map { t -> String in
        let (x0, y0, x1, y1) = endpoints(t)
        let f = { (v: Double) in String(format: "%.1f", v) }
        return #"  <line x1="\#(f(x0))" y1="\#(f(y0))" x2="\#(f(x1))" y2="\#(f(y1))" stroke-width="\#(f(t.width))"/>"#
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="160 160 704 704" role="img" aria-label="Haptic Pod">
    <g stroke="\(color)" stroke-linecap="round" fill="none">
    \(lines.joined(separator: "\n"))
    </g>
    </svg>

    """
}
try svg(color: "#000000").write(to: docsDir.appendingPathComponent("logo.svg"), atomically: true, encoding: .utf8)
try svg(color: "#FFFFFF").write(to: docsDir.appendingPathComponent("logo-dark.svg"), atomically: true, encoding: .utf8)
print("\(written.count) PNGs, \(images.count) icon slots, 2 SVGs")
