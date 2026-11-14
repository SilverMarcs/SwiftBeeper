import SwiftUI

/// Collects the bubbles in flight for `MessageSendFlightLayer`.
struct MessageSendDestinationKey: PreferenceKey {
    static var defaultValue: [MessageSendDestination] { [] }

    static func reduce(value: inout [MessageSendDestination], nextValue: () -> [MessageSendDestination]) {
        value += nextValue()
    }
}
