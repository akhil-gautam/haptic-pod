import SwiftUI
import UniformTypeIdentifiers

/// Root: the whole phone screen is the player. Black display on top, brushed-metal body below.
struct DeviceView: View {
    @Environment(Navigator.self) private var nav
    @Environment(LibraryStore.self) private var library

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
        .fileImporter(
            isPresented: $nav.showImporter,
            allowedContentTypes: [.audio, .folder] + [UTType("org.xiph.flac")].compactMap { $0 },
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                let count = await MusicImporter.importItems(urls)
                nav.importFinished(count: count)
                await library.rescan()
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
                WheelView(diameter: wheelD)
                    .offset(y: -6)
            }
            .frame(width: W, height: H - displayH)
        }
        .frame(width: W, height: H)
    }
}
