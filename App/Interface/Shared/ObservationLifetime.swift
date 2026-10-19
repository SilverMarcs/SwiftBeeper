import Observation

/// Bridges Observation to native controllers. Invalidation is coalesced onto
/// the main actor, after the model mutation has completed; no polling is used.
@MainActor
final class ObservationLifetime {
    private var generation = 0

    func track(_ render: @escaping @MainActor () -> Void) {
        generation += 1
        let current = generation
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.track(render)
            }
        }
    }

    func cancel() { generation += 1 }
}
