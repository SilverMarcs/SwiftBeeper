#if os(macOS)
import SwiftUI

/// One Format menu command, with its shortcut.
struct ComposerFormatButton: View {
    let format: ComposerFormat

    var body: some View {
        Button(format.title) {
            MacComposerEditor.focused?.apply(format)
        }
        .keyboardShortcut(KeyEquivalent(format.key), modifiers: format.modifiers)
    }
}
#endif
