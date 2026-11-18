import SwiftUI
import UniformTypeIdentifiers

/// Root: the whole phone screen is the player. Black display on top, brushed-metal body below.
struct DeviceView: View {
    @Environment(Navigator.self) private var nav
    @Environment(LibraryStore.self) private var library
    @Environment(Haptics.self) private var haptics

    var body: some View {
        @Bindable var nav = nav
        GeometryReader { outer in
            let safeTop = outer.safeAreaInsets.top
            GeometryReader { full in
                device(size: full.size, safeTop: safeTop)
            }
            .ignoresSafeArea()
        }
        .background(Theme.screen.ignoresSafeArea())
        // Lets the wheel set system volume (and hides iOS's own volume HUD).
        .background(alignment: .topLeading) { SystemVolumeHost().frame(width: 40, height: 20) }
        .fileImporter(
            isPresented: $nav.showImporter,
            allowedContentTypes: nav.importerMode == .syncFolder
                ? [.folder]
                : [.audio, .folder] + [UTType("org.xiph.flac")].compactMap { $0 },
            allowsMultipleSelection: nav.importerMode == .music
        ) { result in
            guard case .success(let urls) = result else { return }
            switch nav.importerMode {
            case .syncFolder:
                guard let folder = urls.first else { return }
                Task { await library.setSyncFolder(folder) }
            case .music:
                Task {
                    let count = await MusicImporter.importItems(urls)
                    nav.importFinished(count: count)
                    await library.rescan()
                }
            }
        }
    }

    private func device(size: CGSize, safeTop: CGFloat) -> some View {
        let W = size.width, H = size.height
        let displayH = (H * Theme.displayHeightRatio).rounded()
        let wheelD = min(W * Theme.wheelWidthRatio, Theme.wheelMax)
        // Status bar sits just under the Dynamic Island; no island → small fixed inset.
        let topPadding = safeTop > 30 ? safeTop - 10 : 12

        return VStack(spacing: 0) {
            DisplayView(topPadding: topPadding)
                .frame(width: W, height: displayH)
                .background(Theme.screen)
                .clipped()

            ZStack {
                MetalSurface()
                surfaceTouch(wheelCenter: CGPoint(x: W / 2, y: (H - displayH) / 2 - 6), wheelRadius: wheelD / 2)
                WheelView(diameter: wheelD)
                    .offset(y: -6)
            }
            .frame(width: W, height: H - displayH)
        }
        .frame(width: W, height: H)
        // Watches every touch (alongside the display rows and the wheel) for the display seam bump.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { haptics.surface.trackSeam(y: $0.location.y, seamY: displayH) }
                .onEnded { _ in haptics.surface.endSeam() }
        )
    }

    /// Touch layer under the wheel: lets a finger feel the metal body. Touches that start on the
    /// wheel belong to the wheel; a finger slid onto it from the metal feels its rim and surface.
    private func surfaceTouch(wheelCenter: CGPoint, wheelRadius: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let p = value.location
                        let material: SurfaceHaptics.Material =
                            p.y < 0 ? .glass
                            : hypot(p.x - wheelCenter.x, p.y - wheelCenter.y) < wheelRadius ? .wheel
                            : .metal
                        haptics.surface.track(p, on: material)
                    }
                    .onEnded { _ in haptics.surface.ended() }
            )
    }
}
