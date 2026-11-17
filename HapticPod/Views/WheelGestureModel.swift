import CoreGraphics
import Foundation

enum WheelZone { case center, top, left, right, bottom }

/// Pure angle → detent math for the wheel.
struct WheelGestureModel {
    var detent = 15.0 * Double.pi / 180     // 24 detents per revolution
    private var lastAngle: Double?
    private var acc = 0.0
    private var total = 0.0
    private var signedTotal = 0.0
    private(set) var isScrolling = false
    private var lastTime: TimeInterval = 0
    private(set) var omega = 0.0             // rad/s, low-passed

    static func zone(_ p: CGPoint, size: CGFloat, centerRatio: CGFloat) -> WheelZone? {
        let c = size / 2
        let dx = p.x - c, dy = p.y - c
        let r = hypot(dx, dy)
        if r < size * centerRatio / 2 { return .center }
        if r > size / 2 + 12 { return nil }
        let a = atan2(dy, dx)               // y points down, so +a is clockwise
        switch a {
        case -3 * .pi / 4 ..< -.pi / 4: return .top
        case -.pi / 4 ..< .pi / 4: return .right
        case .pi / 4 ..< 3 * .pi / 4: return .bottom
        default: return .left
        }
    }

    /// Signed detent steps since the last call (+ = clockwise = down the list).
    mutating func move(to p: CGPoint, size: CGFloat, time: TimeInterval) -> Int {
        let c = size / 2
        let dx = Double(p.x - c), dy = Double(p.y - c)
        guard hypot(dx, dy) > Double(size) * 0.12 else { lastAngle = nil; return 0 }
        let a = atan2(dy, dx)
        defer { lastAngle = a; lastTime = time }
        guard let last = lastAngle else { return 0 }
        var d = a - last
        if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
        total += abs(d)
        signedTotal += d
        let dt = max(time - lastTime, 1.0 / 240)
        omega = 0.7 * omega + 0.3 * abs(d) / dt
        let threshold = 6 * Double.pi / 180
        if !isScrolling {
            guard total > threshold else { return 0 }
            isScrolling = true
            // Carry the travel past the threshold so the first detent isn't late.
            acc = signedTotal >= 0 ? max(signedTotal - threshold, 0) : min(signedTotal + threshold, 0)
        } else {
            acc += d
        }
        var steps = 0
        while acc >= detent { acc -= detent; steps += 1 }
        while acc <= -detent { acc += detent; steps -= 1 }
        return steps
    }

    var isFast: Bool { omega > 9 }
    var multiplier: Int { omega > 14 ? 3 : (omega > 9 ? 2 : 1) }
}
