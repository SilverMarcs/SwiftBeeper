import SwiftUI

/// The few messages in one timeline whose text can be selected right now.
///
/// Selectable text gives a bubble its own text view, which lays the text out a
/// second time and joins cursor hit-testing, so on macOS a bubble only becomes
/// selectable once the pointer rests on it or a drag starts across it. A short
/// list of recent messages stays selectable, so a selection made a moment ago
/// survives the pointer passing over a few others.
@MainActor
@Observable
final class SelectableMessages {
    /// Few enough that the extra text views stay cheap.
    private static let capacity = 5

    /// Most recently armed last.
    private var ids: [String] = []

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// Makes a message's text selectable, retiring the oldest when full.
    func arm(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > Self.capacity {
            ids.removeFirst()
        }
    }
}

extension EnvironmentValues {
    /// Nil outside a timeline, where message text is always selectable.
    @Entry var selectableMessages: SelectableMessages?
}
