import Foundation

/// A tiny single-slot memoizer for expensive, pure view computations.
///
/// SwiftUI re-evaluates a view's `body` whenever any observed value it reads
/// changes — including unrelated ones (e.g. a sidebar refresh touching the chat
/// store re-runs the open chat's `body`). Recomputing the timeline grouping
/// (which does per-message `Calendar` work) on every such pass is wasted effort
/// when the inputs are unchanged. Hold one of these in `@State` and gate the
/// computation on an `Equatable` key so it only runs when the inputs actually
/// change.
@MainActor
final class MemoizedValue<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func callAsFunction(_ newKey: Key, _ compute: () -> Value) -> Value {
        if let key, key == newKey, let value {
            return value
        }
        let computed = compute()
        key = newKey
        value = computed
        return computed
    }
}
