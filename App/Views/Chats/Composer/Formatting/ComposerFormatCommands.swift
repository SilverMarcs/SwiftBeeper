#if os(macOS)
import SwiftUI

/// The Format menu: the composer's formatting commands, listed with their
/// shortcuts so they can be found. They act on the focused composer.
struct ComposerFormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            Section {
                ForEach([ComposerFormat.bold, .italic, .strikethrough, .code, .codeBlock, .link], id: \.self) { format in
                    ComposerFormatButton(format: format)
                }
            }
            Section {
                ForEach([ComposerFormat.quote, .bulletedList, .numberedList], id: \.self) { format in
                    ComposerFormatButton(format: format)
                }
            }
        }
    }
}
#endif
