import Foundation

extension InputManager {
    /// Use the same complete, locally filtered member list on every platform.
    static let mentionMemberLimit = 100

    var mentionChatID: String? {
        guard let chat = chatStore.selectedChat, chat.isGroupChat,
              (chat.participants?.total ?? 0) <= Self.mentionMemberLimit else { return nil }
        return chat.id
    }

    var mentionQuery: ComposerMentionQuery? {
        guard mentionChatID != nil else { return nil }
        let text = draft
        let selection = composerSelection ?? NSRange(location: text.utf16.count, length: 0)
        guard selection.length == 0, let cursor = Range(selection, in: text)?.lowerBound else { return nil }
        let prefix = text[..<cursor]
        guard let at = prefix.lastIndex(of: "@"),
              at == text.startIndex || text[text.index(before: at)].isWhitespace
                || "([{,:;".contains(text[text.index(before: at)]) else { return nil }
        let query = String(text[text.index(after: at)..<cursor])
        guard !query.contains(where: { $0.isWhitespace || $0 == "@" }),
              let chatID = selectedChatID else { return nil }
        let range = NSRange(at..<cursor, in: text)
        guard !(draftsByChatID[chatID]?.mentions ?? []).contains(where: {
            NSIntersectionRange($0.range, range).length > 0
        }) else { return nil }
        return ComposerMentionQuery(range: range, text: query)
    }

    var mentionSuggestions: [ChatParticipant] {
        guard let query = mentionQuery, query != dismissedMentionQuery,
              mentionParticipantsChatID == selectedChatID else { return [] }
        return Array(mentionParticipants.lazy.filter { participant in
            participant.isSelf != true && (query.text.isEmpty
                || participant.displayName.localizedStandardContains(query.text)
                || participant.username?.localizedStandardContains(query.text) == true)
        }.prefix(8))
    }

    func loadMentionParticipants() async {
        guard let chatID = mentionChatID, mentionQuery != nil,
              mentionParticipantsChatID != chatID else { return }
        do {
            let chat = try await APIClient.getChat(chatID: chatID, maxParticipantCount: Self.mentionMemberLimit)
            guard !Task.isCancelled, selectedChatID == chatID,
                  let participants = chat.participants, participants.hasMore != true,
                  (participants.total ?? participants.items.count) <= Self.mentionMemberLimit else { return }
            mentionParticipants = participants.items.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            mentionParticipantsChatID = chatID
        } catch {
            // A failed member lookup must not interrupt ordinary composing.
        }
    }

    @discardableResult
    func insertMention(_ participant: ChatParticipant) -> Int? {
        guard let chatID = selectedChatID, let query = mentionQuery,
              mentionSuggestions.contains(where: { $0.id == participant.id }),
              let range = Range(query.range, in: draft) else { return nil }
        let label = "@" + participant.displayName
        var text = draft
        let needsSpace = text[range.upperBound...].first != " "
        text.replaceSubrange(range, with: label + (needsSpace ? " " : ""))
        draft = text
        draftsByChatID[chatID]?.mentions.append(ComposerMention(
            userID: participant.id, location: query.range.location, length: label.utf16.count
        ))
        let cursor = query.range.location + label.utf16.count + 1
        composerSelection = NSRange(location: cursor, length: 0)
        return cursor
    }
}
