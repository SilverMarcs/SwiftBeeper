#if os(iOS)
import UIKit
import UserNotifications

@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var context: AppContext? { (UIApplication.shared.delegate as? AppDelegate)?.context }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        connect(scene)
        // A cold launch can deliver the tap with the scene connection.
        if let response = options.notificationResponse,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let chatID = response.notification.request.content.userInfo["chatID"] as? String {
            context?.openNotificationChat(chatID)
        }
    }

    func connect(_ scene: UIWindowScene) {
        guard window == nil, let context else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = MobileRootController(context: context)
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) { context?.foreground() }
    func sceneWillResignActive(_ scene: UIScene) { context?.resignActive() }
    func sceneDidEnterBackground(_ scene: UIScene) { context?.background() }
}
#endif
