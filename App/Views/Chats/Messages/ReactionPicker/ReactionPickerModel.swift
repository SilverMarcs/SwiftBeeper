import Foundation
import Observation

@MainActor
@Observable
final class ReactionPickerModel: Identifiable {
    let id: String
    let chatID: String
    var text = ""
    private(set) var isChoosing = true
    private(set) var isFinished = false
    private(set) var isSending = false
    private(set) var errorMessage: String?
    private var previousReaction: String?
    private let toggleFeedback: ReactionToggleFeedback?

    init(message: Message, chat: Chat, toggleFeedback: ReactionToggleFeedback? = nil) {
        id = message.id
        self.toggleFeedback = toggleFeedback
        chatID = message.chatID
        if let selfID = chat.participants?.items.first(where: { $0.isSelf == true })?.id {
            previousReaction = message.reactions?.first { $0.participantID == selfID }?.reactionKey
        }
    }

    var reactionKey: String? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Character counts whole emoji, including flags, skin tones, and ZWJ sequences.
        guard candidate.count == 1 else { return nil }
        let scalars = candidate.unicodeScalars
        let isKeycap = scalars.contains { $0.value == 0x20E3 }
        guard scalars.contains(where: {
            $0.properties.isEmoji && ($0.value > 0x7F || isKeycap)
        }) else { return nil }
        return candidate
    }

    func choose(_ value: String) {
        guard isChoosing, !isSending else { return }
        text = value
        guard let reactionKey else { return }
        // Stop receiving keyboard input before starting the network request.
        isChoosing = false
        // Once per pick, not per retry; picking the reaction already there changes nothing.
        if reactionKey != previousReaction { toggleFeedback?.play() }
        retry()
    }

    func retry() {
        guard !isSending, !isFinished, reactionKey != nil else { return }
        errorMessage = nil
        Task {
            if await send() { isFinished = true }
        }
    }

    func cancel() {
        guard !isSending else { return }
        isChoosing = false
        isFinished = true
    }

    func endChoosing() {
        if isChoosing { cancel() }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func send() async -> Bool {
        guard !isSending, let reactionKey else { return false }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            if let previousReaction, previousReaction != reactionKey {
                try await APIClient.removeReaction(chatID: chatID, messageID: id, reactionKey: previousReaction)
                // If adding fails, retry only the add, not the completed removal.
                self.previousReaction = nil
            }
            if previousReaction != reactionKey {
                try await APIClient.addReaction(chatID: chatID, messageID: id, reactionKey: reactionKey)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
