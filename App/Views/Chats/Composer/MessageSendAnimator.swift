import SwiftUI

/// Flies just-sent bubbles in from the composer. Owns only
/// short-lived presentation state; sending never waits for animation.
@MainActor
@Observable
final class MessageSendAnimator {
    private(set) var flights: [MessageSendFlight] = []

    @ObservationIgnored private var expiryTasks: [UUID: Task<Void, Never>] = [:]

    func begin(_ message: OutgoingMessage, from source: MessageSendSource?) {
        guard !message.text.isEmpty, let source else { return }

        // Even hardware-keyboard repeats retain only a bounded animation tail.
        if flights.count >= 8, let oldest = flights.first {
            finish(oldest.id)
        }
        let flight = MessageSendFlight(message: message, source: source)
        flights.append(flight)
        expiryTasks[flight.id] = Task { [weak self] in
            // Drop unused presentation state if the row never appears.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.finish(flight.id)
        }
    }

    func confirm(_ outgoingID: UUID, as message: Message) {
        flights.first { $0.id == outgoingID }?.confirmedMessageIDs.insert(message.id)
    }

    func flight(forOutgoing id: UUID) -> MessageSendFlight? {
        flights.first { $0.id == id }
    }

    func flight(forConfirmed id: String) -> MessageSendFlight? {
        flights.first { $0.confirmedMessageIDs.contains(id) }
    }

    func start(_ id: UUID) {
        guard let flight = flights.first(where: { $0.id == id }),
              flight.startedAt == nil else { return }
        flight.startedAt = .now
        expiryTasks.removeValue(forKey: id)?.cancel()
        expiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MessageSendMotion.duration))
            guard !Task.isCancelled else { return }
            self?.finish(id)
        }
    }

    func finish(_ id: UUID) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        // The flying copy already sits exactly on the bubble when its clock
        // expires, so the bubble takes over without a frame between.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            flights.removeAll { $0.id == id }
        }
    }

    func cancelAll() {
        for task in expiryTasks.values { task.cancel() }
        expiryTasks.removeAll()
        flights.removeAll()
    }
}
