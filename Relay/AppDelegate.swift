#if os(macOS)
import SwiftUI

/// macOS-only: drains the in-process backend cleanly when the user quits.
/// iOS has no equivalent terminate hook — the system suspends the process
/// (and the embedded backend with it), so no explicit shutdown is needed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let backend = EasyMatrixBackend.shared
        guard backend.isRunning else { return .terminateNow }

        Task { @MainActor in
            await backend.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
