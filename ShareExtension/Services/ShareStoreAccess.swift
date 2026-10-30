import Foundation

/// Borrows the Matrix store from the app for the length of one share.
enum ShareStoreAccess {
    /// How long a running app gets to close the store after being asked.
    private static let handoffTimeout = Duration.seconds(5)

    static func open() async throws {
        // Opening a missing store would create an empty one.
        guard MatrixStore.hasDatabase else { throw ShareError.notSignedIn }
        // iOS reuses the extension's process for the next share, and the last
        // share's `close()` left the store yielded for a few seconds.
        await MatrixRuntime.shared.endYield()
        CoreHandoff.requested.post()
        let deadline = ContinuousClock.now + handoffTimeout
        while true {
            do {
                try await MatrixRuntime.shared.start()
                return
            } catch MatrixError.storeInUse {
                guard .now < deadline else { throw ShareError.appBusy }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Closes the store once commands still running finish, then hands it
    /// back. A suspended extension still holding it would lock the app out,
    /// so this must finish before the share sheet is dismissed.
    static func close() async {
        let runtime = MatrixRuntime.shared
        await runtime.yield()
        await runtime.waitUntilClosed()
        CoreHandoff.released.post()
    }
}
