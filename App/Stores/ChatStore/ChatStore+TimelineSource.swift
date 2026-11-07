import Foundation

/// The open chat's main timeline.
extension ChatStore: TimelineSource {
    var timelineChat: Chat? { selectedChat }

    var composerTarget: ComposerTarget? {
        selectedChatID.map { ComposerTarget(chatID: $0) }
    }

    var showsUnreadDivider: Bool { true }
    var isLoadingTimeline: Bool { isLoadingMessages }
    var isLoadingOlderTimeline: Bool { isLoadingOlderMessages || isLoadingServerHistory }
    var timelineError: String? { messagesError }

    func loadTimeline() async {
        await loadMessages()
    }

    func loadOlderTimeline() async {
        await loadOlderMessages()
    }
}
