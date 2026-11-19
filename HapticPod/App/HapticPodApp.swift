import SwiftUI
import UIKit

/// App-wide services, created once.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let haptics = Haptics()
    let library = LibraryStore()
    let player = PlayerService()
    let mixer = SoundMixer()
    let sleepTimer: SleepTimer
    let nav: Navigator

    private init() {
        sleepTimer = SleepTimer(player: player, mixer: mixer)
        mixer.player = player
        player.mixer = mixer
        mixer.onStateChange = { [weak player] in player?.refreshNowPlaying() }
        nav = Navigator(library: library, player: player, haptics: haptics, mixer: mixer, sleepTimer: sleepTimer)
        #if DEBUG
        // `-autoplayMix YES` starts the saved (or `-soundMix`) mix on launch, for checks on device.
        if UserDefaults.standard.bool(forKey: "autoplayMix") { mixer.play() }
        #endif
        library.load()
        player.onPlayCounted = { [weak library] id in library?.recordPlay(id) }
        player.restoreState(library: library.tracks)
    }
}

struct RootView: View {
    let services: AppServices

    var body: some View {
        DeviceView()
            .environment(services.nav)
            .environment(services.library)
            .environment(services.player)
            .environment(services.haptics)
    }
}

/// Hosting controller that unconditionally hides the status bar and home indicator.
/// SwiftUI's `.statusBarHidden` modifier is not reliably honoured, a UIKit override always is.
final class FullScreenHostingController: UIHostingController<RootView> {
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .none }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var sceneObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try? FileManager.default.removeItem(at: Paths.documents.appendingPathComponent("_trace.txt")) // leftover debug log
        // A scene session saved by an earlier SwiftUI-lifecycle build is restored with SwiftUI's
        // own scene delegate, which shows only a black window (iPhone can't discard sessions in
        // code). Take such scenes over with our delegate as they connect.
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification, object: nil, queue: .main
        ) { note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let scene = object as? UIWindowScene, !(scene.delegate is SceneDelegate) else { return }
                let delegate = SceneDelegate()
                scene.delegate = delegate
                delegate.connect(scene)
            }
        }
        return true
    }

    /// Always bind our scene delegate, even for sessions iOS restores from an earlier build.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        connect(windowScene)
    }

    func connect(_ windowScene: UIWindowScene) {
        guard window == nil else { return }
        let services = AppServices.shared
        services.haptics.prepare()

        let controller = FullScreenHostingController(rootView: RootView(services: services))
        controller.view.backgroundColor = .black
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        let services = AppServices.shared
        services.haptics.start()
        Task {
            await services.library.refresh()
            // First launch after a fresh install has no saved index, so restore once tracks exist.
            services.player.restoreState(library: services.library.tracks)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppServices.shared.player.saveState()
        AppServices.shared.haptics.stop()
    }
}
