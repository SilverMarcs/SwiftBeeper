import SwiftUI

/// Date/time divider shown between messages separated by a gap or a day boundary.
struct TimestampDividerView: View {
    let timestamp: Date

    var body: some View {
        Text(displayText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private var displayText: String {
        let calendar = Calendar.app

        if calendar.isDateInToday(timestamp) {
            return timestamp.formatted(date: .omitted, time: .shortened)
        }

        if calendar.isDateInYesterday(timestamp) {
            return "Yesterday at \(timestamp.formatted(date: .omitted, time: .shortened))"
        }

        return timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
