@preconcurrency import AVFoundation
import MediaPlayer
import QuartzCore
import SwiftUI
import UIKit

/// The phone's real (system) media volume, driven by the wheel on Now Playing.
///
/// iOS has no public setter for system volume; the supported route is the slider inside an
/// `MPVolumeView`. A tiny, near-invisible one stays in the window (`SystemVolumeHost`), which also
/// stops iOS from showing its own volume HUD over the app.
@MainActor @Observable
final class VolumeControl {
    static let shared = VolumeControl()

    /// 0...1. Follows the hardware buttons too.
    private(set) var level: Float

    @ObservationIgnored weak var host: MPVolumeView?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// While the wheel is turning, ignore the system echoing back slightly older values.
    @ObservationIgnored private var ownChangeUntil: CFTimeInterval = 0

    private init() {
        level = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in VolumeControl.shared.systemChanged(value) }
        }
    }

    /// Steps the volume; returns false at either end.
    func change(by delta: Float) -> Bool {
        let new = min(max(level + delta, 0), 1)
        guard abs(new - level) > 0.0001 else { return false }
        level = new
        ownChangeUntil = CACurrentMediaTime() + 0.5
        if let slider = host?.subviews.lazy.compactMap({ $0 as? UISlider }).first {
            slider.setValue(new, animated: false)
            slider.sendActions(for: .valueChanged)
        }
        return true
    }

    private func systemChanged(_ value: Float) {
        guard CACurrentMediaTime() > ownChangeUntil else { return }
        level = value
    }
}

/// Keeps an `MPVolumeView` in the window so the wheel can set system volume.
struct SystemVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        view.alpha = 0.011
        view.isUserInteractionEnabled = false
        VolumeControl.shared.host = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
