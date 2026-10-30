import Foundation

/// Darwin notifications that hand the Matrix store between the app and its
/// share extension, which can't both have it open.
nonisolated enum CoreHandoff: String {
    /// The share extension wants the store; a running app closes it.
    case requested = "com.SilverMarcs.RelayEmbedded.core.requested"
    /// The share extension has closed the store again.
    case released = "com.SilverMarcs.RelayEmbedded.core.released"

    func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue as CFString), nil, nil, true
        )
    }

    /// Yields once per post, from any process, until the consumer stops.
    func notifications() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observer = Observer(continuation: continuation)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passRetained(observer).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().continuation.yield()
            },
            rawValue as CFString,
            nil,
            .deliverImmediately
        )
        continuation.onTermination = { _ in
            let pointer = Unmanaged.passUnretained(observer)
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), pointer.toOpaque())
            pointer.release()
        }
        return stream
    }

    /// The Darwin center's observer, retained until the stream ends.
    private final class Observer: Sendable {
        let continuation: AsyncStream<Void>.Continuation

        init(continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }
    }
}
