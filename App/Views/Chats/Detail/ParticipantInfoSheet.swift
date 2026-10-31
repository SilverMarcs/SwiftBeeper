import SwiftUI

/// A person's info on its own, for taps on a sender or mention in the timeline.
struct ParticipantInfoSheet: View {
    let participant: ChatParticipant
    let sourceChat: Chat
    let onOpenChat: (Chat) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ParticipantInfoView(participant: participant, sourceChat: sourceChat, onOpenChat: openChat)
                .toolbar {
                    InfoSheetCloseButton { dismiss() }
                }
        }
        .frame(minWidth: 400, minHeight: 450)
    }

    private func openChat(_ chat: Chat) {
        onOpenChat(chat)
        dismiss()
    }
}
