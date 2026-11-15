import SwiftUI
import RelayPrivateSwiftUI

extension View {
    @ViewBuilder
    func messageSelectionGroup() -> some View {
        if #available(iOS 27.0, macOS 27.0, *) {
            relayTextSelectionGroup()
        } else {
            self
        }
    }
}
