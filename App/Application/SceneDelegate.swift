#if os(iOS)
import UIKit

@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var context: AppContext? { (UIApplication.shared.delegate as? AppDelegate)?.context }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        connect(scene)
    }

    func connect(_ scene: UIWindowScene) {
        guard window == nil, let context else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = MobileRootController(context: context)
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) { context?.foreground() }
    func sceneDidEnterBackground(_ scene: UIScene) { context?.background() }
}
#endif
