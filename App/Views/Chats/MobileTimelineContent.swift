#if os(iOS)
import Foundation

enum MobileTimelineContent: Equatable {
    case message(Message, showsTimestamp: Bool, isFirstInGroup: Bool, isLastInGroup: Bool, linkedMessage: Message?)
    case outgoing(OutgoingMessage, showsTimestamp: Bool, linkedMessage: Message?)
    case loadingOlder

    var id: String {
        switch self {
        case .message(let message, _, _, _, _): message.timelineKey
        case .outgoing(let message, _, _): message.timelineKey
        case .loadingOlder: "loading-older"
        }
    }
}
#endif
