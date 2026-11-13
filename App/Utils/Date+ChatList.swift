import Foundation

extension Date {
    /// A chat list row's date: the time today, "Yesterday", the weekday
    /// within a week, and the date before that.
    var chatListText: String {
        let calendar = Calendar.app
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) {
            return String(localized: "Yesterday")
        }
        if let daysAgo = calendar.dateComponents([.day], from: self, to: .now).day, daysAgo < 7 {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(date: .numeric, time: .omitted)
    }
}
