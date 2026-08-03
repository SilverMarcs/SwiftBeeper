import SwiftUI

struct WatchMessageComposer: View {
    @Environment(WatchChatStore.self) private var store
    @State private var draft = ""
    let chatID: String

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isSendingMessage(for: chatID)
    }

    var body: some View {
        TextField("Message", text: $draft, axis: .vertical)
            .lineLimit(1 ... 3)
            .submitLabel(.send)
            .onSubmit { send() }
            .disabled(store.isSendingMessage(for: chatID))
            .textFieldStyle(.plain)
            .glassEffect()
    }

    private func send() {
        guard canSend else { return }
        let message = draft
        Task {
            if await store.sendMessage(message, to: chatID) {
                draft = ""
            }
        }
    }
}
