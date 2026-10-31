import SwiftUI

/// The reminder delays for a chat, behind a "Remind Me" menu item or a custom label.
struct ChatReminderMenu<Label: View>: View {
    @Environment(NotificationService.self) private var notificationService
    let chat: Chat
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            ForEach(ChatReminderDelay.allCases, id: \.self) { delay in
                Button {
                    Task { await notificationService.remindToReply(to: chat, after: delay) }
                } label: {
                    Text(delay.title)
                }
            }
        } label: {
            label
        }
    }
}

extension ChatReminderMenu where Label == SwiftUI.Label<Text, Image> {
    init(chat: Chat) {
        self.init(chat: chat) {
            SwiftUI.Label("Remind Me", systemImage: "clock")
        }
    }
}
