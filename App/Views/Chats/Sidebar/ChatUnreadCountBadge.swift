import SwiftUI

/// A chat row's unread count in a capsule, accent-filled unless the chat is
/// muted. The digits roll as messages arrive or are read.
struct ChatUnreadCountBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let count: Int
    let isMuted: Bool

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isMuted ? Color.secondary.opacity(0.25) : .accentColor, in: .capsule)
            // Scoped to the badge, so its capsule resizes with the digits while
            // the row and the list around it stay put.
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: count)
    }
}
