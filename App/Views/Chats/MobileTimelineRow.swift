#if os(iOS)
import Foundation

struct MobileTimelineRow: Identifiable, Equatable {
    let content: MobileTimelineContent
    let chat: Chat
    var showsUnreadDivider = false
    var showsReadIndicator = false
    var isFocused = true

    var id: String { content.id }
}
#endif
