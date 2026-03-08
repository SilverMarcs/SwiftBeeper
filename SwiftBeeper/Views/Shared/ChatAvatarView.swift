import Foundation
import SwiftUI

struct ChatAvatarView: View {
    let chat: Chat
    let dimension: CGFloat

    var body: some View {
        Group {
            if chat.isGroupChat {
                GroupChatAvatarView(
                    title: chat.displayTitle,
                    participants: groupParticipants,
                    dimension: dimension
                )
            } else {
                ProfileAvatarView(
                    name: primaryParticipantName,
                    imageURLString: primaryParticipantImageURL,
                    dimension: dimension
                )
            }
        }
        .frame(width: dimension, height: dimension)
    }

    private var primaryParticipantName: String {
        if let otherParticipant = chat.otherParticipant {
            return otherParticipant.displayName
        }

        if let senderName = chat.preview?.senderName,
           senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return senderName
        }

        return chat.displayTitle
    }

    private var primaryParticipantImageURL: String? {
        chat.otherParticipant?.imgURL
    }

    private var groupParticipants: [ChatParticipant] {
        let nonSelfParticipants = chat.participants?.items.filter { $0.isSelf != true } ?? []
        return nonSelfParticipants.isEmpty ? (chat.participants?.items ?? []) : nonSelfParticipants
    }
}

private struct GroupChatAvatarView: View {
    let title: String
    let participants: [ChatParticipant]
    let dimension: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.quinary)

            ForEach(avatarPlacements) { placement in
                ProfileAvatarView(source: placement.source, dimension: placement.size)
                    .offset(x: placement.offset.width, y: placement.offset.height)
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(.circle)
    }

    private var avatarPlacements: [AvatarPlacement] {
        let displaySources = avatarSources

        switch displaySources.count {
        case 1:
            return [
                AvatarPlacement(
                    source: displaySources[0],
                    size: dimension * 0.72,
                    offset: .zero
                )
            ]
        case 2:
            return [
                AvatarPlacement(
                    source: displaySources[0],
                    size: dimension * 0.56,
                    offset: CGSize(width: -dimension * 0.16, height: -dimension * 0.08)
                ),
                AvatarPlacement(
                    source: displaySources[1],
                    size: dimension * 0.56,
                    offset: CGSize(width: dimension * 0.16, height: dimension * 0.12)
                )
            ]
        case 3:
            return [
                AvatarPlacement(
                    source: displaySources[0],
                    size: dimension * 0.46,
                    offset: CGSize(width: -dimension * 0.17, height: -dimension * 0.16)
                ),
                AvatarPlacement(
                    source: displaySources[1],
                    size: dimension * 0.42,
                    offset: CGSize(width: dimension * 0.18, height: -dimension * 0.04)
                ),
                AvatarPlacement(
                    source: displaySources[2],
                    size: dimension * 0.44,
                    offset: CGSize(width: -dimension * 0.02, height: dimension * 0.2)
                )
            ]
        default:
            return [
                AvatarPlacement(
                    source: displaySources[0],
                    size: dimension * 0.4,
                    offset: CGSize(width: -dimension * 0.18, height: -dimension * 0.16)
                ),
                AvatarPlacement(
                    source: displaySources[1],
                    size: dimension * 0.38,
                    offset: CGSize(width: dimension * 0.19, height: -dimension * 0.08)
                ),
                AvatarPlacement(
                    source: displaySources[2],
                    size: dimension * 0.38,
                    offset: CGSize(width: -dimension * 0.16, height: dimension * 0.18)
                ),
                AvatarPlacement(
                    source: displaySources[3],
                    size: dimension * 0.36,
                    offset: CGSize(width: dimension * 0.17, height: dimension * 0.2)
                )
            ]
        }
    }

    private var avatarSources: [AvatarSource] {
        let participantSources = participants.prefix(4).map(AvatarSource.participant)

        if participantSources.isEmpty {
            return [.fallback(title), .fallback("Group")]
        }

        if participantSources.count == 1 {
            return [participantSources[0], .fallback(title)]
        }

        return participantSources
    }
}

private struct AvatarPlacement: Identifiable {
    let source: AvatarSource
    let size: CGFloat
    let offset: CGSize

    var id: String { source.id }
}

private enum AvatarSource: Identifiable {
    case participant(ChatParticipant)
    case fallback(String)

    var id: String {
        switch self {
        case .participant(let participant):
            return participant.id
        case .fallback(let name):
            return "fallback-\(name)"
        }
    }
}

private extension ProfileAvatarView {
    init(source: AvatarSource, dimension: CGFloat) {
        switch source {
        case .participant(let participant):
            self.init(
                name: participant.displayName,
                imageURLString: participant.imgURL,
                dimension: dimension
            )
        case .fallback(let name):
            self.init(
                name: name,
                imageURLString: nil,
                dimension: dimension
            )
        }
    }
}
