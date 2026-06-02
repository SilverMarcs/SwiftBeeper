import SwiftUI

/// "New Messages" divider shown above the first unread message in the timeline.
struct UnreadDividerView: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text("New Messages")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            line
        }
        .padding(.vertical, 4)
    }

    private var line: some View {
        Rectangle()
            .fill(.background.quinary)
            .frame(height: 1)
    }
}
