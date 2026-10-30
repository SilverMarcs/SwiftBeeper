import CoreGraphics
import Foundation
import Observation

/// The share sheet's state: which chat to send to, and what to send.
@MainActor
@Observable
final class ShareModel {
    enum Phase {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var recentChats: [ShareChat] = []
    /// Nil while the search field is empty.
    private(set) var searchResults: [ShareChat]?
    var query = ""
    private(set) var selectedChat: ShareChat?
    var text = ""
    private(set) var attachment: PendingAttachment?
    private(set) var attachmentPreview: CGImage?
    private(set) var isSending = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let providers: [NSItemProvider]
    /// The chat picked from the share sheet's suggestions, if any.
    @ObservationIgnored private let suggestedChatID: String?
    @ObservationIgnored private let complete: () -> Void
    @ObservationIgnored private let cancelRequest: () -> Void
    /// Set once the share sheet is on its way out, so nothing reopens the store.
    @ObservationIgnored private var isFinishing = false

    init(
        providers: [NSItemProvider],
        suggestedChatID: String?,
        complete: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.providers = providers
        self.suggestedChatID = suggestedChatID
        self.complete = complete
        self.cancelRequest = cancel
    }

    var visibleChats: [ShareChat] {
        searchResults ?? recentChats
    }

    /// Changes whenever a search should run: a new query once chats can load.
    var searchTrigger: String? {
        guard case .ready = phase else { return nil }
        return query
    }

    var canSend: Bool {
        selectedChat != nil && !isSending && (attachment != nil || !trimmedText.isEmpty)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func load() async {
        do {
            let content = try await SharedContentLoader.load(providers)
            attachment = content.attachment
            text = content.text
            if let attachment, attachment.mimeType.hasPrefix("image/") {
                attachmentPreview = ImageThumbnail.make(from: attachment.fileData, maximumPixelSize: 400)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            try await ShareStoreAccess.open()
            recentChats = try await APIClient.recentShareChats()
            await selectSuggestedChat()
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Debounced, and cancelled by the next keystroke.
    func search() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let results = try await APIClient.searchShareChats(query)
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    /// Starts at the composer for a suggested chat, listed first.
    private func selectSuggestedChat() async {
        guard let suggestedChatID else { return }
        var chat = recentChats.first { $0.id == suggestedChatID }
        if chat == nil {
            chat = try? await APIClient.shareChat(id: suggestedChatID)
        }
        guard let chat else { return }
        recentChats = [chat] + recentChats.filter { $0.id != chat.id }
        selectedChat = chat
    }

    func select(_ chat: ShareChat) {
        selectedChat = selectedChat == chat ? nil : chat
    }

    func send() async {
        guard let chat = selectedChat, canSend else { return }
        isSending = true
        errorMessage = nil
        do {
            let uploaded = if let attachment { try await AttachmentUploader.upload(attachment) } else { nil as MessageAttachmentInput? }
            let text = trimmedText
            try await APIClient.shareMessage(chatID: chat.id, text: text.isEmpty ? nil : text, attachment: uploaded)
            await donateSentMessage(to: chat)
            await finish(complete)
        } catch {
            errorMessage = error.localizedDescription
            isSending = false
        }
    }

    func cancel() async {
        await finish(cancelRequest)
    }

    /// Hands the store back to the app before the share sheet closes.
    private func finish(_ action: () -> Void) async {
        guard !isFinishing else { return }
        isFinishing = true
        await ShareStoreAccess.close()
        action()
    }

    /// Lets iOS suggest this chat in the share sheet next time. Runs before
    /// the store closes, since the avatar comes from its cache.
    private func donateSentMessage(to chat: ShareChat) async {
        var imageData: Data?
        if let source = chat.avatarURL, let file = try? await MatrixRuntime.shared.localAsset(source) {
            imageData = try? Data(contentsOf: file)
        }
        let others = chat.otherParticipants
        await SentMessageDonation.donate(
            chatID: chat.id,
            title: chat.displayTitle,
            isGroup: chat.isGroup,
            recipients: others.isEmpty
                ? [(id: chat.id, name: chat.displayTitle)]
                : others.map { (id: $0.id, name: $0.displayName) },
            imageData: imageData
        )
    }

    /// Avatars come from the core's media cache, downloading what's missing.
    func avatar(for chat: ShareChat) async -> CGImage? {
        guard !isFinishing, let source = chat.avatarURL,
              let file = try? await MatrixRuntime.shared.localAsset(source) else { return nil }
        return ImageThumbnail.make(contentsOf: file, maximumPixelSize: 120)
    }
}
