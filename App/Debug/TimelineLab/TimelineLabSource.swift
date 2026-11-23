#if DEBUG
import Foundation
import Observation

/// A chat timeline made of fixed messages, with no Matrix core behind it, for
/// measuring how `ChatTimelineView` scrolls. See `TimelineLabProbe`.
@MainActor
@Observable
final class TimelineLabSource: TimelineSource {
    let chat: Chat
    var messages: [Message]
    var outgoing: [OutgoingMessage] = []
    var hasLoadedTimeline: Bool
    @ObservationIgnored private var nextSortKey: Int

    /// - Parameter loadDelay: How long after opening its messages arrive;
    ///   nil has them loaded already, as a chat opened a second time.
    init(fixture: TimelineLabFixture, loadDelay: Duration?) {
        chat = Chat(id: "lab-\(fixture.rawValue)", title: fixture.title, unreadCount: 0, type: .single)
        let loaded = TimelineLabFixture.messages(for: fixture, chatID: chat.id)
        nextSortKey = loaded.count + 1
        if let loadDelay {
            messages = []
            hasLoadedTimeline = false
            Task { [weak self] in
                try? await Task.sleep(for: loadDelay)
                self?.messages = loaded
                self?.hasLoadedTimeline = true
            }
        } else {
            messages = loaded
            hasLoadedTimeline = true
        }
    }

    /// Another participant's message arriving.
    func receive(words: Int) {
        messages.append(TimelineLabFixture.message(
            index: nextSortKey, chatID: chat.id, isSender: false, words: words
        ))
        nextSortKey += 1
    }

    /// Sending as `InputManager` does: an optimistic row first, replaced by
    /// the confirmed message once the core echoes it.
    func send(_ text: String) {
        let row = OutgoingMessage(chatID: chat.id, text: text, attachments: [], replyToMessageID: nil)
        outgoing.append(row)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            self.outgoing.removeAll { $0.id == row.id }
            self.messages.append(TimelineLabFixture.message(
                index: self.nextSortKey, chatID: self.chat.id, isSender: true, text: text
            ))
            self.nextSortKey += 1
        }
    }

    // MARK: - TimelineSource

    var timelineChat: Chat? { chat }
    var composerTarget: ComposerTarget? { ComposerTarget(chatID: chat.id) }
    var timelineMessages: [Message] { messages }
    var timelineOutgoingMessages: [OutgoingMessage] { outgoing }
    var typingBubble: TypingBubble? { nil }
    var typingMessageRowIDs: [Message.ID: String] { [:] }
    var quotedMessages: [Message.ID: Message] { [:] }
    var readReceipts: [ReadReceipt] { [] }
    var showsUnreadDivider: Bool { false }
    var isLoadingTimeline: Bool { !hasLoadedTimeline }
    var isLoadingOlderTimeline: Bool { false }
    var canLoadServerHistory: Bool { false }
    var timelineError: String? { nil }
    var messageRevealRequest: MessageRevealRequest?
    var hasMoreNewerTimeline: Bool { false }
    let timelineWindowID = UUID()

    func loadTimeline() async {}
    func loadOlderTimeline() async {}
    func loadServerHistory() async {}
    func loadNewerTimeline() async {}
    func showLatestTimeline() {}
    func finishMessageReveal(_ request: MessageRevealRequest, reached: Bool) {
        if messageRevealRequest?.id == request.id { messageRevealRequest = nil }
    }
    func loadQuotedMessages(for messages: [Message]) async {}
}
#endif
