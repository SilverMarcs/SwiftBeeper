import SwiftUI

/// The long messages a reader expanded in one timeline. A lazy stack discards
/// a row's `@State` once it scrolls out of view, so the choice can't live in
/// the row: it would collapse again, and shift everything below, on return.
@MainActor
@Observable
final class ExpandedMessages {
    private var ids: Set<String> = []

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.remove(id) == nil { ids.insert(id) }
    }
}

extension EnvironmentValues {
    /// Nil outside a timeline, where long messages show whole.
    @Entry var expandedMessages: ExpandedMessages?
}
