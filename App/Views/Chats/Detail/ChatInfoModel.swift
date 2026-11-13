import Foundation
import Observation

/// What chat info shows below its header: shared media counts and the newest
/// photos, and the groups shared with a DM's other person.
@MainActor
@Observable
final class ChatInfoModel {
    private(set) var info: ChatInfoOutput?
    private(set) var commonGroups: [Chat] = []

    func loadInfo(chatID: String) async {
        guard let info = try? await APIClient.getChatInfo(chatID: chatID), !Task.isCancelled else { return }
        self.info = info
    }

    /// Group chats shared with `participantID` on the source chat's network.
    func loadCommonGroups(participantID: String, sourceChatID: String) async {
        guard let groups = try? await APIClient.listCommonChats(participantID: participantID, sourceChatID: sourceChatID),
              !Task.isCancelled else { return }
        commonGroups = groups
    }
}
