import Foundation

/// What a timeline shows and how it loads: the open chat's main timeline
/// (`ChatStore`) or one of its threads (`ThreadStore`). `ChatTimelineView`
/// renders either, with the composer for `composerTarget`.
@MainActor
protocol TimelineSource: AnyObject {
    /// The chat the timeline belongs to; nil while no chat is open.
    var timelineChat: Chat? { get }
    var composerTarget: ComposerTarget? { get }

    /// Messages oldest first, without echoes an outgoing row still shows.
    var timelineMessages: [Message] { get }
    /// Optimistic rows, after the messages.
    var timelineOutgoingMessages: [OutgoingMessage] { get }
    var typingBubble: TypingBubble? { get }
    /// Messages that took over a typing row, keeping its identity.
    var typingMessageRowIDs: [Message.ID: String] { get }
    /// Messages that replies quote but the timeline hasn't loaded, by ID.
    var quotedMessages: [Message.ID: Message] { get }
    /// How far each other participant has read.
    var readReceipts: [ReadReceipt] { get }
    /// Whether the chat's read marker applies, placing the "New Messages" divider.
    var showsUnreadDivider: Bool { get }

    /// Whether the first page has arrived.
    var hasLoadedTimeline: Bool { get }
    var isLoadingTimeline: Bool { get }
    var isLoadingOlderTimeline: Bool { get }
    /// Whether to offer older history from the server.
    var canLoadServerHistory: Bool { get }
    var timelineError: String? { get }
    /// A loaded message to scroll to, such as a search result.
    var messageRevealRequest: MessageRevealRequest? { get }
    /// Whether the loaded messages stop short of the newest.
    var hasMoreNewerTimeline: Bool { get }
    /// Changes when the loaded messages are replaced by another stretch of
    /// the conversation, so the timeline lays out afresh.
    var timelineWindowID: UUID { get }

    func loadTimeline() async
    func loadOlderTimeline() async
    func loadServerHistory() async
    func loadNewerTimeline() async
    /// Replaces a stretch that stops short of the newest with the newest page.
    func showLatestTimeline()
    /// Called once the timeline has scrolled to `messageRevealRequest`.
    func finishMessageReveal()
}
