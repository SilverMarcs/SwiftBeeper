#if os(macOS)
import SwiftUI

/// Actual Size, Zoom In and Zoom Out in the View menu, for the chat's text.
struct ChatTextSizeCommands: Commands {
    /// Read here only to enable each command.
    @AppStorage(ChatTextSize.storageKey) private var step = 0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Section {
                Button("Actual Size") { ChatTextSize.step = 0 }
                    .keyboardShortcut("0")
                    .disabled(step == 0)
                Button("Zoom In") { ChatTextSize.step += 1 }
                    .keyboardShortcut("+")
                    .disabled(step >= ChatTextSize.steps.upperBound)
                Button("Zoom Out") { ChatTextSize.step -= 1 }
                    .keyboardShortcut("-")
                    .disabled(step <= ChatTextSize.steps.lowerBound)
            }
        }
    }
}
#endif
