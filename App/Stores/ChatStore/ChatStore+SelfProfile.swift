import Foundation

extension ChatStore {
    /// A participant as a chat shows them. The user's own member event in a
    /// bridged room carries their Matrix profile, which often has no image,
    /// so their avatar there is the one the network shows, such as their
    /// Slack photo, falling back to their Matrix avatar.
    func displayedParticipant(_ participant: ChatParticipant, in chat: Chat) -> ChatParticipant {
        guard participant.isSelf == true || participant.id == currentUserProfile?.id else { return participant }
        let imageURL = [networkLogin(for: chat)?.user.imgURL, participant.imgURL, currentUserProfile?.imgURL]
            .lazy
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty }
        guard let imageURL, imageURL != participant.imgURL else { return participant }
        return ChatParticipant(
            id: participant.id,
            username: participant.username,
            fullName: participant.fullName,
            imgURL: imageURL,
            isSelf: participant.isSelf
        )
    }

    /// The bridge login a chat belongs to. Logins on the same bridge share
    /// its account ID, so with several (such as two Slack workspaces) the
    /// chat's ghosts pick one: Slack login IDs are `TEAM-USER` and its ghosts
    /// `@slackgo_team-user:server`, so a ghost names its login's team.
    private func networkLogin(for chat: Chat) -> Account? {
        guard let accountID = chat.accountID else { return nil }
        let logins = connectedAccounts.filter { $0.accountID == accountID }
        guard logins.count > 1 else { return logins.first }
        let ghostIDs = chat.participants?.items.compactMap { $0.isSelf == true ? nil : $0.id.lowercased() } ?? []
        let matches = logins.filter { login in
            guard let team = login.user.id.split(separator: "-").first?.lowercased(), !team.isEmpty else {
                return false
            }
            return ghostIDs.contains { $0.contains("_\(team)-") }
        }
        return matches.count == 1 ? matches.first : nil
    }
}
