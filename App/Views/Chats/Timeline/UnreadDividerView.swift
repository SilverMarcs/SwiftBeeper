import SwiftUI

/// "New Messages" divider shown above the first unread message in the timeline.
struct UnreadDividerView: View {
    var body: some View {
        HStack(spacing: 8) {
            DividerLine()
            Text("New Messages")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            DividerLine()
        }
        .padding(.vertical, 4)
    }
}

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(.background.quinary)
            .frame(height: 1)
    }
}
