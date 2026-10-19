import UserNotifications
#if os(macOS)
import AppKit
typealias PlatformApplicationDelegate = NSApplicationDelegate
typealias PlatformApplication = NSApplication
#else
import UIKit
typealias PlatformApplicationDelegate = UIApplicationDelegate
typealias PlatformApplication = UIApplication
#endif

@MainActor
final class AppDelegate: NSObject, PlatformApplicationDelegate, UNUserNotificationCenterDelegate {
    let context = AppContext()
    #if os(macOS)
    private var windowController: MacWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let controller = MacWindowController(context: context)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate()
        context.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showWindow(nil)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        context.chats.handleAppActivation(true)
        context.foreground()
    }

    func applicationDidResignActive(_ notification: Notification) {
        context.chats.handleAppActivation(false)
    }

    @objc func showSettings(_ sender: Any?) { windowController?.showSettings() }
    #else
    private var sceneMigration: NativeSceneMigration?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        sceneMigration = NativeSceneMigration()
        context.start()
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Relay", sessionRole: session.role)
        configuration.sceneClass = UIWindowScene.self
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
    #endif

    func application(_ application: PlatformApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        context.notifications.receivedDeviceToken(token)
    }

    func application(_ application: PlatformApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        context.notifications.registrationFailed(error)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { context.notifications.badges.reconcileAfterNotification() }
        return []
    }
}
