import SwiftUI

/// The close button for the info sheets: the standard cross on iOS, a "Close"
/// button in the cancellation slot on macOS, which also binds Escape.
struct InfoSheetCloseButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", action: action)
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            Button(role: .close, action: action)
        }
        #endif
    }
}
