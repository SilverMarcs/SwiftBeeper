import Foundation

extension Chat {
    /// The most members a group may have to show who has seen a message.
    /// The core loads no read receipts above it either.
    static let readReceiptMemberLimit = 25

    /// A group too large to show read receipts in: its timeline shows no
    /// "Seen" captions, only whether the user's newest message was sent.
    var isLargeGroup: Bool {
        guard isGroupChat, let participants else { return false }
        return (participants.total ?? participants.items.count) > Self.readReceiptMemberLimit
    }
}
