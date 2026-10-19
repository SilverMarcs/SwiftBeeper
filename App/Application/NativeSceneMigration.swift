#if os(iOS)
import UIKit

/// Existing installations can restore a session whose archived delegate is
/// SwiftUI.AppSceneDelegate. UIKit does not ask for a new scene configuration
/// when restoring that session. Adopt it without deleting app or account data.
@MainActor
final class NativeSceneMigration {
    private var connectObserver: NSObjectProtocol?

    init() {
        connectObserver = NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            MainActor.assumeIsolated {
                guard scene.session.role == .windowApplication, !(scene.delegate is SceneDelegate) else { return }
                let delegate = SceneDelegate()
                for window in scene.windows { window.isHidden = true }
                scene.delegate = delegate
                delegate.connect(scene)
            }
        }

    }

    isolated deinit {
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
    }
}
#endif
