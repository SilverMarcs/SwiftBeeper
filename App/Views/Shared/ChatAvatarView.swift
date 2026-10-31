import SwiftUI

/// A chat's own image, a group collage, or the other participant's avatar.
struct ChatAvatarView: View {
    let chat: Chat
    let dimension: CGFloat
    var allowsFullscreen: Bool = false

    var body: some View {
        Group {
            if let chatImageURL {
                ProfileAvatarView(
                    name: chat.displayTitle,
                    imageURLString: chatImageURL,
                    dimension: dimension,
                    allowsFullscreen: allowsFullscreen
                )
            } else if chat.isGroupChat {
                GroupChatAvatarView(title: chat.displayTitle, participants: groupParticipants, dimension: dimension)
            } else {
                ProfileAvatarView(
                    name: primaryParticipantName,
                    imageURLString: chat.otherParticipant?.imgURL,
                    dimension: dimension,
                    allowsFullscreen: allowsFullscreen
                )
            }
        }
        .frame(width: dimension, height: dimension)
    }

    private var chatImageURL: String? {
        guard let url = chat.imgURL?.trimmed, !url.isEmpty else { return nil }
        return url
    }

    private var primaryParticipantName: String {
        if let otherParticipant = chat.otherParticipant {
            return otherParticipant.displayName
        }
        if let senderName = chat.preview?.senderName, !senderName.isBlank {
            return senderName
        }
        return chat.displayTitle
    }

    /// Everyone but the user, or everyone when the user is the only one listed.
    private var groupParticipants: [ChatParticipant] {
        let others = chat.participants?.items.filter { $0.isSelf != true } ?? []
        return others.isEmpty ? (chat.participants?.items ?? []) : others
    }
}
