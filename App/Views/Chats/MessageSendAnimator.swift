import SwiftUI

/// Owns only short-lived presentation state; sending never waits for animation.
@MainActor
@Observable
final class MessageSendAnimator {
    private(set) var flights: [MessageSendFlight] = []

    // Read at submission, before clearing the draft can shrink the composer.
    @ObservationIgnored var sourceFrame: (() -> CGRect?)?
    @ObservationIgnored var searchReferenceFrame = CGRect.zero
    @ObservationIgnored private var expiryTasks: [UUID: Task<Void, Never>] = [:]

    func begin(_ message: OutgoingMessage, from frame: CGRect?) {
        guard !message.text.isEmpty,
              let frame, frame.width > 0, frame.height > 0 else { return }

        // Even hardware-keyboard repeats retain only a bounded animation tail.
        if flights.count >= 8, let oldest = flights.first {
            finish(oldest.id)
        }
        let flight = MessageSendFlight(message: message, sourceFrame: frame)
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

    func isAnimatingTail(_ timelineID: String?) -> Bool {
        guard let timelineID else { return false }
        return flights.contains {
            timelineID == "outgoing-\($0.id.uuidString)" || $0.confirmedMessageIDs.contains(timelineID)
        }
    }

    func start(_ id: UUID) {
        guard let flight = flights.first(where: { $0.id == id }),
              flight.startedAt == nil else { return }
        flight.startedAt = .now
        expiryTasks.removeValue(forKey: id)?.cancel()
        expiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MessageSendFlight.duration))
            guard !Task.isCancelled else { return }
            self?.finish(id)
        }
    }

    func finish(_ id: UUID) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        // The render transform is already identity when its clock expires.
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
