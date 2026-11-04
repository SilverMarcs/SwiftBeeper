import Foundation

/// Borrows the Matrix store from the app for the length of one share.
enum ShareStoreAccess {
    /// How long a running app gets to close the store after being asked.
    private static let handoffTimeout = Duration.seconds(5)

    static func open() async throws {
        // Opening a missing store would create an empty one.
        guard MatrixStore.hasDatabase else { throw ShareError.notSignedIn }
        let runtime = MatrixRuntime.shared
        do {
            try await takeStore(from: runtime)
        } catch {
            await runtime.endShare()
            throw error
        }
    }

    /// Closes the store once commands still running finish, then hands it
    /// back. A suspended extension still holding it would lock the app out,
    /// so this must finish before the share sheet is dismissed. Commands that
    /// arrive later can't reopen it without the share lock.
    static func close() async {
        let runtime = MatrixRuntime.shared
        await runtime.closeWhenIdle()
        await runtime.waitUntilClosed()
        await runtime.endShare()
        CoreHandoff.released.post()
    }

    /// Marks the share as underway before asking the app for the store, so
    /// the app can tell this request from one it hears late.
    private static func takeStore(from runtime: MatrixRuntime) async throws {
        let deadline = ContinuousClock.now + handoffTimeout
        var hasRequested = false
        while true {
            if try await runtime.beginShare() {
                if !hasRequested {
                    CoreHandoff.requested.post()
                    hasRequested = true
                }
                do {
                    try await runtime.start()
                    return
                } catch MatrixError.storeInUse {}
            }
            guard .now < deadline else { throw ShareError.appBusy }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
