import Foundation

/// A transient incoming row whose identity can pass to the arriving message.
struct TypingBubble: Identifiable, Equatable {
    let id = "typing-\(UUID())"
    let participant: ChatParticipant
}
