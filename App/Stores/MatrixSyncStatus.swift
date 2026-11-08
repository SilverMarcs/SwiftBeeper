import Foundation

/// The core's sync status, from its `sync.status` signal.
enum MatrixSyncStatus: String {
    /// No sync of the current active period has been applied yet.
    case waiting
    /// The latest sync was applied; the local database is up to date.
    case ok
    /// Syncs are failing and being retried, such as while offline.
    case erroring
    /// Sync stopped after a fatal error.
    case failed = "permanently-failed"

    /// Whether the core is still working toward an up-to-date database.
    var isCatchingUp: Bool { self == .waiting || self == .erroring }
}
