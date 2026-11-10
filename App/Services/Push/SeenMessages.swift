import Foundation

/// Incoming messages already shown in an open chat. A push can reach the
/// device seconds after sync has shown its message, when the user may have
/// left the chat or the app. Seen messages stay quiet both in the foreground,
/// through this in-memory record, and in the background, through the push
/// server, which drops later pushes for them on every device.
///
/// Seeing a message never marks the chat as read; read state stays manual.
@MainActor
final class SeenMessages {
    /// Only a recent message can still have a push on the way. Bridged
    /// messages carry their original network's send time, which can trail
    /// their arrival here (and their push) by tens of seconds, so this
    /// allows more than the usual few seconds of push lag.
    private static let window: TimeInterval = 2 * 60
    /// The push server accepts at most this many messages per request.
    private static let batchSize = 200

    /// Message IDs and when each was seen, pruned after `window`.
    private var seen: [String: Date] = [:]
    private var pending: [SeenMessage] = []
    private var uploadTask: Task<Void, Never>?

    func contains(_ messageID: String) -> Bool {
        !messageID.isEmpty && seen[messageID] != nil
    }

    /// Records the recent incoming messages among `messages` and reports the
    /// new ones to the push server.
    func insert(_ messages: [Message], server: PushServer?) {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-Self.window)
        seen = seen.filter { $0.value > cutoff }
        for message in messages
        where !message.isSender && message.timestamp > cutoff
            && message.id.hasPrefix("$") && seen[message.id] == nil {
            seen[message.id] = now
            pending.append(SeenMessage(chatID: message.chatID, messageID: message.id))
        }
        guard let server, !pending.isEmpty, uploadTask == nil else { return }
        uploadTask = Task {
            defer { uploadTask = nil }
            while !pending.isEmpty {
                let batch = Array(pending.prefix(Self.batchSize))
                pending.removeFirst(batch.count)
                // Best effort: a failed report only means a push may still show.
                try? await server.markSeen(batch)
            }
        }
    }

    func removeAll() {
        uploadTask?.cancel()
        uploadTask = nil
        seen = [:]
        pending = []
    }
}
