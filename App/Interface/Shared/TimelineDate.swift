import Foundation

enum TimelineDate {
    static func label(for date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.app.isDateInToday(date) { return time }
        if Calendar.app.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
