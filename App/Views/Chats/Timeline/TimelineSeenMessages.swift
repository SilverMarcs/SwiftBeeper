import SwiftUI

/// Observe the rows actually shown, including thread replies and galleries.
/// Loading a page or a lazy row off screen does not mean the reader saw it.
struct TimelineSeenMessages: ViewModifier {
    let isPresented: Bool
    private let messages: [Message]

    @Environment(NotificationService.self) private var notificationService
    @State private var isVisible = false

    init(item: TimelineItem, isPresented: Bool) {
        self.isPresented = isPresented
        if case .message(let entry, _) = item {
            messages = entry.messages
        } else {
            messages = []
        }
    }

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.1) { visible in
                isVisible = visible
                recordIfVisible()
            }
            .onDisappear { isVisible = false }
            // An unchanged row can become seen when Relay returns, notification
            // setup finishes, or the retained thread inspector reopens.
            .onChange(of: notificationService.isAppActive) { recordIfVisible() }
            .onChange(of: notificationService.isSignedIn) { recordIfVisible() }
            .onChange(of: isPresented) { recordIfVisible() }
            .onChange(of: messages) { recordIfVisible() }
    }

    private func recordIfVisible() {
        guard isVisible, isPresented, notificationService.isAppActive else { return }
        notificationService.markSeen(messages)
    }
}
