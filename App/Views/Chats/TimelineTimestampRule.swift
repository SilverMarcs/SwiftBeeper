import Foundation

/// Shared timeline divider rule, so the optimistic tail and the canonical
/// timeline can't drift apart.
enum TimelineTimestampRule {
    /// Gap after which the timeline breaks into a new time-stamped section.
    static let gap: TimeInterval = 30 * 60

    static func showsDivider(before timestamp: Date, previous: Date?) -> Bool {
        guard let previous else { return true }
        if !Calendar.app.isDate(timestamp, inSameDayAs: previous) { return true }
        return timestamp.timeIntervalSince(previous) >= gap
    }
}
