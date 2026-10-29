import SwiftUI

struct ChatReminderMenu: View {
    @Environment(NotificationService.self) private var notificationService
    let chat: Chat

    var body: some View {
        Menu("Remind Me to Reply", systemImage: "clock") {
            ForEach(ChatReminderDelay.allCases, id: \.self) { delay in
                Button {
                    Task { await notificationService.remindToReply(to: chat, after: delay) }
                } label: {
                    Text(delay.title)
                }
            }
        }
    }
}
