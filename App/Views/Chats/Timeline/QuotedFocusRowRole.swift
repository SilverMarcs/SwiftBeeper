import SwiftUI

/// How a timeline row gives parts of itself up to a tapped quote's chain:
/// a quoted message moves up into the chain, and in a group the sender's
/// name and avatar move to the reply, whose own quote recedes.
struct QuotedFocusRowRole: Equatable {
    /// The whole message, for one the chain shows.
    var message = QuotedFocusHandoff.kept
    var senderName = QuotedFocusHandoff.kept
    var senderAvatar = QuotedFocusHandoff.kept
    var replyPreview = QuotedFocusHandoff.kept
    /// On the reply, the avatar it takes from the last row of its run.
    var avatarCopy: QuotedMorphCopy?

    /// A row the chain takes nothing from.
    static let none = QuotedFocusRowRole()

    /// Each row's role while `focus` shows, keyed by row ID. `chainRowIDs`
    /// are the rows whose message the chain shows.
    static func roles(for focus: QuotedMessageFocus, chainRowIDs: Set<Message.ID>) -> [Message.ID: QuotedFocusRowRole] {
        // A part with a copy moving from it stays hidden until the copy is
        // back; the rest fade back in as the chain closes.
        func handoff(moves: Bool) -> QuotedFocusHandoff {
            moves ? .moved : focus.isPresented ? .faded : .kept
        }

        var roles: [Message.ID: QuotedFocusRowRole] = [:]
        for rowID in chainRowIDs {
            roles[rowID, default: .none].message = handoff(moves: focus.origins[rowID] != nil)
        }
        if let name = focus.senderName {
            roles[name.rowID, default: .none].senderName = handoff(moves: name.origin != nil)
        }
        if let avatar = focus.senderAvatar {
            roles[avatar.rowID, default: .none].senderAvatar = handoff(moves: avatar.origin != nil)
            roles[focus.rowID, default: .none].avatarCopy = QuotedMorphCopy(
                id: focus.id, origin: avatar.origin, isPresented: focus.isPresented
            )
        }
        roles[focus.rowID, default: .none].replyPreview = focus.isPresented ? .faded : .kept
        return roles
    }
}

extension EnvironmentValues {
    /// The part of a tapped quote's handoff the row this sits in plays.
    @Entry var quotedFocusRole = QuotedFocusRowRole.none
}
