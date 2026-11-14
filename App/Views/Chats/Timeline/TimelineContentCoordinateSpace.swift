import SwiftUI

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The timeline's scrolled content. Positions in it stay put while the
    /// reader or the app scrolls, so a quoted message's copy can find its
    /// row however the timeline moves meanwhile.
    nonisolated static var timelineContent: NamedCoordinateSpace { .named("timeline-content") }
}
