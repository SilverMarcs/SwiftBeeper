#if os(macOS)
import AppKit

extension ComposerFormat {
    /// The format whose shortcut `event` is.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.characters(byApplyingModifiers: [])?.lowercased().first,
              let format = Self.allCases.first(where: { $0.key == key && $0.modifierFlags == flags }) else { return nil }
        self = format
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}
#endif
