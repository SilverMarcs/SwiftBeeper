import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
enum RelayApplication {
    @MainActor static func main() {
        #if os(macOS)
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
        #else
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
        #endif
    }
}
