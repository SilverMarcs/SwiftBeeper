import Foundation

/// Local observation time, independent of a bridge's original send time.
nonisolated struct SeenMessageRecord: Codable {
    let message: SeenMessage
    let seenAt: Date
    var isReported = false
}
