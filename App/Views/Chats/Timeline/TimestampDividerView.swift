import SwiftUI

/// Date/time divider shown between messages separated by a gap or a day
/// boundary. As in Messages, the day is bold and the time regular:
/// "**Today** 9:41", "**Yesterday** 9:41", "**Wed, 12 Nov** 9:41".
struct TimestampDividerView: View {
    let timestamp: Date

    var body: some View {
        let time = timestamp.formatted(date: .omitted, time: .shortened)
        Text("\(Text(dayLabel).bold()) \(time)")
            .chatFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    /// Today, yesterday, or the weekday and date, with the year only when it
    /// isn't this one.
    private var dayLabel: String {
        let calendar = Calendar.app

        if calendar.isDateInToday(timestamp) {
            return String(localized: "Today")
        }

        if calendar.isDateInYesterday(timestamp) {
            return String(localized: "Yesterday")
        }

        let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        if calendar.isDate(timestamp, equalTo: .now, toGranularity: .year) {
            return timestamp.formatted(day)
        }
        return timestamp.formatted(day.year())
    }
}
